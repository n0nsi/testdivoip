#!/bin/bash

################################################################################
# UTILITIES LAYER - utils.sh
# Pure utility functions: arrays, formatting, system info
# NO presentation layer calls (no print_* or colors)
# Input validation is in logging.sh
################################################################################

################################################################################
# ARRAY UTILITIES - Pure logic
################################################################################

# array_add_unique: Add element to array if not duplicate
array_add_unique() {
    local -n arr=$1
    local element=$2
    
    for item in "${arr[@]}"; do
        if [ "$item" = "$element" ]; then
            return 1  # Already exists
        fi
    done
    
    arr+=("$element")
    return 0
}

# array_remove: Remove element from array
array_remove() {
    local -n arr=$1
    local element=$2
    
    local new_arr=()
    for item in "${arr[@]}"; do
        if [ "$item" != "$element" ]; then
            new_arr+=("$item")
        fi
    done
    
    arr=("${new_arr[@]}")
}

# array_index_of: Find index of element in array
array_index_of() {
    local -n arr=$1
    local element=$2
    
    for i in "${!arr[@]}"; do
        if [ "${arr[$i]}" = "$element" ]; then
            echo "$i"
            return 0
        fi
    done
    
    return 1
}

################################################################################
# FORMATTING UTILITIES - Pure string manipulation
################################################################################

# format_number: Format number with decimal places
format_number() {
    local number="$1"
    local decimals="${2:-2}"
    
    if ! is_float "$number"; then
        echo "$number"
        return 1
    fi
    
    printf "%.${decimals}f" "$number"
}

# format_bytes: Convert bytes to human-readable format
format_bytes() {
    local bytes="$1"
    
    if ! is_number "$bytes"; then
        return 1
    fi
    
    if (( bytes < 1024 )); then
        echo "${bytes}B"
    elif (( bytes < 1024*1024 )); then
        echo "$((bytes/1024))KB"
    elif (( bytes < 1024*1024*1024 )); then
        echo "$((bytes/1024/1024))MB"
    else
        echo "$((bytes/1024/1024/1024))GB"
    fi
}

# format_uptime: Format seconds to human-readable uptime
format_uptime() {
    local seconds="$1"
    
    if ! is_number "$seconds"; then
        return 1
    fi
    
    local days=$((seconds / 86400))
    local hours=$(( (seconds % 86400) / 3600 ))
    local minutes=$(( (seconds % 3600) / 60 ))
    
    if (( days > 0 )); then
        echo "${days}d ${hours}h ${minutes}m"
    elif (( hours > 0 )); then
        echo "${hours}h ${minutes}m"
    else
        echo "${minutes}m"
    fi
}

################################################################################
# NUMERIC UTILITIES - Pure calculations
################################################################################

# max_of: Find maximum from list of numbers
max_of() {
    printf '%s\n' "$@" | sort -nr | head -1
}

# min_of: Find minimum from list of numbers
min_of() {
    printf '%s\n' "$@" | sort -n | head -1
}

# average_of: Calculate average of numbers
average_of() {
    local sum=0
    local count=0
    
    for num in "$@"; do
        if is_float "$num"; then
            sum=$(echo "$sum + $num" | bc -l)
            ((count++))
        fi
    done
    
    if (( count > 0 )); then
        echo "$sum / $count" | bc -l
    fi
}

# sum_of: Calculate sum of numbers
sum_of() {
    local sum=0
    
    for num in "$@"; do
        if is_float "$num"; then
            sum=$(echo "$sum + $num" | bc -l)
        fi
    done
    
    echo "$sum"
}

################################################################################
# TIME UTILITIES - Pure functions
################################################################################

# get_timestamp: Get current timestamp ISO format
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# get_timestamp_compact: Get compact timestamp
get_timestamp_compact() {
    date '+%Y%m%d_%H%M%S'
}

# elapsed_time: Calculate seconds between timestamps
elapsed_time() {
    local start_time="$1"
    local end_time="${2:-$(date +%s)}"
    
    if ! is_number "$start_time" || ! is_number "$end_time"; then
        return 1
    fi
    
    echo $((end_time - start_time))
}

################################################################################
# SYSTEM INFORMATION - Read-only queries
################################################################################

# get_os_info: Get operating system information
get_os_info() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        echo "$PRETTY_NAME"
    else
        echo "Unknown Linux"
    fi
}

# get_kernel_version: Get kernel version
get_kernel_version() {
    uname -r
}

# get_cpu_count: Get CPU core count
get_cpu_count() {
    nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "1"
}

# get_memory_total: Get total system memory
get_memory_total() {
    free -h 2>/dev/null | awk '/^Mem/ {print $2}' || echo "UNKNOWN"
}

# get_disk_space: Check available disk space
get_disk_space() {
    local path="${1:-.}"
    
    df -h "$path" 2>/dev/null | tail -1 | awk '{print $4}' || echo "UNKNOWN"
}

################################################################################
# CONFIGURATION FILE HANDLING - Pure read/write
################################################################################

# save_config: Save variables to config file
# Usage: save_config "/path/to/config" "VAR1" "VAR2" ...
save_config() {
    local config_file="$1"
    shift
    
    {
        echo "# testdivoip configuration"
        echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        
        for var in "$@"; do
            local value="${!var}"
            # Escape single quotes in value
            value="${value//\'/\'\"\'\"\'}"
            echo "export ${var}='${value}'"
        done
    } > "$config_file"
    
    [ $? -eq 0 ] && return 0 || return 1
}

# load_config: Load variables from config file
# Usage: load_config "/path/to/config"
load_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    
    # shellcheck source=/dev/null
    source "$config_file" 2>/dev/null && return 0 || return 1
}

################################################################################
# FILE UTILITIES - Pure operations
################################################################################

# file_exists: Check if file exists
file_exists() {
    [ -f "$1" ] && return 0 || return 1
}

# dir_exists: Check if directory exists
dir_exists() {
    [ -d "$1" ] && return 0 || return 1
}

# ensure_dir: Create directory if not exists
ensure_dir() {
    local dir="$1"
    
    [ -d "$dir" ] && return 0
    mkdir -p "$dir" 2>/dev/null && return 0 || return 1
}

# cleanup_old_files: Remove files older than N days
cleanup_old_files() {
    local directory="$1"
    local days="${2:-7}"
    
    if ! is_number "$days" || ! [ -d "$directory" ]; then
        return 1
    fi
    
    find "$directory" -type f -mtime "+$days" -delete 2>/dev/null && return 0 || return 1
}

################################################################################
# GENERATE UTILITIES - IDs and identifiers
################################################################################

# generate_id: Generate unique ID with prefix
generate_id() {
    local prefix="${1:-id}"
    echo "${prefix}_$(date +%s)_$$"
}

# generate_uuid_like: Generate UUID-like string
generate_uuid_like() {
    local output=""
    local chars="0123456789abcdef"
    
    for i in {1..8}; do output="${output}${chars:$((RANDOM % 16)):1}"; done
    output="${output}-"
    for i in {1..4}; do output="${output}${chars:$((RANDOM % 16)):1}"; done
    output="${output}-"
    for i in {1..4}; do output="${output}${chars:$((RANDOM % 16)):1}"; done
    output="${output}-"
    for i in {1..4}; do output="${output}${chars:$((RANDOM % 16)):1}"; done
    output="${output}-"
    for i in {1..12}; do output="${output}${chars:$((RANDOM % 16)):1}"; done
    
    echo "$output"
}

