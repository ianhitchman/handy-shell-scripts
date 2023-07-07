#!/bin/bash

# This script checks the status of the mongodb service, and if it is not running or contains the text "Active: failed",
# it restarts the service and writes the current date, time, output and process ID if available to a log file,
# limiting the log file to a maximum of 1000 lines

LOG_FILE="/root/scripts/logs/mongodb-status.log"
EMAIL="tessmarka@gmail.com"

status=$(sudo systemctl status mongodb.service)
current_time=$(date +"%Y-%m-%d %T")

if echo "$status" | grep -qE "Active: running|Active: active"; then
  echo "[$current_time] Success $(echo "$status" | grep "Main PID")" >> "$LOG_FILE"
else
  echo "[$current_time] Failed" >> "$LOG_FILE"

  email_body="MongoDB database service is down.\n"
  
  # Directory path
  directory="/var/run/mongodb"

  # Check if directory exists, and create it if it doesn't
  if [ ! -d "$directory" ]; then
    email_body+="Directory $directory does not exist, and will be created.\n"
    if ! mkdir -p "$directory"; then
      echo "Failed to create directory: $directory" >> "$LOG_FILE"
      email_body+="Failed to create directory: $directory\n"
    else
      echo "Created directory: $directory" >> "$LOG_FILE"
      email_body+="Created directory: $directory\n"
    fi
  fi

  # File path
  file="$directory/mongod.pid"

  # Check if file exists, and create it if it doesn't
  if [ ! -f "$file" ]; then
    email_body+="File $file does not exist, and will be created.\n"
    if ! touch "$file"; then
      echo "Failed to create file: $file" >> "$LOG_FILE"
      email_body+="Failed to create file: $file\n"
    else
      echo "Created file: $file" >> "$LOG_FILE"
      email_body+="Created file: $file\n"
    fi
  fi

  # Change ownership of the file to mongod:mongod
  email_body+="Changing ownership of $file to mongod:mongod\n"
  if ! chown mongod:mongod "$file"; then
    echo "Failed to change ownership of $file to mongod:mongod" >> "$LOG_FILE"
    email_body+="Failed to change ownership of $file to mongod:mongod\n"
  else
    echo "Changed ownership of $file to mongod:mongod" >> "$LOG_FILE"
    email_body+="Changed ownership of $file to mongod:mongod\n"
  fi

  # Do a final check to see if the file exists and is owned by mongod:mongod
  if [ -f "$file" ] && [ "$(stat -c %U:%G "$file")" == "mongod:mongod" ]; then
    email_body+="File $file exists and is owned by mongod:mongod\n"
  else
    email_body+="File $file does not exist or is not owned by mongod:mongod\n"
    exit
  fi

  sleep 5

  # Restart service
  email_body+="Restarting MongoDB database service\n"
  sudo systemctl restart mongodb.service

  sleep 5

  status=$(sudo systemctl status mongodb.service)
  if echo "$status" | grep -qE "Active: running|Active: active"; then
    email_body+="MongoDB database service has been restarted successfully.\n"
    echo "[$current_time] Successfully restarted" >> "$LOG_FILE"
  else
    email_body+="MongoDB database service failed to restart.\n"
    echo "[$current_time] Failed to restart" >> "$LOG_FILE"
  fi

  # Send email
  echo -e "$email_body" | mail -s "MongoDB service has stopped" "$EMAIL"

  
fi

lines=$(wc -l < $LOG_FILE)
if [ $lines -gt 1000 ]; then
  tail -n +2 $LOG_FILE > "$LOG_FILE.tmp"
  mv "$LOG_FILE.tmp" $LOG_FILE
fi
