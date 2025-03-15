#####-- Initial Setup --######

# Load Libraries
library(data.table)
library(xml2)
library(shiny)
library(DT)
library(rstudioapi)

# Set path to script location
setwd(dirname(getActiveDocumentContext()$path))

# Load in base data
user_ratings <- fread("user_ratings.csv")
dim_games <- fread("dim_games.csv")
game_attributes <- fread("game_attributes.csv")
user_refresh <- fread("user_refresh.csv")
user_similarity <- fread("user_similarity.csv")


# Define UI --------------------------------------------------------------------
ui <- fluidPage(
  
  title = "Board Game Geek Collector",
  
  fluidRow(
    column(width = 2,
           textInput(
             inputId = "username",
             label = "BGG Username",
             value = "BGG Username"
           )
    ),
    column(width = 1,
           br(),
           actionButton(
             inputId = "check",
             label = "Check Username"
           )
    ),
    column(width = 3),
    # column(width = 1,
    #        br(),
    #        actionButton(
    #          inputId = "seeit",
    #          label = "View on BGG",
    #          icon = icon("th"),
    #          onclick = "window.open('https://boardgamegeek.com/user/deniedpluto', '_blank')"
    #        )
    # ),
    column(width = 1,
           br(),
           actionButton(
             inputId = "pullreviews",
             label = "Pull Reviews"
           )
    ),
    column(width = 1,
           br(),
           actionButton(
             inputId = "reloaduser",
             label = "Reload User"
           )
    ),
    column(width = 1,
           br(),
           actionButton(
             inputId = "refreshreviews",
             label = "Refresh Reviews"
           )
    ),
    column(width = 1,
           br(),
           actionButton(
             inputId = "lsacosine",
             label = "Compute Similarity"
           )
    ),
    column(width = 1,
           br(),
           actionButton(
             inputId = "checkgames",
             label = "Check Games"
           )
    ),
    column(width = 1,
           br(),
           actionButton(
             inputId = "newgames",
             label = "Pull New Games"
           )
    )
  ),
  fluidRow(
    column(width = 6,
           br(),
           textOutput(outputId = "checkout")
    ),
    
    column(width = 3,
           br(),
           textOutput(outputId = "checkreviews")
    ),
    column(width = 1,
           br(),
           textOutput(outputId = "similarity")
    ),
    column(width = 2,
           br(),
           textOutput(outputId = "missinggames")
    )
  ),
  fluidRow(
    column(width= 3,
           br(),
           br(),
           dataTableOutput(outputId = "userrefresh")
    ),
    column(width = 3,
           br(),
           br(),
           dataTableOutput(outputId = "userratings")
    ),
    column(width = 3,
           br(),
           br(),
           dataTableOutput(outputId = "usersimilarity")
    )
  )
)

# Define server ----------------------------------------------------------------

