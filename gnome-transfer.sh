#!/bin/bash

# This script is used to backup and restore GNOME settings and extensions.

BACKUP_DIR="./gnome-backup"
USER_EXTENSIONS_DIR="$HOME/.local/share/gnome-shell/extensions"

echo "Would you like to:"
echo "  (1) Backup GNOME settings"
echo "  (2) Restore GNOME settings"
read -rp "Enter 1 or 2: " choice

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

if [[ "$choice" == "1" ]]; then
    echo "🔄 Backing up GNOME settings and extensions..."

    echo "📦 Backing up user extensions..."
    mkdir -p "$BACKUP_DIR/extensions"
    cp -r "$USER_EXTENSIONS_DIR" "$BACKUP_DIR/extensions/" 2>/dev/null || echo "No user extensions found."

    echo "📋 Saving enabled extensions list..."
    gsettings get org.gnome.shell enabled-extensions > "$BACKUP_DIR/enabled-extensions.list"

    echo "🧠 Dumping dconf settings..."
    dconf dump / > "$BACKUP_DIR/dconf-settings.ini"

    echo "✅ Backup complete! Files saved to: $BACKUP_DIR"

elif [[ "$choice" == "2" ]]; then
    echo "♻️ Restoring GNOME settings and extensions..."

    if [ ! -f "$BACKUP_DIR/dconf-settings.ini" ]; then
        echo "❌ Backup not found in $BACKUP_DIR"
        exit 1
    fi

    echo "📂 Restoring extensions..."
    mkdir -p "$USER_EXTENSIONS_DIR"
    cp -r "$BACKUP_DIR/extensions/extensions/"* "$USER_EXTENSIONS_DIR/" 2>/dev/null || echo "No extensions to restore."

    echo "⚙️ Setting enabled extensions..."
    if [ -f "$BACKUP_DIR/enabled-extensions.list" ]; then
        ENABLED=$(cat "$BACKUP_DIR/enabled-extensions.list")
        gsettings set org.gnome.shell enabled-extensions "$ENABLED"
    fi

    echo "🧠 Restoring dconf settings..."
    dconf load / < "$BACKUP_DIR/dconf-settings.ini"

    echo "🔁 Reloading GNOME Shell..."
    if [ "$XDG_SESSION_TYPE" == "x11" ]; then
        echo "Using X11: reloading shell (Alt+F2 then 'r' and Enter)..."
    else
        echo "You're on Wayland. Please log out and log back in to apply changes."
    fi

    echo "✅ Restore complete!"

else
    echo "❌ Invalid selection. Please run the script again and choose 1 or 2."
    exit 1
fi
