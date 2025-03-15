library(data.table)
library(xgboost)
library(rstudioapi)

# Set path to script location
setwd(dirname(getActiveDocumentContext()$path))

# Load in base data
user_ratings <- fread("user_ratings.csv")
dim_games <- fread("dim_games.csv")
game_attributes <- fread("game_attributes.csv")

# Create attribute list for later use
attributes_list <- unique(game_attributes[,ATTRIBUTE_TYPE])
# Flag all expansions
expansions <- unique(game_attributes[ATTRIBUTE_TYPE=="boardgamecategory" & tolower(ATTRIBUTE) %like% "expansion", GAME_ID])
# Convert ranks to category flags
ranks <- game_attributes[ATTRIBUTE_TYPE %like% "Rank",]
ranks[, ATTRIBUTE_TYPE:=tstrsplit(ATTRIBUTE_TYPE, " "), by = c("GAME_ID", "ATTRIBUTE_ID")]
major_category_flags <- dcast(ranks, GAME_ID~ATTRIBUTE_TYPE, value.var = "ATTRIBUTE")
major_category_flags[, c("Accessory", "Amiga", "Arcade", "Atari", "Board", "Commodore", "RPG", "Video"):=NULL]
major_category_flags[Abstract > 1, Abstract := 1][`Children's` > 1, `Children's` := 1][Customizable > 1, Customizable := 1][Family > 1, Family := 1][Party > 1, Party := 1][Strategy > 1, Strategy := 1][Thematic > 1, Thematic := 1][War > 1, War := 1]
major_category_flags[is.na(major_category_flags)] <- 0
major_category_flags[, c("Abstract", "Children's", "Customizable", "Family", "Party", "Strategy", "Thematic", "War") := lapply(.SD, as.integer), .SDcols = c("Abstract", "Children's", "Customizable", "Family", "Party", "Strategy", "Thematic", "War")]

# Remove expansion games and create user stats
user_stats <- user_ratings[!(GAME_ID %in% expansions), .(GAMES = .N, AVERAGE_RATING = mean(USER_RATING), SD_RATING = sd(USER_RATING), MEDIAN_RATING = median(USER_RATING), MIN_RATING=min(USER_RATING), MAX_RATING=max(USER_RATING)), by = USERNAME]
user_stats[, RATING_RANGE:=MAX_RATING-MIN_RATING]

# merge user stats with ratings to set recommendation flags
user_recommendations <- merge(user_ratings, user_stats, by = "USERNAME")[, `:=`(RECOMMEND = 0, STRONGLY_RECOMMEND = 0, FLAT_RECOMMEND = 0)]
user_recommendations[USER_RATING >= 7, FLAT_RECOMMEND := 1][USER_RATING >= AVERAGE_RATING, RECOMMEND := 1][USER_RATING >= AVERAGE_RATING + SD_RATING, STRONGLY_RECOMMEND := 1]
user_recommendations[, NORMALIZED_RATING := (USER_RATING-AVERAGE_RATING)/RATING_RANGE]

# set final recommendation logic
user_recommendations[, FINAL_RECOMMENDATION:=0][FLAT_RECOMMEND == 1 | STRONGLY_RECOMMEND == 1, FINAL_RECOMMENDATION := 1]

# Create user matrix for Cosine Similarity
user_matrix <- as.matrix(dcast(user_recommendations, GAME_ID~USERNAME, value.var = "USER_RATING", mean, fill = 0)[, -c("GAME_ID")])
user <- lsa::cosine(user_matrix)

# Create top 25 most similar users for each user
users <- nrow(user) - 1
user_list <- colnames(user)
user.dt <- data.table(user)
user_long <- melt(cbind(USERNAME = user_list ,user.dt), id.vars = "USERNAME")
user_long <- user_long[USERNAME!=variable,]
setkey(user_long, key = "USERNAME")
top_25 <- user_long[value > 0, .SD[value %in% tail(sort(unique(value)), 25)], by=USERNAME]

# Cleaning up
rm(users, user_list, user.dt, user_matrix, ranks)

# select target user 
set.seed(12345)
target_user <- "Lythari311"

#####-- Setting up a small prediction --#####

train_percent <- 2/3

