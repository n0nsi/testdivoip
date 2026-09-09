#!/bin/bash

# Scoring stays intentionally small. It summarizes measurements from one run;
# it does not try to identify a guilty carrier or prove a routing cause.

calculate_voip_score() {
    local latency="$1"
    local variation="$2"
    local loss="$3"
    local hops="$4"
    local score=100

    is_float "$latency" && is_float "$variation" && is_float "$loss" && is_number "$hops" || {
        echo "0"
        return 1
    }

    if (( $(echo "$latency > 200" | bc -l) )); then
        ((score -= 35))
    elif (( $(echo "$latency > 150" | bc -l) )); then
        ((score -= 25))
    elif (( $(echo "$latency > 100" | bc -l) )); then
        ((score -= 15))
    elif (( $(echo "$latency > 70" | bc -l) )); then
        ((score -= 5))
    fi

    if (( $(echo "$variation > 50" | bc -l) )); then
        ((score -= 25))
    elif (( $(echo "$variation > 30" | bc -l) )); then
        ((score -= 15))
    elif (( $(echo "$variation > 20" | bc -l) )); then
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

    # Hop count is weak evidence by itself, so it barely affects the score.
    (( hops > 25 )) && ((score -= 5))

    (( score < 0 )) && score=0
    (( score > 100 )) && score=100

    echo "$score"
}

classify_voip_quality() {
    local score="$1"

    is_number "$score" || {
        echo "CRÍTICO"
        return 1
    }

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

# Output: risk_level|evidence_weight|reason
# evidence_weight is just a count of warning signals. It is not a probability.
assess_route_risk() {
    local latency="$1"
    local loss="$2"
    local variation="$3"
    local hops="$4"

    local risk="low"
    local evidence=0
    local reasons=""

    if (( $(echo "$loss > 3" | bc -l) )); then
        risk="high"
        ((evidence += 40))
        reasons+="Packet loss is high (${loss}%). "
    elif (( $(echo "$loss > 1" | bc -l) )); then
        risk="high"
        ((evidence += 30))
        reasons+="Packet loss is above 1% (${loss}%). "
    elif (( $(echo "$loss > 0.5" | bc -l) )); then
        risk="medium-high"
        ((evidence += 20))
        reasons+="Packet loss is above 0.5% (${loss}%). "
    elif (( $(echo "$loss > 0" | bc -l) )); then
        risk="medium"
        ((evidence += 10))
        reasons+="Some packet loss was measured (${loss}%). "
    fi

    if (( $(echo "$latency > 200" | bc -l) )); then
        risk="high"
        ((evidence += 30))
        reasons+="RTT is high (${latency} ms). "
    elif (( $(echo "$latency > 150" | bc -l) )); then
        [[ "$risk" == "low" || "$risk" == "medium" ]] && risk="medium-high"
        ((evidence += 20))
        reasons+="RTT is elevated (${latency} ms). "
    elif (( $(echo "$latency > 100" | bc -l) )); then
        [[ "$risk" == "low" ]] && risk="medium"
        ((evidence += 10))
        reasons+="RTT is above 100 ms (${latency} ms). "
    fi

    if (( $(echo "$variation > 50" | bc -l) )); then
        risk="high"
        ((evidence += 30))
        reasons+="Latency variation is high (${variation} ms StDev). "
    elif (( $(echo "$variation > 30" | bc -l) )); then
        [[ "$risk" == "low" || "$risk" == "medium" ]] && risk="medium-high"
        ((evidence += 20))
        reasons+="Latency variation is elevated (${variation} ms StDev). "
    elif (( $(echo "$variation > 20" | bc -l) )); then
        [[ "$risk" == "low" ]] && risk="medium"
        ((evidence += 10))
        reasons+="Latency variation is noticeable (${variation} ms StDev). "
    fi

    if (( hops > 25 )); then
        [[ "$risk" == "low" ]] && risk="medium"
        ((evidence += 5))
        reasons+="The path has many hops ($hops); inspect the route before drawing a conclusion. "
    fi

    (( evidence > 100 )) && evidence=100
    [ -n "$reasons" ] || reasons="No obvious warning in the measurements collected by this run."

    echo "${risk}|${evidence}|${reasons}"
}
