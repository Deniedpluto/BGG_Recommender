import duckdb
import polars as pl
import pyarrow as pa
import yaml
from sklearn.metrics.pairwise import cosine_similarity as cs
import scipy.sparse

# Read in the token from the yaml file
mdt = yaml.safe_load(open('C:\\Users\\Matso\\source\\repos\\Deniedpluto\\BGG_Recommender\\Python Scripts\\MDToken.yaml', 'r'))['token']

# Authenticate motherduck using token
con = duckdb.connect('md:?motherduck_token=' + mdt) 

# Attach database
con.sql("USE my_db")

# Read from motherduck
ratings = pl.DataFrame(con.sql("SELECT * FROM BGG.User_Ratings"))
ratings = ratings.with_columns(ratings["rating"].cast(pl.Decimal).alias("rating"))
users = pl.DataFrame(con.sql("SELECT username FROM BGG.User_Refresh"))

# Select a username to calculate cosine similarity
username = users['username'][0]

# Pull the user's game list
gamelist = ratings.filter(ratings['username'] == username).select('game_id')

# Create base data for the cosine similarity
base_data = ratings.filter(ratings["game_id"].is_in(gamelist["game_id"])).select("game_id", "username", "rating")

# Pivot the base data to create a user-item matrix
pivot_data = base_data.pivot("game_id", index="username", values="rating", aggregate_function="first")

# Convert pivot to scipy sparse matrix
np_array = pivot_data.select(pivot_data.columns[1:]).to_numpy()
sp_matrix = scipy.sparse.csr_matrix(np_array)
cs_matrix = cs()

'''
base_data.filter(base_data.is_duplicated()==True)
base_data.select("game_id", "username").filter(base_data.is_duplicated()==True)

base_data.filter(base_data["username"] == "gameguru", base_data["game_id"] == "320")'
'''