# Setting up game lists for training and testing
target_game_list <- unique(user_recommendations[USERNAME == target_user & !(GAME_ID %in% expansions), GAME_ID])
train_rows <- floor(length(target_game_list) * train_percent)
# train_rows <- floor(nrow(user_stats) * train_percent)
train_game_list <- unique(user_recommendations[USERNAME == target_user & !(GAME_ID %in% expansions), ][sample(.N, train_rows), GAME_ID])
test_game_list <- unique(user_recommendations[USERNAME == target_user & !(GAME_ID %in% train_game_list) & !(GAME_ID %in% expansions), GAME_ID])

# Setting up Data structure
similar_users <- top_25[USERNAME == target_user,]
user_similarity_data <-merge(user_recommendations[USERNAME %in% similar_users$variable & GAME_ID %in% target_game_list,], similar_users[, c("variable", "value")], by.x = "USERNAME", by.y = "variable")

user_game_meta <- merge(user_similarity_data[, .(RECOMMENDATION = sum(FINAL_RECOMMENDATION), WEIGHTED_RECOMMENDATION = sum(FINAL_RECOMMENDATION * value)), by = "GAME_ID"], dcast(user_similarity_data, GAME_ID~USERNAME, value.var = "FINAL_RECOMMENDATION"), by = "GAME_ID")
user_game_meta <- merge(user_game_meta, major_category_flags, by = "GAME_ID", all.x = T)

game_data <- dim_games[GAME_ID %in% target_game_list, c("GAME_ID", "MIN_PLAYERS", "MAX_PLAYERS", "PLAY_TIME", "NUMBER_OF_RATINGS", "AVERAGE_RATING", "GEEK_SCORE", "ST_DEV", "OWNED", "TRADING", "WANTING", "WISHING", "NUMBER_OF_COMMENTS", "NUMBER_OF_WEIGHTS", "AVERAGE_WEIGHT")]

full_data <- merge(game_data, user_game_meta, all.x = TRUE, by = "GAME_ID")
full_data[is.na(full_data)] <- 0

# Final Data Prep
full_data[, c("MIN_PLAYERS", "MAX_PLAYERS", "PLAY_TIME", "NUMBER_OF_RATINGS", "OWNED", "TRADING", "WANTING", "WISHING", "NUMBER_OF_COMMENTS", "NUMBER_OF_WEIGHTS") := lapply(.SD, as.numeric), .SDcols = c("MIN_PLAYERS", "MAX_PLAYERS", "PLAY_TIME", "NUMBER_OF_RATINGS", "OWNED", "TRADING", "WANTING", "WISHING", "NUMBER_OF_COMMENTS", "NUMBER_OF_WEIGHTS")]
full_data[, `:=`(DESIRED = WANTING + WISHING, COMMENTS_RATING_RATIO = NUMBER_OF_COMMENTS/NUMBER_OF_RATINGS)]
full_data[, c("WANTING", "WISHING", "NUMBER_OF_COMMENTS")] <- NULL

# Setting up training data
train_data <- merge(full_data[GAME_ID %in% train_game_list, ], user_recommendations[USERNAME == target_user, c("GAME_ID", "FINAL_RECOMMENDATION")], by = "GAME_ID")
test_data <- merge(full_data[GAME_ID %in% test_game_list, ], user_recommendations[USERNAME == target_user, c("GAME_ID", "FINAL_RECOMMENDATION")], by = "GAME_ID")

dtrain <- xgb.DMatrix(data = as.matrix(train_data[, -c("GAME_ID", "FINAL_RECOMMENDATION")]), label = as.matrix(train_data[, FINAL_RECOMMENDATION])) 
dtest <- xgb.DMatrix(data = as.matrix(test_data[, -c("GAME_ID", "FINAL_RECOMMENDATION")]), label = as.matrix(test_data[, FINAL_RECOMMENDATION])) 

watchlist <- list(train = dtrain, test = dtest)

xgb_split_model <- xgb.train(data = dtrain,
                             max.depth = 10,
                             eta = .3,
                             nthread = 2,
                             nround = 5,
                             watchlist = watchlist,
                             eval.metric = "error",
                             eval.metric = "logloss",
                             objective = "binary:logistic")

pred <- predict(xgb_split_model, dtest)

