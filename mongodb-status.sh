#!/bin/bash

# This script checks the status of the mongodb service, and if it is not running or contains the text "Active: failed", 
# it restarts the service and writes the current date, time, output and process ID if available to a log file,
# limiting the log file to a maximum of 1000 lines

LOG_FILE="/root/scripts/logs/mongodb-status.log"

status=$(sudo systemctl status mongodb.service)
current_time=$(date +"%Y-%m-%d %T")

if echo "$status" | grep -qE "Active: running|Active: active"; then
  echo "[$current_time] Success $(echo "$status" | grep "Main PID")" >> $LOG_FILE
else
  echo "[$current_time] Failed" >> $LOG_FILE
  sudo systemctl restart mongodb.service
  echo "MongoDB database service has stopped running, and was restarted" | mail -s "MongoDB down" tessmarka@gmail.com

  status=$(sudo systemctl status mongodb.service)
  if echo "$status" | grep -qE "Active: running|Active: active"; then
    echo "[$current_time] Successfully restarted" >> $LOG_FILE
  else
    echo "[$current_time] Failed to restart" >> $LOG_FILE
    
    # Directory path
    directory="/var/run/mongodb"

    # Check if directory exists, and create it if it doesn't
    if [ ! -d "$directory" ]; then
      mkdir -p "$directory"
      echo "Created directory: $directory" >> $LOG_FILE
    fi

    # File path
    file="$directory/mongod.pid"

    # Check if file exists, and create it if it doesn't
    if [ ! -f "$file" ]; then
      touch "$file"
      echo "Created file: $file" >> $LOG_FILE
    fi

    # Change ownership of the file to mongod:mongod
    chown mongod:mongod "$file"
    echo "Changed ownership of $file to mongod:mongod" >> $LOG_FILE

    # Restart service
    sudo systemctl restart mongodb.service
    status=$(sudo systemctl status mongodb.service)
    if echo "$status" | grep -qE "Active: running|Active: active"; then
      echo "[$current_time] Successfully restarted" >> $LOG_FILE
    else
      echo "[$current_time] Failed to restart" >> $LOG_FILE
    fi

  fi
fi

lines=$(wc -l < $LOG_FILE)
if [ $lines -gt 1000 ]; then
  tail -n +2 $LOG_FILE > "$LOG_FILE.tmp"
  mv "$LOG_FILE.tmp" $LOG_FILE
fi
