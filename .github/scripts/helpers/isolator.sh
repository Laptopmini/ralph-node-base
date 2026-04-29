#!/usr/bin/env bash

BACKPRESSURE_BACKUP_FOLDER=".maestro.backpressure"
BACKPRESSURE_FOLDER="tests"

# Moves all tests to a backup folder to avoid agents reading them before they are needed
isolate_backpressure() {
    log INFO "Isolating backpressure..."
    if [[ -d "$BACKPRESSURE_BACKUP_FOLDER" ]]; then
        log ERROR "There is already backpressure isolated. Aborting."
        exit 1
    fi

    if [[ ! -d "$BACKPRESSURE_FOLDER" ]]; then
        log WARN "There is no backpressure to isolate. Skipping isolation..."
        return 0
    fi

    # Move e2e, scripts, and unit folders to ".maestro.backpressure/tests/"
    mkdir -p "$BACKPRESSURE_BACKUP_FOLDER/$BACKPRESSURE_FOLDER"
    [ -e "$BACKPRESSURE_FOLDER/e2e" ] && mv -f "$BACKPRESSURE_FOLDER/e2e" "$BACKPRESSURE_BACKUP_FOLDER/$BACKPRESSURE_FOLDER/e2e"
    [ -e "$BACKPRESSURE_FOLDER/scripts" ] && mv -f "$BACKPRESSURE_FOLDER/scripts" "$BACKPRESSURE_BACKUP_FOLDER/$BACKPRESSURE_FOLDER/scripts"
    [ -e "$BACKPRESSURE_FOLDER/unit" ] && mv -f "$BACKPRESSURE_FOLDER/unit" "$BACKPRESSURE_BACKUP_FOLDER/$BACKPRESSURE_FOLDER/unit"

    log INFO "Isolated backpressure!"
}

# Restore backpressure to its original location so that the agents can read them
# If called with no arguments, restore all backpressure
# If called with a single argument, restore backpressure for that command
restore_backpressure() {
    local COMMAND="${1:-}"
    if [ -z "$COMMAND" ]; then
        log INFO "Restoring all backpressure..."

        if [[ ! -d "$BACKPRESSURE_BACKUP_FOLDER" ]]; then
            log WARN "There is no remaining backpressure to restore. Skipping restoration..."
            return 0
        fi

        mkdir -p "$BACKPRESSURE_FOLDER"
        rsync -av --ignore-existing "$BACKPRESSURE_BACKUP_FOLDER/$BACKPRESSURE_FOLDER"/ "$BACKPRESSURE_FOLDER"/
        rm -rf "$BACKPRESSURE_BACKUP_FOLDER"
    else
        log INFO "Restoring backpressure for $COMMAND..."
        local file_path="${COMMAND##* }"

        if [[ ! "$file_path" == *.* ]]; then
            log INFO "No test file resolvable from '$COMMAND'. Skipping restoration..."
            return 0
        fi

        # Verify that the file path is not already moved
        if [[ -f "$file_path" ]]; then
            log INFO "The file $file_path has already been moved. Skipping restoration..."
            return 0
        fi

        # Verify that the given file exists in the backpressure backup folder
        if [[ ! -f "$BACKPRESSURE_BACKUP_FOLDER/$file_path" ]]; then
            log WARN "The test file $file_path does not exist in $BACKPRESSURE_BACKUP_FOLDER. Skipping restoration..."
            return 0
        fi

        # Move back the targeted backpressure into its expected location
        mkdir -p "$(dirname "$file_path")"
        mv -f "$BACKPRESSURE_BACKUP_FOLDER/$file_path" "$file_path"
    fi
    
    log INFO "Restored backpressure!"
}

remove_backpressure() {
    log INFO "Removing backpressure..."
    local NEW_TESTS=$(git diff --name-only maestro...HEAD | grep '^tests/' || true)

    if [ -z "$NEW_TESTS" ]; then
        log INFO "No backpressure to remove. Continuing..."
        return 0
    fi

    echo "$NEW_TESTS" | xargs git rm --ignore-unmatch

    git add .
    git diff --cached --quiet || git commit -m "chore(ai): Clean out backpressure"

    log INFO "Removed backpressure!"
}
