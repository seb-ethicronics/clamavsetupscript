#!/bin/bash

QUARANTINE_DIR="/quarantine"
LOG_FILE="/var/log/realtime_scan.log"

# Ensure quarantine folder exists and is secure
mkdir -p "$QUARANTINE_DIR"
chmod 700 "$QUARANTINE_DIR"
chown root:root "$QUARANTINE_DIR"

# Function to send a desktop notification to the user who owns the file
send_notification() {
    local USERNAME="$1"
    local TITLE="$2"
    local BODY="$3"

    # Get user's environment info
    local USER_HOME="/home/$USERNAME"
    local USER_ID=$(id -u "$USERNAME")
    local DISPLAY_NUM=$(w -hs | grep "^$USERNAME" | awk '{print $2}' | grep -E '^:0|:1' | head -n1)
    local DBUS_ENV_FILE=$(find /run/user/$USER_ID -name 'bus' 2>/dev/null | head -n1)

    if [[ -n "$DISPLAY_NUM" && -n "$DBUS_ENV_FILE" ]]; then
        export DISPLAY="$DISPLAY_NUM"
        export DBUS_SESSION_BUS_ADDRESS="unix:path=$DBUS_ENV_FILE"
        sudo -u "$USERNAME" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" DISPLAY="$DISPLAY" \
            notify-send "$TITLE" "$BODY"
    fi
}

# Watch all users' Downloads folders
for USER_HOME in /home/*; do
    USERNAME=$(basename "$USER_HOME")
    DOWNLOADS_PATH="$USER_HOME/Downloads"

    [[ -d "$DOWNLOADS_PATH" ]] || continue

    inotifywait -m -r -e close_write -e moved_to --format '%w%f' "$DOWNLOADS_PATH" |
    while read FILE; do
        echo "$(date): Scanning $FILE" >> "$LOG_FILE"
        clamdscan --fdpass --move="$QUARANTINE_DIR" "$FILE" >> "$LOG_FILE"

        BASENAME=$(basename "$FILE")
        QUARANTINED_FILE="$QUARANTINE_DIR/$BASENAME"

        if [[ -f "$QUARANTINED_FILE" ]]; then
            chmod 000 "$QUARANTINED_FILE"
            echo "$(date): $BASENAME quarantined and locked down." >> "$LOG_FILE"
            send_notification "$USERNAME" "🛡️ ClamAV Alert" "Malware quarantined: $BASENAME"
        fi
    done &
done

# Wait for all background watchers
wait
