#!/bin/bash

# Ensure a file was passed
if [ -z "$1" ]; then
  echo "Usage: install-deb.sh path/to/file.deb"
  exit 1
fi

# Use full path in case file manager only gives filename
DEB_PATH="$(realpath "$1")"

gnome-terminal -- bash -c "sudo apt install \"$DEB_PATH\"; echo 'Press any key to close...'; read -n 1"
