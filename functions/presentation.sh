#!/bin/bash

################################################################################
# PRESENTATION LAYER - presentation.sh
# UI/Display functions - All user-facing output
# Consumes data from logic layer and formats for display
# All colors, formatting, user prompts here
################################################################################

# Resolve this module and load sibling dependencies with absolute paths.
PRESENTATION_SOURCE="${BASH_SOURCE[0]}"
PRESENTATION_DIR="$(cd "$(dirname "$PRESENTATION_SOURCE")" && pwd -P)"
PROJECT_ROOT="$(cd "${PRESENTATION_DIR}/.." && pwd -P)"

source_required() {
    local module_file="$1"
    if [ ! -f "$module_file" ]; then
        printf 'Fatal: required module missing: %s\n' "$module_file" >&2
        return 1
    fi

    # shellcheck source=/dev/null
    source "$module_file" || {
        printf 'Fatal: failed to load module: %s\n' "$module_file" >&2
        return 1
    }
}

source_required "${PRESENTATION_DIR}/colors.sh" || return 1

################################################################################
# SUCCESS/ERROR/INFO MESSAGES
################################################################################

# ui_print_success: Display success message
ui_print_success() {
    local message="$1"
    printf "%b✓ %s%b\n" "$GREEN" "$message" "$NC" >&2
}

# ui_print_error: Display error message
ui_print_error() {
    local message="$1"
    printf "%b✗ %s%b\n" "$RED" "$message" "$NC" >&2
}

# ui_print_warning: Display warning message
ui_print_warning() {
    local message="$1"
    printf "%b⚠ %s%b\n" "$YELLOW" "$message" "$NC" >&2
}

# ui_print_info: Display info message
ui_print_info() {
    local message="$1"
    printf "%bℹ %s%b\n" "$BLUE" "$message" "$NC" >&2
}

# ui_print_debug: Display debug message
ui_print_debug() {
    local message="$1"
    [ "$DEBUG" = "1" ] && printf "%b➤ %s%b\n" "$MAGENTA" "$message" "$NC" >&2
}

################################################################################
# FORMATTED DISPLAY
################################################################################

# ui_print_header: Display section header
ui_print_header() {
    local text="$1"
    local char="${2:-=}"
    local width="${3:-60}"
    
    printf "\n%b" "$BOLD"
    printf '%*s\n' "$width" | tr ' ' "$char"
    printf " %s\n" "$text"
    printf '%*s\n' "$width" | tr ' ' "$char"
    printf "%b\n" "$NC"
}

# ui_print_subheader: Display subsection header
ui_print_subheader() {
    local text="$1"
    printf "\n%b▸ %s%b\n" "$CYAN" "$text" "$NC" >&2
}

# ui_print_metric: Display metric with value
# Usage: ui_print_metric "Latency" "45.2" "ms"
ui_print_metric() {
    local label="$1"
    local value="$2"
    local unit="$3"
    
    printf "%b%-20s %b%s%b %s\n" "$BOLD" "$label:" "$GREEN" "$value" "$NC" "$unit" >&2
}

# ui_print_metric_critical: Display critical metric (in red)
ui_print_metric_critical() {
    local label="$1"
    local value="$2"
    local unit="$3"
    
    printf "%b%-20s %b%s%b %s\n" "$BOLD" "$label:" "$RED" "$value" "$NC" "$unit" >&2
}

# ui_print_metric_warning: Display warning metric (in yellow)
ui_print_metric_warning() {
    local label="$1"
    local value="$2"
    local unit="$3"
    
    printf "%b%-20s %b%s%b %s\n" "$BOLD" "$label:" "$YELLOW" "$value" "$NC" "$unit" >&2
}

################################################################################
# TABLES & LISTS
################################################################################

# ui_print_table_row: Display table row with columns
ui_print_table_row() {
    local -a columns=("$@")
    
    for col in "${columns[@]}"; do
        printf "%-20s " "$col"
    done
    printf "\n"
}

# ui_print_separator: Print visual separator
ui_print_separator() {
    local char="${1:-─}"
    local width="${2:-60}"
    printf "%b%*s%b\n" "$DIM" "$width" | tr ' ' "$char" "$NC"
}

