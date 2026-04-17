#!/usr/bin/env bash

notify() {
    # Get the topic from the .env file
    eval "local $(grep '^NTFY_TOPIC=' .env)"

    # Check if the topic is set
    if [ -z "$NTFY_TOPIC" ]; then
        log INFO "Notification push ignored. Set NTFY_TOPIC in .env file to enable notifications." >&2
        return
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        log ERROR "curl is not installed." >&2
        exit 1
    fi

    # Check if the message is provided
    if [ -z "$1" ]; then
        log ERROR "No message specified. Please provide a message as the first argument." >&2
        exit 1
    fi

    # Send the notification
    curl -d "$1" "https://ntfy.sh/$NTFY_TOPIC" || { log ERROR "Failed to send notification. Ignoring error and continuing..."; }
}