#!/bin/bash

################################################################################
# TESTDIVOIP Installation Script
# Installs dependencies and sets up the testing environment
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PREFIX="${INSTALL_PREFIX:-/opt/testdivoip}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

################################################################################
# FUNCTIONS
################################################################################

print_header() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════════════╗
║                   TESTDIVOIP Installation Script                      ║
║                                                                        ║
║              VoIP Route Quality Analysis Tool Installer                ║
╚════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

################################################################################
# SYSTEM CHECKS
################################################################################

check_os() {
    print_info "Detecting operating system..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        
        if [[ "$ID" == "debian" || "$ID" == "ubuntu" ]]; then
            print_success "Running on: $PRETTY_NAME"
            return 0
        else
            print_error "Unsupported OS: $PRETTY_NAME"
            print_warning "This tool is designed for Debian/Ubuntu"
            return 1
        fi
    else
        print_error "Cannot detect OS"
        return 1
    fi
}

check_bash() {
    local bash_version="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
    
    if (( BASH_VERSINFO[0] >= 4 )); then
        print_success "bash version: $bash_version"
        return 0
    else
        print_error "bash 4.0+ required (current: $bash_version)"
        return 1
    fi
}

check_root() {
    if [[ "$INSTALL_PREFIX" != "/opt"* ]] || [[ "$INSTALL_PREFIX" == "/usr/local"* ]]; then
        return 0
    fi
    
    if (( EUID != 0 )); then
        print_warning "Not running as root - installing to user directory"
        INSTALL_PREFIX="$HOME/.local/testdivoip"
        return 0
    fi
    
    return 0
}

################################################################################
# DEPENDENCY INSTALLATION
################################################################################

