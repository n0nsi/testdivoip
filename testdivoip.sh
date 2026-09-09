#!/bin/bash

################################################################################
# TESTDIVOIP
# Repeatable network-path checks for VoIP troubleshooting.
# Author: Murilo Prestes
################################################################################

set -o pipefail

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

source_required "${FUNCTIONS_DIR}/colors.sh"
source_required "${FUNCTIONS_DIR}/logging.sh"
source_required "${FUNCTIONS_DIR}/network.sh"
source_required "${FUNCTIONS_DIR}/analysis.sh"
source_required "${FUNCTIONS_DIR}/reporting.sh"
source_required "${FUNCTIONS_DIR}/presentation.sh"

DEBUG="${DEBUG:-0}"
MTR_PACKETS="${MTR_PACKETS:-100}"
CONFIG_FILE=""
ACTION="run"
SHOW_REPORT_NAME=""

CLIENT_NAME=""
SCENARIO_NAME=""
CLOUD_PROVIDER=""
PABX_IP=""

declare -a OFFICE_NAMES=()
declare -a OFFICE_IPS=()
declare -a TRUNK_NAMES=()
declare -a TRUNK_IPS=()
declare -a RESULTS=()

trap cleanup_temp EXIT

show_help() {
    cat <<'EOF'
TESTDIVOIP

A Bash helper for repeatable network-path checks around VoIP troubleshooting.

Usage:
  ./testdivoip.sh
  ./testdivoip.sh --config config/local.conf
  ./testdivoip.sh --debug
  ./testdivoip.sh --list-reports
  ./testdivoip.sh --show-report FILE

Options:
  -h, --help          Show this help
  -d, --debug         Enable debug logging
  -c, --config FILE   Load a local configuration file
      --list-reports  List local TXT reports
      --show-report   Print one report from the local reports directory

The script collects ping, MTR, traceroute and ASN context. The score is a
troubleshooting summary, not a carrier verdict or a production-readiness test.
EOF
}

require_option_value() {
    local option="$1"
    local value="${2:-}"

    if [ -z "$value" ] || [[ "$value" == -* ]]; then
        printf 'Missing value for %s\n' "$option" >&2
        exit 2
    fi
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--debug)
                DEBUG=1
                shift
                ;;
            -c|--config)
                require_option_value "$1" "${2:-}"
                CONFIG_FILE="$2"
                shift 2
                ;;
            --list-reports)
                ACTION="list-reports"
                shift
                ;;
            --show-report)
                require_option_value "$1" "${2:-}"
                ACTION="show-report"
                SHOW_REPORT_NAME="$2"
                shift 2
                ;;
            *)
                printf 'Unknown option: %s\n\n' "$1" >&2
                show_help >&2
                exit 2
                ;;
        esac
    done
}

initialize_environment() {
    umask 077
    mkdir -p "$REPORTS_DIR" "$LOGS_DIR" "$TEMP_DIR" "$CONFIG_DIR" || return 1

    LOG_DIR="$LOGS_DIR"
    init_logging || return 1
    init_audit_log || return 1

    log_debug "Project root: $PROJECT_ROOT"
}

trim_whitespace() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

