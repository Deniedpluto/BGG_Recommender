import duckdb
import polars as pl
import xmltodict as xtd
import yaml
import os
import pyarrow as pa
import xml.etree.ElementTree as ET

# Setup all the functions for parsing the xml files
def xml_to_dataframe(file_path):
    # Parse the XML file
    tree = ET.parse(file_path)
    root = tree.getroot()

    # Prepare lists to store extracted data
    bggid = []
    names = []
    types = []
    descriptions = []
    years_published = []
    min_players = []
    max_players = []
    play_times = []
    min_play_times = []
    max_play_times = []
    min_ages = []
    thumbnail = []
    image = []
    usersrated = []
    average = []
    bayesaverage = []
    stddev = []
    median = []
    owned = []
    trading = []
    wanting = []
    wishing = []
    numcomments = []
    numweights = []
    averageweight = []

    # Iterate through each item in the XML
    for item in root.findall('.//item'):
        if item.get('type') in ('boardgame', 'boardgameexpansion'): # only do board games and expansions
            bggid.append(item.get('id'))
            types.append(item.get('type'))
            names.append(item.find('.//name[@type="primary"]').get('value'))
            descriptions.append(item.find('description').text)
            years_published.append(item.find('yearpublished').get('value'))
            min_players.append(item.find('minplayers').get('value'))
            max_players.append(item.find('maxplayers').get('value'))
            play_times.append(item.find('playingtime').get('value'))
            min_play_times.append(item.find('minplaytime').get('value'))
            max_play_times.append(item.find('maxplaytime').get('value'))
            min_ages.append(item.find('minage').get('value'))
            try: # Sometimes the thumbnail does not exist
                thumbnail.append(item.find('thumbnail').text)
            except AttributeError:
                thumbnail.append(None)
            try: # Sometimes the image does not exists
                image.append(item.find('image').text)
            except AttributeError:
                image.append(None)
            usersrated.append(item.find('.//usersrated').get('value'))
            average.append(item.find('.//average').get('value'))
            bayesaverage.append(item.find('.//bayesaverage').get('value'))
            stddev.append(item.find('.//stddev').get('value'))
            median.append(item.find('.//median').get('value'))
            owned.append(item.find('.//owned').get('value'))
            trading.append(item.find('.//trading').get('value'))
            wanting.append(item.find('.//wanting').get('value'))
            wishing.append(item.find('.//wishing').get('value'))
            numcomments.append(item.find('.//numcomments').get('value'))
            numweights.append(item.find('.//numweights').get('value'))
            averageweight.append(item.find('.//averageweight').get('value'))

    # Create a DataFrame
    df = pl.DataFrame({
        'bggid': bggid,
        'type': types,
        'name': names,
        'description': descriptions,
        'year_published': years_published,
        'min_players': min_players,
        'max_players': max_players,
        'play_time': play_times,
        'min_play_time': min_play_times,
        'max_play_time': max_play_times,
        'min_age': min_ages,
        'thumbnail': thumbnail,
        'image': image,
        'usersrated': usersrated,
        'average': average,
        'bayesaverage': bayesaverage,
        'stddev': stddev,
        'median': median,
        'owned': owned,
        'trading': trading,
        'wanting': wanting,
        'wishing': wishing,
        'numcomments': numcomments,
        'numweights': numweights,
        'averageweight': averageweight

    })

    return df;

def get_bggtags(file_path):
    # Parse the XML file
    tree = ET.parse(file_path)
    root = tree.getroot()

    # Prepare lists to store extracted data
    bggid = []
    tagtype = []
    tagvalue = []

    for item in root.findall('.//item'):
        if item.get('type') in ('boardgame', 'boardgameexpansion'):
        # Iterate through each item in the XML
            for i in range(len(item.findall('.//link[@type="boardgamecategory"]'))):
                bggid.append(item.get('id'))
                tagtype.append('boardgamecategory')
                tagvalue.append(item.findall('.//link[@type="boardgamecategory"]')[i].get('value'))
            for i in range(len(item.findall('.//link[@type="boardgamemechanic"]'))):
                bggid.append(item.get('id'))
                tagtype.append('boardgamemechanic')
                tagvalue.append(item.findall('.//link[@type="boardgamemechanic"]')[i].get('value'))
            for i in range(len(item.findall('.//link[@type="boardgamefamily"]'))):
                bggid.append(item.get('id'))
                tagtype.append('boardgamefamily')
                tagvalue.append(item.findall('.//link[@type="boardgamefamily"]')[i].get('value'))
            for i in range(len(item.findall('.//link[@type="boardgameartist"]'))):
                bggid.append(item.get('id'))
                tagtype.append('boardgameartist')
                tagvalue.append(item.findall('.//link[@type="boardgameartist"]')[i].get('value'))
            for i in range(len(item.findall('.//link[@type="boardgamepublisher"]'))):
                bggid.append(item.get('id'))
                tagtype.append('boardgamepublisher')
                tagvalue.append(item.findall('.//link[@type="boardgamepublisher"]')[i].get('value'))
            for i in range(len(item.findall('.//link[@type="boardgameartist"]'))):
                bggid.append(item.get('id'))
                tagtype.append('boardgameartist')
                tagvalue.append(item.findall('.//link[@type="boardgameartist"]')[i].get('value'))

    df = pl.DataFrame({
        'id': bggid,
        'tagtype': tagtype,
        'tagvalue': tagvalue
    })

    return df;

