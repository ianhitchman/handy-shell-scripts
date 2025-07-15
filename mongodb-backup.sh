#!/bin/bash

# Use script by passing username, password and path: ./mongodb-backup.sh USER PASSWORD PATH
# If no arguments are passed, the script will use the environment variables: 
# BACKUP_MONGO_USER
# BACKUP_MONGO_PASSWORD
# BACKUP_MONGO_PATH
# Optionally, these variables can be specified in a .env file

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.env"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi
backup_folder_root=${3:-$BACKUP_MONGO_PATH}
mongo_user=${1:-$BACKUP_MONGO_USER}
mongo_password=${2:-$BACKUP_MONGO_PASSWORD}
mongo_cmd="mongosh mongodb://$mongo_user:$mongo_password@localhost:27017/?authSource=admin --quiet"

# Determine backup folder names
date_str=$(date +"%Y%m%d")
backup_path="$backup_folder_root/$date_str/$(date +"%H:%M:%S")"
prev_path=$(ls -d $backup_folder_root/$date_str/*/ 2>/dev/null | tail -n 1)
prev_dirname=$(basename "$prev_path" 2>/dev/null)

# Create backup directory
mkdir -p "$backup_path"

# Get information about all current databases and collections
declare -A db_current
db_collection_info=$($mongo_cmd --eval '
var result = "";
db.getMongo().getDBNames().forEach(function(dbName){
    var database = db.getSiblingDB(dbName);
    database.getCollectionInfos().forEach(function(coll){
        var collName = coll.name;
        var stats = database[collName].stats();
        result += dbName + "-" + collName + "=" + stats.size + "\n";
    });
});
print(result);
')

# Populate db_current dictionary
while IFS='=' read -r key value; do
    if [[ -n "$key" ]]; then
        db_current["$key"]="$value"
    fi
done <<< "$db_collection_info"

# Load previous collection sizes
declare -A db_previous
if [ -f "${backup_folder_root}/db_info.txt" ]; then
    while IFS='=' read -r key value; do
        if [[ -n "$key" ]]; then
            db_previous["$key"]="$value"
        fi
    done < "${backup_folder_root}/db_info.txt"
fi

# If no valid previous backup, do a full backup
if [ -z "$prev_dirname" ] || [ ! -d "$prev_path" ] || [ -z "$(find "$prev_path" -mindepth 1 -print -quit)" ]; then
    mongodump --username "$mongo_user" --password "$mongo_password" --authenticationDatabase admin --out "$backup_path"
else
    # Incremental backup - only changed collections
    for folder_path in "$prev_path"/*/; do
        database_folder=$(basename "$folder_path")
        for collection_path in "$folder_path"/*.bson; do
            filename=$(basename "$collection_path")
            collection_name="${filename%.*}"
            collection_key="$database_folder-$collection_name"

            if [[ "${db_previous[$collection_key]}" == "${db_current[$collection_key]}" ]]; then
                mkdir -p "$backup_path/$database_folder"
                mv "$prev_path/$database_folder/$collection_name".* "$backup_path/$database_folder/"
                                ln -sf "$backup_path/$database_folder/$collection_name.bson" "$prev_path/$database_folder/$collection_name.bson"
                ln -sf "$backup_path/$database_folder/$collection_name.metadata.json" "$prev_path/$database_folder/$collection_name.metadata.json"
            else
                mongodump --username "$mongo_user" --password "$mongo_password" --authenticationDatabase admin --out "$backup_path" --db="$database_folder" --collection="$collection_name"
            fi
        done
    done
fi

# Save updated collection info
echo "$db_collection_info" > "${backup_folder_root}/db_info.txt"

# Cleanup - delete backup folders older than 14 days
find "$backup_folder_root" -mindepth 1 -maxdepth 1 -type d -regextype posix-extended -regex ".*/[0-9]{8}" -mtime +14 -exec rm -rf {} +