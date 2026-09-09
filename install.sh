#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if (( EUID == 0 )); then
    INSTALL_PREFIX="${INSTALL_PREFIX:-/opt/testdivoip}"
    BIN_DIR="${BIN_DIR:-/usr/local/bin}"
else
    INSTALL_PREFIX="${INSTALL_PREFIX:-$HOME/.local/share/testdivoip}"
    BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
fi

info()  { printf '[INFO] %s\n' "$*"; }
ok()    { printf '[OK]   %s\n' "$*"; }
error() { printf '[ERR]  %s\n' "$*" >&2; }

check_system() {
    if (( BASH_VERSINFO[0] < 4 )); then
        error "Bash 4 or newer is required"
        return 1
    fi

    if [ ! -f /etc/os-release ]; then
        error "Could not identify the Linux distribution"
        return 1
    fi

    # shellcheck source=/dev/null
    . /etc/os-release

    case "${ID:-}" in
        debian|ubuntu)
            ok "Detected ${PRETTY_NAME:-$ID}"
            ;;
        *)
            error "Automatic dependency installation currently supports Debian/Ubuntu"
            return 1
            ;;
    esac
}

install_dependencies() {
    local -a missing_packages=()
    local entry command_name package_name
    local -a dependencies=(
        "ping:iputils-ping"
        "mtr:mtr-tiny"
        "traceroute:traceroute"
        "whois:whois"
        "bc:bc"
    )

    for entry in "${dependencies[@]}"; do
        command_name="${entry%%:*}"
        package_name="${entry#*:}"
        command -v "$command_name" >/dev/null 2>&1 || missing_packages+=("$package_name")
    done

    if (( ${#missing_packages[@]} == 0 )); then
        ok "Runtime dependencies are already installed"
        return 0
    fi

    info "Installing: ${missing_packages[*]}"

    if (( EUID == 0 )); then
        apt-get update
        apt-get install -y "${missing_packages[@]}"
    else
        if ! command -v sudo >/dev/null 2>&1; then
            error "Missing packages and sudo is not available"
            return 1
        fi
        sudo apt-get update
        sudo apt-get install -y "${missing_packages[@]}"
    fi
}

install_project() {
    info "Installing TESTDIVOIP in $INSTALL_PREFIX"

    mkdir -p "$INSTALL_PREFIX/functions" "$INSTALL_PREFIX/config" \
             "$INSTALL_PREFIX/reports" "$INSTALL_PREFIX/logs" "$INSTALL_PREFIX/temp" \
             "$BIN_DIR"

    install -m 0755 "$SCRIPT_DIR/testdivoip.sh" "$INSTALL_PREFIX/testdivoip.sh"
    install -m 0755 "$SCRIPT_DIR/functions/"*.sh "$INSTALL_PREFIX/functions/"
    install -m 0644 "$SCRIPT_DIR/config/example.conf" "$INSTALL_PREFIX/config/example.conf"

    ln -sfn "$INSTALL_PREFIX/testdivoip.sh" "$BIN_DIR/testdivoip"

    ok "Installed command: $BIN_DIR/testdivoip"
}

verify_installation() {
    local -a required_modules=(
        colors.sh
        logging.sh
        network.sh
        analysis.sh
        reporting.sh
        presentation.sh
    )

    [ -x "$INSTALL_PREFIX/testdivoip.sh" ] || {
        error "Main script was not installed correctly"
        return 1
    }

    local module
    for module in "${required_modules[@]}"; do
        [ -f "$INSTALL_PREFIX/functions/$module" ] || {
            error "Missing installed module: $module"
            return 1
        }
    done

    bash -n "$INSTALL_PREFIX/testdivoip.sh"
    bash -n "$INSTALL_PREFIX/functions/"*.sh

    ok "Syntax check passed"
}

main() {
    check_system
    install_dependencies
    install_project
    verify_installation

    echo ""
    ok "TESTDIVOIP installed"
    echo "Run: $BIN_DIR/testdivoip --help"

    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        echo "Add $BIN_DIR to PATH if you want to call 'testdivoip' directly."
    fi
}

main "$@"
