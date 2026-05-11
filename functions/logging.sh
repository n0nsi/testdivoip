#!/bin/bash

################################################################################
# LOGGING & VALIDATION - testdivoip
# Funções para logging, validação e tratamento de erros
################################################################################

LOG_DIR="${LOG_DIR:-.logs}"
TEMP_DIR="${TEMP_DIR:-.temp}"

################################################################################
# INITIALIZE LOGGING
################################################################################

init_logging() {
    mkdir -p "$LOG_DIR" "$TEMP_DIR"
    LOG_FILE="${LOG_DIR}/testdivoip_$(date +%Y%m%d_%H%M%S).log"
    touch "$LOG_FILE"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] === TESTDIVOIP Started ===" >> "$LOG_FILE"
}

################################################################################
# LOG FUNCTIONS
################################################################################

log_info() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $msg" >> "$LOG_FILE"
}

log_error() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $msg" >> "$LOG_FILE"
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        local msg="$1"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $msg" >> "$LOG_FILE"
    fi
}

log_command() {
    local cmd="$1"
    log_debug "Executing: $cmd"
}

################################################################################
# VALIDATION FUNCTIONS
################################################################################

# Validar IP
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

# Validar hostname
is_valid_hostname() {
    local hostname="$1"
    local hostname_regex='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'
    
    [[ $hostname =~ $hostname_regex ]] && return 0 || return 1
}

# Validar número
is_number() {
    local num="$1"
    [[ $num =~ ^[0-9]+$ ]] && return 0 || return 1
}

# Validar port
is_valid_port() {
    local port="$1"
    if is_number "$port" && ((port >= 1 && port <= 65535)); then
        return 0
    fi
    return 1
}

################################################################################
# DEPENDENCY CHECK
################################################################################

check_dependency() {
    local cmd="$1"
    
    if ! command -v "$cmd" &> /dev/null; then
        return 1
    fi
    return 0
}

check_all_dependencies() {
    local deps=(
        "ping"
        "mtr"
        "traceroute"
        "whois"
        "dig"
        "host"
        "curl"
        "jq"
        "awk"
        "sed"
        "grep"
        "netstat"
        "ss"
        "bc"
    )
    
    local missing=()
    
    print_info "Checking dependencies..."
    
    for dep in "${deps[@]}"; do
        if check_dependency "$dep"; then
            print_success "Found: $dep"
        else
            print_error "Missing: $dep"
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo ""
        print_warning "Missing dependencies: ${missing[*]}"
        print_info "On Debian/Ubuntu, install with:"
        echo "  sudo apt-get install -y mtr-tiny dnsutils whois curl bc net-tools iproute2"
        return 1
    fi
    
    return 0
}

################################################################################
# ERROR HANDLING
################################################################################

error_exit() {
    local msg="$1"
    local code="${2:-1}"
    
    print_error "$msg"
    log_error "$msg"
    exit "$code"
}

trap_error() {
    local line_no="$1"
    local bash_lineno="$2"
    print_error "Error in script at line $line_no"
    exit 1
}

################################################################################
# RETRY LOGIC
################################################################################

retry() {
    local max_attempts="$1"
    shift
    local n=1
    
    while true; do
        print_debug "Attempt $n/$max_attempts: $*"
        if "$@"; then
            return 0
        fi
        
        if [[ $n -lt $max_attempts ]]; then
            ((n++))
            sleep 2
        else
            return 1
        fi
    done
}

################################################################################
# CLEANUP
################################################################################

cleanup() {
    print_debug "Cleaning up temporary files"
    # Não removemos arquivos importantes, apenas limpeza menor
    find "$TEMP_DIR" -mtime +7 -delete 2>/dev/null || true
}

trap cleanup EXIT

