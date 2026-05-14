#!/bin/bash

################################################################################
# REPORTING - testdivoip
# Funções para geração de relatórios
################################################################################

REPORTS_DIR="${REPORTS_DIR:-.reports}"

sanitize_filename_component() {
    local value="$1"

    value="${value//[^A-Za-z0-9._-]/_}"
    value="${value//__/_}"
    value="${value##_}"
    value="${value%%_}"

    [[ -n "$value" ]] || value="report"
    printf '%s' "$value"
}

################################################################################
# REPORT INITIALIZATION
################################################################################

init_report() {
    local client_name="$1"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local safe_client_name
    safe_client_name="$(sanitize_filename_component "$client_name")"
    
    umask 077

    REPORT_FILE="${REPORTS_DIR}/${safe_client_name}_${timestamp}.txt"
    
    mkdir -p "$REPORTS_DIR"
    
    # Cabeçalho do relatório
    {
        echo "╔════════════════════════════════════════════════════════════════════════╗"
        echo "║                    TESTDIVOIP - VoIP Quality Report                   ║"
        echo "║              Cloud Provider VoIP Infrastructure Analysis              ║"
        echo "╚════════════════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Report Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Report File: $REPORT_FILE"
        echo ""
    } >> "$REPORT_FILE"
    
    log_info "Report initialized: $REPORT_FILE"
}

################################################################################
# REPORT SECTIONS
################################################################################

add_report_header() {
    local title="$1"
    
    {
        echo ""
        echo "╔═════════════════════════════════════════════════════════════════════╗"
        printf "║ %-67s │\n" "$title"
        echo "╚═════════════════════════════════════════════════════════════════════╝"
        echo ""
    } >> "$REPORT_FILE"
}

add_report_section() {
    local section="$1"
    
    {
        echo ""
        echo "═══ $section ═══"
        echo ""
    } >> "$REPORT_FILE"
}

add_report_subsection() {
    local subsection="$1"
    
    {
        echo "  ▶ $subsection"
        echo ""
    } >> "$REPORT_FILE"
}

add_report_metric() {
    local label="$1"
    local value="$2"
    local unit="${3:-}"
    
    printf "    %-30s: %-20s %s\n" "$label" "$value" "$unit" >> "$REPORT_FILE"
}

add_report_text() {
    local text="$1"
    
    echo "$text" >> "$REPORT_FILE"
}

add_report_blank() {
    echo "" >> "$REPORT_FILE"
}

add_report_separator() {
    echo "    ─────────────────────────────────────────────────" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

################################################################################
# GENERAL INFORMATION SECTION
################################################################################

add_general_information() {
    local client="$1"
    local cloud_provider="$2"
    local pabx_ip="$3"
    local scenario="$4"
    
    add_report_section "GENERAL INFORMATION"
    
    add_report_metric "Client" "$client"
    add_report_metric "Scenario" "$scenario"
    add_report_metric "Cloud Provider" "$cloud_provider"
    add_report_metric "PABX IP" "$pabx_ip"
    add_report_blank
    
    add_report_subsection "Execution Metadata"
    add_report_metric "Kernel" "$(uname -r)"
    add_report_metric "Uptime" "$(uptime -p)"
    add_report_metric "Timestamp" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
}

################################################################################
# OFFICE ANALYSIS SECTION
################################################################################

add_office_analysis() {
    local office_name="$1"
    local office_ip="$2"
    local latency="$3"
    local jitter="$4"
    local loss="$5"
    local hops="$6"
    local asn="$7"
    local score="$8"
    local quality_category="$9"
    
    add_report_subsection "Office: $office_name ($office_ip)"
    
    add_report_metric "IP Address" "$office_ip"
    add_report_metric "RTT Average" "${latency}ms"
    add_report_metric "Jitter (StdDev)" "${jitter}ms"
    add_report_metric "Packet Loss" "${loss}%"
    add_report_metric "Hop Count" "$hops"
    add_report_metric "Primary ASN" "$asn"
    add_report_metric "VoIP Quality Score" "$score/100 ($quality_category)"
    
    add_report_separator
}

################################################################################
# SIP TRUNK ANALYSIS SECTION
################################################################################

add_sip_trunk_analysis() {
    local trunk_name="$1"
    local trunk_ip="$2"
    local latency="$3"
    local jitter="$4"
    local loss="$5"
    local hops="$6"
    local asn="$7"
    local score="$8"
    local quality_category="$9"
    
    add_report_subsection "SIP Trunk: $trunk_name ($trunk_ip)"
    
    add_report_metric "IP Address" "$trunk_ip"
    add_report_metric "RTT Average" "${latency}ms"
    add_report_metric "Jitter (StdDev)" "${jitter}ms"
    add_report_metric "Packet Loss" "${loss}%"
    add_report_metric "Hop Count" "$hops"
    add_report_metric "Provider ASN" "$asn"
    add_report_metric "Route Quality Score" "$score/100 ($quality_category)"
    
    add_report_separator
}

################################################################################
# FINDINGS & ANALYSIS
################################################################################

add_findings_section() {
    add_report_section "FINDINGS & ANALYSIS"
    
    add_report_subsection "Network Quality Summary"
    
    add_report_text "This section contains detailed analysis of the VoIP infrastructure quality."
    add_report_blank
}

add_finding() {
    local severity="$1"  # OK, WARNING, CRITICAL
    local title="$2"
    local description="$3"
    
    local icon=""
    case "$severity" in
        "OK") icon="✓" ;;
        "WARNING") icon="⚠" ;;
        "CRITICAL") icon="✗" ;;
    esac
    
    add_report_text "  [$severity] $icon $title"
    add_report_text "    $description"
    add_report_blank
}

