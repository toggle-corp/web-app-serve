#!/bin/env bash

set -xe

ENABLE_DEBUG=${APPLY_CONFIG__ENABLE_DEBUG:-false}
APPLY_CONFIG_PATH=${APPLY_CONFIG__APPLY_CONFIG_PATH?Required}
SOURCE_DIRECTORY=${APPLY_CONFIG__SOURCE_DIRECTORY?Required}
DESTINATION_DIRECTORY=${APPLY_CONFIG__DESTINATION_DIRECTORY?Required}
DESTINATION_DIRECTORY=${DESTINATION_DIRECTORY%/}  # Remove trailing slash

DEBUG_DIRECTORY="$DESTINATION_DIRECTORY/__debug"
DEBUG_USE_BIOME=${APPLY_CONFIG__DEBUG_USE_BIOME:-true}

function pre_debug {
    if [[ "$DEBUG_USE_BIOME" == "true" ]]; then
        biome format --write "$SOURCE_DIRECTORY"
    fi
    mkdir -p "$DEBUG_DIRECTORY"
}

function post_debug {
    ln -sf /web-app-serve/debug.html "$DEBUG_DIRECTORY/index.html"

    set +xe
    # Check for WEB_APP_SERVE_PLACEHOLDER__ and dump to file
    rg \
        -A 2 -B 2 \
        -F "WEB_APP_SERVE_PLACEHOLDER__" \
        -g '!**/*.map' \
        -g '!**/*.gz' \
        --json \
        "$DESTINATION_DIRECTORY" \
        | jq -s . > "$DEBUG_DIRECTORY/missing_placeholders.json"

    # Show diffs (Useful to debug issues)
    find "$SOURCE_DIRECTORY" -type f -printf '%P\n' | while IFS= read -r file; do
        diff -u \
            --label "a/$file" \
            --label "b/$file" \
            "$SOURCE_DIRECTORY/$file" \
            "$DESTINATION_DIRECTORY/$file" \
            --suppress-common-lines || true
    done > "$DEBUG_DIRECTORY/changes.diff"
    echo "Generated debugging. Visit /__debug/ to check it out"
    set -xe
}

function apply_config {
    mkdir -p $(dirname "$DESTINATION_DIRECTORY")
    cp -r --no-target-directory "$SOURCE_DIRECTORY" "$DESTINATION_DIRECTORY"

    DESTINATION_DIRECTORY="$DESTINATION_DIRECTORY" "$APPLY_CONFIG_PATH"
}

# Cleanup if DESTINATION_DIRECTORY already exists
if [ -d "$DESTINATION_DIRECTORY" ]; then
    echo "Destination directory <$DESTINATION_DIRECTORY> already exists. Force deleting..."
    rm -rf "$DESTINATION_DIRECTORY"
fi

# DEBUG (PRE)
if [[ "$ENABLE_DEBUG" == "true" ]]; then pre_debug; fi

time apply_config

# DEBUG (POST)
if [[ "$ENABLE_DEBUG" == "true" ]]; then post_debug; fi
