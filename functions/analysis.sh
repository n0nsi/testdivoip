#!/bin/bash

################################################################################
# ANALYSIS & SCORING LAYER - analysis.sh
# LOGIC LAYER: Pure calculations, scoring, classification
# NO decorative output, NO ANSI codes
# Returns only numeric scores and status codes
################################################################################

################################################################################
# QUALITY SCORING - Returns ONLY numeric score
################################################################################

# calculate_voip_score: Calculate numeric score 0-100
# Input: latency, jitter, loss, hops, asn_suspicious, international
# Output: Single integer (score), no text
calculate_voip_score() {
    local latency="$1"
    local jitter="$2"
    local loss="$3"
    local hops="$4"
    local asn_suspicious="${5:-0}"
    local international="${6:-0}"
    
    local score=100
    
    # Validate inputs are numbers
    if ! is_float "$latency" || ! is_float "$jitter" || ! is_float "$loss" || ! is_number "$hops"; then
        echo "0"
        return 1
    fi
    
    # Latency: ideal <50ms, warning <100ms, critical >150ms
    if (( $(echo "$latency > 150" | bc -l) )); then
        ((score -= 30))
    elif (( $(echo "$latency > 100" | bc -l) )); then
        ((score -= 15))
    elif (( $(echo "$latency > 50" | bc -l) )); then
        ((score -= 5))
    fi
    
    # Jitter: ideal <20ms, warning <50ms, critical >100ms
    if (( $(echo "$jitter > 100" | bc -l) )); then
        ((score -= 25))
    elif (( $(echo "$jitter > 50" | bc -l) )); then
        ((score -= 15))
    elif (( $(echo "$jitter > 20" | bc -l) )); then
        ((score -= 5))
    fi
    
    # Packet Loss: ideal 0%, warning <0.5%, critical >1%
    if (( $(echo "$loss > 1" | bc -l) )); then
        ((score -= 30))
    elif (( $(echo "$loss > 0.5" | bc -l) )); then
        ((score -= 15))
    elif (( $(echo "$loss > 0" | bc -l) )); then
        ((score -= 5))
    fi
    
    # Hops: ideal <10, warning <15, critical >20
    if (( hops > 20 )); then
        ((score -= 10))
    elif (( hops > 15 )); then
        ((score -= 5))
    fi
    
    # ASN suspicious flag
    if [ "$asn_suspicious" = "1" ]; then
        ((score -= 10))
    fi
    
    # International route flag
    if [ "$international" = "1" ]; then
        ((score -= 5))
    fi
    
    # Ensure score stays 0-100
    if (( score < 0 )); then
        score=0
    elif (( score > 100 )); then
        score=100
    fi
    
    echo "$score"
}

# classify_voip_quality: Map score to category
# Input: score (0-100)
# Output: Category string (EXCELENTE|BOM|ATENÇÃO|CRÍTICO)
classify_voip_quality() {
    local score="$1"
    
    if ! is_number "$score"; then
        echo "CRÍTICO"
        return 1
    fi
    
    if (( score >= 85 )); then
        echo "EXCELENTE"
    elif (( score >= 70 )); then
        echo "BOM"
    elif (( score >= 50 )); then
        echo "ATENÇÃO"
    else
        echo "CRÍTICO"
    fi
}

################################################################################
# ASN ANALYSIS - Pure logic, return status codes
################################################################################

# is_asn_suspicious: Check if ASN is known problematic
# Returns: 0 (suspicious) or 1 (acceptable)
is_asn_suspicious() {
    local asn="$1"
    
    # Known problematic transit/peering ASNs
    case "$asn" in
        AS1299|AS174|AS3356|AS2914|AS3257|AS1668|AS12389|AS5511)
            return 0  # Suspicious
            ;;
        *)
            return 1  # Not known as suspicious
            ;;
    esac
}

# get_asn_carrier_name: Get human-readable carrier name
# Returns: Carrier name string
get_asn_carrier_name() {
    local asn="$1"
    
    case "$asn" in
        AS3356|AS1)     echo "Level3/Lumen" ;;
        AS174)          echo "Cogent" ;;
        AS1299)         echo "Telia" ;;
        AS2914)         echo "NTT" ;;
        AS3257)         echo "GTT" ;;
        AS16509)        echo "Amazon AWS" ;;
        AS14061)        echo "DigitalOcean" ;;
        AS8452)         echo "Telemig" ;;
        AS27699)        echo "Telefonica Brasil" ;;
        *)              echo "Unknown" ;;
    esac
}

################################################################################
# ROUTE ANALYSIS - Pure metrics extraction
################################################################################

# estimate_route_quality: Estimate quality based on hop count
# Returns: 0 (good), 1 (fair), 2 (poor)
estimate_route_quality() {
    local hop_count="$1"
    
    if ! is_number "$hop_count"; then
        return 1
    fi
    
    if (( hop_count < 8 )); then
        return 0  # Good
    elif (( hop_count < 15 )); then
        return 1  # Fair
    else
        return 2  # Poor
    fi
}

# check_instability: Assess route instability
# Returns: Numeric instability indicator
check_instability() {
    local instability_count="$1"
    
    if ! is_number "$instability_count"; then
        echo "0"
        return 1
    fi
    
    if (( instability_count > 3 )); then
        echo "2"  # High instability
    elif (( instability_count > 0 )); then
        echo "1"  # Some instability
    else
        echo "0"  # Stable
    fi
}

################################################################################
# METRICS EXTRACTION - Pure data extraction, no text
################################################################################

# extract_metrics_from_ping: Parse ping output
# Returns: "avg loss min max stddev" (space-separated numbers only)
extract_metrics_from_ping() {
    local ping_output="$1"
    
    local avg min max stddev loss
    avg=$(echo "$ping_output" | grep -oP 'avg=\K[0-9.]+' | head -1)
    min=$(echo "$ping_output" | grep -oP 'min=\K[0-9.]+' | head -1)
    max=$(echo "$ping_output" | grep -oP 'max=\K[0-9.]+' | head -1)
    stddev=$(echo "$ping_output" | grep -oP 'stddev=\K[0-9.]+' | head -1)
    loss=$(echo "$ping_output" | grep -oP '[0-9.]+(?=% packet loss)' | head -1)
    
    printf '%s %s %s %s %s\n' \
        "${avg:-0}" "${loss:-0}" "${min:-0}" "${max:-0}" "${stddev:-0}"
}

################################################################################
# NUMERIC VALIDATION - Safe comparison
################################################################################

# safe_compare_float: Compare two floats safely
# Usage: safe_compare_float "3.5" "-gt" "2.5"
# Returns: 0 (true) or 1 (false)
safe_compare_float() {
    local value1="$1"
    local operator="$2"
    local value2="$3"
    
    if ! is_float "$value1" || ! is_float "$value2"; then
        return 1
    fi
    
    (( $(echo "$value1 $operator $value2" | bc -l) )) && return 0 || return 1
}

# safe_compare_int: Compare two integers safely
safe_compare_int() {
    local value1="$1"
    local operator="$2"
    local value2="$3"
    
    if ! is_number "$value1" || ! is_number "$value2"; then
        return 1
    fi
    
    (( value1 $operator value2 )) && return 0 || return 1
}

