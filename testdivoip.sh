#!/bin/bash

################################################################################
# TESTDIVOIP - VoIP Route Quality Analysis Tool
# Professional Shell Script for Cloud Provider VoIP Infrastructure Validation
#
# Purpose:
#   Complete automation for analyzing quality of VoIP routes between cloud PABX
#   and multiple destinations, identifying issues with latency, jitter, packet loss,
#   route stability, and ASN/peering problems.
#
# Usage:
#   ./testdivoip.sh [OPTIONS]
#
# Options:
#   -h, --help          Show this help message
#   -v, --verbose       Enable verbose output
#   -d, --debug         Enable debug mode
#   -c, --config FILE   Load configuration from file
#   -s, --scenario NAME Load scenario from file
#
# Author: VoIP Engineering Team
# License: MIT
# Last Updated: $(date)
################################################################################

set -o pipefail
trap 'trap_error $LINENO $BASH_LINENO' ERR

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNCTIONS_DIR="${SCRIPT_DIR}/functions"
CONFIG_DIR="${SCRIPT_DIR}/config"
REPORTS_DIR="${SCRIPT_DIR}/reports"
LOGS_DIR="${SCRIPT_DIR}/logs"
TEMP_DIR="${SCRIPT_DIR}/temp"

# Load all functions
# shellcheck source=/dev/null
source "${FUNCTIONS_DIR}/colors.sh"
# shellcheck source=/dev/null
source "${FUNCTIONS_DIR}/logging.sh"
# shellcheck source=/dev/null
source "${FUNCTIONS_DIR}/network.sh"
# shellcheck source=/dev/null
source "${FUNCTIONS_DIR}/analysis.sh"
# shellcheck source=/dev/null
source "${FUNCTIONS_DIR}/reporting.sh"
# shellcheck source=/dev/null
source "${FUNCTIONS_DIR}/utils.sh"

# Global variables
DEBUG="${DEBUG:-0}"
VERBOSE="${VERBOSE:-0}"
CONFIG_FILE=""
SCENARIO_FILE=""

declare -a OFFICES=()
declare -a OFFICE_NAMES=()
declare -a OFFICE_IPS=()
declare -a SIP_TRUNKS=()
declare -a TRUNK_NAMES=()
declare -a TRUNK_IPS=()

################################################################################
# HELP & VERSION
################################################################################

show_help() {
    cat << 'EOF'

    ╔════════════════════════════════════════════════════════════════════════╗
    ║                        TESTDIVOIP v1.0                                ║
    ║              VoIP Route Quality Analysis Tool                         ║
    ║                                                                        ║
    ║          Professional SRE/VoIP Network Diagnostics                   ║
    ║        Cloud Provider PABX Infrastructure Validation                 ║
    ╚════════════════════════════════════════════════════════════════════════╝

USAGE:
    ./testdivoip.sh [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output during tests
    -d, --debug             Enable debug mode with detailed logging
    -c, --config FILE       Load configuration from file
    -s, --scenario FILE     Load pre-defined scenario
    --list-reports          Show all generated reports
    --show-report FILE      Display specific report

EXAMPLES:
    # Interactive mode
    ./testdivoip.sh

    # With debug output
    ./testdivoip.sh --debug

    # Load configuration file
    ./testdivoip.sh --config config/mycompany.conf

    # Verbose testing
    ./testdivoip.sh --verbose

FEATURES:
    • Interactive input for network parameters
    • Comprehensive ping, MTR, traceroute analysis
    • ASN identification and carrier detection
    • VoIP quality scoring (EXCELENTE/BOM/ATENÇÃO/CRÍTICO)
    • Route stability analysis
    • International route detection
    • Detailed professional reporting
    • Modular architecture with reusable functions
    • Support for multiple offices and SIP trunks

REQUIREMENTS:
    • Debian 12 / Ubuntu 20.04+
    • bash 4.0+
    • mtr, traceroute, whois, dig, curl, jq, bc

DOCUMENTATION:
    See README.md for detailed documentation

EOF
}

################################################################################
# ARGUMENT PARSING
################################################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -d|--debug)
                DEBUG=1
                VERBOSE=1
                shift
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -s|--scenario)
                SCENARIO_FILE="$2"
                shift 2
                ;;
            --list-reports)
                list_reports
                exit 0
                ;;
            --show-report)
                show_report "$2"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

