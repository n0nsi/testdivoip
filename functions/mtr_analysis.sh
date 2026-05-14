#!/bin/bash

################################################################################
# MTR-BASED ANALYSIS MODULE - mtr_analysis.sh
# Purpose: Collect and analyze route quality using MTR as primary source
# Exposes functions:
#  - collect_mtr_metrics <target> [count]
#  - detect_false_loss <mtr_output>
#  - calculate_jitter_from_mtr <mtr_output>
#  - compute_voip_score_mtr <latency> <jitter> <loss> <hops>
#  - classify_voip_quality_mtr <score>
#  - generate_mtr_report <target> <mtr_output>
################################################################################

# Ensure this file can be sourced safely
if [ -n "${_MTR_ANALYSIS_LOADED:-}" ]; then
    return 0
fi
_MTR_ANALYSIS_LOADED=1

# Ensure dependency: is_valid_ip exists. If not, try to source logging.sh from same dir,
# otherwise provide a minimal fallback implementation so the module can be sourced
# standalone for quick testing.
if ! type is_valid_ip >/dev/null 2>&1; then
    # locate this file's directory
    _MTR_ANALYSIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "${_MTR_ANALYSIS_DIR}/logging.sh" ]; then
        # shellcheck source=/dev/null
        . "${_MTR_ANALYSIS_DIR}/logging.sh"
    fi
fi

