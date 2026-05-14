#!/bin/bash

################################################################################
# LOGGING & VALIDATION LAYER - logging.sh
# REFACTORED ARCHITECTURE:
# - Pure logic functions - NO decorative output to stdout
# - All errors and warnings to stderr ONLY
# - All file logging to $LOG_FILE
# - Functions return status codes ONLY (0=success, 1=failure)
# - NO print_success/print_error functions here
################################################################################

LOG_DIR="${LOG_DIR:-logs}"
TEMP_DIR="${TEMP_DIR:-temp}"
LOG_FILE=""
AUDIT_LOG_FILE=""

################################################################################
# INITIALIZE LOGGING
################################################################################

init_logging() {
    umask 077

    mkdir -p "$LOG_DIR" "$TEMP_DIR" 2>/dev/null || return 1
    LOG_FILE="${LOG_DIR}/testdivoip_$(date +%Y%m%d_%H%M%S).log"
    touch "$LOG_FILE" 2>/dev/null || return 1
    
    {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] === TESTDIVOIP Started ==="
    } >> "$LOG_FILE" 2>/dev/null
}

init_audit_log() {
    umask 077

    mkdir -p "$LOG_DIR" "$TEMP_DIR" 2>/dev/null || return 1
    AUDIT_LOG_FILE="${LOG_DIR}/testdivoip_audit_$(date +%Y%m%d_%H%M%S).log"
    touch "$AUDIT_LOG_FILE" 2>/dev/null || return 1

    {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [AUDIT] TESTDIVOIP execution started"
    } >> "$AUDIT_LOG_FILE" 2>/dev/null
}

audit_log_event() {
    local task="$1"
    local message="$2"

    [ -z "$AUDIT_LOG_FILE" ] && return 0
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$task" "$message" >> "$AUDIT_LOG_FILE" 2>/dev/null
}

audit_log_ping_output() {
    local target="$1"
    local count="$2"
    local ping_output="$3"

    [ -z "$AUDIT_LOG_FILE" ] && return 0

    audit_log_event "PING" "target=$target packets=$count"

    local seq_details=()
    local line seq ttl time_ms bytes source

    while IFS= read -r line; do
        if [[ "$line" =~ icmp_seq=([0-9]+) ]]; then
            seq="${BASH_REMATCH[1]}"
            bytes=$(echo "$line" | grep -oP '^[0-9]+' | head -1)
            ttl=$(echo "$line" | grep -oP 'ttl=\K[0-9]+' | head -1)
            time_ms=$(echo "$line" | grep -oP 'time=\K[0-9.]+(?=\s*ms)' | head -1)
            source=$(echo "$line" | grep -oP '(?<=from )[0-9]+(?:\.[0-9]+){3}' | head -1)
            seq_details[$seq]="bytes=${bytes:-64}|ttl=${ttl:-0}|time_ms=${time_ms:-0}|source=${source:-UNKNOWN}|raw=${line}"
        fi
    done <<< "$ping_output"

    local seq_index
    for ((seq_index=1; seq_index<=count; seq_index++)); do
        if [ -n "${seq_details[$seq_index]}" ]; then
            audit_log_event "PING" "seq=$seq_index status=reply ${seq_details[$seq_index]}"
        else
            audit_log_event "PING" "seq=$seq_index status=timeout"
        fi
    done
}

audit_log_traceroute_output() {
    local target="$1"
    local traceroute_output="$2"

    [ -z "$AUDIT_LOG_FILE" ] && return 0

    audit_log_event "TRACEROUTE" "target=$target"

    local line hop ips times
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*([0-9]+)[[:space:]]+(.*)$ ]]; then
            hop="${BASH_REMATCH[1]}"
            ips=$(echo "$line" | grep -oP '[0-9]+(?:\.[0-9]+){3}' | tr '\n' ',' | sed 's/,$//')
            times=$(echo "$line" | grep -oP '[0-9.]+(?=\s*ms)' | tr '\n' ',' | sed 's/,$//')
            audit_log_event "TRACEROUTE" "hop=$hop ips=${ips:-UNKNOWN} times_ms=${times:-UNKNOWN} raw=${line}"
        fi
    done <<< "$traceroute_output"
}

