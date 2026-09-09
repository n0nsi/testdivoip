#!/bin/bash

################################################################################
# REPORTING - reporting.sh
# Plain-text reports for later comparison. No deployment verdicts or marketing text.
################################################################################

REPORTS_DIR="${REPORTS_DIR:-reports}"

sanitize_filename_component() {
    local value="$1"

    value="${value//[^A-Za-z0-9._-]/_}"
    while [[ "$value" == *"__"* ]]; do
        value="${value//__/_}"
    done
    value="${value##_}"
    value="${value%%_}"

    [[ -n "$value" ]] || value="report"
    printf '%s' "$value"
}

init_report() {
    local client_name="$1"
    local timestamp safe_client_name

    timestamp=$(date +%Y%m%d_%H%M%S)
    safe_client_name=$(sanitize_filename_component "$client_name")

    umask 077
    mkdir -p "$REPORTS_DIR"
    REPORT_FILE="${REPORTS_DIR}/${safe_client_name}_${timestamp}.txt"

    {
        echo "TESTDIVOIP - route troubleshooting report"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo ""
        echo "This file summarizes measurements collected during one run."
        echo "Read it together with the audit log and the raw route evidence."
        echo ""
    } > "$REPORT_FILE"

    log_info "Report initialized: $REPORT_FILE"
}

add_report_header() {
    local title="$1"
    {
        echo ""
        echo "$title"
        printf '%*s\n' "${#title}" '' | tr ' ' '='
        echo ""
    } >> "$REPORT_FILE"
}

add_report_section() {
    local section="$1"
    {
        echo ""
        echo "## $section"
        echo ""
    } >> "$REPORT_FILE"
}

add_report_subsection() {
    local subsection="$1"
    {
        echo "### $subsection"
        echo ""
    } >> "$REPORT_FILE"
}

add_report_metric() {
    local label="$1"
    local value="$2"
    local unit="${3:-}"
    printf '%-24s : %s %s\n' "$label" "$value" "$unit" >> "$REPORT_FILE"
}

add_report_text() {
    printf '%s\n' "$1" >> "$REPORT_FILE"
}

add_report_blank() {
    echo "" >> "$REPORT_FILE"
}

add_report_separator() {
    echo "----------------------------------------" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

add_general_information() {
    local client="$1"
    local cloud_provider="$2"
    local pabx_ip="$3"
    local scenario="$4"

    add_report_section "Run context"
    add_report_metric "Client / label" "$client"
    add_report_metric "Scenario" "$scenario"
    add_report_metric "Cloud provider" "$cloud_provider"
    add_report_metric "PBX IP" "$pabx_ip"
    add_report_metric "Kernel" "$(uname -r)"
    add_report_metric "Timestamp" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
}

add_path_analysis() {
    local label="$1"
    local target_ip="$2"
    local latency="$3"
    local jitter="$4"
    local loss="$5"
    local hops="$6"
    local asn="$7"
    local score="$8"
    local category="$9"

    add_report_subsection "$label"
    add_report_metric "Target" "$target_ip"
    add_report_metric "RTT average" "$latency" "ms"
    add_report_metric "MTR StDev" "$jitter" "ms"
    add_report_metric "Packet loss" "$loss" "%"
    add_report_metric "Hop count" "$hops"
    add_report_metric "Target ASN" "$asn"
    add_report_metric "Troubleshooting score" "$score/100" "($category)"
    add_report_separator
}

add_office_analysis() {
    add_path_analysis "Office: $1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
}

add_sip_trunk_analysis() {
    add_path_analysis "SIP trunk: $1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
}

add_findings_section() {
    add_report_section "Findings"
}

add_finding() {
    local severity="$1"
    local title="$2"
    local description="$3"

    add_report_text "[$severity] $title"
    add_report_text "$description"
    add_report_blank
}

add_recommendations_section() {
    add_report_section "What I would check next"
}

add_recommendation() {
    local priority="$1"
    local text="$2"
    add_report_text "[$priority] $text"
}

add_conclusion_section() {
    local overall_score="$1"
    local overall_category="$2"

    add_report_section "Run summary"
    add_report_metric "Average score" "$overall_score/100"
    add_report_metric "Classification" "$overall_category"
    add_report_blank
    add_report_text "The score is only a compact summary of the measurements collected in this run."
    add_report_text "It is not a carrier verdict, an SLA measurement or a production-readiness decision."
}

add_technical_details_section() {
    add_report_section "Evidence"
}

add_mtr_result() {
    local target="$1"
    local mtr_output="$2"
    add_report_subsection "MTR: $target"
    printf '%s\n\n' "$mtr_output" >> "$REPORT_FILE"
}

add_traceroute_result() {
    local target="$1"
    local traceroute_output="$2"
    add_report_subsection "Traceroute: $target"
    printf '%s\n\n' "$traceroute_output" >> "$REPORT_FILE"
}

print_report_path() {
    print_success "Report saved to: $REPORT_FILE"
}

show_report() {
    local report_file="${1:-${REPORT_FILE:-}}"
    [ -n "$report_file" ] && [ -f "$report_file" ] || return 1
    cat "$report_file"
}

list_reports() {
    mkdir -p "$REPORTS_DIR"

    local found=0 file
    while IFS= read -r file; do
        found=1
        printf '%s\n' "$(basename "$file")"
    done < <(find "$REPORTS_DIR" -maxdepth 1 -type f -name '*.txt' -print | sort)

    if [ "$found" -eq 0 ]; then
        echo "No reports found."
    fi
}
