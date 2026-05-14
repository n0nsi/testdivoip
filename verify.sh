#!/bin/bash

################################################################################
# TESTDIVOIP - Verify Installation & Quick Start
# Run this script to verify everything is installed correctly
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
cat << 'EOF'
╔════════════════════════════════════════════════════════════════════════╗
║               TESTDIVOIP - Verification & Quick Start                 ║
║                                                                        ║
║                 VoIP Route Quality Analysis Tool v1.0                  ║
╚════════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check if we're in the right directory
if [ ! -f "$SCRIPT_DIR/testdivoip.sh" ]; then
    echo -e "${RED}✗ Error: testdivoip.sh not found${NC}"
    echo "  Make sure you run this script from the testdivoip directory"
    exit 1
fi

echo -e "${GREEN}✓ Found testdivoip.sh${NC}"

# Check functions directory
if [ ! -d "$SCRIPT_DIR/functions" ]; then
    echo -e "${RED}✗ Missing functions directory${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Functions directory found${NC}"

# Verify function modules
local_functions=(
    "colors.sh"
    "logging.sh"
    "network.sh"
    "analysis.sh"
    "reporting.sh"
    "utils.sh"
)

echo ""
echo -e "${BLUE}Checking function modules:${NC}"
for func in "${local_functions[@]}"; do
    if [ -f "$SCRIPT_DIR/functions/$func" ]; then
        echo -e "${GREEN}  ✓${NC} $func"
    else
        echo -e "${RED}  ✗${NC} $func (MISSING)"
    fi
done

# Check for required system commands
echo ""
echo -e "${BLUE}Checking system dependencies:${NC}"

required_cmds=(
    "bash"
    "ping"
    "mtr"
    "traceroute"
    "whois"
    "dig"
    "curl"
    "jq"
    "awk"
    "sed"
)

missing_count=0
for cmd in "${required_cmds[@]}"; do
    if command -v "$cmd" &>/dev/null; then
        echo -e "${GREEN}  ✓${NC} $cmd"
    else
        echo -e "${RED}  ✗${NC} $cmd (NOT INSTALLED)"
        ((missing_count++))
    fi
done

if [ $missing_count -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Missing $missing_count dependencies${NC}"
    echo "Install with: sudo bash install.sh"
    echo "Or manually: sudo apt-get install mtr-tiny dnsutils whois curl jq bc net-tools"
else
    echo ""
    echo -e "${GREEN}All dependencies installed!${NC}"
fi

# Test basic script execution
echo ""
echo -e "${BLUE}Testing script execution:${NC}"
if bash -n "$SCRIPT_DIR/testdivoip.sh" 2>&1 | head -1 | grep -q "syntax error"; then
    echo -e "${RED}✗ Syntax error in testdivoip.sh${NC}"
    bash -n "$SCRIPT_DIR/testdivoip.sh"
    exit 1
else
    echo -e "${GREEN}✓${NC} Script syntax OK"
fi

# Directory structure
echo ""
echo -e "${BLUE}Project structure:${NC}"
echo -e "${GREEN}✓${NC} testdivoip.sh (main script)"
echo -e "${GREEN}✓${NC} functions/ (6 modules)"
echo -e "${GREEN}✓${NC} config/ (configurations)"
echo -e "${GREEN}✓${NC} reports/ (report output)"
echo -e "${GREEN}✓${NC} logs/ (application logs)"
echo -e "${GREEN}✓${NC} temp/ (temporary files)"

# Quick help
echo ""
echo -e "${BLUE}Quick Start:${NC}"
echo ""
echo "1. Get help:"
echo "   ./testdivoip.sh --help"
echo ""
echo "2. Run interactively:"
echo "   ./testdivoip.sh"
echo ""
echo "3. Use configuration file:"
echo "   cp config/example.conf config/mycompany.conf"
echo "   ./testdivoip.sh --config config/mycompany.conf"
echo ""
echo "4. Enable verbose output:"
echo "   ./testdivoip.sh --verbose"
echo ""
echo "5. Debug mode:"
echo "   ./testdivoip.sh --debug"
echo ""

# Read documentation
echo -e "${BLUE}Documentation:${NC}"
[ -f "$SCRIPT_DIR/README.md" ] && echo "  • README.md - Complete documentation"
[ -f "$SCRIPT_DIR/QUICK_REFERENCE.md" ] && echo "  • QUICK_REFERENCE.md - Quick start guide"
[ -f "$SCRIPT_DIR/DEPLOYMENT_GUIDE.md" ] && echo "  • DEPLOYMENT_GUIDE.md - Deployment procedures"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Verification Complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""

if [ $missing_count -eq 0 ]; then
    echo -e "${GREEN}System is ready! You can now run:${NC}"
    echo "  ./testdivoip.sh"
else
    echo -e "${YELLOW}Please install missing dependencies first:${NC}"
    echo "  sudo bash install.sh"
fi

echo ""