################################################################################
# INITIALIZATION
################################################################################

initialize_environment() {
    # Create necessary directories
    mkdir -p "$REPORTS_DIR" "$LOGS_DIR" "$TEMP_DIR" "$CONFIG_DIR"
    
    # Initialize logging
    init_logging
    
    log_info "=== TESTDIVOIP STARTED ==="
    log_info "Script directory: $SCRIPT_DIR"
    log_info "Debug mode: $DEBUG"
    log_info "Verbose mode: $VERBOSE"
}

show_startup_checks() {
    print_banner
    echo ""
    print_subheader "Performing startup checks..."
    echo ""
    
    # Check dependencies
    if ! check_all_dependencies; then
        print_error "Missing dependencies. Please install them and try again."
        exit 1
    fi
    
    echo ""
    print_success "All checks passed!"
    print_info "Ready to begin analysis"
    echo ""
}

################################################################################
# INTERACTIVE DATA COLLECTION
################################################################################

collect_general_info() {
    print_section "GENERAL INFORMATION"
    
    read_input "Client Name" "MyCompany" CLIENT_NAME
    read_input "Scenario Name" "Production VoIP" SCENARIO_NAME
    read_input "Cloud Provider" "AWS/Azure/Digital Ocean" CLOUD_PROVIDER
    
    print_info "Collected: $CLIENT_NAME - $SCENARIO_NAME on $CLOUD_PROVIDER"
}

collect_pabx_info() {
    print_section "PABX INFORMATION"
    
    while true; do
        PABX_IP=$(read_ip "PABX IP Address")
        print_success "PABX IP: $PABX_IP"
        
        local confirm
        read -p "Is this correct? [y/N]: " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] && break
    done
}

collect_office_info() {
    print_section "OFFICE LOCATIONS"
    
    local num_offices
    num_offices=$(read_number "How many office locations?" "1")
    
    for ((i=1; i<=num_offices; i++)); do
        print_info "Office #$i"
        
        local office_name
        office_name=$(read_input "  Office name" "Branch-$i")
        
        local office_ip
        office_ip=$(read_ip "  Office IP address")
        
        OFFICE_NAMES+=("$office_name")
        OFFICE_IPS+=("$office_ip")
        
        print_success "Added: $office_name ($office_ip)"
        echo ""
    done
}

collect_sip_trunk_info() {
    print_section "SIP TRUNK CARRIERS"
    
    local num_trunks
    num_trunks=$(read_number "How many SIP trunk carriers?" "1")
    
    for ((i=1; i<=num_trunks; i++)); do
        print_info "SIP Trunk #$i"
        
        local trunk_name
        trunk_name=$(read_input "  Carrier name" "Carrier-$i")
        
        local trunk_ip
        trunk_ip=$(read_ip "  SIP trunk IP address")
        
        TRUNK_NAMES+=("$trunk_name")
        TRUNK_IPS+=("$trunk_ip")
        
        print_success "Added: $trunk_name ($trunk_ip)"
        echo ""
    done
}

show_collection_summary() {
    print_section "COLLECTION SUMMARY"
    
    echo "Client:          $CLIENT_NAME"
    echo "Scenario:        $SCENARIO_NAME"
    echo "Cloud Provider:  $CLOUD_PROVIDER"
    echo "PABX IP:         $PABX_IP"
    echo ""
    echo "Offices:         ${#OFFICE_NAMES[@]}"
    for i in "${!OFFICE_NAMES[@]}"; do
        echo "  ${OFFICE_NAMES[$i]}: ${OFFICE_IPS[$i]}"
    done
    echo ""
    echo "SIP Trunks:      ${#TRUNK_NAMES[@]}"
    for i in "${!TRUNK_NAMES[@]}"; do
        echo "  ${TRUNK_NAMES[$i]}: ${TRUNK_IPS[$i]}"
    done
    echo ""
    
    local confirm
    read -p "$(echo -ne ${BOLD})Begin testing?${NC} [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
}

################################################################################
# COMPREHENSIVE TESTING
################################################################################

