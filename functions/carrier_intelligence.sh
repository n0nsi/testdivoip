#!/bin/bash

################################################################################
# ROUTE CONTEXT - carrier_intelligence.sh
# Keep carrier/ASN information as context. Do not turn a provider name into a verdict.
################################################################################

# Compatibility helpers kept for older callers. Static carrier blacklists are not used.
get_carrier_asns() {
    return 1
}

is_problematic_carrier() {
    echo "no"
}

get_carrier_risk_profile() {
    echo "neutral|Carrier identity alone is not used as a quality signal."
}

# Numeric traceroute output does not contain enough geography to prove that a path
# crossed a country border. Keep this explicit instead of guessing from provider names.
detect_international_route() {
    echo "unknown"
}

# The current traceroute is numeric, so provider names are not inferred from hostnames.
get_transit_providers() {
    printf '%s\n' ""
}

# Compatibility name. This only reports an endpoint/path warning from MTR data;
# it does not claim to have proven backbone congestion.
detect_backbone_congestion() {
    local mtr_output="$1"
    local metrics mtr_loss mtr_avg mtr_best mtr_worst mtr_stddev

    metrics=$(parse_mtr_raw "$mtr_output") || {
        echo "no"
        return 0
    }

    read -r mtr_loss mtr_avg mtr_best mtr_worst mtr_stddev <<< "$metrics"

    if (( $(echo "${mtr_loss:-0} > 0.5" | bc -l 2>/dev/null || echo 0) )); then
        echo "yes"
        echo "Endpoint MTR shows ${mtr_loss}% packet loss." >&2
        return 0
    fi

    if (( $(echo "${mtr_stddev:-0} > 30" | bc -l 2>/dev/null || echo 0) )); then
        echo "yes"
        echo "Endpoint MTR shows high latency variation (${mtr_stddev} ms StDev)." >&2
        return 0
    fi

    echo "no"
}

# Output: risk_level|evidence_weight|reasons
# evidence_weight is only an internal weight for how many measurable warning signals
# were present. It is not a statistical confidence percentage.
assess_route_risk() {
    local _traceroute_output="$1"
    local mtr_output="$2"
    local latency="$3"
    local loss="$4"
    local hops="$5"

    local risk_level="low"
    local evidence_weight=0
    local reasons=""

    local metrics mtr_loss mtr_avg mtr_best mtr_worst mtr_stddev
    metrics=$(parse_mtr_raw "$mtr_output" 2>/dev/null || true)
    read -r mtr_loss mtr_avg mtr_best mtr_worst mtr_stddev <<< "$metrics"

    mtr_loss="${mtr_loss:-0}"
    mtr_stddev="${mtr_stddev:-0}"

    if (( $(echo "$loss > 3" | bc -l 2>/dev/null || echo 0) )); then
        risk_level="high"
        ((evidence_weight += 40))
        reasons+="Ping shows ${loss}% packet loss. "
    elif (( $(echo "$loss > 1" | bc -l 2>/dev/null || echo 0) )); then
        risk_level="high"
        ((evidence_weight += 30))
        reasons+="Ping shows ${loss}% packet loss. "
    elif (( $(echo "$loss > 0.5" | bc -l 2>/dev/null || echo 0) )); then
        risk_level="medium-high"
        ((evidence_weight += 20))
        reasons+="Ping shows ${loss}% packet loss. "
    elif (( $(echo "$loss > 0" | bc -l 2>/dev/null || echo 0) )); then
        risk_level="medium"
        ((evidence_weight += 10))
        reasons+="Ping shows some packet loss (${loss}%). "
    fi

    if (( $(echo "$latency > 200" | bc -l 2>/dev/null || echo 0) )); then
        risk_level="high"
        ((evidence_weight += 30))
        reasons+="RTT is high (${latency} ms). "
    elif (( $(echo "$latency > 150" | bc -l 2>/dev/null || echo 0) )); then
        [[ "$risk_level" == "low" || "$risk_level" == "medium" ]] && risk_level="medium-high"
        ((evidence_weight += 20))
        reasons+="RTT is elevated (${latency} ms). "
    elif (( $(echo "$latency > 100" | bc -l 2>/dev/null || echo 0) )); then
        [[ "$risk_level" == "low" ]] && risk_level="medium"
        ((evidence_weight += 10))
        reasons+="RTT is above 100 ms (${latency} ms). "
    fi

    if (( $(echo "$mtr_stddev > 50" | bc -l 2>/dev/null || echo 0) )); then
        risk_level="high"
        ((evidence_weight += 30))
        reasons+="MTR endpoint latency varies a lot (${mtr_stddev} ms StDev). "
    elif (( $(echo "$mtr_stddev > 30" | bc -l 2>/dev/null || echo 0) )); then
        [[ "$risk_level" == "low" || "$risk_level" == "medium" ]] && risk_level="medium-high"
        ((evidence_weight += 20))
        reasons+="MTR endpoint latency variation is elevated (${mtr_stddev} ms StDev). "
    elif (( $(echo "$mtr_stddev > 20" | bc -l 2>/dev/null || echo 0) )); then
        [[ "$risk_level" == "low" ]] && risk_level="medium"
        ((evidence_weight += 10))
        reasons+="MTR endpoint latency variation is noticeable (${mtr_stddev} ms StDev). "
    fi

    # Hop count is context only and gets a small weight.
    if is_number "$hops" && (( hops > 25 )); then
        [[ "$risk_level" == "low" ]] && risk_level="medium"
        ((evidence_weight += 5))
        reasons+="The path has many hops ($hops); inspect the route before drawing a conclusion. "
    fi

    (( evidence_weight > 100 )) && evidence_weight=100

    if [ -z "$reasons" ]; then
        reasons="No obvious warning in the measurements collected by this run."
    fi

    echo "${risk_level}|${evidence_weight}|${reasons}"
}

get_provider_recommendation() {
    local risk_level="$1"
    local _providers="$2"
    local _latency="$3"

    case "$risk_level" in
        high)
            echo "Repeat the test during the problem window and compare another path or carrier before blaming one side. Check endpoint loss, MTR and traceroute together."
            ;;
        medium-high)
            echo "Repeat the test at different times and compare the route with a known-good path. Look for persistent endpoint loss or latency variation."
            ;;
        medium)
            echo "Keep the result as a baseline and repeat the test if users report voice quality problems."
            ;;
        low)
            echo "No obvious warning in this run. Keep the report for comparison with future tests."
            ;;
        *)
            echo "Review the raw measurements before making a routing or carrier decision."
            ;;
    esac
}

export -f get_carrier_asns
export -f is_problematic_carrier
export -f get_carrier_risk_profile
export -f detect_international_route
export -f get_transit_providers
export -f detect_backbone_congestion
export -f assess_route_risk
export -f get_provider_recommendation
