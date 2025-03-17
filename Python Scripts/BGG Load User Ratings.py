import duckdb
import polars as pl
import requests as req
import xmltodict as xtd
import yaml
import os
import pyarrow as pa
import time

# This function extracts the ratings from the xml file. It returns the username, bggid, rating, and comments.
# If there is no comment it will return an empty string.``
def extract_ratings(js):
    ratings = []
    for i in range(len(js["items"]["item"])):
        try:
            ratings.append([username, js["items"]["item"][i]["@objectid"], js["items"]["item"][i]["stats"]["rating"]["@value"], js["items"]["item"][i]["comment"]])
        except:
            ratings.append([username, js["items"]["item"][i]["@objectid"], js["items"]["item"][i]["stats"]["rating"]["@value"], ""])
    return ratings

def update_ratings(username):
    # Perform actions with each username
    print("Pulling data for "+ username)
    # username = users['USERNAME'][1] # "deniedpluto" is 214
    url = "https://www.boardgamegeek.com/xmlapi2/collection?username=" + username + "&rated=1&stats=1"

    # Pull the data from BGG - this requires two pulls. The first one will setup the request. Then you need to wait and repull.
    r = req.get(url)
    while r.status_code == 202:
        print("Request accepted. Waiting 5 seconds to repull.")
        time.sleep(5)
        r = req.get(url)
        print(r.status_code)
    if r.status_code != 200:
        raise Exception("Failed to fetch data from BGG. Status code: " + str(r.status_code))

    # Parse the xml file to a dictionary
    js = xtd.parse(r.content)

    # Check to see if an error message was returned
    if "items" in js:
        print(js["items"]["@totalitems"])
    else:
        print("Error: " + js["errors"]["error"]["message"])
        return

    # Get total items in the collection
    total_items = js["items"]["@totalitems"]

    # Convert the dictionary to a polars dataframe
    out = pl.DataFrame(extract_ratings(js), schema={"username": pl.String, "game_id": pl.String, "rating": pl.String, "comment":pl.String}, orient="row")

    # Convert the polars dataframe to an arrow table
    user_ratings = pa.table(out)

    # Write game ratings motherduck (drop old values for the user and insert new values)
    # con.sql("CREATE OR REPLACE TABLE BGG.User_Ratings AS SELECT * FROM user_ratings")
    con.sql("DELETE FROM BGG.User_Ratings WHERE username = '" + username + "'")
    con.sql("INSERT INTO BGG.User_Ratings SELECT * FROM user_ratings");
    print(total_items + " ratings for " + username + " have been updated.")

    # Get the date and time
    refreshed = pl.DataFrame({"username": username, "date": js["items"]["@pubdate"]}).with_columns( 
        pl.col("date").str.to_datetime("%a, %d %b %Y %H:%M:%S %z"))
    refreshed_table = pa.table(refreshed)

    # Write the date and time to motherduck (Delete old values for the user and insert new values)
    # con.sql("CREATE OR REPLACE TABLE BGG.User_Refresh AS SELECT username, CAST(date AS timestamp) AS date FROM refreshed_table")
    con.sql("DELETE FROM BGG.User_Refresh WHERE username = '" + username + "'")
    con.sql("INSERT INTO BGG.User_Refresh SELECT * FROM refreshed_table");
    print("Data for " + username + " has been updated.")
    time.sleep(5)


# Read in the token from the yaml file
mdt = yaml.safe_load(open('C:\\Users\\Matso\\source\\repos\\Deniedpluto\\BGG_Recommender\\Python Scripts\\MDToken.yaml', 'r'))['token']

# Authenticate motherduck using token
con = duckdb.connect('md:?motherduck_token=' + mdt) 

# Attach database
con.sql("USE my_db")

# Read from motherduck
users = pl.DataFrame(con.sql("SELECT * FROM BGG.User_Refresh"))
# con.sql("CREATE OR REPLACE TABLE MTG.CommanderDecksWRA AS SELECT * FROM 'Data/CommanderDecksWRA.csv'");
# con.sql("CREATE OR REPLACE TABLE MTG.CommanderHistory AS SELECT * FROM 'Data/CommanderHistory.csv'");

# Select a username and create the url for pulling collections
#i = 0
i += 1
username = users['USERNAME'][i] # "deniedpluto" is 214
print(username)
update_ratings(username)
# for username in users['USERNAME']:

for i in range(175, 213):
    username = users['USERNAME'][i]
    update_ratings(username)

''' This was used for testing and will eventually be removed mcghltlll bjjldlj,.jbgvld 
# This extracts the name of the first game in the collection
js["items"]["item"][0]["name"]["#text"]
# This extracts the game id of the first game in the collection
js["items"]["item"][0]["@objectid"]
# This extracts the rating of the first game in the collection
js["items"]["item"][0]["stats"]["rating"]["@value"]
# This extracts the comments and only works if there is a comment oterwise it erros
js["items"]["item"][4]["comment"]
'''