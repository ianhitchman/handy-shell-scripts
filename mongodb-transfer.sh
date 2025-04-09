#!/bin/bash

# This script is used to transfer MongoDB databases from one server to another.

# Settings - adjust these to your environment
DUMP_FOLDER=$TRANSFER_DUMP_FOLDER  # Local folder to store dumped files
NEW_SERVER_SSH_USER=$TRANSFER_NEW_SERVER_SSH_USER  # SSH user for the new server
NEW_SERVER_IP=$TRANSFER_NEW_SERVER_HOST  # IP address / URL of the new server
NEW_SERVER_MONGO_USER=$TRANSFER_NEW_SERVER_MONGO_USER  # MongoDB user on the new server
NEW_SERVER_MONGO_PASSWORD=$TRANSFER_NEW_SERVER_MONGO_PASSWORD  # MongoDB password for the new server
NEW_SERVER_MONGO_AUTH_DB=$TRANSFER_NEW_SERVER_MONGO_AUTH_DB  # MongoDB authentication DB
NEW_SERVER_IMPORT_PATH=$TRANSFER_NEW_SERVER_IMPORT_PATH  # Path to dump export on the new server
OLD_SERVER_MONGO_AUTH_DB=$TRANSFER_OLD_SERVER_MONGO_AUTH_DB  # MongoDB authentication DB for the old server
OLD_SERVER_MONGO_USER=$TRANSFER_OLD_SERVER_MONGO_USER  # MongoDB user for the old server
OLD_SERVER_MONGO_PASSWORD=$TRANSFER_OLD_SERVER_MONGO_PASSWORD  # MongoDB password for the old server
DATABASE_PREFIX=$TRANSFER_DATABASE_PREFIX  # Prefix for all database names to be transferred

# Ensure dump folder exists
mkdir -p ${DUMP_FOLDER}
rm -rf ${DUMP_FOLDER}/*

# Step 1: Dump all MongoDB databases from the local server that begin with specified prefix
echo "Dumping MongoDB databases from the local server that begin with '${DATABASE_PREFIX}'..."

databases=$(mongo --quiet --username ${OLD_SERVER_MONGO_USER} --password ${OLD_SERVER_MONGO_PASSWORD} --authenticationDatabase ${OLD_SERVER_MONGO_AUTH_DB} --eval "db.getMongo().getDBNames().filter(db => db.startsWith('${DATABASE_PREFIX}')).join(',')" --host ${OLD_SERVER_IP})

for db in $(echo $databases | tr "," "\n"); do
  echo "Dumping database: $db"
  mongodump --authenticationDatabase ${OLD_SERVER_MONGO_AUTH_DB} --username ${OLD_SERVER_MONGO_USER} --password ${OLD_SERVER_MONGO_PASSWORD} --db $db --out ${DUMP_FOLDER}
  if [ $? -ne 0 ]; then
    echo "Error dumping MongoDB data for database $db."
    exit 1
  fi
done

# Step 2: Compress the dump into a zip file
echo "Compressing dump folder..."
cd /root/dump && zip -r /root/transfer.zip ./*

# Step 3: Copy the zip file to the new server
echo "Copying transfer.zip to the new server..."
scp /root/transfer.zip ${NEW_SERVER_SSH_USER}@${NEW_SERVER_IP}:${NEW_SERVER_IMPORT_PATH}

if [ $? -ne 0 ]; then
  echo "Error copying transfer.zip to the new server."
  exit 1
fi

# Step 4: Extract and restore the databases on the remote server
echo "Extracting and restoring databases on the new server..."
ssh ${NEW_SERVER_SSH_USER}@${NEW_SERVER_IP} <<EOF
  unzip -o ${NEW_SERVER_IMPORT_PATH}/transfer.zip -d ${NEW_SERVER_IMPORT_PATH}
  for dump_dir in ${NEW_SERVER_IMPORT_PATH}/*; do
    if [[ -d "\$dump_dir" ]]; then
      db_name=\$(basename "\$dump_dir")
      if [[ \$db_name == "${DATABASE_PREFIX}"* ]]; then
        echo "Restoring database: \$db_name"
        mongorestore --authenticationDatabase ${NEW_SERVER_MONGO_AUTH_DB} --username ${NEW_SERVER_MONGO_USER} --password ${NEW_SERVER_MONGO_PASSWORD} --drop --db \$db_name --dir="\$dump_dir"
      fi
    fi
  done
EOF

if [ $? -ne 0 ]; then
  echo "Error importing data into MongoDB on the new server."
  exit 1
fi

echo "MongoDB transfer completed successfully."