def get_polldata(file_path):
    # Parse the XML file
    tree = ET.parse(file_path)
    root = tree.getroot()

    # Prepare lists to store extracted data
    bggid = []
    pollname = []
    pollcategory = []
    pollsubcategory = []
    votes = []

    # Iterate through each item in the XML
    for item in root.findall('.//item'):
        if item.get('type') in ('boardgame', 'boardgameexpansion'):
            bgg_id = item.get('id')
            # Iterate through each poll within each item
            for poll in item.findall('.//poll'):
                poll_name = poll.get('name')
                # This isn't needed as it just a more verbose version of poll name - polltitle = poll.get('title')
                # Each results set within the poll
                for results in poll.findall('.//results'):
                    # For suggested number of players, pull in the subcategory
                    if poll_name == 'suggested_numplayers':
                        poll_category = results.get('numplayers')
                        for result in results.findall('.//result'):
                            bggid.append(bgg_id)
                            pollname.append(poll_name)
                            pollcategory.append(poll_category)
                            pollsubcategory.append(result.get('value'))
                            votes.append(result.get('numvotes'))
                    # For all other polls, leave subcategory blank
                    else:
                        for result in results.findall('.//result'):
                            bggid.append(bgg_id)
                            pollname.append(poll_name)
                            pollcategory.append(result.get('value'))
                            pollsubcategory.append(None)
                            votes.append(result.get('numvotes'))
            # Poll Summary is special for suggest number of players only
            for pollsummary in item.findall('.//poll-summary'):
                poll_name = pollsummary.get('name')
                for result in pollsummary.findall('.//result'):
                    bggid.append(bgg_id)
                    pollname.append(poll_name)
                    pollcategory.append(result.get('name'))
                    pollsubcategory.append(result.get('value'))
                    votes.append(None)     

    # Create a DataFrame
    df = pl.DataFrame({
        'bggid': bggid,
        'pollname': pollname,
        'pollcategory': pollcategory,
        'pollsubcategory': pollsubcategory,
        'votes': votes
    })

    return df;

### The Code for uploading new data to MotherDuck

folder_path = 'C:\\Users\\Matso\\source\\repos\\Deniedpluto\\BGG-Data\\BGG Data\\XML New\\'

# Get all .xml files in the folder
xml_files = [file for file in os.listdir(folder_path) if file.endswith(".xml")]


bgg_base = pl.DataFrame()
game_tags = pl.DataFrame()
poll_data = pl.DataFrame()

for file in xml_files:
    bgg_base = bgg_base.vstack(xml_to_dataframe(folder_path + file))
    game_tags = game_tags.vstack(get_bggtags(folder_path + file))
    poll_data = poll_data.vstack(get_polldata(folder_path + file))
    print(file)
bgg_base.rechunk()
game_tags.rechunk()
poll_data.rechunk()

bgg_data = pa.table(bgg_base)
bgg_tags = pa.table(game_tags)
bgg_polls = pa.table(poll_data)

# Read in the token from the yaml file
mdt = yaml.safe_load(open('C:\\Users\\Matso\\source\\repos\\Deniedpluto\\BGG_Recommender\\Python Scripts\\MDToken.yaml', 'r'))['token']

# Authenticate motherduck using token
con = duckdb.connect('md:?motherduck_token=' + mdt) 

# Attach database
con.sql("USE my_db")

# Write to MotherDuck
con.sql("CREATE OR REPLACE TABLE BGG.Dim_Games AS SELECT * FROM bgg_data");
con.sql("CREATE OR REPLACE TABLE BGG.Dim_Game_Tags AS SELECT * FROM bgg_tags");
con.sql("CREATE OR REPLACE TABLE BGG.Dim_Game_Polls AS SELECT * FROM bgg_polls")