install_dependencies() {
    print_info "Checking and installing dependencies..."
    
    local deps_needed=()
    
    # Essential tools
    local essential_packages=(
        "mtr:mtr-tiny"
        "dig:dnsutils"
        "whois:whois"
        "curl:curl"
        "jq:jq"
        "bc:bc"
        "netstat:net-tools"
    )
    
    for package_info in "${essential_packages[@]}"; do
        local cmd="${package_info%:*}"
        local package="${package_info#*:}"
        
        if ! command -v "$cmd" &>/dev/null; then
            print_warning "Missing: $cmd"
            deps_needed+=("$package")
        else
            print_success "Found: $cmd"
        fi
    done
    
    if [ ${#deps_needed[@]} -gt 0 ]; then
        print_info "Installing missing packages: ${deps_needed[*]}"
        
        if [ -f /etc/debian_version ]; then
            sudo apt-get update -qq
            sudo apt-get install -y "${deps_needed[@]}"
            print_success "Packages installed"
        else
            print_error "Cannot install packages on this system"
            return 1
        fi
    else
        print_success "All dependencies are installed"
    fi
    
    return 0
}

################################################################################
# INSTALLATION
################################################################################

setup_directories() {
    print_info "Creating installation directories..."
    
    mkdir -p "$INSTALL_PREFIX"/{functions,config,reports,logs,temp}
    
    print_success "Directories created: $INSTALL_PREFIX"
}

copy_files() {
    print_info "Copying files to installation directory..."
    
    cp "$SCRIPT_DIR"/testdivoip.sh "$INSTALL_PREFIX/"
    cp -r "$SCRIPT_DIR"/functions/* "$INSTALL_PREFIX"/functions/
    
    # Create symlink in /usr/local/bin if root
    if (( EUID == 0 )); then
        ln -sf "$INSTALL_PREFIX/testdivoip.sh" /usr/local/bin/testdivoip
        print_success "Created symlink: /usr/local/bin/testdivoip"
    fi
    
    # Make scripts executable
    chmod +x "$INSTALL_PREFIX"/testdivoip.sh
    chmod +x "$INSTALL_PREFIX"/functions/*.sh
    
    print_success "Files copied"
}

create_example_config() {
    print_info "Creating example configuration file..."
    
    cat > "$INSTALL_PREFIX/config/example.conf" << 'EOF'
#!/bin/bash
# Example configuration for testdivoip

# Client Information
export CLIENT_NAME="Example Client"
export SCENARIO_NAME="Production Environment"
export CLOUD_PROVIDER="AWS"
export PABX_IP="192.168.1.100"

# Office Locations
declare -a OFFICE_NAMES=("HQ" "Branch-1" "Branch-2")
declare -a OFFICE_IPS=("203.0.113.10" "203.0.113.20" "203.0.113.30")

# SIP Trunks
declare -a TRUNK_NAMES=("Carrier-1" "Carrier-2")
declare -a TRUNK_IPS=("198.51.100.10" "198.51.100.20")

# Advanced Options
export MTR_PACKETS=100
export VERBOSE=0
export DEBUG=0
EOF
    
    print_success "Example configuration created: $INSTALL_PREFIX/config/example.conf"
}

################################################################################
# VERIFICATION
################################################################################

verify_installation() {
    print_info "Verifying installation..."
    
    local errors=0
    
    # Check main script
    if [ -x "$INSTALL_PREFIX/testdivoip.sh" ]; then
        print_success "Main script is executable"
    else
        print_error "Main script is not executable"
        ((errors++))
    fi
    
    # Check functions
    local required_functions=(
        "colors.sh"
        "logging.sh"
        "network.sh"
        "analysis.sh"
        "reporting.sh"
        "utils.sh"
    )
    
    for func in "${required_functions[@]}"; do
        if [ -f "$INSTALL_PREFIX/functions/$func" ]; then
            print_success "Function module: $func"
        else
            print_error "Missing function module: $func"
            ((errors++))
        fi
    done
    
    # Check directories
    for dir in functions config reports logs temp; do
        if [ -d "$INSTALL_PREFIX/$dir" ]; then
            print_success "Directory created: $dir"
        else
            print_error "Directory not created: $dir"
            ((errors++))
        fi
    done
    
    if [ $errors -eq 0 ]; then
        print_success "Installation verified successfully"
        return 0
    else
        print_error "Installation verification failed with $errors errors"
        return 1
    fi
}

################################################################################
# FINAL SETUP
################################################################################

print_usage_info() {
    echo ""
    echo -e "${BLUE}╔═ INSTALLATION COMPLETE ═╗${NC}"
    echo ""
    
    if (( EUID == 0 )); then
        print_success "testdivoip installed to: $INSTALL_PREFIX"
        print_success "Command available as: testdivoip"
        print_info "Run 'testdivoip --help' to get started"
    else
        print_success "testdivoip installed to: $INSTALL_PREFIX"
        print_info "Run '$INSTALL_PREFIX/testdivoip.sh --help' to get started"
        print_info "Or add to PATH: export PATH=\"$INSTALL_PREFIX:\$PATH\""
    fi
    
    echo ""
    echo -e "${BLUE}╔═ NEXT STEPS ═╗${NC}"
    echo ""
    print_info "1. Review the README.md file"
    print_info "2. Check example configuration: $INSTALL_PREFIX/config/example.conf"
    print_info "3. Run: $([ $EUID -eq 0 ] && echo 'testdivoip' || echo "$INSTALL_PREFIX/testdivoip.sh") --help"
    print_info "4. Start interactive analysis: $([ $EUID -eq 0 ] && echo 'testdivoip' || echo "$INSTALL_PREFIX/testdivoip.sh")"
    
    echo ""
}

################################################################################
# MAIN
################################################################################

main() {
    print_header
    
    # System checks
    if ! check_os; then
        exit 1
    fi
    
    check_bash || exit 1
    check_root
    
    # Install dependencies
    if ! install_dependencies; then
        print_error "Failed to install dependencies"
        exit 1
    fi
    
    echo ""
    
    # Setup
    setup_directories
    copy_files
    create_example_config
    
    echo ""
    
    # Verify
    if ! verify_installation; then
        print_error "Installation verification failed"
        exit 1
    fi
    
    # Print usage info
    print_usage_info
}

# Run main
main "$@"

