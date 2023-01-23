#!/bin/bash

# This script checks the status of the mongodb service, and if it is not running or contains the text "Active: failed", 
# it restarts the service and writes the current date, time, output and process ID if available to a log file,
# limiting the log file to a maximum of 1000 lines

LOG_FILE="./logs/mongodb-status.log"

status=$(sudo systemctl status mongod)
current_time=$(date +"%Y-%m-%d %T")

if echo "$status" | grep -qE "Active: running|Active: active"; then
  echo "[$current_time] Success $(echo "$status" | grep "Main PID")" >> $LOG_FILE
else
  echo "[$current_time] Failed" >> $LOG_FILE
fi

lines=$(wc -l < $LOG_FILE)
if [ $lines -gt 1000 ]; then
  tail -n +2 $LOG_FILE > "$LOG_FILE.tmp"
  mv "$LOG_FILE.tmp" $LOG_FILE
fi