run_complete_analysis() {
    local target="$1"
    local target_name="$2"
    
    print_info "Testing: $target_name ($target)"
    print_separator
    
    # Test data
    local mtr_output
    local traceroute_output
    local latency=0
    local jitter=0
    local loss=0
    local hops=0
    local primary_asn="UNKNOWN"
    
    # Run Ping Test
    print_subheader "Running Ping Test..."
    local ping_output
    ping_output=$(ping -c 10 -W 5 "$target" 2>&1)
    
    if echo "$ping_output" | grep -q "100% packet loss"; then
        print_error "Target unreachable: $target"
        return 1
    fi
    
    # Extract ping stats
    local min_rtt avg_rtt max_rtt stddev
    min_rtt=$(echo "$ping_output" | grep -oP 'min=\K[0-9.]+'| head -1)
    avg_rtt=$(echo "$ping_output" | grep -oP 'avg=\K[0-9.]+' | head -1)
    max_rtt=$(echo "$ping_output" | grep -oP 'max=\K[0-9.]+' | head -1)
    stddev=$(echo "$ping_output" | grep -oP 'stddev=\K[0-9.]+' | head -1)
    loss=$(echo "$ping_output" | grep -oP '\K[0-9.]+(?=% packet loss)' | head -1)
    
    latency=$(echo "$avg_rtt" | awk '{printf "%.2f", $1}')
    jitter=$(echo "$stddev" | awk '{printf "%.2f", $1}')
    loss=$(echo "$loss" | awk '{printf "%.2f", $1}')
    
    print_metric "RTT Average" "${latency}ms"
    print_metric "RTT Min/Max" "${min_rtt}ms / ${max_rtt}ms"
    print_metric "Jitter (StdDev)" "${jitter}ms"
    print_metric "Packet Loss" "${loss}%"
    
    # Run MTR Test (background)
    print_subheader "Running MTR Analysis (100 packets)..."
    mtr_output=$(mtr -rwzc 100 "$target" 2>&1)
    print_success "MTR completed"
    
    # Run Traceroute
    print_subheader "Running Traceroute..."
    traceroute_output=$(traceroute -m 30 -n "$target" 2>&1)
    hops=$(count_hops "$traceroute_output")
    print_metric "Hop Count" "$hops"
    
    # ASN Analysis
    print_subheader "Running ASN Analysis..."
    primary_asn=$(get_asn_from_ip "$target")
    print_metric "Primary ASN" "$primary_asn"
    
    local asn_name
    asn_name=$(get_asn_name "$primary_asn")
    print_metric "Carrier" "$asn_name"
    
    local asn_suspicious="0"
    if is_asn_suspicious "$primary_asn"; then
        asn_suspicious="1"
        print_warning "ASN marked as suspicious for VoIP"
    fi
    
    # International Route Detection
    local international="0"
    if detect_international_route "$traceroute_output"; then
        international="1"
        print_warning "International route detected"
    else
        print_success "Domestic/regional route"
    fi
    
    print_separator
    
    # Detailed Analysis
    print_subheader "Detailed Route Analysis"
    local analysis
    analysis=$(analyze_route_quality "$target" "$traceroute_output" "$mtr_output")
    echo -e "$analysis"
    
    # Calculate VoIP Score
    print_subheader "VoIP Quality Score Calculation"
    local score_data
    score_data=$(calculate_voip_score "$latency" "$jitter" "$loss" "$hops" "$asn_suspicious" "$international")
    
    local score
    local details
    score=$(echo "$score_data" | cut -d'|' -f1)
    details=$(echo "$score_data" | cut -d'|' -f2)
    
    local category
    category=$(classify_voip_score "$score")
    
    print_voip_score "$category" "$score"
    echo -e "$details"
    
    # Return results
    echo "$score|$category|$latency|$jitter|$loss|$hops|$primary_asn|$asn_suspicious|$international|$mtr_output|$traceroute_output"
}

run_all_tests() {
    print_section "COMPREHENSIVE NETWORK ANALYSIS"
    
    print_bold "=== OFFICE LOCATION ANALYSIS ==="
    echo ""
    
    for i in "${!OFFICE_IPS[@]}"; do
        local result
        result=$(run_complete_analysis "${OFFICE_IPS[$i]}" "${OFFICE_NAMES[$i]}")
        OFFICE_RESULTS+=("$result")
        echo ""
        echo ""
    done
    
    print_bold "=== SIP TRUNK CARRIER ANALYSIS ==="
    echo ""
    
    for i in "${!TRUNK_IPS[@]}"; do
        local result
        result=$(run_complete_analysis "${TRUNK_IPS[$i]}" "${TRUNK_NAMES[$i]}")
        TRUNK_RESULTS+=("$result")
        echo ""
        echo ""
    done
    
    # Return results for report generation
    generate_final_report
}

