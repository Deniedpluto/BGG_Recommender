import duckdb
import polars as pl
import yaml

# Useful links: 
#   - Cosine Similarity: https://stackoverflow.com/questions/77567521/optimize-computation-of-similarity-scores-by-executing-native-polars-command-ins
#   - Collaborative Filtering: https://medium.com/@zhikaichen1999/user-and-item-based-collaborative-filtering-for-movie-recommendations-c3c4efdfd6ff

# Read in the token from the yaml file
mdt = yaml.safe_load(open('C:\\Users\\Matso\\source\\repos\\Deniedpluto\\BGG_Recommender\\Python Scripts\\MDToken.yaml', 'r'))['token']

# Authenticate motherduck using token
con = duckdb.connect('md:?motherduck_token=' + mdt) 

# Attach database
con.sql("USE my_db")

# Read from motherduck
ratings = pl.DataFrame(con.sql("SELECT username, game_id, rating FROM BGG.User_Ratings"))
ratings = ratings.with_columns(ratings["rating"].cast(pl.Decimal).alias("rating"))
# users = pl.DataFrame(con.sql("SELECT username FROM BGG.User_Refresh"))

# pivot the ratings table to create a user-item matrix
user_ratings = ratings.pivot(index = ['game_id'], columns = ['username'],
                            values = 'rating', aggregate_function="first")
# Grab the game ids and drop them from the userRatings table
game_ids = user_ratings.select('game_id')
user_ratings = user_ratings.drop('game_id')
# Calculate the pearson correlation between all users
user_corr = user_ratings.select(pl.corr(pl.all(),pl.col(c)).name.suffix("|" + c) for c in user_ratings.columns).unpivot()
# Split columns so that users are in separate columns, filter ot self-correlation, and drop nans
user_corr = user_corr.select(base_user=pl.col("variable").str.split("|").list.get(0),comp_user=pl.col("variable").str.split("|").list.get(1),corr=pl.col("value")).filter(pl.col("base_user") != pl.col("comp_user")).drop_nans()


# Write the user correlation table to motherduck
con.sql("CREATE OR REPLACE TABLE BGG.User_Correlation AS SELECT base_user, comp_user, corr::float AS correlation FROM user_corr")


# Setup for adding or replacing a single users correlation data.
# username = ''
# single_user_ratings = user_corr.filter(pl.col("base_user") == 'username')
# con.sql("DELETE FROM BGG.User_Correlation WHERE base_user = '" + username + "'")
# con.sql("INSERT INTO BGG.User_Correlation SELECT * FROM single_user_ratings");
    

# Create a user similarity matrix
# user_corr_matrix = user_ratings.select(pl.struct(pl.corr(pl.all(),pl.col(c))).alias(c) for c in user_ratings.columns).unpivot().unnest("value")

# Test for a single user
# user_corr.filter(pl.col("base_user") == 'deniedpluto').sort('corr', descending = True).head(10)


''' # This doesn't need to be run since this can be done in a SQL Query
    # This also uses pandas and is very slow and memory inefficient. I will likely replace this with similar polars code.

import pandas as pd
user_ratings = ratings.pivot(index = ['username'], columns = ['game_id'],
                            values = 'rating', aggregate_function="first").to_pandas()
user_ratings = user_ratings.set_index('username').astype(float)
user_corr_matrix = user_corr_matrix.to_pandas()
user_corr_matrix = user_corr_matrix.set_index('variable').astype(float)

def user_recommend_game(u, k, threshold, num_recommendations):
    # u = username of target user
    # k = number of similar users to consider
    # threshold = minimum similarity score to consider a user similar
    # num_recommendations = number of recommendations to return

    # Get the game ids that the target user has played
    target_played = user_ratings[user_ratings.index == u].dropna(axis = 1, how = 'all')
    # remove target user so that they are not amongst one of the similar users.
    user_corr_matrix.drop(index = u)
    # Return the top k (10) similar users
    k_Neighbours = user_corr_matrix[user_corr_matrix[u] > threshold][u].sort_values(ascending = False)[:k]
    target_not_played = user_ratings[user_ratings.index == u].dropna(axis = 1, how = 'all')
    target_not_played = user_ratings[user_ratings.index.isin(k_Neighbours.index)].dropna(axis = 1, how = 'all')
    # remove movies that the target user has watched.
    target_not_played.drop(target_played.columns, axis = 1, inplace = True, errors = 'ignore')
    
    games = target_not_played.columns
    recommended_game_list = []
    predicted_rating_list = []
    # calcualte mean rating for user u
    mu_u = user_ratings[user_ratings.index == u].T.mean()[u]

    for j in games:
        game_ratings = target_not_played
        rating_sum = 0
        similarity_sum = 0
        for v in game_ratings.index :
            # Get rating user v gave to movie j
            rating = game_ratings.loc[v][j]
            # Get Pearson Similarity score between user u and user v
            similarity = user_corr_matrix[u][v]
            if pd.isna(rating) == False:
                # calculate mean rating of user v
                mu_v = user_ratings[user_ratings.index == v].T.mean()[v]
                # calculate mean-centered rating
                mean_centered_rating = rating - mu_v
                rating_sum = rating_sum + similarity*mean_centered_rating
                similarity_sum = similarity_sum + similarity
        # Predict rating
        prediction_rating = mu_u + rating_sum/similarity_sum
        recommended_game_list.append(j)
        predicted_rating_list.append(prediction_rating)

    results = pd.DataFrame(list(zip(recommended_game_list, predicted_rating_list)), 
                          columns = ['game_id', 'predicted_rating']).sort_values('predicted_rating', ascending = False).head(num_recommendations)
    return results

user_recommend_game('deniedpluto', 10, 0.3, 15)
'''