test_prediction <- cbind(test_data, pred)
test_prediction[, PREDICTION:=0][pred >= .8, PREDICTION:=1]
prediction_stats <- list(wrong = test_prediction[FINAL_RECOMMENDATION != PREDICTION, .N],
                         error = test_prediction[FINAL_RECOMMENDATION != PREDICTION, .N]/nrow(test_prediction),
                         true_positive = test_prediction[FINAL_RECOMMENDATION == PREDICTION & PREDICTION == 1, .N]/test_prediction[PREDICTION == 1, .N],
                         true_negative = test_prediction[FINAL_RECOMMENDATION == PREDICTION & PREDICTION == 0, .N]/test_prediction[PREDICTION == 0, .N]
                         
)
prediction_stats

feature_importance <- xgb.importance(feature_names = colnames(train_data[, -c("GAME_ID", "FINAL_RECOMMENDATION")]), model = xgb_split_model)
feature_importance

#####-- Setting up full training data --#####

# Find users who have no new recommendations
similar_users <- top_25[USERNAME == target_user,]
target_game_list <- unique(user_recommendations[USERNAME == target_user & !(GAME_ID %in% expansions), GAME_ID])

user_similarity_data <-merge(user_recommendations[USERNAME %in% similar_users$variable & GAME_ID %in% target_game_list,], similar_users[, c("variable", "value")], by.x = "USERNAME", by.y = "variable")
user_game_meta <- merge(user_similarity_data[, .(RECOMMENDATION = sum(FINAL_RECOMMENDATION), WEIGHTED_RECOMMENDATION = sum(FINAL_RECOMMENDATION * value)), by = "GAME_ID"], dcast(user_similarity_data, GAME_ID~USERNAME, value.var = "FINAL_RECOMMENDATION", mean), by = "GAME_ID")
user_game_meta <- merge(user_game_meta, major_category_flags, all.x = TRUE, by = "GAME_ID")

game_data <- dim_games[GAME_ID %in% target_game_list , c("GAME_ID", "MIN_PLAYERS", "MAX_PLAYERS", "PLAY_TIME", "NUMBER_OF_RATINGS", "AVERAGE_RATING", "GEEK_SCORE", "ST_DEV", "OWNED", "TRADING", "WANTING", "WISHING", "NUMBER_OF_COMMENTS", "NUMBER_OF_WEIGHTS", "AVERAGE_WEIGHT")]

full_data <- merge(game_data, user_game_meta, all.x = TRUE, by = "GAME_ID")
full_data[, c("MIN_PLAYERS", "MAX_PLAYERS", "PLAY_TIME", "NUMBER_OF_RATINGS", "OWNED", "TRADING", "WANTING", "WISHING", "NUMBER_OF_COMMENTS", "NUMBER_OF_WEIGHTS") := lapply(.SD, as.numeric), .SDcols = c("MIN_PLAYERS", "MAX_PLAYERS", "PLAY_TIME", "NUMBER_OF_RATINGS", "OWNED", "TRADING", "WANTING", "WISHING", "NUMBER_OF_COMMENTS", "NUMBER_OF_WEIGHTS")]
full_data[, `:=`(DESIRED = WANTING + WISHING, COMMENTS_RATING_RATIO = NUMBER_OF_COMMENTS/NUMBER_OF_RATINGS)]
full_data[, c("WANTING", "WISHING", "NUMBER_OF_COMMENTS")] <- NULL
full_data[is.na(full_data)] <- 0

full_train_data <- merge(full_data, user_recommendations[USERNAME == target_user, c("GAME_ID", "FINAL_RECOMMENDATION")], by = "GAME_ID")
dfull_train <- xgb.DMatrix(data = as.matrix(full_train_data[, -c("GAME_ID", "FINAL_RECOMMENDATION")]), label = as.matrix(full_train_data[, FINAL_RECOMMENDATION])) 

xgb_full_model <- xgb.train(data = dfull_train,
                            max.depth = 10,
                            eta = .3,
                            nthread = 2,
                            nround = 5,
                            eval.metric = "error",
                            eval.metric = "logloss",
                            objective = "binary:logistic")


#####-- Setting up new games to predict on --#####

