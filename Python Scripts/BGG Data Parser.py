import duckdb
import polars as pl
import xmltodict as xtd
import yaml
import os
import pyarrow as pa
import xml.etree.ElementTree as ET


file_path = 'C:\\Users\\Matso\\source\\repos\\Deniedpluto\\BGG-Data\\BGG Data\\XML New\\XMLData_1.xml'

tree = ET.parse(file_path)
root = tree.getroot()  # Get the root element of the XML
for child in root:
    print(f"Tag: {child.tag}, Attributes: {child.attrib}, Text: {child.text}")
    for subchild in child:
        print(f"Tag: {subchild.tag}, Attributes: {subchild.attrib}, Text: {subchild.text}")
        for subsubchild in subchild:
            print(f"Tag: {subsubchild.tag}, Attributes: {subsubchild.attrib}, Text: {subsubchild.text}")
            for subsubsubchild in subsubchild:
                print(f"Tag: {subsubsubchild.tag}, Attributes: {subsubsubchild.attrib}, Text: {subsubsubchild.text}")
                for subsubsubsubchild in subsubsubchild:
                    print(f"Tag: {subsubsubsubchild.tag}, Attributes: {subsubsubsubchild.attrib}, Text: {subsubsubsubchild.text}")
                    for subsubsubsubsubchild in subsubsubsubchild:
                        print(f"Tag: {subsubsubsubsubchild.tag}, Attributes: {subsubsubsubsubchild.attrib}, Text: {subsubsubsubsubchild.text}")
                        for subsubsubsubsubsubchild in subsubsubsubsubchild:
                            print(f"Tag: {subsubsubsubsubsubchild.tag}, Attributes: {subsubsubsubsubsubchild.attrib}, Text: {subsubsubsubsubsubchild.text}")
                            for subsubsubsubsubsubsubchild in subsubsubsubsubsubchild:
                                print(f"Tag: {subsubsubsubsubsubsubchild.tag}, Attributes: {subsubsubsubsubsubsubchild.attrib}, Text: {subsubsubsubsubsubsubchild.text}")


def xml_to_dataframe(file_path):
    # Parse the XML file
    tree = ET.parse(file_path)
    root = tree.getroot()

    # Prepare lists to store extracted data
    ids = []
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

    # Iterate through each item in the XML
    for item in root.findall('.//item'):
        ids.append(item.get('id'))
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

    # Create a DataFrame
    df = pl.DataFrame({
        'id': ids,
        'type': types,
        'name': names,
        'description': descriptions,
        'year_published': years_published,
        'min_players': min_players,
        'max_players': max_players,
        'play_time': play_times,
        'min_play_time': min_play_times,
        'max_play_time': max_play_times,
        'min_age': min_ages
    })

    return df

# Usage example:
df = xml_to_dataframe(file_path)
print(df)

bgg_data = pa.table(df)
