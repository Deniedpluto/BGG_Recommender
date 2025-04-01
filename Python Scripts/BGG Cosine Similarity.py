import duckdb
import polars as pl
import yaml
import numpy as np
from sklearn.metrics.pairwise import cosine_similarity as cs

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
users = pl.DataFrame(con.sql("SELECT username FROM BGG.User_Refresh"))

# Define cutpoint for when a rating is considered a recommendation
cutpoint = 7
ratings = ratings.with_columns(pl.when(pl.col("rating") >= cutpoint).then(1).otherwise(0).alias("recommendation"))

'''
# Select a username to calculate cosine similarity
username = users['username'][0]

# Pull the user's game list
gamelist = ratings.filter(ratings['username'] == username).select('game_id')

# Create base data for the cosine similarity
base_data = ratings.filter(ratings["game_id"].is_in(gamelist["game_id"])).select("game_id", "username", "rating")
'''

def related_user_ratings(username):
    # Pull the user's game list
    gamelist = ratings.filter(ratings['username'] == username).select('game_id')

    # Create base data for the cosine similarity
    base_data = ratings.filter(ratings["game_id"].is_in(gamelist["game_id"])).select("game_id", "username", "rating", "recommendation")
    
    # Filter the base data to include only the specified user and other users who have rated the same games
    intersection = (duckdb.sql("""
WITH db as (FROM base_data)
FROM db target, db other
SELECT target.username              base_user
      ,other.username               comp_user
      ,list(other.game_id)          common_games
      ,count(other.game_id)         common_games_frequency
      ,list(target.recommendation)  base_user_recs
      ,list(other.recommendation)   comp_user_recs
      ,list(target.rating)          base_user_ratings
      ,list(other.rating)           comp_user_ratings
WHERE base_user = '"""+username+"""' 
  AND comp_user != '"""+username+"""'
  AND target.game_id = other.game_id
  --AND other.username NOT IN ('"""+completed_users+"""')
GROUP BY base_user, comp_user""").pl()
    )
    return intersection

# Iterate through the users and pull the list of all potentially similar users
user_similarity = pl.DataFrame()
completed_users = str()
for user in users['username']:
    user_similarity = user_similarity.vstack(related_user_ratings(user))
    if completed_users == "":
        completed_users = user
    else:
        completed_users = completed_users+"', '"+user
    # print(user)
user_similarity.rechunk()

similarity_scores = []
for row in range(len(user_similarity)):
    # Get the two arrays of ratings for the two users
    x = user_similarity.select(pl.col("base_user_recs"))[row].to_numpy()[0]
    x = np.array([float(item) for item in x[0]]).reshape(1, -1)
    y = user_similarity.select(pl.col("comp_user_recs"))[row].to_numpy()[0]
    y = np.array([float(item) for item in y[0]]).reshape(1, -1)

    # Calculate the cosine similarity between the two users
    similarity_scores.append(cs(x, y)[0][0])

# Add the new similarity score column to the user_similarity DataFrame
user_similarity = user_similarity.with_columns(pl.DataFrame({"similarity_score": similarity_scores}))

# Write the user correlation table to motherduck
con.sql("CREATE OR REPLACE TABLE BGG.User_Similarity AS SELECT base_user, comp_user, common_games, common_games_frequency::INT64 AS common_games_count, base_user_recs, comp_user_recs, base_user_ratings, comp_user_ratings, similarity_score::float AS cosine_similarity FROM user_similarity")

'''
# Pivot the base data to create a user-item matrix
pivot_data = base_data.pivot("username", index="game_id", values="rating", aggregate_function="first")

# Convert pivot to scipy sparse matrix
np_array = pivot_data.select(pivot_data.columns[1:]) #.to_numpy()
sp_matrix = scipy.sparse.csr_matrix(np_array)
cs_matrix = cs()

base_data.filter(base_data.is_duplicated()==True)
base_data.select("game_id", "username").filter(base_data.is_duplicated()==True)

base_data.filter(base_data["username"] == "gameguru", base_data["game_id"] == "320")'
'''