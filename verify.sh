#!/bin/bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
errors=0

ok()    { printf '[OK]   %s\n' "$*"; }
warn()  { printf '[WARN] %s\n' "$*"; }
error() { printf '[ERR]  %s\n' "$*" >&2; errors=$((errors + 1)); }

check_file() {
    local path="$1"

    if [ -f "$path" ]; then
        ok "$(basename "$path")"
    else
        error "Missing file: $path"
    fi
}

check_command() {
    local command_name="$1"

    if command -v "$command_name" >/dev/null 2>&1; then
        ok "dependency: $command_name"
    else
        error "missing dependency: $command_name"
    fi
}

check_syntax() {
    local path="$1"
    local display_path="${path#"$SCRIPT_DIR"/}"

    if bash -n "$path"; then
        ok "syntax: $display_path"
    else
        error "syntax error: $display_path"
    fi
}

main() {
    echo "TESTDIVOIP verification"
    echo ""

    check_file "$SCRIPT_DIR/testdivoip.sh"
    check_file "$SCRIPT_DIR/install.sh"
    check_file "$SCRIPT_DIR/README.md"
    check_file "$SCRIPT_DIR/config/example.conf"

    local -a modules=(
        logging.sh
        network.sh
        analysis.sh
        reporting.sh
        presentation.sh
    )

    local module
    for module in "${modules[@]}"; do
        check_file "$SCRIPT_DIR/functions/$module"
    done

    echo ""
    echo "Syntax"
    check_syntax "$SCRIPT_DIR/testdivoip.sh"
    check_syntax "$SCRIPT_DIR/install.sh"
    check_syntax "$SCRIPT_DIR/verify.sh"
    for module in "${modules[@]}"; do
        if [ -f "$SCRIPT_DIR/functions/$module" ]; then
            check_syntax "$SCRIPT_DIR/functions/$module"
        fi
    done

    echo ""
    echo "Runtime commands"
    local -a commands=(bash ping mtr traceroute whois timeout bc awk sed grep find)
    local command_name
    for command_name in "${commands[@]}"; do
        check_command "$command_name"
    done

    echo ""
    if [ -x "$SCRIPT_DIR/testdivoip.sh" ]; then
        ok "testdivoip.sh is executable"
    else
        warn "testdivoip.sh is not executable in this checkout (bash testdivoip.sh still works)"
    fi

    if [ "$errors" -eq 0 ]; then
        echo ""
        ok "Repository checks passed"
        echo "Try: ./testdivoip.sh --help"
        return 0
    fi

    echo ""
    printf '[ERR]  %d check(s) need attention\n' "$errors" >&2
    return 1
}

main "$@"
