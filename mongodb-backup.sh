#!/bin/bash

# Use script by passing username, password and path: ./mongodb-backup.sh USER PASSWORD PATH
# If no arguments are passed, the script will use the environment variables: 
# BACKUP_MONGO_USER
# BACKUP_MONGO_PASSWORD
# BACKUP_MONGO_PATH
# Optionally, these variables can be specified in a separate file, config.sh instead.


# Get the directory of the script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set the relative path to the config file
CONFIG_FILE="$SCRIPT_DIR/config.sh"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

mongo_host="localhost"
mongo_port="27017"
mongo_user=${1:-$BACKUP_MONGO_USER}
mongo_password=${2:-$BACKUP_MONGO_PASSWORD}
mongo_auth_db="admin"
backup_folder_root=${3:-$BACKUP_MONGO_PATH}

if [[ -z "$backup_folder_root" ]]; then
    echo "Backup folder not set. Aborting script."
    exit 1
fi

# set the threshold date as two weeks ago
threshold_date=$(date --date="-2 weeks" +%Y%m%d)

# set the backup parent directory name as today's date in YYYYMMDD format
backup_parent_dir=$(date +%Y%m%d)

# set the backup child directory name as the current time in HH:MM format
backup_child_dir=$(date +%H:%M:%S)

# set the full backup path name as a variable
backup_path="${backup_folder_root}/$backup_parent_dir/$backup_child_dir"

# create the backup parent directory if it doesn't exist
mkdir -p "$backup_path"

# loop through all directories in the backup root directory
for dir in "$backup_folder_root"/*/; do
    # check if the directory name is in YYYYMMDD format
    echo "Checking $dir"
    if [[ "$dir" =~ ^$backup_folder_root/[0-9]{8}/$ ]]; then
        # get the directory name as a date string        
        dir_date=$(basename "$dir")
        echo "Directory date: $dir_date"
        # compare the directory date to the threshold date
        if [ "$dir_date" -lt "$threshold_date" ]; then
            # delete the directory and its contents
            echo "Deleting $dir"
            rm -rf "$dir"
        fi
    fi
done

# create the backup child directory if it doesn't exist
mkdir -p "$backup_path"

# Connect to MongoDB

mongo_uri="mongodb://${mongo_user}:${mongo_password}@${mongo_host}:${mongo_port}/?authSource=${mongo_auth_db}"
mongo_cmd="mongo \"${mongo_uri}\" --quiet"
echo $mongo_uri

# Get information about all current databases and collections
declare -A db_current
db_collection_info=$($mongo_cmd --eval 'db.getMongo().getDBNames().forEach(function(dbName){var database = db.getSiblingDB(dbName);database.getCollectionNames().forEach(function(collName){var size=database.getCollection(collName).stats().size;print(dbName + "-" + collName + "=" + size);});});')
while read -r line; do
    # split line by equals sign to get key and value
    key=${line%=*}
    value=${line#*=}
    # add key-value pair to dictionary
    db_current["$key"]="$value"
done <<< "$db_collection_info"

# Get data from previous backup
declare -A db_previous
# read key-value pairs from file and add to array
while IFS='=' read -r key value; do
    db_previous["$key"]="$value"
done < "${backup_folder_root}/db_info.txt"

# We need the previous backup folder... 
# get a sorted list of directory names
dirlist=$(find ${backup_folder_root}/$backup_parent_dir -maxdepth 1 -type d -printf '%f\n' | sort -n)
# find the index of the current directory name
index=$(echo "$dirlist" | grep -n "$backup_child_dir" | cut -d: -f1)
prev_index=$((index - 1))
prev_dirname=$(echo "$dirlist" | sed "${prev_index}q;d")
prev_path="${backup_folder_root}/$backup_parent_dir/$prev_dirname"

echo "Previous directory name: $prev_dirname"
echo "Current directory name: $backup_child_dir"

# if previous folder doesn't exist, or is empty, do a full backup
if [ -z "$prev_dirname" ] || [ ! -d "${prev_path}" ] || [ -z "$(find "${prev_path}" -mindepth 1 -print -quit)" ]; then
  mongodump --username "$mongo_user" --password "$mongo_password" --authenticationDatabase admin --out "$backup_path"
else
  # otherwise only backup what has changed.
  # Get the list of db folders in previous backup folder
    for folder_path in "$prev_path"/*/; do
      database_folder=$(basename "$folder_path")
      for collection_path in "$folder_path"/*.bson; do
        filename=$(basename "$collection_path")
        collection_name="${filename%.*}"
        collection_key="${database_folder}-${collection_name}"
        # Check size of previous backed-up collection
        if test "${db_previous["$collection_key"]}" = "${db_current["$collection_key"]}"; then
          # Collection size is the same
          # Move the backup to the new folder
          mkdir -p "${backup_path}/${database_folder}"          
          mv ${prev_path}/${database_folder}/${collection_name}.* ${backup_path}/${database_folder}
          # Create symbolic link from files in previous folder to newest one
          ln -sf ${backup_path}/${database_folder}/${collection_name}.bson ${prev_path}/${database_folder}/${collection_name}.bson
          ln -sf ${backup_path}/${database_folder}/${collection_name}.metadata.json ${prev_path}/${database_folder}/${collection_name}.metadata.json
        else
          # Collection size has changed - backup new data
          mongodump --username "$mongo_user" --password "$mongo_password" --authenticationDatabase admin --out "$backup_path" --db="$database_folder" --collection="$collection_name"
        fi
      done
    done
fi

# Write current data info to file for next time
echo "${db_collection_info}" > "${backup_folder_root}/db_info.txt"