strip_quotes() {
    local value
    value=$(trim_whitespace "$1")

    if [[ ${#value} -ge 2 ]]; then
        if [[ ("${value:0:1}" == '"' && "${value: -1}" == '"') || ("${value:0:1}" == "'" && "${value: -1}" == "'") ]]; then
            value="${value:1:${#value}-2}"
        fi
    fi

    printf '%s' "$value"
}

reset_configuration() {
    CLIENT_NAME=""
    SCENARIO_NAME=""
    CLOUD_PROVIDER=""
    PABX_IP=""
    OFFICE_NAMES=()
    OFFICE_IPS=()
    TRUNK_NAMES=()
    TRUNK_IPS=()
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

# Parse the small config format instead of sourcing arbitrary shell code.
load_configuration_file() {
    local config_path="$1"
    local in_array=""
    local raw_line cleaned_line key value

    reset_configuration

    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        cleaned_line=$(trim_whitespace "$raw_line")
        [[ -z "$cleaned_line" || "$cleaned_line" == \#* ]] && continue

        if [[ -n "$in_array" ]]; then
            if [[ "$cleaned_line" == ")" ]]; then
                in_array=""
                continue
            fi

            value="${cleaned_line%%#*}"
            value=$(strip_quotes "$value")
            [[ -n "$value" ]] && append_config_array_item "$in_array" "$value"
            continue
        fi

        [[ "$cleaned_line" == declare\ -a* ]] && cleaned_line="${cleaned_line#declare -a }"
        [[ "$cleaned_line" == export\ * ]] && cleaned_line="${cleaned_line#export }"
        cleaned_line=$(trim_whitespace "$cleaned_line")

        if [[ "$cleaned_line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=\($ ]]; then
            in_array="${BASH_REMATCH[1]}"
            continue
        fi

        if [[ "$cleaned_line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            value="${value%%#*}"
            value=$(strip_quotes "$value")
            set_config_scalar "$key" "$value"
        fi
    done < "$config_path"

    if [ -n "$in_array" ]; then
        ui_print_error "Config ended before array '$in_array' was closed"
        return 1
    fi
}

load_configuration() {
    [ -n "$CONFIG_FILE" ] || return 0

    if [ ! -f "$CONFIG_FILE" ]; then
        ui_print_error "Configuration file not found: $CONFIG_FILE"
        return 1
    fi

    ui_print_info "Loading configuration: $CONFIG_FILE"
    load_configuration_file "$CONFIG_FILE" || return 1
    ui_print_success "Configuration loaded"
}

validate_configuration() {
    local errors=0
    local ip

    [ -n "$CLIENT_NAME" ] || { ui_print_error "CLIENT_NAME is missing"; errors=1; }
    [ -n "$SCENARIO_NAME" ] || { ui_print_error "SCENARIO_NAME is missing"; errors=1; }
    [ -n "$CLOUD_PROVIDER" ] || { ui_print_error "CLOUD_PROVIDER is missing"; errors=1; }
    is_valid_ip "$PABX_IP" || { ui_print_error "PABX_IP is missing or invalid"; errors=1; }

    if [[ ${#OFFICE_NAMES[@]} -ne ${#OFFICE_IPS[@]} ]]; then
        ui_print_error "OFFICE_NAMES and OFFICE_IPS have different lengths"
        errors=1
    fi

    if [[ ${#TRUNK_NAMES[@]} -ne ${#TRUNK_IPS[@]} ]]; then
        ui_print_error "TRUNK_NAMES and TRUNK_IPS have different lengths"
        errors=1
    fi

    if (( ${#OFFICE_IPS[@]} + ${#TRUNK_IPS[@]} == 0 )); then
        ui_print_error "At least one office or SIP trunk target is required"
        errors=1
    fi

    for ip in "${OFFICE_IPS[@]}" "${TRUNK_IPS[@]}"; do
        is_valid_ip "$ip" || {
            ui_print_error "Invalid target IP: $ip"
            errors=1
        }
    done

    if ! is_number "$MTR_PACKETS" || (( MTR_PACKETS < 10 || MTR_PACKETS > 1000 )); then
        ui_print_error "MTR_PACKETS must be an integer between 10 and 1000"
        errors=1
    fi

    case "$DEBUG" in
        0|1) ;;
        *)
            ui_print_error "DEBUG must be 0 or 1"
            errors=1
            ;;
    esac

    return "$errors"
}

collect_general_info() {
    ui_print_header "GENERAL INFORMATION"
    CLIENT_NAME=$(ui_prompt_text "Client / label" "${CLIENT_NAME:-Lab}")
    SCENARIO_NAME=$(ui_prompt_text "Scenario" "${SCENARIO_NAME:-VoIP route check}")
    CLOUD_PROVIDER=$(ui_prompt_text "Cloud / location" "${CLOUD_PROVIDER:-Not specified}")
}

collect_pabx_info() {
    ui_print_header "PBX INFORMATION"
    PABX_IP=$(ui_prompt_ip "PBX IP address" "${PABX_IP:-}")
}

collect_office_info() {
    ui_print_header "OFFICE / REMOTE TARGETS"

    local num_offices i office_name office_ip
    num_offices=$(ui_prompt_number "How many office/remote targets?" "1")

    for ((i=1; i<=num_offices; i++)); do
        office_name=$(ui_prompt_text "Target #$i name" "Office-$i")
        office_ip=$(ui_prompt_ip "Target #$i IP" "")
        OFFICE_NAMES+=("$office_name")
        OFFICE_IPS+=("$office_ip")
    done
}

collect_sip_trunk_info() {
    ui_print_header "SIP TRUNK TARGETS"

    local num_trunks i trunk_name trunk_ip
    num_trunks=$(ui_prompt_number "How many SIP trunk targets?" "1")

    for ((i=1; i<=num_trunks; i++)); do
        trunk_name=$(ui_prompt_text "Trunk #$i name" "Carrier-$i")
        trunk_ip=$(ui_prompt_ip "Trunk #$i IP" "")
        TRUNK_NAMES+=("$trunk_name")
        TRUNK_IPS+=("$trunk_ip")
    done
}

show_configuration() {
    ui_print_header "RUN CONFIGURATION"
    printf '%-18s %s\n' "Label:" "$CLIENT_NAME" >&2
    printf '%-18s %s\n' "Scenario:" "$SCENARIO_NAME" >&2
    printf '%-18s %s\n' "Cloud/location:" "$CLOUD_PROVIDER" >&2
    printf '%-18s %s\n' "PBX:" "$PABX_IP" >&2
    printf '%-18s %s\n' "MTR packets:" "$MTR_PACKETS" >&2

    local i
    for i in "${!OFFICE_IPS[@]}"; do
        printf '  office %-3d %-24s %s\n' "$((i+1))" "${OFFICE_NAMES[$i]}" "${OFFICE_IPS[$i]}" >&2
    done
    for i in "${!TRUNK_IPS[@]}"; do
        printf '  trunk  %-3d %-24s %s\n' "$((i+1))" "${TRUNK_NAMES[$i]}" "${TRUNK_IPS[$i]}" >&2
    done
}

prepare_configuration() {
    if [ -n "$CONFIG_FILE" ]; then
        load_configuration || return 1
        validate_configuration || return 1
        show_configuration
        ui_prompt_yes_no "Run these checks?" || return 1
        return 0
    fi

    reset_configuration
    collect_general_info
    collect_pabx_info
    collect_office_info
    collect_sip_trunk_info
    validate_configuration || return 1
    show_configuration
    ui_prompt_yes_no "Run these checks?"
}

show_startup_checks() {
    ui_print_header "TESTDIVOIP - route troubleshooting"

    if ! check_all_dependencies; then
        ui_print_error "Missing dependencies. Run install.sh or install them manually."
        return 1
    fi

    ui_print_success "Dependencies look OK"
}

sanitize_result_field() {
    local value="$1"
    value="${value//$'\n'/ }"
    value="${value//|/-}"
    printf '%s' "$value"
}

run_complete_analysis() {
    local target="$1"
    local target_name="$2"
    local kind="$3"
    local result_name
    result_name=$(sanitize_result_field "$target_name")

    ui_print_subheader "Testing: $target_name ($target)"
    audit_log_event "TARGET" "kind=$kind name=$target_name ip=$target status=start"

    local ping_output="" ping_stats=""
    local latency="" loss="" ping_min="" ping_max="" ping_stddev=""

    ping_output=$(run_ping_raw "$target" 10 5) || true
    if [ -n "$ping_output" ]; then
        audit_log_ping_output "$target" 10 "$ping_output"
        ping_stats=$(get_ping_stats_raw "$target" 10 5 "$ping_output" 2>/dev/null || true)
    fi

    if [ -n "$ping_stats" ]; then
        read -r latency loss ping_min ping_max ping_stddev <<< "$ping_stats"
        ui_print_metric "Ping RTT" "$latency" "ms"
        ui_print_metric "Ping loss" "$loss" "%"
        audit_log_event "PING" "target=$target avg_ms=$latency loss_pct=$loss min_ms=$ping_min max_ms=$ping_max stddev_ms=$ping_stddev"
    else
        ui_print_warning "Ping did not give a usable RTT. Continuing with MTR/traceroute."
        audit_log_event "PING" "target=$target status=no_usable_metrics"
    fi

    local mtr_output="" mtr_metrics=""
    local mtr_loss="" mtr_avg="" mtr_best="" mtr_worst="" mtr_stddev=""

    ui_print_info "Running MTR ($MTR_PACKETS packets)..."
    mtr_output=$(run_mtr_raw "$target" "$MTR_PACKETS") || true
    if [ -n "$mtr_output" ]; then
        mtr_metrics=$(parse_mtr_raw "$mtr_output" 2>/dev/null || true)
    fi

    if [ -n "$mtr_metrics" ]; then
        read -r mtr_loss mtr_avg mtr_best mtr_worst mtr_stddev <<< "$mtr_metrics"
        ui_print_metric "MTR avg" "$mtr_avg" "ms"
        ui_print_metric "MTR loss" "$mtr_loss" "%"
        ui_print_metric "MTR StDev" "$mtr_stddev" "ms"
        audit_log_event "MTR" "target=$target loss_pct=$mtr_loss avg_ms=$mtr_avg best_ms=$mtr_best worst_ms=$mtr_worst stddev_ms=$mtr_stddev"
    else
        ui_print_warning "MTR did not return parsable endpoint metrics"
        audit_log_event "MTR" "target=$target status=no_usable_metrics"
    fi

    # Prefer ping for RTT/loss. If ping is filtered, final-hop MTR is a fallback.
    if [ -z "$latency" ] && [ -n "$mtr_avg" ]; then
        latency="$mtr_avg"
        loss="$mtr_loss"
    fi

    if [ -z "$latency" ] || [ -z "$loss" ]; then
        ui_print_error "No usable latency/loss measurement for $target"
        audit_log_event "TARGET" "kind=$kind name=$target_name ip=$target status=unmeasured"
        printf 'failed|%s|%s|%s|0|UNKNOWN|unknown|0|0|0|0|0|UNKNOWN|No usable latency/loss measurement.\n' \
            "$kind" "$result_name" "$target"
        return 0
    fi

    local traceroute_output="" hops=0
    ui_print_info "Running traceroute..."
    traceroute_output=$(run_traceroute_raw "$target" 30) || true
    if [ -n "$traceroute_output" ]; then
        hops=$(get_hop_count "$traceroute_output")
        audit_log_traceroute_output "$target" "$traceroute_output"
        ui_print_metric "Hop count" "$hops" ""
    else
        ui_print_warning "Traceroute did not return usable output"
    fi

    local primary_asn asn_name
    primary_asn=$(lookup_asn "$target")
    asn_name="UNKNOWN"
    if [ "$primary_asn" != "UNKNOWN" ]; then
        asn_name=$(lookup_asn_name "$primary_asn")
        ui_print_metric "Target ASN" "$primary_asn" ""
        [ "$asn_name" != "UNKNOWN" ] && ui_print_metric "ASN name" "$asn_name" ""
    fi

    local variation="${mtr_stddev:-${ping_stddev:-0}}"
    local risk_assessment risk_level evidence_weight risk_reasons
    risk_assessment=$(assess_route_risk "$latency" "$loss" "$variation" "$hops")
    risk_level=$(printf '%s' "$risk_assessment" | cut -d'|' -f1)
    evidence_weight=$(printf '%s' "$risk_assessment" | cut -d'|' -f2)
    risk_reasons=$(printf '%s' "$risk_assessment" | cut -d'|' -f3-)

    ui_print_subheader "Measurement summary"
    ui_print_metric "Risk flag" "$risk_level" ""
    ui_print_metric "Evidence weight" "$evidence_weight" "/100"
    ui_print_info "$risk_reasons"

    local score category
    score=$(calculate_voip_score "$latency" "$variation" "$loss" "$hops") || score=0
    category=$(classify_voip_quality "$score")

    ui_show_quality_status "$category" "$score"
    audit_log_summary "$target" "$score" "$category" "$risk_level" "$evidence_weight"
    audit_log_event "TARGET" "kind=$kind name=$target_name ip=$target status=done"

    risk_reasons=$(sanitize_result_field "$risk_reasons")

    printf 'ok|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$kind" "$result_name" "$target" "$score" "$category" "$risk_level" "$evidence_weight" \
        "$latency" "$variation" "$loss" "$hops" "$primary_asn" "$risk_reasons"
}

run_all_tests() {
    RESULTS=()
    ui_print_header "NETWORK PATH CHECKS"

    local i result
    for i in "${!OFFICE_IPS[@]}"; do
        result=$(run_complete_analysis "${OFFICE_IPS[$i]}" "${OFFICE_NAMES[$i]}" "office")
        RESULTS+=("$result")
    done

    for i in "${!TRUNK_IPS[@]}"; do
        result=$(run_complete_analysis "${TRUNK_IPS[$i]}" "${TRUNK_NAMES[$i]}" "trunk")
        RESULTS+=("$result")
    done
}

risk_to_severity() {
    case "$1" in
        high) echo "CRITICAL" ;;
        medium-high|medium) echo "WARNING" ;;
        low) echo "OK" ;;
        *) echo "WARNING" ;;
    esac
}

generate_final_report() {
    local total_score=0 valid_count=0
    local result status kind name ip score category risk evidence latency variation loss hops asn reasons

    for result in "${RESULTS[@]}"; do
        IFS='|' read -r status kind name ip score category risk evidence latency variation loss hops asn reasons <<< "$result"
        if [ "$status" = "ok" ] && is_number "$score"; then
            ((total_score += score))
            ((valid_count++))
        fi
    done

    init_report "$CLIENT_NAME"
    add_general_information "$CLIENT_NAME" "$CLOUD_PROVIDER" "$PABX_IP" "$SCENARIO_NAME"
    add_report_metric "Audit log" "$AUDIT_LOG_FILE"

    add_report_section "Path measurements"
    for result in "${RESULTS[@]}"; do
        IFS='|' read -r status kind name ip score category risk evidence latency variation loss hops asn reasons <<< "$result"
        [ "$status" = "ok" ] || continue

        if [ "$kind" = "office" ]; then
            add_office_analysis "$name" "$ip" "$latency" "$variation" "$loss" "$hops" "$asn" "$score" "$category"
        else
            add_sip_trunk_analysis "$name" "$ip" "$latency" "$variation" "$loss" "$hops" "$asn" "$score" "$category"
        fi
    done

    add_report_section "Findings"
    for result in "${RESULTS[@]}"; do
        IFS='|' read -r status kind name ip score category risk evidence latency variation loss hops asn reasons <<< "$result"
        if [ "$status" = "ok" ]; then
            add_finding "$(risk_to_severity "$risk")" "$name" "$reasons"
        else
            add_finding "WARNING" "$name" "$reasons"
        fi
    done

    if (( valid_count > 0 )); then
        local overall_score overall_category
        overall_score=$((total_score / valid_count))
        overall_category=$(classify_voip_quality "$overall_score")

        add_conclusion_section "$overall_score" "$overall_category"
        add_recommendations_section

        case "$overall_category" in
            CRÍTICO)
                add_recommendation "HIGH" "Compare another route and repeat the checks during the reported problem window."
                ;;
            ATENÇÃO)
                add_recommendation "MEDIUM" "Repeat the run at another time and compare the measurements before changing routing."
                ;;
            *)
                add_recommendation "LOW" "Keep this report as a baseline for the next incident or route change."
                ;;
        esac

        ui_print_subheader "Overall run summary"
        ui_show_quality_status "$overall_category" "$overall_score"
    else
        add_report_section "Run summary"
        add_report_text "No target returned enough measurements for a score."
        ui_print_warning "No target returned enough measurements for a score"
    fi

    add_technical_details_section
    add_report_text "Detailed local audit log: $AUDIT_LOG_FILE"
    add_report_text "Runtime logs and reports are ignored by Git and should stay local."

    print_report_path
    audit_log_event "REPORT" "summary_report=$REPORT_FILE"
}

handle_report_action() {
    case "$ACTION" in
        list-reports)
            list_reports
            return 0
            ;;
        show-report)
            local report_name report_path
            report_name=$(basename "$SHOW_REPORT_NAME")
            report_path="$REPORTS_DIR/$report_name"

            if [ ! -f "$report_path" ]; then
                printf 'Report not found: %s\n' "$report_name" >&2
                return 1
            fi

            show_report "$report_path"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

main() {
    parse_arguments "$@"

    if [ "$ACTION" != "run" ]; then
        mkdir -p "$REPORTS_DIR"
        handle_report_action
        exit $?
    fi

    initialize_environment || {
        printf 'Could not initialize local runtime directories.\n' >&2
        exit 1
    }

    show_startup_checks || exit 1
    prepare_configuration || {
        ui_print_warning "Run cancelled or configuration is invalid"
        exit 1
    }

    run_all_tests
    generate_final_report
    ui_print_success "Done"
}

main "$@"
