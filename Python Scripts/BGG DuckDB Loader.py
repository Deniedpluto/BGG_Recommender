import duckdb
import polars as pl
import requests as req
import xmltodict as xtd
import yaml
import os

# Read in the token from the yaml file
mdt = yaml.safe_load(open('MDToken.yaml', 'r'))['token']

# Authenticate motherduck using token
con = duckdb.connect('md:?motherduck_token=' + mdt) 

# Attach database
con.sql("USE my_db")

# Read from motherduck
# con.sql("CREATE OR REPLACE TABLE MTG.CommanderDecksWRA AS SELECT * FROM 'Data/CommanderDecksWRA.csv'");
# con.sql("CREATE OR REPLACE TABLE MTG.CommanderHistory AS SELECT * FROM 'Data/CommanderHistory.csv'");



username = "deniedpluto"
url = "https://www.boardgamegeek.com/xmlapi2/collection?username=" + username + "&rated=1&stats=1"

r = req.get(url)

js = xtd.parse(r.content)

# This extracts the name of the first game in the collection
js["items"]["item"][0]["name"]["#text"]
# This extracts the game id of the first game in the collection
js["items"]["item"][0]["@objectid"]
# This extracts the rating of the first game in the collection
js["items"]["item"][0]["stats"]["rating"]["@value"]
# This extracts the comments and only works if there is a comment oterwise it erros
js["items"]["item"][4]["comment"]
