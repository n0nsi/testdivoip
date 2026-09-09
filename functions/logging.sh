#!/bin/bash

# Local logs are runtime evidence. They are ignored by Git and should stay local.

LOG_DIR="${LOG_DIR:-logs}"
TEMP_DIR="${TEMP_DIR:-temp}"
LOG_FILE=""
AUDIT_LOG_FILE=""

set_runtime_dirs() {
    LOG_DIR="$1"
    TEMP_DIR="$2"
}

init_logging() {
    umask 077
    mkdir -p "$LOG_DIR" "$TEMP_DIR" || return 1
    LOG_FILE="${LOG_DIR}/testdivoip_$(date +%Y%m%d_%H%M%S).log"
    : > "$LOG_FILE" || return 1
    log_info "TESTDIVOIP started"
}

init_audit_log() {
    umask 077
    mkdir -p "$LOG_DIR" "$TEMP_DIR" || return 1
    AUDIT_LOG_FILE="${LOG_DIR}/testdivoip_audit_$(date +%Y%m%d_%H%M%S).log"
    : > "$AUDIT_LOG_FILE" || return 1
    audit_log_event "RUN" "started"
}

audit_log_event() {
    local task="$1"
    local message="$2"

    [ -n "$AUDIT_LOG_FILE" ] || return 0
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$task" "$message" >> "$AUDIT_LOG_FILE"
}

audit_log_ping_output() {
    local target="$1"
    local count="$2"
    local ping_output="$3"
    local line seq

    [ -n "$AUDIT_LOG_FILE" ] || return 0
    audit_log_event "PING" "target=$target packets=$count"

    while IFS= read -r line; do
        if [[ "$line" =~ icmp_seq=([0-9]+) ]]; then
            seq="${BASH_REMATCH[1]}"
            audit_log_event "PING" "target=$target seq=$seq raw=$line"
        fi
    done <<< "$ping_output"
}

audit_log_traceroute_output() {
    local target="$1"
    local traceroute_output="$2"
    local line hop

    [ -n "$AUDIT_LOG_FILE" ] || return 0
    audit_log_event "TRACEROUTE" "target=$target"

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*([0-9]+)[[:space:]] ]]; then
            hop="${BASH_REMATCH[1]}"
            audit_log_event "TRACEROUTE" "target=$target hop=$hop raw=$line"
        fi
    done <<< "$traceroute_output"
}

audit_log_summary() {
    local target="$1"
    local score="$2"
    local category="$3"
    local risk_level="$4"
    local evidence_weight="$5"

    audit_log_event "SUMMARY" "target=$target score=$score category=$category risk=$risk_level evidence_weight=$evidence_weight"
}

log_info() {
    local message="$1"
    [ -n "$LOG_FILE" ] || return 0
    printf '[%s] [INFO] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >> "$LOG_FILE"
}

log_error() {
    local message="$1"
    [ -n "$LOG_FILE" ] || return 0
    printf '[%s] [ERROR] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >> "$LOG_FILE"
}

log_debug() {
    [ "${DEBUG:-0}" = "1" ] || return 0
    local message="$1"
    [ -n "$LOG_FILE" ] || return 0
    printf '[%s] [DEBUG] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >> "$LOG_FILE"
}

is_valid_ip() {
    local ip="$1"
    local octet

    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

    for octet in ${ip//./ }; do
        (( octet >= 0 && octet <= 255 )) || return 1
    done
}

is_number() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

is_float() {
    [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

get_missing_dependencies() {
    local -a dependencies=(ping mtr traceroute whois timeout awk sed grep bc find)
    local dependency missing=0

    for dependency in "${dependencies[@]}"; do
        if ! command -v "$dependency" >/dev/null 2>&1; then
            printf '%s\n' "$dependency"
            missing=1
        fi
    done

    return "$missing"
}

check_all_dependencies() {
    local missing dependency

    if missing=$(get_missing_dependencies); then
        return 0
    fi

    while IFS= read -r dependency; do
        [ -n "$dependency" ] && report_warning "Missing dependency: $dependency"
    done <<< "$missing"

    return 1
}

report_error() {
    local message="$1"
    printf 'ERROR: %s\n' "$message" >&2
    log_error "$message"
}

report_warning() {
    local message="$1"
    printf 'WARNING: %s\n' "$message" >&2
    log_info "WARNING: $message"
}

cleanup_temp() {
    [ -d "$TEMP_DIR" ] || return 0
    find "$TEMP_DIR" -type f -mtime +7 -delete 2>/dev/null || true
}
