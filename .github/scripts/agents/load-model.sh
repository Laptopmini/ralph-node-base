#!/usr/bin/env bash

source .github/scripts/helpers/log.sh

# Check if the model argument is provided
if [ -z "$1" ]; then
  log ERROR "No model specified. Please provide the model name as the first argument." >&2
  exit 1
fi

# Check the LM Studio CLI is installed
if ! command -v lms &> /dev/null; then
    log ERROR "lms is not installed." >&2
    exit 1
fi

# Get the status output from lms command
STATUS_OUTPUT=$(lms status)

# Check if the specified model is already loaded
if ! echo "$STATUS_OUTPUT" | grep -q "· $1"; then
  # Unload all currently running models
  lms unload --all
  if [ $? -ne 0 ]; then
    log ERROR "Failed to stop currently running model(s) in LM Studio." >&2
  fi

  # Load the specified model
  lms load "$1"
  if [ $? -ne 0 ]; then
    log ERROR "Failed to load model '$1' in LM Studio." >&2
  fi
fi
