#!/bin/bash

################################################################################
# MTR HELPERS - mtr_analysis.sh
# Compatibility helpers built on top of network.sh and analysis.sh.
################################################################################

if [ -n "${_MTR_ANALYSIS_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
_MTR_ANALYSIS_LOADED=1

# Output: loss avg best worst stdev hops
collect_mtr_metrics() {
    local target="$1"
    local count="${2:-100}"
    local mtr_output metrics hops

    mtr_output=$(run_mtr_raw "$target" "$count") || return 1
    metrics=$(parse_mtr_raw "$mtr_output") || return 1
    hops=$(printf '%s\n' "$mtr_output" | awk '/[0-9.]+%/ {count++} END {print count+0}')

    printf '%s %s\n' "$metrics" "$hops"
}

# Intermediate MTR loss can be ICMP rate limiting. Only destination loss is treated
# as end-to-end evidence by this helper.
detect_false_loss() {
    local mtr_output="$1"
    local metrics last_loss

    metrics=$(parse_mtr_raw "$mtr_output") || {
        echo "unknown"
        return 1
    }

    read -r last_loss _ <<< "$metrics"

    if (( $(echo "${last_loss:-0} > 1" | bc -l 2>/dev/null || echo 0) )); then
        echo "destination_loss"
        return 0
    fi

    local intermediate_high=0 line loss
    while IFS= read -r line; do
        [[ "$line" == *%* ]] || continue
        loss=$(printf '%s\n' "$line" | awk '{print $(NF-6)}' | tr -d '%')
        if [[ "$loss" =~ ^[0-9]+([.][0-9]+)?$ ]] && (( $(echo "$loss > 30" | bc -l) )); then
            intermediate_high=1
        fi
    done <<< "$mtr_output"

    if [ "$intermediate_high" -eq 1 ]; then
        echo "possible_icmp_artifact"
    else
        echo "no_obvious_artifact"
    fi
}

calculate_jitter_from_mtr() {
    local mtr_output="$1"
    local metrics loss avg best worst stdev

    metrics=$(parse_mtr_raw "$mtr_output") || return 1
    read -r loss avg best worst stdev <<< "$metrics"
    printf '%s\n' "$stdev"
}

compute_voip_score_mtr() {
    calculate_voip_score "$1" "$2" "$3" "$4"
}

classify_voip_quality_mtr() {
    classify_voip_quality "$1"
}

generate_mtr_report() {
    local target="$1"
    local mtr_output="$2"
    local metrics loss avg best worst stdev hops score category loss_context

    metrics=$(parse_mtr_raw "$mtr_output") || return 1
    read -r loss avg best worst stdev <<< "$metrics"
    hops=$(printf '%s\n' "$mtr_output" | awk '/[0-9.]+%/ {count++} END {print count+0}')
    score=$(calculate_voip_score "$avg" "$stdev" "$loss" "$hops") || return 1
    category=$(classify_voip_quality "$score")
    loss_context=$(detect_false_loss "$mtr_output" || true)

    printf 'Target: %s\n' "$target"
    printf 'Loss: %s%%\n' "$loss"
    printf 'Average RTT: %s ms\n' "$avg"
    printf 'StDev: %s ms\n' "$stdev"
    printf 'Hops: %s\n' "$hops"
    printf 'Loss context: %s\n' "$loss_context"
    printf 'Troubleshooting score: %s/100 (%s)\n' "$score" "$category"
    printf 'Note: this is a summary of MTR measurements, not a carrier or SLA verdict.\n'
}

export -f collect_mtr_metrics
export -f detect_false_loss
export -f calculate_jitter_from_mtr
export -f compute_voip_score_mtr
export -f classify_voip_quality_mtr
export -f generate_mtr_report