if ! type is_valid_ip >/dev/null 2>&1; then
    is_valid_ip() {
        local ip="$1"
        local ipv4_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
        if [[ $ip =~ $ipv4_regex ]]; then
            for octet in ${ip//./ }; do
                if ((octet > 255)); then
                    return 1
                fi
            done
            return 0
        fi
        return 1
    }
fi

# collect_mtr_metrics: run MTR and parse destination line
# Output: space-separated: loss avg best worst stdev hops
collect_mtr_metrics() {
    local target="$1"
    local count="${2:-100}"

    if ! is_valid_ip "$target"; then
        echo "" >&2
        return 1
    fi

    local mtr_out
    mtr_out=$(mtr -rwzc "$count" "$target" 2>/dev/null) || {
        echo "" >&2
        return 1
    }

    # Get last hop line: find last line that looks like " <num>. ... <loss>% ... Avg ... StDev"
    # We'll look for lines containing a percentage and numeric columns
    local dest_line
    dest_line=$(echo "$mtr_out" | awk '/%/ {line=$0} END {print line}')

    if [ -z "$dest_line" ]; then
        # might be single-line output or different format; fallback to last line
        dest_line=$(echo "$mtr_out" | tail -n 1)
    fi

    # Extract numbers: loss (percent), Avg, Best, Wrst, StDev
    local loss avg best worst stdev
    loss=$(echo "$dest_line" | grep -oP '[0-9]+(?=%)' | head -1 || true)
    avg=$(echo "$dest_line" | grep -oP '\b[0-9]+\.?[0-9]*\b' | awk '{print $(NF-4)}' 2>/dev/null || true)
    best=$(echo "$dest_line" | grep -oP '\b[0-9]+\.?[0-9]*\b' | awk '{print $(NF-3)}' 2>/dev/null || true)
    worst=$(echo "$dest_line" | grep -oP '\b[0-9]+\.?[0-9]*\b' | awk '{print $(NF-2)}' 2>/dev/null || true)
    stdev=$(echo "$dest_line" | grep -oP '\b[0-9]+\.?[0-9]*\b' | awk '{print $(NF-1)}' 2>/dev/null || true)

    # Fallback parsing if above indices are wrong: try to extract by column names
    if [ -z "$avg" ] || [ -z "$stdev" ]; then
        avg=$(echo "$mtr_out" | grep -oP 'Avg\s+\K[0-9.]+')
        stdev=$(echo "$mtr_out" | grep -oP 'StDev\s+\K[0-9.]+')
        best=$(echo "$mtr_out" | grep -oP 'Best\s+\K[0-9.]+')
        worst=$(echo "$mtr_out" | grep -oP 'Wrst\s+\K[0-9.]+')
    fi

    loss=${loss:-0}
    avg=${avg:-0}
    best=${best:-0}
    worst=${worst:-0}
    stdev=${stdev:-0}

    # Count responsive hops (lines starting with number)
    local hops
    hops=$(echo "$mtr_out" | grep -E '^\s*[0-9]+\.' | wc -l | tr -d ' ')
    hops=${hops:-0}

    printf '%s %s %s %s %s %s\n' "$loss" "$avg" "$best" "$worst" "$stdev" "$hops"
}

# detect_false_loss: determine if high loss in intermediate hops is ICMP artifact
# Returns: "real_loss" or "artifact" and writes reason to stderr
detect_false_loss() {
    local mtr_out="$1"
    if [ -z "$mtr_out" ]; then
        echo "unknown" >&2
        return 1
    fi

    # Build array of hop losses
    # Lines containing a % are candidate hops
    local hop_losses
    hop_losses=$(echo "$mtr_out" | awk '/%/ {for(i=1;i<=NF;i++) if ($i ~ /%$/) print $i}' | sed 's/%//' )

    # If no hop_losses found, consider unknown
    if [ -z "$hop_losses" ]; then
        echo "unknown" >&2
        return 1
    fi

    # Get last hop loss
    local last_loss
    last_loss=$(echo "$hop_losses" | tail -n1)
    last_loss=${last_loss:-0}

    # If last hop loss > 1% consider real
    if (( $(echo "$last_loss > 1" | bc -l) )); then
        echo "real_loss"
        return 0
    fi

    # Check for intermediate hop with high loss (>30%) but subsequent hops have low loss (<10%)
    # If found, mark as artifact
    local index=0
    local found_artifact=0
    local losses_array
    IFS=$'\n' read -r -d '' -a losses_array < <(printf '%s\n' "$hop_losses" && printf '\0')
    local total=${#losses_array[@]}
    for ((i=0;i<total;i++)); do
        val=${losses_array[i]}
        if [ -z "$val" ]; then
            continue
        fi
        if (( $(echo "$val > 30" | bc -l) )); then
            # check later hops
            local later_ok=1
            for ((j=i+1;j<total;j++)); do
                later_val=${losses_array[j]}
                if [ -z "$later_val" ]; then continue; fi
                if (( $(echo "$later_val > 10" | bc -l) )); then
                    later_ok=0
                    break
                fi
            done
            if [ $later_ok -eq 1 ]; then
                found_artifact=1
                break
            fi
        fi
    done

    if [ $found_artifact -eq 1 ]; then
        echo "artifact"
        echo "Detected high loss on intermediate hop but subsequent hops show low loss => ICMP rate-limit/artifact" >&2
        return 0
    fi

    # Otherwise, no clear artifact found
    echo "no_artifact"
    return 0
}

# calculate_jitter_from_mtr: estimate jitter from MTR stdev of destination
# Returns jitter in ms (number)
calculate_jitter_from_mtr() {
    local mtr_out="$1"
    if [ -z "$mtr_out" ]; then
        echo "-1" >&2
        return 1
    fi

    # Attempt to extract StDev for last hop
    local stdev
    stdev=$(echo "$mtr_out" | awk '/StDev/ {found=1} found && /%/ {print $(NF) }' | tail -n1)
    # fallback: try column extraction from last hop
    if [ -z "$stdev" ]; then
        stdev=$(echo "$mtr_out" | awk '/%/ {line=$0} END { if (line) { n=split(line,a," "); print a[n-1] } }')
    fi
    stdev=${stdev:-0}
    # Ensure numeric
    if ! printf '%s' "$stdev" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
        stdev=0
    fi
    # Use stdev as jitter estimate
    printf '%s\n' "$stdev"
}

# compute_voip_score_mtr: compute weighted score 0-100
# Inputs: latency(ms) jitter(ms) loss(%) hops
compute_voip_score_mtr() {
    local latency="$1"
    local jitter="$2"
    local loss="$3"
    local hops="$4"

    # Validation
    for v in "$latency" "$jitter" "$loss" "$hops"; do
        if ! printf '%s' "$v" | grep -qE '^-?[0-9]+(\.[0-9]+)?$'; then
            echo "UNKNOWN" >&2
            return 1
        fi
    done

    # Normalize criteria to 0-100 (higher better)
    # Latency scoring (ideal <50)
    local latency_score
    if (( $(echo "$latency <= 50" | bc -l) )); then
        latency_score=100
    elif (( $(echo "$latency <= 100" | bc -l) )); then
        latency_score=80
    elif (( $(echo "$latency <= 150" | bc -l) )); then
        latency_score=60
    elif (( $(echo "$latency <= 250" | bc -l) )); then
        latency_score=40
    else
        latency_score=20
    fi

    # Jitter scoring
    local jitter_score
    if (( $(echo "$jitter < 5" | bc -l) )); then
        jitter_score=100
    elif (( $(echo "$jitter <= 15" | bc -l) )); then
        jitter_score=80
    elif (( $(echo "$jitter <= 30" | bc -l) )); then
        jitter_score=50
    else
        jitter_score=20
    fi

    # Loss scoring - end-to-end loss only
    local loss_score
    if (( $(echo "$loss <= 0" | bc -l) )); then
        loss_score=100
    elif (( $(echo "$loss <= 0.5" | bc -l) )); then
        loss_score=85
    elif (( $(echo "$loss <= 1" | bc -l) )); then
        loss_score=60
    elif (( $(echo "$loss <= 3" | bc -l) )); then
        loss_score=30
    else
        loss_score=5
    fi

    # Stability score (hops and ASN churn proxy)
    local stability_score
    if (( hops <= 10 )); then
        stability_score=100
    elif (( hops <= 15 )); then
        stability_score=80
    elif (( hops <= 20 )); then
        stability_score=60
    else
        stability_score=30
    fi

    # Weighted average: latency 30%, jitter 30%, loss 30%, stability 10%
    local weighted
    weighted=$(echo "scale=2; ( $latency_score*0.3 + $jitter_score*0.3 + $loss_score*0.3 + $stability_score*0.1 )" | bc -l)
    # Round to integer
    local score
    score=$(printf '%.0f' "$weighted")
    if (( score < 0 )); then score=0; fi
    if (( score > 100 )); then score=100; fi

    printf '%s\n' "$score"
}

# classify_voip_quality_mtr: map score to human category
classify_voip_quality_mtr() {
    local score="$1"
    if ! printf '%s' "$score" | grep -qE '^[0-9]+$'; then
        echo "UNKNOWN"
        return 1
    fi
    if [ "$score" -ge 85 ]; then
        echo "EXCELENTE"
    elif [ "$score" -ge 70 ]; then
        echo "BOM"
    elif [ "$score" -ge 50 ]; then
        echo "MÉDIO"
    elif [ "$score" -ge 30 ]; then
        echo "RUIM"
    else
        echo "CRÍTICO"
    fi
}

# generate_mtr_report: produce human-readable diagnosis from mtr output
# Outputs multi-line report to stdout
generate_mtr_report() {
    local target="$1"
    local mtr_out="$2"

    if [ -z "$mtr_out" ]; then
        echo "No MTR data available for $target" >&2
        return 1
    fi

    # Collect metrics
    read -r loss avg best worst stdev hops <<< "$(collect_mtr_metrics "$target")"

    # Validate numeric
    loss=${loss:-0}
    avg=${avg:-0}
    stdev=${stdev:-0}
    hops=${hops:-0}

    # Detect false loss
    local loss_type
    loss_type=$(detect_false_loss "$mtr_out")

    # Jitter
    local jitter
    jitter=$(calculate_jitter_from_mtr "$mtr_out")

    # Compute score
    local score
    score=$(compute_voip_score_mtr "$avg" "$jitter" "$loss" "$hops") || score=0
    local category
    category=$(classify_voip_quality_mtr "$score")

    # Print report
    printf 'Target: %s\n' "$target"
    printf 'MTR summary: Loss=%s%% Avg=%.2fms StDev=%.2fms Hops=%s\n' "$loss" "$avg" "$stdev" "$hops"
    printf 'Estimated jitter: %s ms\n' "$jitter"
    printf 'Loss analysis: %s\n' "$loss_type"
    printf 'VoIP Score: %s (%s)\n' "$score" "$category"

    # Reasons and recommendations
    if [ "$loss_type" = "real_loss" ] && (( $(echo "$loss > 1" | bc -l) )); then
        printf 'Reason: End-to-end packet loss detected (%.2f%%) - likely actual degradation.\n' "$loss"
    elif [ "$loss_type" = "artifact" ]; then
        printf 'Reason: Intermediate hop ICMP rate-limit detected; end-to-end appears healthy.\n'
    fi

    if (( $(echo "$avg > 120" | bc -l) )); then
        printf 'Recommendation: High RTT (>120ms). For VoIP consider regional provider or migrate voice servers closer to destination.\n'
    fi

    if (( $(echo "$jitter > 30" | bc -l) )); then
        printf 'Recommendation: High jitter. Investigate queuing/congestion on transit providers.\n'
    fi

    if (( $(echo "$loss > 1" | bc -l) )); then
        printf 'Recommendation: Packet loss >1%% - contact transit providers and check backbone hops. Consider redundancy.\n'
    fi

    return 0
}

# Export functions
export -f collect_mtr_metrics
export -f detect_false_loss
export -f calculate_jitter_from_mtr
export -f compute_voip_score_mtr
export -f classify_voip_quality_mtr
export -f generate_mtr_report
