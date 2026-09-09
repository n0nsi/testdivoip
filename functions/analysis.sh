#!/bin/bash

################################################################################
# ANALYSIS & SCORING - analysis.sh
# Keep scoring based on measurements we can actually collect.
################################################################################

calculate_voip_score() {
    local latency="$1"
    local jitter="$2"
    local loss="$3"
    local hops="$4"

    # Kept in the function signature for compatibility with older callers.
    # Carrier/ASN identity and guessed route geography do not affect the score.
    local _asn_flag="${5:-0}"
    local _international_flag="${6:-0}"

    local score=100

    if ! is_float "$latency" || ! is_float "$jitter" || ! is_float "$loss" || ! is_number "$hops"; then
        echo "0"
        return 1
    fi

    # RTT is useful context, but packet loss and variation usually hurt voice first.
    if (( $(echo "$latency > 200" | bc -l) )); then
        ((score -= 35))
    elif (( $(echo "$latency > 150" | bc -l) )); then
        ((score -= 25))
    elif (( $(echo "$latency > 100" | bc -l) )); then
        ((score -= 15))
    elif (( $(echo "$latency > 70" | bc -l) )); then
        ((score -= 5))
    fi

    if (( $(echo "$jitter > 50" | bc -l) )); then
        ((score -= 25))
    elif (( $(echo "$jitter > 30" | bc -l) )); then
        ((score -= 15))
    elif (( $(echo "$jitter > 20" | bc -l) )); then
        ((score -= 5))
    fi

    if (( $(echo "$loss > 3" | bc -l) )); then
        ((score -= 40))
    elif (( $(echo "$loss > 1" | bc -l) )); then
        ((score -= 30))
    elif (( $(echo "$loss > 0.5" | bc -l) )); then
        ((score -= 20))
    elif (( $(echo "$loss > 0" | bc -l) )); then
        ((score -= 5))
    fi

    # Hop count is weak evidence by itself, so it has little weight.
    if (( hops > 25 )); then
        ((score -= 5))
    fi

    (( score < 0 )) && score=0
    (( score > 100 )) && score=100

    echo "$score"
}

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

# Compatibility helper. I do not blacklist an ASN just because of its number.
is_asn_suspicious() {
    return 1
}

# The live WHOIS lookup in network.sh is preferred over a hardcoded provider table.
get_asn_carrier_name() {
    echo "Unknown"
}

# Hop count is context only. It is not a quality verdict by itself.
estimate_route_quality() {
    local hop_count="$1"

    if ! is_number "$hop_count"; then
        return 1
    fi

    if (( hop_count <= 15 )); then
        return 0
    elif (( hop_count <= 25 )); then
        return 1
    else
        return 2
    fi
}

check_instability() {
    local instability_count="$1"

    if ! is_number "$instability_count"; then
        echo "0"
        return 1
    fi

    if (( instability_count > 3 )); then
        echo "2"
    elif (( instability_count > 0 )); then
        echo "1"
    else
        echo "0"
    fi
}

# Parse common Linux ping summary formats.
# Output: "avg loss min max stddev"
extract_metrics_from_ping() {
    local ping_output="$1"
    local loss avg min max stddev rhs

    loss=$(printf '%s\n' "$ping_output" | grep -oP '[0-9.]+(?=% packet loss)' | head -1)

    if printf '%s\n' "$ping_output" | grep -qiE 'rtt .*min/avg/max'; then
        rhs=$(printf '%s\n' "$ping_output" | grep -iE 'rtt .*min/avg/max' | tail -1 | sed -E 's/.*= *//' | sed -E 's/ ms$//')
        min=$(printf '%s\n' "$rhs" | awk -F/ '{print $1}')
        avg=$(printf '%s\n' "$rhs" | awk -F/ '{print $2}')
        max=$(printf '%s\n' "$rhs" | awk -F/ '{print $3}')
        stddev=$(printf '%s\n' "$rhs" | awk -F/ '{print $4}')
    else
        avg=$(printf '%s\n' "$ping_output" | grep -oP 'avg=\K[0-9.]+' | head -1)
        min=$(printf '%s\n' "$ping_output" | grep -oP 'min=\K[0-9.]+' | head -1)
        max=$(printf '%s\n' "$ping_output" | grep -oP 'max=\K[0-9.]+' | head -1)
        stddev=$(printf '%s\n' "$ping_output" | grep -oP 'stddev=\K[0-9.]+' | head -1)
    fi

    printf '%s %s %s %s %s\n' \
        "${avg:-0}" "${loss:-0}" "${min:-0}" "${max:-0}" "${stddev:-0}"
}

safe_compare_float() {
    local value1="$1"
    local operator="$2"
    local value2="$3"

    if ! is_float "$value1" || ! is_float "$value2"; then
        return 1
    fi

    (( $(echo "$value1 $operator $value2" | bc -l) ))
}

safe_compare_int() {
    local value1="$1"
    local operator="$2"
    local value2="$3"

    if ! is_number "$value1" || ! is_number "$value2"; then
        return 1
    fi

    case "$operator" in
        -eq) (( value1 == value2 )) ;;
        -ne) (( value1 != value2 )) ;;
        -gt) (( value1 > value2 )) ;;
        -ge) (( value1 >= value2 )) ;;
        -lt) (( value1 < value2 )) ;;
        -le) (( value1 <= value2 )) ;;
        *) return 1 ;;
    esac
}