################################################################################
# INPUT PROMPTS WITH VALIDATION
################################################################################

# ui_prompt_text: Prompt for text input with optional default
ui_prompt_text() {
    local prompt="$1"
    local default="${2:-}"
    local input
    
    if [ -n "$default" ]; then
        printf "%b%s%b [%b%s%b]: " "$BOLD" "$prompt" "$NC" "$CYAN" "$default" "$NC" >&2
    else
        printf "%b%s%b: " "$BOLD" "$prompt" "$NC" >&2
    fi
    
    read -r input
    input="${input:-$default}"
    echo "$input"
}

# ui_prompt_confirmed: Prompt and ask for confirmation
ui_prompt_confirmed() {
    local prompt="$1"
    local value
    
    value=$(ui_prompt_text "$prompt")
    
    printf "%bEntered: %b%s%b\n" "$CYAN" "$GREEN" "$value" "$NC" >&2
    
    local confirm
    printf "%bIs this correct? %b[y/N]%b: " "$BOLD" "$CYAN" "$NC" >&2
    read -r confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "$value"
        return 0
    else
        return 1
    fi
}

# ui_prompt_menu: Display menu and get choice
ui_prompt_menu() {
    local prompt="$1"
    shift
    local -a options=("$@")
    
    printf "\n%b%s%b\n\n" "$BOLD" "$prompt" "$NC" >&2
    
    for i in "${!options[@]}"; do
        printf "  %b%d)%b %s\n" "$CYAN" "$((i+1))" "$NC" "${options[$i]}" >&2
    done
    
    local choice
    printf "\n%bSelect option [1-%d]:%b " "$BOLD" "${#options[@]}" "$NC" >&2
    read -r choice
    
    if [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
        echo "$((choice-1))"
        return 0
    else
        ui_print_error "Invalid selection"
        return 1
    fi
}

# ui_prompt_yes_no: Prompt for yes/no answer
ui_prompt_yes_no() {
    local prompt="$1"
    local response
    
    printf "%b%s%b [%by%b/%bn%b]: " "$BOLD" "$prompt" "$NC" "$GREEN" "$NC" "$RED" "$NC" >&2
    read -r response
    
    [[ "$response" =~ ^[Yy]$ ]] && return 0 || return 1
}

# ui_prompt_number: Prompt for number with optional validation
ui_prompt_number() {
    local prompt="$1"
    local default="${2:-}"
    local input
    
    while true; do
        input=$(ui_prompt_text "$prompt" "$default")
        
        if is_number "$input"; then
            echo "$input"
            return 0
        else
            ui_print_error "Invalid number: $input"
        fi
    done
}

# ui_prompt_ip: Prompt for IP address with validation
ui_prompt_ip() {
    local prompt="$1"
    local default="$2"
    local input
    
    while true; do
        input=$(ui_prompt_text "$prompt" "$default")
        
        if is_valid_ip "$input"; then
            echo "$input"
            return 0
        else
            ui_print_error "Invalid IP address: $input"
        fi
    done
}

################################################################################
# STATUS DISPLAYS
################################################################################

# ui_show_quality_status: Display VoIP quality status
# Usage: ui_show_quality_status "EXCELENTE" "85"
ui_show_quality_status() {
    local category="$1"
    local score="$2"
    
    local color status_icon
    
    case "$category" in
        EXCELENTE)
            color="$GREEN"
            status_icon="✓"
            ;;
        BOM)
            color="$CYAN"
            status_icon="◇"
            ;;
        ATENÇÃO)
            color="$YELLOW"
            status_icon="⚠"
            ;;
        CRÍTICO)
            color="$RED"
            status_icon="✗"
            ;;
        *)
            color="$NC"
            status_icon="?"
            ;;
    esac
    
    printf "%b%s %s (Score: %s)%b\n" "$color" "$status_icon" "$category" "$score" "$NC" >&2
}

# ui_show_metric_assessment: Show assessment for metric
ui_show_metric_assessment() {
    local label="$1"
    local value="$2"
    local unit="$3"
    local status="$4"  # good/warning/critical
    
    local color
    case "$status" in
        good)     color="$GREEN" ;;
        warning)  color="$YELLOW" ;;
        critical) color="$RED" ;;
        *)        color="$NC" ;;
    esac
    
    printf "%b%-15s %b%8s %b %s\n" "$BOLD" "$label:" "$color" "$value" "$NC" "$unit" >&2
}