audit_log_summary() {
    local target="$1"
    local score="$2"
    local category="$3"
    local risk_level="$4"
    local confidence="$5"

    audit_log_event "SUMMARY" "target=$target score=$score category=$category risk=$risk_level confidence=$confidence"
}

################################################################################
# LOGGING FUNCTIONS (file only - NO stdout contamination)
################################################################################

log_info() {
    local msg="$1"
    [ -z "$LOG_FILE" ] && return 0
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $msg" >> "$LOG_FILE" 2>/dev/null
}

log_error() {
    local msg="$1"
    [ -z "$LOG_FILE" ] && return 0
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $msg" >> "$LOG_FILE" 2>/dev/null
}

log_debug() {
    [ "$DEBUG" != "1" ] && return 0
    local msg="$1"
    [ -z "$LOG_FILE" ] && return 0
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $msg" >> "$LOG_FILE" 2>/dev/null
}

################################################################################
# VALIDATION FUNCTIONS - Pure logic, return status codes ONLY
# NO stdout, NO stderr output from these functions
################################################################################

# is_valid_ip: returns 0 (valid) or 1 (invalid)
is_valid_ip() {
    local ip="$1"
    local ipv4_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    if [[ $ip =~ $ipv4_regex ]]; then
        for octet in ${ip//./ }; do
            if ((octet > 255)); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# is_number: returns 0 (valid number) or 1 (invalid)
is_number() {
    local num="$1"
    [[ $num =~ ^[0-9]+$ ]] && return 0 || return 1
}

# is_float: returns 0 (valid float) or 1 (invalid)
is_float() {
    local num="$1"
    [[ $num =~ ^[0-9]+(\.[0-9]+)?$ ]] && return 0 || return 1
}

# is_valid_port: returns 0 (valid) or 1 (invalid)
is_valid_port() {
    local port="$1"
    if is_number "$port" && ((port >= 1 && port <= 65535)); then
        return 0
    fi
    return 1
}

# is_valid_hostname: returns 0 (valid) or 1 (invalid)
is_valid_hostname() {
    local hostname="$1"
    local hostname_regex='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'
    [[ $hostname =~ $hostname_regex ]] && return 0 || return 1
}

################################################################################
# DEPENDENCY CHECK
################################################################################

check_dependency() {
    local cmd="$1"
    command -v "$cmd" &>/dev/null && return 0 || return 1
}

# Returns list of missing dependencies to stdout (caller displays)
get_missing_dependencies() {
    local deps=("ping" "mtr" "traceroute" "whois" "dig" "curl" "jq" "awk" "sed" "grep" "bc")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! check_dependency "$dep"; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        printf '%s\n' "${missing[@]}"
        return 1
    fi
    return 0
}

# check_all_dependencies: compatibility wrapper used by the main script
# Returns 0 when everything is available, 1 otherwise.
check_all_dependencies() {
    local missing
    missing=$(get_missing_dependencies)
    local status=$?

    if [ $status -ne 0 ]; then
        while IFS= read -r dep; do
            [ -n "$dep" ] || continue
            report_warning "Missing dependency: $dep"
        done <<< "$missing"
        return 1
    fi

    return 0
}

################################################################################
# ERROR REPORTING (stderr only - for user-facing errors)
################################################################################

report_error() {
    local msg="$1"
    echo "ERROR: $msg" >&2
    log_error "$msg"
}

report_warning() {
    local msg="$1"
    echo "WARNING: $msg" >&2
    log_info "WARNING: $msg"
}

################################################################################
# CLEANUP
################################################################################

cleanup_temp() {
    [ -d "$TEMP_DIR" ] && find "$TEMP_DIR" -mtime +7 -delete 2>/dev/null
}

trap cleanup_temp EXIT