server <- function(input, output, session) {
  
  username <- reactive({input$username})
  
  observeEvent(input$username, {
    # updateActionButton(session,
    #                   inputId = "seeit",
    #                   onclick = paste0("window.open('https://boardgamegeek.com/user/'", input$username, ", '_blank')")
    # )
    output$checkout <- renderText("")
    output$checkreviews <- renderText("")
    output$missinggames <- renderText("")
    output$similarity <- renderText("")
  })
  
  
  #####-- Check Username --#####
  observeEvent(input$check, {
    if(length(grep(" ", input$username))>0) {
      output$checkout = renderText("Do you have a space in the username? Cut that out!")
      updateTextInput(session, "username", value = gsub(" ", "%20", input$username))
    } else if(length(grep("Invalid username", as.character(xml_find_all(read_xml(paste0(
      "https://www.boardgamegeek.com/xmlapi2/collection?username=", input$username, "&rated=1&stats=1&brief=1")), "//message")))) == 0) {
      output$checkout <- renderText(paste0("Username ", input$username, " checks out!"))
    } else {
      output$checkout <- renderText(paste0("Are you sure you spelled that right? It appears ", input$username, " is not in the system"))
    }
  })
  
  #####-- Pull Reviews --#####
  observeEvent(input$pullreviews, {
    
    if(input$username %in% user_ratings[, USERNAME]) {
      
      output$checkreviews <- renderText(paste0("Reviews already have been pulled for ", input$username, ".
                                               To reload user reviews click \"Reload User\""))
      
    } else if(length(grep("Invalid username", as.character(xml_find_all(read_xml(paste0(
      "https://www.boardgamegeek.com/xmlapi2/collection?username=", input$username, "&rated=1&stats=1&brief=1")), "//message")))) != 0) {
      
      output$checkreviews <- renderText(paste0("Username ", input$username, " does not exist. Are you sure you checked it?"))
      
    } else {
      
      output$checkreviews <- renderText(paste0("Pulling reivews for user: ", input$username))
      
      bgg_api <- paste0("https://www.boardgamegeek.com/xmlapi2/collection?username=", input$username, "&rated=1&stats=1&brief=1")
      
      read_xml(bgg_api)
      n <- 1L
      while(n < 10) {
        Sys.sleep(3 * n)
        print(paste("waited", 3 * n, "seconds"))
        n <- n + 1
        if(length(xml_find_all(read_xml(bgg_api), "//message")) == 0) {
          bgg_data <- read_xml(bgg_api)
          break
        }
      }
      
      items <- xml_find_all(bgg_data, "//items")
      number_of_reviews <- as.integer(xml_attr(bgg_data, "totalitems"))
      pub_date <- xml_attr(bgg_data, "pubdate")
      
      if(number_of_reviews > 0) {
        reviews <- data.table(username = as.character(), game_id = as.integer(), rating = as.numeric(), comments = as.character())
        n = 1L
        for(n in 1:number_of_reviews) {
          current_item <- xml_children(items)[n]
          
          temp <- data.table(
            username = input$username,
            game_id = as.integer(xml_attr(current_item, "objectid")),
            rating = as.numeric(xml_attr(xml_find_all(current_item, ".//rating"), "value")),
            comments = gsub("</comment>", "", gsub("<comment>", "", as.character(xml_find_all(current_item, ".//comment"))))
          )
          
          reviews <- rbind(reviews, temp)
        }
        user_ratings <- rbind(user_ratings, reviews)
        fwrite(user_ratings, "user_ratings.csv")
        

        reviews_pulled <- data.table(USERNAME = input$username, LAST_REFRESH_DATE = pub_date)
        user_refresh <- rbind(user_refresh, reviews_pulled)
        fwrite(user_refresh, "user_refresh.csv")
        
        output$checkreviews <- renderText(paste0(number_of_reviews, " Reviews updated for ", input$username, ". Smack that refresh reviews button!"))
        
      } else {
        output$checkreviews <- renderText(paste0(input$username, " has no reviews... rip the dream :("))
      }
    }
  })
  
  #####-- Reload User Data --#####
  observeEvent(input$reloaduser, {
    browser()
    if(length(grep("Invalid username", as.character(xml_find_all(read_xml(paste0(
      "https://www.boardgamegeek.com/xmlapi2/collection?username=", input$username, "&rated=1&stats=1&brief=1")), "//message")))) != 0) {
      
      output$checkreviews <- renderText(paste0("Username ", input$username, " does not exist. Are you sure you checked it?"))
      
    } else {
      
      user_refresh <- user_refresh[USERNAME != input$username, ]
      user_ratings <- user_ratings[USERNAME != input$username, ]

      output$checkreviews <- renderText(paste0("Pulling reivews for user: ", input$username))
      
      bgg_api <- paste0("https://www.boardgamegeek.com/xmlapi2/collection?username=", input$username, "&rated=1&stats=1&brief=1")
      
      read_xml(bgg_api)
      n <- 1L
      while(n < 10) {
        Sys.sleep(3 * n)
        print(paste("waited", 3 * n, "seconds"))
        n <- n + 1
        if(length(xml_find_all(read_xml(bgg_api), "//message")) == 0) {
          bgg_data <- read_xml(bgg_api)
          break
        }
      }
      
      items <- xml_find_all(bgg_data, "//items")
      number_of_reviews <- as.integer(xml_attr(bgg_data, "totalitems"))
      pub_date <- xml_attr(bgg_data, "pubdate")
      
      if(number_of_reviews > 0) {
        reviews <- data.table(username = as.character(), game_id = as.integer(), rating = as.numeric(), comments = as.character())
        n = 1L
        for(n in 1:number_of_reviews) {
          current_item <- xml_children(items)[n]
          
          temp <- data.table(
            username = input$username,
            game_id = as.integer(xml_attr(current_item, "objectid")),
            rating = as.numeric(xml_attr(xml_find_all(current_item, ".//rating"), "value")),
            comments = gsub("</comment>", "", gsub("<comment>", "", as.character(xml_find_all(current_item, ".//comment"))))
          )
          
          reviews <- rbind(reviews, temp)
        }
        
        user_ratings <- rbind(user_ratings, reviews)
        fwrite(user_ratings, "user_ratings.csv")
        
        reviews_pulled <- data.table(USERNAME = input$username, LAST_REFRESH_DATE = pub_date)
        user_refresh <- rbind(user_refresh, reviews_pulled)
        fwrite(user_refresh, "user_refresh.csv")
        
        output$checkreviews <- renderText(paste0(number_of_reviews, " Reviews reloaded for ", input$username, "!"))
        
      } else {
        output$checkreviews <- renderText(paste0(input$username, " has no reviews... rip the dream :("))
      }
    }
  })
  
  #####-- Refreshing Reviews --#####
  
  observeEvent(input$refreshreviews, {
    
    user_refresh <- fread("user_refresh.csv")
    user_ratings <- fread("user_ratings.csv")
    
    output$userrefresh <- renderDataTable(
      datatable(user_refresh,
                caption = htmltools::tags$caption("User Refresh", style = 'text-align: center; font-size: 24px; font-family: Times New Roman; color: black'),
                options = list(scrollX = TRUE)
                # ,rownames = FALSE
      )
    )
    
    output$userratings <- renderDataTable(
      datatable(user_ratings[, .(`Games Rated` = .N), by = USERNAME],
                caption = htmltools::tags$caption("User Ratings", style = 'text-align: center; font-size: 24px; font-family: Times New Roman; color: black'),
                options = list(scrollX = TRUE)
                # ,rownames = FALSE
      )
    )
  })
  
  #####-- Compute Similarity  --#####
  observeEvent(input$lsacosine, {
    
    user_ratings <- fread("user_ratings.csv")
    
    user_matrix <- as.matrix(dcast(user_ratings, GAME_ID~USERNAME, value.var = "USER_RATING", mean, fill = 0)[, -c("GAME_ID")])
    user <- lsa::cosine(user_matrix)
    user_list <- colnames(user)
    user.dt <- data.table(user)
    user_long <- melt(cbind(USERNAME = user_list ,user.dt), id.vars = "USERNAME")
    user_long <- user_long[USERNAME!=variable,]
    setkey(user_long, key = "USERNAME")
    top_25 <- user_long[value > 0, .SD[value %in% tail(sort(unique(value)), 25)], by=USERNAME]
    setnames(top_25, c("Username", "Related User", "Similarity"))
    
    fwrite(top_25, "user_similarity.csv")
    
    output$similarity <- renderText("Done.")
    
    output$usersimilarity <- renderDataTable(
      datatable(top_25,
                caption = htmltools::tags$caption("User Similarity", style = 'text-align: center; font-size: 24px; font-family: Times New Roman; color: black'),
                options = list(scrollX = TRUE),
                rownames = FALSE
      )
    )
  })
  
  #####-- Check Games --#####
  observeEvent(input$checkgames, {
    user_ratings <- fread("user_ratings.csv")
    dim_games <- fread("dim_games.csv")
    new_games <- data.table(GAME_ID = setdiff(user_ratings[, GAME_ID], dim_games[, GAME_ID]))
    
    missing_games <- nrow(new_games[GAME_ID != 28531])
    output$missinggames = renderText(paste0("There are currently ", missing_games, " missing games."))
  })
  
  #####-- Pull New Games --#####
  observeEvent(input$newgames, {
    user_ratings <- fread("user_ratings.csv")
    dim_games <- fread("dim_games.csv")
    new_games <- setdiff(user_ratings[, GAME_ID], dim_games[, GAME_ID])
    
    API_CALL <- gsub(" ", "", paste0("https://www.boardgamegeek.com/xmlapi2/thing?id=", toString(new_games), "&stats=1"))
    
    xml_data <- read_xml(API_CALL)        
    games <- xml_find_all(xml_data, "//item")
    number_of_games <- length(games)
    game_attributes_empty <- data.table(GAME_ID = integer(), ATTRIBUTE_TYPE = character(), ATTRIBUTE_ID = integer(), ATTRIBUTE = character())
    dim_games_empty <- data.table( GAME_ID = numeric(), BOARD_GAME = character(), DESCRIPTION = character(), YEAR_PUBLISHED = numeric(), MIN_PLAYERS = numeric(), MAX_PLAYERS = numeric(), PLAY_TIME = numeric(), MIN_PLAY_TIME = numeric(), MAX_PLAY_TIME = numeric(), MIN_AGE = numeric(), THUMBNAIL = character(), IMAGE = character(), URL = character(), NUMBER_OF_RATINGS = numeric(), AVERAGE_RATING = numeric(), GEEK_SCORE = numeric(), ST_DEV = numeric(), OWNDED = numeric(), TRADING = numeric(), WANTING = numeric(), WISHING = numeric(), NUMBER_OF_COMMENTS = numeric(), NUMBER_OF_WEIGHTS = numeric(), AVERAGE_WEIGHT = numeric())
    n <- 1L
    for(n in 1:number_of_games) {
      current_game <- games[[n]]
      game_id <- xml_attr(current_game, "id")
      
      # Game Attributes and Ranks
      attributes <- xml_find_all(current_game, "link")
      game_attributes_temp <- data.table(
        GAME_ID = game_id,  
        ATTRIBUTE_TYPE = xml_attr(attributes, "type"), 
        ATTRIBUTE_ID = xml_attr(attributes, "id"), 
        ATTRIBUTE = xml_attr(attributes, "value")
      )
      
      ranks <- xml_find_all(current_game, ".//rank")
      ranks_temp <- data.table(
        GAME_ID = game_id,  
        ATTRIBUTE_TYPE = xml_attr(ranks, "friendlyname"), 
        ATTRIBUTE_ID = xml_attr(ranks, "id"), 
        ATTRIBUTE = xml_attr(ranks, "value")
      )
      
      game_attributes_empty <- rbind(game_attributes_empty, game_attributes_temp, ranks_temp)
      
      # Game Stats and Info
      
      stats <- xml_find_all(current_game, ".//ratings")
      game_list <- as_list(current_game)
      
      dim_games_temp <- data.table(
        GAME_ID = game_id,
        BOARD_GAME = xml_attr(xml_find_first(current_game, "name"), "value"),
        DESCRIPTION = unlist(game_list$description),
        YEAR_PUBLISHED = xml_attr(xml_find_first(current_game, "yearpublished"), "value"),
        MIN_PLAYERS = xml_attr(xml_find_first(current_game, "minplayers"), "value"),
        MAX_PLAYERS = xml_attr(xml_find_first(current_game, "maxplayers"), "value"),
        PLAY_TIME = xml_attr(xml_find_first(current_game, "playingtime"), "value"),
        MIN_PLAY_TIME = xml_attr(xml_find_first(current_game, "minplaytime"), "value"),
        MAX_PLAY_TIME = xml_attr(xml_find_first(current_game, "maxplaytime"), "value"),
        MIN_AGE = xml_attr(xml_find_first(current_game, "minage"), "value"),
        THUMBNAIL = unlist(game_list$thumbnail),
        IMAGE = unlist(game_list$image),
        URL = paste0("https://www.boardgamegeek.com/boardgame/", game_id),
        NUMBER_OF_RATINGS = xml_attr(xml_find_first(stats, "usersrated"), "value"),
        AVERAGE_RATING = xml_attr(xml_find_first(stats, "average"), "value"),
        GEEK_SCORE = xml_attr(xml_find_first(stats, "bayesaverage"), "value"),
        ST_DEV = xml_attr(xml_find_first(stats, "stddev"), "value"),
        OWNDED = xml_attr(xml_find_first(stats, "owned"), "value"),
        TRADING = xml_attr(xml_find_first(stats, "trading"), "value"),
        WANTING = xml_attr(xml_find_first(stats, "wanting"), "value"),
        WISHING = xml_attr(xml_find_first(stats, "wishing"), "value"),
        NUMBER_OF_COMMENTS = xml_attr(xml_find_first(stats, "numcomments"), "value"),
        NUMBER_OF_WEIGHTS = xml_attr(xml_find_first(stats, "numweights"), "value"),
        AVERAGE_WEIGHT = xml_attr(xml_find_first(stats, "averageweight"), "value")
      )
      
      dim_games_empty <- rbind(dim_games_empty, dim_games_temp, fill = TRUE)
    }
    
    game_attributes <- rbind(game_attributes, dim_games_empty)
    fwrite(game_attributes)
    
    new_dim_games[, c("GAME_ID", "MIN_PLAYERS", "MAX_PLAYERS", "PLAY_TIME", "MIN_PLAY_TIME", "MAX_PLAY_TIME", "MIN_AGE", "NUMBER_OF_RATINGS", "AVERAGE_RATING", "GEEK_SCORE", "ST_DEV", "OWNDED", "TRADING", "WANTING", "WISHING", "NUMBER_OF_COMMENTS", "NUMBER_OF_WEIGHTS","AVERAGE_WEIGHT") := lapply(.SD, as.numeric),
              .SDcols = c("GAME_ID", "MIN_PLAYERS", "MAX_PLAYERS", "PLAY_TIME", "MIN_PLAY_TIME", "MAX_PLAY_TIME", "MIN_AGE", "NUMBER_OF_RATINGS", "AVERAGE_RATING", "GEEK_SCORE", "ST_DEV", "OWNDED", "TRADING", "WANTING", "WISHING", "NUMBER_OF_COMMENTS", "NUMBER_OF_WEIGHTS","AVERAGE_WEIGHT")]
    new_dim_games[dim_games == "",] <- 0
    new_dim_games[is.na(dim_games), ] <- 0
    
    dim_games <- rbind(dim_games, dim_games_empty)
    fwrite(dim_games)
    
    output$missinggames = renderText("Missing games loaded!")
    
  })
  
  #####-- Displayed Tables --#####
  
  output$userrefresh <- renderDataTable(
    datatable(user_refresh,
              caption = htmltools::tags$caption("User Refresh", style = 'text-align: center; font-size: 24px; font-family: Times New Roman; color: black'),
              options = list(scrollX = TRUE, order = c(2, 'desc'))
              # ,rownames = FALSE
    )
  )
  
  output$userratings <- renderDataTable(
    datatable(user_ratings[, .(`Games Rated` = .N), by = USERNAME],
              caption = htmltools::tags$caption("User Ratings", style = 'text-align: center; font-size: 24px; font-family: Times New Roman; color: black'),
              options = list(scrollX = TRUE)
              # ,rownames = FALSE
    )
  )
  
  output$usersimilarity <- renderDataTable(
    datatable(user_similarity,
              caption = htmltools::tags$caption("User Similarity", style = 'text-align: center; font-size: 24px; font-family: Times New Roman; color: black'),
              options = list(scrollX = TRUE),
              rownames = FALSE
    )
  )
  
}

# Create a Shiny app object ----------------------------------------------------

shinyApp(ui = ui, server = server)
