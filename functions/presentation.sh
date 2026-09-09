#!/bin/bash

# Small terminal UI used by testdivoip.sh.

if [ -z "${NC+x}" ]; then
    PRESENTATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    # shellcheck source=/dev/null
    source "${PRESENTATION_DIR}/colors.sh" || return 1
fi

ui_print_success() {
    printf '%b✓ %s%b\n' "$GREEN" "$1" "$NC" >&2
}

ui_print_error() {
    printf '%b✗ %s%b\n' "$RED" "$1" "$NC" >&2
}

ui_print_warning() {
    printf '%b⚠ %s%b\n' "$YELLOW" "$1" "$NC" >&2
}

ui_print_info() {
    printf '%bℹ %s%b\n' "$BLUE" "$1" "$NC" >&2
}

ui_print_debug() {
    [ "${DEBUG:-0}" = "1" ] && printf '%b➤ %s%b\n' "$MAGENTA" "$1" "$NC" >&2
}

ui_print_header() {
    local text="$1"
    local width="${3:-60}"
    local char="${2:-=}"

    printf '\n%b' "$BOLD" >&2
    printf '%*s\n' "$width" '' | tr ' ' "$char" >&2
    printf ' %s\n' "$text" >&2
    printf '%*s\n' "$width" '' | tr ' ' "$char" >&2
    printf '%b\n' "$NC" >&2
}

ui_print_subheader() {
    printf '\n%b▸ %s%b\n' "$CYAN" "$1" "$NC" >&2
}

ui_print_metric() {
    local label="$1"
    local value="$2"
    local unit="${3:-}"
    printf '%b%-20s%b %s %s\n' "$BOLD" "$label:" "$NC" "$value" "$unit" >&2
}

ui_prompt_text() {
    local prompt="$1"
    local default="${2:-}"
    local input

    if [ -n "$default" ]; then
        printf '%b%s%b [%s]: ' "$BOLD" "$prompt" "$NC" "$default" >&2
    else
        printf '%b%s%b: ' "$BOLD" "$prompt" "$NC" >&2
    fi

    IFS= read -r input
    printf '%s\n' "${input:-$default}"
}

ui_prompt_yes_no() {
    local prompt="$1"
    local response

    printf '%b%s%b [y/N]: ' "$BOLD" "$prompt" "$NC" >&2
    IFS= read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

ui_prompt_number() {
    local prompt="$1"
    local default="${2:-}"
    local input

    while true; do
        input=$(ui_prompt_text "$prompt" "$default")
        if is_number "$input"; then
            printf '%s\n' "$input"
            return 0
        fi
        ui_print_error "Expected a non-negative integer, got: $input"
    done
}

ui_prompt_ip() {
    local prompt="$1"
    local default="${2:-}"
    local input

    while true; do
        input=$(ui_prompt_text "$prompt" "$default")
        if is_valid_ip "$input"; then
            printf '%s\n' "$input"
            return 0
        fi
        ui_print_error "Invalid IPv4 address: $input"
    done
}

ui_show_quality_status() {
    local category="$1"
    local score="$2"
    local color="$NC"

    case "$category" in
        EXCELENTE) color="$GREEN" ;;
        BOM) color="$CYAN" ;;
        ATENÇÃO) color="$YELLOW" ;;
        CRÍTICO) color="$RED" ;;
    esac

    printf '%b%s%b (score %s/100)\n' "$color" "$category" "$NC" "$score" >&2
}