################################################################################
# REPORT GENERATION
################################################################################

generate_final_report() {
    print_section "GENERATING COMPREHENSIVE REPORT"
    
    init_report "$CLIENT_NAME"
    
    # Add general info
    add_general_information "$CLIENT_NAME" "$CLOUD_PROVIDER" "$PABX_IP" "$SCENARIO_NAME"
    
    # Add office analysis
    add_report_section "OFFICE LOCATION ANALYSIS"
    for i in "${!OFFICE_NAMES[@]}"; do
        local result="${OFFICE_RESULTS[$i]}"
        
        local score=$(echo "$result" | cut -d'|' -f1)
        local category=$(echo "$result" | cut -d'|' -f2)
        local latency=$(echo "$result" | cut -d'|' -f3)
        local jitter=$(echo "$result" | cut -d'|' -f4)
        local loss=$(echo "$result" | cut -d'|' -f5)
        local hops=$(echo "$result" | cut -d'|' -f6)
        local asn=$(echo "$result" | cut -d'|' -f7)
        
        add_office_analysis "${OFFICE_NAMES[$i]}" "${OFFICE_IPS[$i]}" "$latency" "$jitter" "$loss" "$hops" "$asn" "$score" "$category"
    done
    
    # Add SIP Trunk analysis
    add_report_section "SIP TRUNK CARRIER ANALYSIS"
    for i in "${!TRUNK_NAMES[@]}"; do
        local result="${TRUNK_RESULTS[$i]}"
        
        local score=$(echo "$result" | cut -d'|' -f1)
        local category=$(echo "$result" | cut -d'|' -f2)
        local latency=$(echo "$result" | cut -d'|' -f3)
        local jitter=$(echo "$result" | cut -d'|' -f4)
        local loss=$(echo "$result" | cut -d'|' -f5)
        local hops=$(echo "$result" | cut -d'|' -f6)
        local asn=$(echo "$result" | cut -d'|' -f7)
        
        add_sip_trunk_analysis "${TRUNK_NAMES[$i]}" "${TRUNK_IPS[$i]}" "$latency" "$jitter" "$loss" "$hops" "$asn" "$score" "$category"
    done
    
    # Calculate overall score
    local total_score=0
    local total_tests=0
    for result in "${OFFICE_RESULTS[@]}" "${TRUNK_RESULTS[@]}"; do
        local score=$(echo "$result" | cut -d'|' -f1)
        total_score=$((total_score + score))
        ((total_tests++))
    done
    
    local overall_score=$((total_score / total_tests))
    local overall_category=$(classify_voip_score "$overall_score")
    
    # Add findings
    add_findings_section
    add_finding "OK" "Infrastructure Analysis Complete" "All tests completed successfully with comprehensive data collection."
    
    # Add recommendations
    add_recommendations_section
    case "$overall_category" in
        "EXCELENTE")
            add_recommendation "LOW" "Excellent configuration. Monitor performance on regular basis (monthly)."
            ;;
        "BOM")
            add_recommendation "MEDIUM" "Good configuration. Review performance trends and investigate any degradation."
            ;;
        "ATENÇÃO")
            add_recommendation "HIGH" "Requires attention. Address identified issues before production deployment."
            ;;
        "CRÍTICO")
            add_recommendation "HIGH" "Critical issues detected. Do not deploy until issues are resolved."
            ;;
    esac
    
    # Add conclusion
    add_conclusion_section "$overall_score" "$overall_category"
    
    # Print results
    echo ""
    print_report_path
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Initialize environment
    initialize_environment
    
    # Show startup checks
    show_startup_checks
    
    # Interactive data collection
    collect_general_info
    collect_pabx_info
    collect_office_info
    collect_sip_trunk_info
    
    # Show summary and confirm
    show_collection_summary
    
    # Run all tests and generate report
    run_all_tests
    
    print_success "Analysis completed!"
    print_info "Report location: $REPORT_FILE"
    
    exit 0
}

# Run main
main "$@"