# Create list of similar users
similar_user_games <- user_recommendations[USERNAME %in% similar_users$variable & !(GAME_ID %in% target_game_list), GAME_ID]
# Create list of new games
new_games <- user_recommendations[GAME_ID %in% similar_user_games & !(GAME_ID %in% expansions), .(RATINGS = .N), by = "GAME_ID"][RATINGS > 10, GAME_ID]

new_user_similarity_data <-merge(user_recommendations[USERNAME %in% similar_users$variable & GAME_ID %in% new_games,], similar_users[, c("variable", "value")], by.x = "USERNAME", by.y = "variable")
new_user_game_meta <- merge(new_user_similarity_data[, .(RECOMMENDATION = sum(FINAL_RECOMMENDATION), WEIGHTED_RECOMMENDATION = sum(FINAL_RECOMMENDATION * value)), by = "GAME_ID"], dcast(new_user_similarity_data, GAME_ID~USERNAME, value.var = "FINAL_RECOMMENDATION", mean), by = "GAME_ID")
new_user_game_meta <- merge(new_user_game_meta, major_category_flags, all.x = TRUE, by = "GAME_ID")

new_game_data <- dim_games[GAME_ID %in% new_games , c("GAME_ID", "MIN_PLAYERS", "MAX_PLAYERS", "PLAY_TIME", "NUMBER_OF_RATINGS", "AVERAGE_RATING", "GEEK_SCORE", "ST_DEV", "OWNED", "TRADING", "WANTING", "WISHING", "NUMBER_OF_COMMENTS", "NUMBER_OF_WEIGHTS", "AVERAGE_WEIGHT")]

new_full_data <- merge(new_game_data, new_user_game_meta, all.x = TRUE, by = "GAME_ID")
new_full_data[, c("MIN_PLAYERS", "MAX_PLAYERS", "PLAY_TIME", "NUMBER_OF_RATINGS", "OWNED", "TRADING", "WANTING", "WISHING", "NUMBER_OF_COMMENTS", "NUMBER_OF_WEIGHTS") := lapply(.SD, as.numeric), .SDcols = c("MIN_PLAYERS", "MAX_PLAYERS", "PLAY_TIME", "NUMBER_OF_RATINGS", "OWNED", "TRADING", "WANTING", "WISHING", "NUMBER_OF_COMMENTS", "NUMBER_OF_WEIGHTS")]
new_full_data[, `:=`(DESIRED = WANTING + WISHING, COMMENTS_RATING_RATIO = NUMBER_OF_COMMENTS/NUMBER_OF_RATINGS)]
new_full_data[, c("WANTING", "WISHING", "NUMBER_OF_COMMENTS")] <- NULL
# Check for missing similar users
missing <- setdiff(xgb_full_model$feature_names, colnames(new_full_data))
# add the missing users if any exist.
if( length(missing) > 0) {new_full_data[, (missing) := 0]}
new_full_data[is.na(new_full_data)] <- 0
# reorder the columns
setcolorder(new_full_data, xgb_full_model$feature_names)

# Create matrix for new games
dnew <- xgb.DMatrix(data = as.matrix(new_full_data[, -c("GAME_ID")]))

# Predict which new games should be recommended.
new_pred <- predict(xgb_full_model, dnew)
new_prediction <- cbind(new_full_data, new_pred)
new_feature_importance = xgb.importance(feature_names = colnames(train_data[, -c("GAME_ID", "FINAL_RECOMMENDATION")]), model = xgb_full_model)

new_prediction <- merge(new_prediction, dim_games[, c("GAME_ID", "BOARD_GAME")], by = "GAME_ID")
new_pred_simple <- new_prediction[, c("GAME_ID", "BOARD_GAME", "new_pred", "WEIGHTED_RECOMMENDATION")]
setorderv(new_pred_simple, c("new_pred", "WEIGHTED_RECOMMENDATION"), c(-1,-1))
head(new_pred_simple, 10)
# user_recommendations[USERNAME == target_user & !(GAME_ID %in% game_data$ID), ]

# train_user <- user_stats[sample(.N, train_rows), USERNAME]
# match("deniedpluto", train_user) # check if Deniedpluto is in the list of users
# esquisse::esquisser(user_recommendations)

