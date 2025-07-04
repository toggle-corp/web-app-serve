#!/bin/env bash

set -xe

while IFS='=' read -r KEY VALUE; do
    find "$DESTINATION_DIRECTORY" -type f -exec sed -i "s|\<WEB_APP_SERVE_PLACEHOLDER__$KEY\>|$VALUE|g" {} +
done < <(env | grep '^APP_')