################################################################################
# PROGRESS DISPLAY
################################################################################

# ui_progress_bar: Display animated progress bar
ui_progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-40}"
    local message="${4:-Progress}"
    
    if ! is_number "$current" || ! is_number "$total"; then
        return 1
    fi
    
    if (( total == 0 )); then
        total=1
    fi
    
    local percentage=$((current * 100 / total))
    local filled=$((percentage * width / 100))
    
    printf "%b%s: [" "$CYAN" "$message" >&2
    printf "%${filled}s" | tr ' ' '█' >&2
    printf "%$((width-filled))s" | tr ' ' '░' >&2
    printf "] %d%% (%d/%d)%b\n" "$percentage" "$current" "$total" "$NC" >&2
}

# ui_spinner: Show spinner animation
ui_spinner() {
    local message="$1"
    local -a frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local frame=0
    
    # This would typically be called in a background process
    while true; do
        printf "\r%b%s %s%b" "$CYAN" "${frames[$((frame % ${#frames[@]}))]}" "$message" "$NC" >&2
        ((frame++))
        sleep 0.1
    done
}

################################################################################
# ANALYSIS DISPLAY
################################################################################

# ui_show_route_analysis: Display route analysis results
ui_show_route_analysis() {
    local hops="$1"
    local instability="$2"
    local international="$3"
    
    ui_print_subheader "Route Analysis"
    
    ui_print_metric "Hop Count" "$hops" "hops"
    ui_print_metric "Route Changes" "$instability" "changes"
    
    if [ "$international" = "1" ]; then
        ui_print_warning "International route detected"
    else
        ui_print_info "Domestic/regional route"
    fi
}

# ui_show_quality_breakdown: Display quality score breakdown
ui_show_quality_breakdown() {
    local latency="$1"
    local jitter="$2"
    local loss="$3"
    local hops="$4"
    
    ui_print_subheader "Quality Metrics"
    
    # Determine colors based on thresholds
    if (( $(echo "$latency <= 50" | bc -l) )); then
        ui_show_metric_assessment "Latency" "$latency" "ms" "good"
    elif (( $(echo "$latency <= 100" | bc -l) )); then
        ui_show_metric_assessment "Latency" "$latency" "ms" "warning"
    else
        ui_show_metric_assessment "Latency" "$latency" "ms" "critical"
    fi
    
    if (( $(echo "$jitter <= 20" | bc -l) )); then
        ui_show_metric_assessment "Jitter" "$jitter" "ms" "good"
    elif (( $(echo "$jitter <= 50" | bc -l) )); then
        ui_show_metric_assessment "Jitter" "$jitter" "ms" "warning"
    else
        ui_show_metric_assessment "Jitter" "$jitter" "ms" "critical"
    fi
    
    if (( $(echo "$loss == 0" | bc -l) )); then
        ui_show_metric_assessment "Packet Loss" "$loss" "%" "good"
    elif (( $(echo "$loss <= 0.5" | bc -l) )); then
        ui_show_metric_assessment "Packet Loss" "$loss" "%" "warning"
    else
        ui_show_metric_assessment "Packet Loss" "$loss" "%" "critical"
    fi
    
    ui_print_metric "Hop Count" "$hops" "hops"
}

################################################################################
# WAITING/COMPLETION DISPLAY
################################################################################

# ui_wait_message: Display wait message with countdown
ui_wait_message() {
    local seconds="$1"
    local message="${2:-Waiting}"
    
    if ! is_number "$seconds"; then
        return 1
    fi
    
    for ((i=seconds; i>0; i--)); do
        printf "\r%b%s... %d%b" "$CYAN" "$message" "$i" "$NC" >&2
        sleep 1
    done
    printf "\r%*s\r" "$((${#message} + 5))" "" >&2
}

# ui_done: Show completion message
ui_done() {
    local message="${1:-Done}"
    ui_print_success "$message"
}

# ui_clear_line: Clear current line
ui_clear_line() {
    printf "\r%*s\r" "80" "" >&2
}

