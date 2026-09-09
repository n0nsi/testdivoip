#!/bin/bash

if [ -n "${TESTDIVOIP_COLORS_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
TESTDIVOIP_COLORS_LOADED=1

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

print_success() {
    printf '%b✓%b %s\n' "$GREEN" "$NC" "$1"
}

print_error() {
    printf '%b✗%b %s\n' "$RED" "$NC" "$1" >&2
}

print_warning() {
    printf '%b⚠%b %s\n' "$YELLOW" "$NC" "$1" >&2
}

print_info() {
    printf '%bℹ%b %s\n' "$BLUE" "$NC" "$1"
}