################################################################################
# RECOMMENDATIONS
################################################################################

add_recommendations_section() {
    add_report_section "RECOMMENDATIONS"
}

add_recommendation() {
    local priority="$1"  # HIGH, MEDIUM, LOW
    local text="$2"
    
    local marker=""
    case "$priority" in
        "HIGH") marker="[HIGH]" ;;
        "MEDIUM") marker="[MED]" ;;
        "LOW") marker="[LOW]" ;;
    esac
    
    add_report_text "  $marker $text"
    add_report_blank
}

################################################################################
# CONCLUSION
################################################################################

add_conclusion_section() {
    local overall_score="$1"
    local overall_category="$2"
    
    add_report_section "OVERALL CONCLUSION"
    
    add_report_metric "Overall VoIP Quality" "$overall_score/100"
    add_report_metric "Classification" "$overall_category"
    add_report_blank
    
    case "$overall_category" in
        "EXCELENTE")
            add_report_text "This cloud provider/route configuration is EXCELLENT for VoIP deployment."
            add_report_text "All metrics indicate production-ready infrastructure with minimal risk."
            ;;
        "BOM")
            add_report_text "This cloud provider/route configuration is GOOD for VoIP deployment."
            add_report_text "Most metrics are within acceptable ranges. Monitor performance regularly."
            ;;
        "ATENÇÃO")
            add_report_text "This cloud provider/route configuration requires ATTENTION before VoIP deployment."
            add_report_text "Some metrics indicate potential issues. Address recommendations before production."
            ;;
        "CRÍTICO")
            add_report_text "This cloud provider/route configuration is NOT RECOMMENDED for VoIP."
            add_report_text "Critical metrics indicate high risk of voice quality degradation."
            ;;
    esac
    
    add_report_blank
}

################################################################################
# TECHNICAL DETAILS
################################################################################

add_technical_details_section() {
    add_report_section "TECHNICAL DETAILS & RAW DATA"
}

add_mtr_result() {
    local target="$1"
    local mtr_output="$2"
    
    add_report_subsection "MTR Report: $target"
    
    {
        echo "$mtr_output"
        echo ""
    } >> "$REPORT_FILE"
}

add_traceroute_result() {
    local target="$1"
    local traceroute_output="$2"
    
    add_report_subsection "Traceroute: $target"
    
    {
        echo "$traceroute_output"
        echo ""
    } >> "$REPORT_FILE"
}

################################################################################
# PRINT REPORT
################################################################################

print_report_path() {
    echo ""
    print_success "Report saved to: $REPORT_FILE"
    echo ""
}

show_report() {
    if [ -f "$REPORT_FILE" ]; then
        less "$REPORT_FILE" 2>/dev/null || cat "$REPORT_FILE"
    fi
}

################################################################################
# EXPORT FUNCTIONS
################################################################################

export_report_json() {
    local output_file="${REPORT_FILE%.txt}.json"
    
    # TODO: Implementar exportação para JSON
    log_info "JSON export not yet implemented"
}

export_report_csv() {
    local output_file="${REPORT_FILE%.txt}.csv"
    
    # TODO: Implementar exportação para CSV
    log_info "CSV export not yet implemented"
}

list_reports() {
    print_info "Available reports:"
    ls -lh "$REPORTS_DIR"/*.txt 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
}

