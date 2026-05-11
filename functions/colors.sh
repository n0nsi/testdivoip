#!/bin/bash

################################################################################
# PRESENTATION LAYER - colors.sh
# UI functions ONLY - never contaminate data output
# ALL output to stdout is for terminal display only
################################################################################

# ANSI Colors - ONLY for display
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly UNDERLINE='\033[4m'

# High intensity colors
readonly BRIGHT_RED='\033[1;31m'
readonly BRIGHT_GREEN='\033[1;32m'
readonly BRIGHT_YELLOW='\033[1;33m'
readonly BRIGHT_BLUE='\033[1;34m'
readonly BRIGHT_CYAN='\033[1;36m'
readonly BRIGHT_WHITE='\033[1;37m'

################################################################################
# OUTPUT FUNCTIONS
################################################################################

print_header() {
    local text="$1"
    local char="${2:-=}"
    echo ""
    printf "%s\n" "${BRIGHT_CYAN}${text}${NC}"
    printf "%${#text}s\n" | sed "s/ /${char}/g" | sed "s/^/${BRIGHT_CYAN}/" | sed "s/$/${NC}/"
    echo ""
}

print_subheader() {
    local text="$1"
    echo ""
    printf "${BRIGHT_BLUE}▶ ${text}${NC}\n"
}

print_success() {
    printf "${BRIGHT_GREEN}✓${NC} ${1}\n"
}

print_error() {
    printf "${BRIGHT_RED}✗${NC} ${1}\n"
}

print_warning() {
    printf "${BRIGHT_YELLOW}⚠${NC} ${1}\n"
}

print_info() {
    printf "${BLUE}ℹ${NC} ${1}\n"
}

print_debug() {
    [ "$DEBUG" = "1" ] && printf "${DIM}[DEBUG]${NC} ${1}\n"
}

print_separator() {
    local char="${1:-─}"
    local color="${2:-${DIM}}"
    printf "%s\n" "${color}$(printf '%*s' "80" | tr ' ' "${char}")${NC}"
}

print_bold() {
    printf "${BOLD}${1}${NC}\n"
}

print_dimmed() {
    printf "${DIM}${1}${NC}\n"
}

# Loading animation
print_loading() {
    local text="$1"
    local pid=$2
    local chars=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
    local delay=0.1
    
    while kill -0 "$pid" 2>/dev/null; do
        for char in "${chars[@]}"; do
            printf "\r${CYAN}${char}${NC} ${text}"
            sleep "$delay"
        done
    done
    printf "\r%${#text}s\r" ""
}

# Spinner simpler
spinner() {
    local text="$1"
    local pid=$2
    local i=0
    local sp='-\|/'
    
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${CYAN}${sp:i++%${#sp}:1}${NC} ${text}"
        sleep 0.1
    done
    printf "\r%${#text}s\r" ""
}

################################################################################
# TABLE FUNCTIONS
################################################################################

# Print table row
table_row() {
    local col1="$1"
    local col2="$2"
    local col3="${3:-}"
    printf "${BOLD}%-30s${NC} ${CYAN}:${NC} %-40s"
    [ -n "$col3" ] && printf " ${DIM}%s${NC}" "$col3"
    printf "\n"
    printf "%-30s" "$col1"
}

################################################################################
# BANNER
################################################################################

print_banner() {
    clear
    printf "${BRIGHT_CYAN}"
    cat << 'EOF'
  ╔════════════════════════════════════════════════════════════════════════╗
  ║                                                                        ║
  ║                       🔊  TESTDIVOIP  🔊                              ║
  ║                  VoIP Route Quality Analysis Tool                      ║
  ║                    Cloud Provider Validation                          ║
  ║                                                                        ║
  ║              Professional SRE/VoIP Network Diagnostics                ║
  ║                                                                        ║
  ╚════════════════════════════════════════════════════════════════════════╝
EOF
    printf "${NC}\n"
}

print_small_banner() {
    printf "${BRIGHT_CYAN}"
    echo "┌─ TESTDIVOIP - VoIP Route Quality Analysis"
    printf "${NC}\n"
}

print_section() {
    echo ""
    printf "${BRIGHT_MAGENTA}╔═══════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BRIGHT_MAGENTA}║${NC} ${BOLD}%-55s${NC} ${BRIGHT_MAGENTA}║${NC}\n" "$1"
    printf "${BRIGHT_MAGENTA}╚═══════════════════════════════════════════════════════════╝${NC}\n"
    echo ""
}

################################################################################
# SCORE DISPLAY
################################################################################

print_voip_score() {
    local score="$1"
    local percentage="$2"
    
    case "$score" in
        "EXCELENTE")
            printf "${BRIGHT_GREEN}${BOLD}[$score]${NC} (${percentage}%%) - Fully suitable for VoIP production\n"
            ;;
        "BOM")
            printf "${GREEN}${BOLD}[$score]${NC} (${percentage}%%) - Good for VoIP, monitor performance\n"
            ;;
        "ATENÇÃO")
            printf "${BRIGHT_YELLOW}${BOLD}[$score]${NC} (${percentage}%%) - Needs attention before VoIP deployment\n"
            ;;
        "CRÍTICO")
            printf "${BRIGHT_RED}${BOLD}[$score]${NC} (${percentage}%%) - NOT recommended for VoIP\n"
            ;;
    esac
}

################################################################################
# METRIC DISPLAY
################################################################################

print_metric() {
    local label="$1"
    local value="$2"
    local unit="${3:-}"
    local color="${4:-${CYAN}}"
    
    printf "  ${BOLD}%-25s${NC} ${color}%s${NC} %s\n" "$label" "$value" "$unit"
}

print_metric_with_status() {
    local label="$1"
    local value="$2"
    local unit="$3"
    local threshold="$4"
    
    local color="${BRIGHT_GREEN}"
    local symbol="✓"
    
    if (( $(echo "$value > $threshold" | bc -l) )); then
        color="${BRIGHT_RED}"
        symbol="✗"
    fi
    
    printf "  ${BOLD}%-25s${NC} ${color}${symbol} %s${NC} %s\n" "$label" "$value" "$unit"
}

# Color based on value
get_color_by_value() {
    local value="$1"
    local good_threshold="$2"
    local warning_threshold="$3"
    
    if (( $(echo "$value <= $good_threshold" | bc -l) )); then
        echo "${BRIGHT_GREEN}"
    elif (( $(echo "$value <= $warning_threshold" | bc -l) )); then
        echo "${BRIGHT_YELLOW}"
    else
        echo "${BRIGHT_RED}"
    fi
}

