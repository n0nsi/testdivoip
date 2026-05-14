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

# Resolve the real script path so symlinks and alternate launch locations work.
resolve_script_path() {
    local source_path="${BASH_SOURCE[0]}"
    while [ -L "$source_path" ]; do
        local source_dir
        source_dir="$(cd "$(dirname "$source_path")" && pwd -P)"
        source_path="$(readlink "$source_path")"
        [[ "$source_path" != /* ]] && source_path="$source_dir/$source_path"
    done
    printf '%s\n' "$source_path"
}

SCRIPT_PATH="$(resolve_script_path)"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd -P)"
PROJECT_ROOT="$SCRIPT_DIR"
FUNCTIONS_DIR="${PROJECT_ROOT}/functions"
CONFIG_DIR="${PROJECT_ROOT}/config"
REPORTS_DIR="${PROJECT_ROOT}/reports"
LOGS_DIR="${PROJECT_ROOT}/logs"
TEMP_DIR="${PROJECT_ROOT}/temp"

source_required() {
    local module_file="$1"
    if [ ! -f "$module_file" ]; then
        printf 'Fatal: required module missing: %s\n' "$module_file" >&2
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$module_file" || {
        printf 'Fatal: failed to load module: %s\n' "$module_file" >&2
        exit 1
    }
}

# Load all functions
source_required "${FUNCTIONS_DIR}/colors.sh"
source_required "${FUNCTIONS_DIR}/logging.sh"
source_required "${FUNCTIONS_DIR}/network.sh"
source_required "${FUNCTIONS_DIR}/analysis.sh"
source_required "${FUNCTIONS_DIR}/carrier_intelligence.sh"
source_required "${FUNCTIONS_DIR}/mtr_analysis.sh"
source_required "${FUNCTIONS_DIR}/reporting.sh"
source_required "${FUNCTIONS_DIR}/utils.sh"
source_required "${FUNCTIONS_DIR}/presentation.sh"

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
                ui_print_info "Report listing not yet implemented"
                exit 0
                ;;
            --show-report)
                ui_print_info "Report display not yet implemented"
                exit 0
                ;;
            *)
                ui_print_error "Unknown option: $1"
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
    umask 077

    # Create necessary directories
    mkdir -p "$REPORTS_DIR" "$LOGS_DIR" "$TEMP_DIR" "$CONFIG_DIR"

    LOG_DIR="$LOGS_DIR"
    
    # Initialize logging
    init_logging
    init_audit_log
    
    log_info "=== TESTDIVOIP STARTED ==="
    log_debug "Script directory: $SCRIPT_DIR"
    log_info "Debug mode: $DEBUG"
    log_info "Verbose mode: $VERBOSE"
}

reset_configuration_defaults() {
    CLIENT_NAME=""
    SCENARIO_NAME=""
    CLOUD_PROVIDER=""
    PABX_IP=""

    OFFICE_NAMES=()
    OFFICE_IPS=()
    TRUNK_NAMES=()
    TRUNK_IPS=()
}

trim_whitespace() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

strip_quotes() {
    local value
    value="$(trim_whitespace "$1")"

    if [[ ${#value} -ge 2 ]]; then
        if [[ ("${value:0:1}" == '"' && "${value: -1}" == '"') || ("${value:0:1}" == "'" && "${value: -1}" == "'") ]]; then
            value="${value:1:${#value}-2}"
        fi
    fi

    printf '%s' "$value"
}

set_config_scalar() {
    local key="$1"
    local value="$2"

    case "$key" in
        CLIENT_NAME) CLIENT_NAME="$value" ;;
        SCENARIO_NAME) SCENARIO_NAME="$value" ;;
        CLOUD_PROVIDER) CLOUD_PROVIDER="$value" ;;
        PABX_IP) PABX_IP="$value" ;;
        MTR_PACKETS) MTR_PACKETS="$value" ;;
        VERBOSE) VERBOSE="$value" ;;
        DEBUG) DEBUG="$value" ;;
    esac
}

append_config_array_item() {
    local key="$1"
    local value="$2"

    case "$key" in
        OFFICE_NAMES) OFFICE_NAMES+=("$value") ;;
        OFFICE_IPS) OFFICE_IPS+=("$value") ;;
        TRUNK_NAMES) TRUNK_NAMES+=("$value") ;;
        TRUNK_IPS) TRUNK_IPS+=("$value") ;;
    esac
}

load_configuration_file() {
    local config_path="$1"
    local in_array=""
    local raw_line cleaned_line key value

    reset_configuration_defaults

    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        cleaned_line="$(trim_whitespace "$raw_line")"

        [[ -z "$cleaned_line" || "$cleaned_line" == \#* ]] && continue

        if [[ -n "$in_array" ]]; then
            if [[ "$cleaned_line" == ")" ]]; then
                in_array=""
                continue
            fi

            value="${cleaned_line%%#*}"
            value="$(strip_quotes "$value")"
            [[ -n "$value" ]] && append_config_array_item "$in_array" "$value"
            continue
        fi

        if [[ "$cleaned_line" == declare\ -a* ]]; then
            cleaned_line="${cleaned_line#declare -a }"
            cleaned_line="$(trim_whitespace "$cleaned_line")"
        fi

        if [[ "$cleaned_line" == export\ * ]]; then
            cleaned_line="${cleaned_line#export }"
            cleaned_line="$(trim_whitespace "$cleaned_line")"
        fi

        if [[ "$cleaned_line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=\($ ]]; then
            in_array="${BASH_REMATCH[1]}"
            continue
        fi

        if [[ "$cleaned_line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=\((.*)\)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            value="${value%%#*}"
            value="$(strip_quotes "$value")"
            [[ -n "$value" ]] && append_config_array_item "$key" "$value"
            continue
        fi

        if [[ "$cleaned_line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            value="${value%%#*}"
            value="$(strip_quotes "$value")"
            set_config_scalar "$key" "$value"
        fi
    done < "$config_path"
}

load_configuration() {
    if [[ -n "$CONFIG_FILE" ]]; then
        if [[ -f "$CONFIG_FILE" ]]; then
            ui_print_info "Loading configuration: $CONFIG_FILE"

            load_configuration_file "$CONFIG_FILE"

            ui_print_success "Configuration loaded"
        else
            ui_print_error "Configuration file not found: $CONFIG_FILE"
            exit 1
        fi
    fi
}

show_startup_checks() {
    ui_print_header "TESTDIVOIP v1.0 - VoIP Route Quality Analysis" "=" 60
    
    ui_print_subheader "Performing startup checks..."
    
    # Check dependencies
    if ! check_all_dependencies; then
        ui_print_error "Missing dependencies. Please install them and try again."
        exit 1
    fi
    
    ui_print_success "All checks passed!"
    ui_print_info "Ready to begin analysis"
}

################################################################################
# INTERACTIVE DATA COLLECTION
################################################################################

collect_general_info() {
    # Skip interactive collection if config was loaded and data exists
    if [[ -n "$CONFIG_FILE" ]] && [[ -n "$CLIENT_NAME" ]] && [[ -n "$SCENARIO_NAME" ]] && [[ -n "$CLOUD_PROVIDER" ]]; then
        return 0
    fi
    
    ui_print_header "GENERAL INFORMATION"
    
    CLIENT_NAME=$(ui_prompt_text "Client Name" "${CLIENT_NAME:-MyCompany}")
    SCENARIO_NAME=$(ui_prompt_text "Scenario Name" "${SCENARIO_NAME:-Production VoIP}")
    CLOUD_PROVIDER=$(ui_prompt_text "Cloud Provider" "${CLOUD_PROVIDER:-AWS/Azure/DigitalOcean}")
    
    ui_print_success "General information collected"
}

collect_pabx_info() {
    # Skip interactive collection if PABX_IP already exists from config
    if [[ -n "$CONFIG_FILE" ]] && [[ -n "$PABX_IP" ]]; then
        return 0
    fi
    
    ui_print_header "PABX INFORMATION"
    
    PABX_IP=$(ui_prompt_ip "PABX IP Address" "${PABX_IP:-}")
    ui_print_success "PABX IP: $PABX_IP"
}

collect_office_info() {
    ui_print_header "OFFICE LOCATIONS"
    
    if [[ ${#OFFICE_NAMES[@]} -eq 0 ]]; then
        local num_offices
        num_offices=$(ui_prompt_number "How many office locations?" "1")
        
        for ((i=1; i<=num_offices; i++)); do
            ui_print_subheader "Office #$i"
            
            local office_name office_ip
            office_name=$(ui_prompt_text "Office name" "Branch-$i")
            office_ip=$(ui_prompt_ip "Office IP address")
            
            OFFICE_NAMES+=("$office_name")
            OFFICE_IPS+=("$office_ip")
            
            ui_print_success "Added: $office_name ($office_ip)"
        done
    else
        # Config was loaded with office data
        ui_print_success "Loaded ${#OFFICE_NAMES[@]} offices from config"
        
        # Show offices and ask for confirmation
        ui_print_subheader "Configured Offices:"
        for i in "${!OFFICE_NAMES[@]}"; do
            printf "  %b%d.%b %s: %s\n" "$CYAN" "$((i+1))" "$NC" "${OFFICE_NAMES[$i]}" "${OFFICE_IPS[$i]}" >&2
        done
    fi
}

collect_sip_trunk_info() {
    ui_print_header "SIP TRUNK CARRIERS"
    
    if [[ ${#TRUNK_NAMES[@]} -eq 0 ]]; then
        local num_trunks
        num_trunks=$(ui_prompt_number "How many SIP trunk carriers?" "1")
        
        for ((i=1; i<=num_trunks; i++)); do
            ui_print_subheader "SIP Trunk #$i"
            
            local trunk_name trunk_ip
            trunk_name=$(ui_prompt_text "Carrier name" "Carrier-$i")
            trunk_ip=$(ui_prompt_ip "SIP trunk IP address")
            
            TRUNK_NAMES+=("$trunk_name")
            TRUNK_IPS+=("$trunk_ip")
            
            ui_print_success "Added: $trunk_name ($trunk_ip)"
        done
    else
        # Config was loaded with trunk data
        ui_print_success "Loaded ${#TRUNK_NAMES[@]} SIP trunks from config"
        
        # Show trunks and ask for confirmation
        ui_print_subheader "Configured SIP Trunks:"
        for i in "${!TRUNK_NAMES[@]}"; do
            printf "  %b%d.%b %s: %s\n" "$CYAN" "$((i+1))" "$NC" "${TRUNK_NAMES[$i]}" "${TRUNK_IPS[$i]}" >&2
        done
    fi
}

show_collection_summary() {
    ui_print_header "COLLECTION SUMMARY"
    
    printf "%b%-20s%b %s\n" "$BOLD" "Client:" "$NC" "$CLIENT_NAME" >&2
    printf "%b%-20s%b %s\n" "$BOLD" "Scenario:" "$NC" "$SCENARIO_NAME" >&2
    printf "%b%-20s%b %s\n" "$BOLD" "Cloud Provider:" "$NC" "$CLOUD_PROVIDER" >&2
    printf "%b%-20s%b %s\n" "$BOLD" "PABX IP:" "$NC" "$PABX_IP" >&2
    
    printf "\n%b%-20s%b %d\n" "$BOLD" "Offices:" "$NC" "${#OFFICE_NAMES[@]}" >&2
    for i in "${!OFFICE_NAMES[@]}"; do
        printf "  %-18s %s\n" "${OFFICE_NAMES[$i]}:" "${OFFICE_IPS[$i]}" >&2
    done
    
    printf "\n%b%-20s%b %d\n" "$BOLD" "SIP Trunks:" "$NC" "${#TRUNK_NAMES[@]}" >&2
    for i in "${!TRUNK_NAMES[@]}"; do
        printf "  %-18s %s\n" "${TRUNK_NAMES[$i]}:" "${TRUNK_IPS[$i]}" >&2
    done
    printf "\n" >&2
    
    if ui_prompt_yes_no "Begin testing?"; then
        return 0
    else
        ui_print_warning "Testing cancelled by user"
        exit 0
    fi
}

validate_config_data() {
    # Validates if all required data is loaded from config
    if [[ -z "$CLIENT_NAME" ]] || [[ -z "$SCENARIO_NAME" ]] || [[ -z "$CLOUD_PROVIDER" ]] || [[ -z "$PABX_IP" ]]; then
        ui_print_error "Configuration incomplete. Missing required fields."
        return 1
    fi
    
    if [[ ${#OFFICE_NAMES[@]} -eq 0 ]] || [[ ${#OFFICE_IPS[@]} -eq 0 ]]; then
        ui_print_error "Configuration incomplete. No offices defined."
        return 1
    fi
    
    if [[ ${#TRUNK_NAMES[@]} -eq 0 ]] || [[ ${#TRUNK_IPS[@]} -eq 0 ]]; then
        ui_print_error "Configuration incomplete. No SIP trunks defined."
        return 1
    fi
    
    # Validate array lengths match
    if [[ ${#OFFICE_NAMES[@]} -ne ${#OFFICE_IPS[@]} ]]; then
        ui_print_error "Configuration error: Office names and IPs count mismatch"
        return 1
    fi
    
    if [[ ${#TRUNK_NAMES[@]} -ne ${#TRUNK_IPS[@]} ]]; then
        ui_print_error "Configuration error: Trunk names and IPs count mismatch"
        return 1
    fi
    
    return 0
}

show_config_review() {
    # Display configuration loaded from file with formatted output
    ui_print_header "CONFIGURATION REVIEW" "=" 70
    
    ui_print_subheader "General Information"
    printf "%b%-25s%b %s\n" "$BOLD" "Client Name:" "$NC" "$CLIENT_NAME" >&2
    printf "%b%-25s%b %s\n" "$BOLD" "Scenario Name:" "$NC" "$SCENARIO_NAME" >&2
    printf "%b%-25s%b %s\n" "$BOLD" "Cloud Provider:" "$NC" "$CLOUD_PROVIDER" >&2
    printf "%b%-25s%b %s\n" "$BOLD" "PABX IP Address:" "$NC" "$PABX_IP" >&2
    
    ui_print_subheader "Office Locations (${#OFFICE_NAMES[@]})"
    for i in "${!OFFICE_NAMES[@]}"; do
        printf "  %b[%d]%b %-30s %s\n" "$CYAN" "$((i+1))" "$NC" "${OFFICE_NAMES[$i]}" "${OFFICE_IPS[$i]}" >&2
    done
    
    ui_print_subheader "SIP Trunk Carriers (${#TRUNK_NAMES[@]})"
    for i in "${!TRUNK_NAMES[@]}"; do
        printf "  %b[%d]%b %-30s %s\n" "$CYAN" "$((i+1))" "$NC" "${TRUNK_NAMES[$i]}" "${TRUNK_IPS[$i]}" >&2
    done
    
    printf "\n" >&2
    
    if ui_prompt_yes_no "Is this configuration correct?"; then
        ui_print_success "Configuration confirmed. Starting analysis..."
        return 0
    else
        ui_print_error "Configuration rejected. Exiting."
        exit 1
    fi
}

################################################################################
# COMPREHENSIVE TESTING
################################################################################

run_complete_analysis() {
    local target="$1"
    local target_name="$2"
    
    ui_print_subheader "Testing: $target_name ($target)"
    audit_log_event "TARGET" "name=$target_name ip=$target status=start"
    
    # Validate target is reachable
    if ! test_ip_reachable "$target" 5; then
        ui_print_error "Target unreachable: $target"
        audit_log_event "TARGET" "name=$target_name ip=$target status=unreachable"
        return 1
    fi
    
    # Test data variables
    local latency=0 jitter=0 loss=0 hops=0
    local primary_asn="" asn_suspicious="0" international="0"
    
    # Run Ping Test
    ui_print_info "Running ping test (10 packets)..."
    local ping_stats
    local ping_output
    ping_output=$(run_ping_raw "$target" 10)
    
    if [ -z "$ping_output" ]; then
        ui_print_error "Ping test failed"
        audit_log_event "PING" "target=$target status=failed"
        return 1
    fi

    audit_log_ping_output "$target" 10 "$ping_output"
    ping_stats=$(get_ping_stats_raw "$target" 10 5 "$ping_output")
    
    # Parse ping results: "avg loss min max stddev"
    latency=$(echo "$ping_stats" | awk '{print $1}')
    loss=$(echo "$ping_stats" | awk '{print $2}')
    local ping_min ping_max ping_stddev
    ping_min=$(echo "$ping_stats" | awk '{print $3}')
    ping_max=$(echo "$ping_stats" | awk '{print $4}')
    ping_stddev=$(echo "$ping_stats" | awk '{print $5}')
    
    ui_print_metric "Average RTT" "$latency" "ms"
    ui_print_metric "Packet Loss" "$loss" "%"
    audit_log_event "PING" "target=$target avg_ms=$latency loss_pct=$loss min_ms=$ping_min max_ms=$ping_max stddev_ms=$ping_stddev"
    
    # Run MTR Test
    ui_print_info "Running MTR (100 packets)..."
    local mtr_output
    mtr_output=$(run_mtr_raw "$target" 100)
    
    if [ -z "$mtr_output" ]; then
        ui_print_error "MTR test failed"
        return 1
    fi
    
    ui_print_success "MTR completed"
    audit_log_event "MTR" "target=$target packets=100 lines=$(printf '%s\n' "$mtr_output" | wc -l | awk '{print $1}')"
    
    # Run Traceroute
    ui_print_info "Running traceroute..."
    local traceroute_output
    traceroute_output=$(run_traceroute_raw "$target")
    
    if [ -z "$traceroute_output" ]; then
        ui_print_error "Traceroute failed"
        audit_log_event "TRACEROUTE" "target=$target status=failed"
        return 1
    fi
    
    hops=$(get_hop_count "$traceroute_output")
    ui_print_metric "Hop Count" "$hops" "hops"
    audit_log_traceroute_output "$target" "$traceroute_output"
    
    # ASN Analysis
    ui_print_info "Running ASN analysis..."
    primary_asn=$(lookup_asn "$target")
    
    if [ "$primary_asn" != "UNKNOWN" ]; then
        ui_print_metric "Primary ASN" "$primary_asn" ""
        
        local asn_name
        asn_name=$(lookup_asn_name "$primary_asn")
        ui_print_metric "Carrier" "$asn_name" ""
        
        if is_asn_suspicious "$primary_asn"; then
            asn_suspicious="1"
            ui_print_warning "ASN marked as suspicious for VoIP"
        fi
    fi
    
    # International Route Detection
    if is_international_route "$traceroute_output"; then
        international="1"
        ui_print_warning "International route detected"
    else
        ui_print_success "Domestic/regional route"
    fi
    
    # Extract jitter from MTR
    local mtr_metrics
    mtr_metrics=$(parse_mtr_raw "$mtr_output")
    local mtr_loss mtr_avg mtr_best mtr_worst mtr_stddev
    mtr_loss=$(echo "$mtr_metrics" | awk '{print $1}')
    mtr_avg=$(echo "$mtr_metrics" | awk '{print $2}')
    mtr_best=$(echo "$mtr_metrics" | awk '{print $3}')
    mtr_worst=$(echo "$mtr_metrics" | awk '{print $4}')
    mtr_stddev=$(echo "$mtr_metrics" | awk '{print $5}')
    jitter="$mtr_stddev"
    audit_log_event "MTR" "target=$target loss_pct=$mtr_loss avg_ms=$mtr_avg best_ms=$mtr_best worst_ms=$mtr_worst stddev_ms=$mtr_stddev"
    
    # === RISK ASSESSMENT ENGINE ===
    ui_print_subheader "VoIP Quality Assessment"
    
    # Get comprehensive risk assessment
    local risk_assessment
    risk_assessment=$(assess_route_risk "$traceroute_output" "$mtr_output" "$latency" "$loss" "$hops")
    
    local risk_level
    local risk_confidence
    local risk_reasons
    risk_level=$(echo "$risk_assessment" | cut -d'|' -f1)
    risk_confidence=$(echo "$risk_assessment" | cut -d'|' -f2)
    risk_reasons=$(echo "$risk_assessment" | cut -d'|' -f3-)
    
    # Display risk assessment
    case "$risk_level" in
        high)
            ui_print_error "Risk Level: CRITICAL"
            ;;
        medium-high)
            ui_print_warning "Risk Level: HIGH"
            ;;
        medium)
            ui_print_warning "Risk Level: MEDIUM"
            ;;
        low)
            ui_print_success "Risk Level: LOW"
            ;;
        *)
            ui_print_info "Risk Level: UNKNOWN"
            ;;
    esac
    
    ui_print_metric "Confidence" "$risk_confidence" "%"
    
    if [ -n "$risk_reasons" ]; then
        ui_print_info "Assessment Reasons:"
        printf '%s\n' "$risk_reasons" | while read -r reason; do
            [ -n "$reason" ] && printf '  • %s\n' "$reason"
        done
    fi

    local score
    score=$(calculate_voip_score "$latency" "$jitter" "$loss" "$hops" "$asn_suspicious" "$international")
    audit_log_summary "$target" "$score" "$(classify_voip_quality "$score")" "$risk_level" "$risk_confidence"
    
    # Show provider-specific recommendations
    local carriers
    carriers=$(get_transit_providers "$traceroute_output")
    local recommendations
    recommendations=$(get_provider_recommendation "$risk_level" "$carriers" "$latency")
    
    if [ -n "$recommendations" ] && [ "$recommendations" != "Route acceptable for VoIP. Continue monitoring." ]; then
        ui_print_subheader "Recommendations"
        printf '%s\n' "$recommendations"
    fi
    
    # Return results as pipe-separated values (include risk assessment)
    echo "$score|$risk_level|$risk_confidence|$risk_reasons|$latency|$jitter|$loss|$hops|$primary_asn|$asn_suspicious|$international"
}

run_all_tests() {
    ui_print_header "COMPREHENSIVE NETWORK ANALYSIS"
    
    ui_print_subheader "Office Location Analysis"
    
    for i in "${!OFFICE_IPS[@]}"; do
        local result
        result=$(run_complete_analysis "${OFFICE_IPS[$i]}" "${OFFICE_NAMES[$i]}")
        
        if [ $? -eq 0 ]; then
            OFFICE_RESULTS+=("$result")
        else
            OFFICE_RESULTS+=("0|CRÍTICO|0|Target unreachable|100|0|100|0|UNKNOWN|1|0")
            ui_print_error "Analysis failed for ${OFFICE_NAMES[$i]}"
        fi
        
        echo ""
    done
    
    ui_print_subheader "SIP Trunk Carrier Analysis"
    
    for i in "${!TRUNK_IPS[@]}"; do
        local result
        result=$(run_complete_analysis "${TRUNK_IPS[$i]}" "${TRUNK_NAMES[$i]}")
        
        if [ $? -eq 0 ]; then
            TRUNK_RESULTS+=("$result")
        else
            TRUNK_RESULTS+=("0|CRÍTICO|0|Target unreachable|100|0|100|0|UNKNOWN|1|0")
            ui_print_error "Analysis failed for ${TRUNK_NAMES[$i]}"
        fi
        
        echo ""
    done
    
    # Generate final report
    generate_final_report
}

################################################################################
# REPORT GENERATION
################################################################################

generate_final_report() {
    ui_print_header "GENERATING AUDIT SUMMARY"
    
    # Calculate overall score
    local total_score=0
    local total_tests=0
    
    for result in "${OFFICE_RESULTS[@]}" "${TRUNK_RESULTS[@]}"; do
        local score
        score=$(echo "$result" | cut -d'|' -f1)
        
        if is_number "$score"; then
            total_score=$(echo "$total_score + $score" | bc)
            ((total_tests++))
        fi
    done
    
    if (( total_tests > 0 )); then
        local overall_score
        overall_score=$(echo "$total_score / $total_tests" | bc)
        local overall_category
        overall_category=$(classify_voip_quality "$overall_score")
        
        ui_print_subheader "Overall Assessment"
        ui_show_quality_status "$overall_category" "$overall_score"
        audit_log_summary "OVERALL" "$overall_score" "$overall_category" "$overall_category" "n/a"

        init_report "$CLIENT_NAME"
        add_general_information "$CLIENT_NAME" "$CLOUD_PROVIDER" "$PABX_IP" "$SCENARIO_NAME"

        add_report_section "EXECUTION SUMMARY"
        add_report_metric "Audit Log" "$AUDIT_LOG_FILE"
        add_report_metric "Targets Analyzed" "$total_tests"
        add_report_metric "Overall VoIP Score" "$overall_score/100"
        add_report_metric "Classification" "$overall_category"
        add_report_blank

        add_report_section "OFFICE ANALYSIS"
        for i in "${!OFFICE_RESULTS[@]}"; do
            local score risk_level risk_confidence risk_reasons latency jitter loss hops primary_asn asn_suspicious international
            IFS='|' read -r score risk_level risk_confidence risk_reasons latency jitter loss hops primary_asn asn_suspicious international <<< "${OFFICE_RESULTS[$i]}"

            add_office_analysis "${OFFICE_NAMES[$i]}" "${OFFICE_IPS[$i]}" "$latency" "$jitter" "$loss" "$hops" "$primary_asn" "$score" "$(classify_voip_quality "$score")"

            case "$risk_level" in
                high|high-risk|CRÍTICO|CRITICO)
                    add_finding "CRITICAL" "${OFFICE_NAMES[$i]}" "${risk_reasons:-High risk detected.}" ;;
                medium-high|medium)
                    add_finding "WARNING" "${OFFICE_NAMES[$i]}" "${risk_reasons:-Moderate risk detected.}" ;;
                *)
                    add_finding "OK" "${OFFICE_NAMES[$i]}" "${risk_reasons:-Route acceptable for VoIP.}" ;;
            esac
        done

        add_report_section "SIP TRUNK ANALYSIS"
        for i in "${!TRUNK_RESULTS[@]}"; do
            local score risk_level risk_confidence risk_reasons latency jitter loss hops primary_asn asn_suspicious international
            IFS='|' read -r score risk_level risk_confidence risk_reasons latency jitter loss hops primary_asn asn_suspicious international <<< "${TRUNK_RESULTS[$i]}"

            add_sip_trunk_analysis "${TRUNK_NAMES[$i]}" "${TRUNK_IPS[$i]}" "$latency" "$jitter" "$loss" "$hops" "$primary_asn" "$score" "$(classify_voip_quality "$score")"

            case "$risk_level" in
                high|high-risk|CRÍTICO|CRITICO)
                    add_finding "CRITICAL" "${TRUNK_NAMES[$i]}" "${risk_reasons:-High risk detected.}" ;;
                medium-high|medium)
                    add_finding "WARNING" "${TRUNK_NAMES[$i]}" "${risk_reasons:-Moderate risk detected.}" ;;
                *)
                    add_finding "OK" "${TRUNK_NAMES[$i]}" "${risk_reasons:-Route acceptable for VoIP.}" ;;
            esac
        done

        add_recommendations_section
        if [ "$overall_category" = "CRÍTICO" ]; then
            add_recommendation "HIGH" "Review carrier routing, packet loss, and hop-by-hop evidence in the audit log before production use."
        elif [ "$overall_category" = "ATENÇÃO" ]; then
            add_recommendation "MEDIUM" "Keep monitoring the route and compare results across peak and off-peak windows."
        else
            add_recommendation "LOW" "The route is acceptable, but keep the audit log for future comparison."
        fi

        add_conclusion_section "$overall_score" "$overall_category"

        add_technical_details_section
        add_report_text "Detailed audit log: ${AUDIT_LOG_FILE:-unknown}"
        add_report_text "This report is the shareable summary; the audit log is the technical evidence trail."

        print_report_path
        audit_log_event "REPORT" "summary_report=$REPORT_FILE"
    else
        ui_print_warning "No valid test results to summarize"
        audit_log_event "SUMMARY" "no_valid_test_results"
    fi
    
    if [ -n "$AUDIT_LOG_FILE" ]; then
        ui_print_info "Audit log written to: $AUDIT_LOG_FILE"
        audit_log_event "AUDIT" "log_file=$AUDIT_LOG_FILE"
    fi

    ui_print_success "Summary report and audit log complete"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Initialize environment
    initialize_environment
    
    # Load configuration if provided
    load_configuration
    
    # Show startup checks
    show_startup_checks
    
    # Workflow depends on whether config was provided
    if [[ -n "$CONFIG_FILE" ]]; then
        # Config file provided - validate and show for review
        if validate_config_data; then
            # All required data is present
            show_config_review
        else
            # Config is incomplete - collect missing data interactively
            ui_print_warning "Configuration is incomplete. Collecting additional information..."
            collect_general_info
            collect_pabx_info
            collect_office_info
            collect_sip_trunk_info
            show_collection_summary
        fi
    else
        # No config file - collect data interactively
        collect_general_info
        collect_pabx_info
        collect_office_info
        collect_sip_trunk_info
        show_collection_summary
    fi
    
    # Run all tests and generate report
    run_all_tests
    
    ui_print_success "Analysis completed!"
    
    exit 0
}

# Run main
main "$@"

