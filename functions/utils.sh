#!/bin/bash

# Small file helpers kept here so the main script does not need to know about
# cleanup details. Configuration parsing lives in testdivoip.sh and is never sourced.

file_exists() {
    [ -f "$1" ]
}

dir_exists() {
    [ -d "$1" ]
}

ensure_dir() {
    mkdir -p "$1"
}

cleanup_old_files() {
    local directory="$1"
    local days="${2:-7}"

    is_number "$days" || return 1
    [ -d "$directory" ] || return 0

    find "$directory" -type f -mtime "+$days" -delete 2>/dev/null
}
