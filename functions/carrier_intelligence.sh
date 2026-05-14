#!/bin/bash

################################################################################
# CARRIER INTELLIGENCE & PATTERN DETECTION - carrier_intelligence.sh
# LOGIC LAYER: Detect problematic carriers, international routes, transit issues
# Returns: "risk_level|reason|recommendations" or status codes
# NO stdout contamination (except data), errors to stderr
################################################################################

################################################################################
# CARRIER DATABASE - Known problematic carriers and their ASNs
################################################################################

# get_carrier_asns: Return ASN list for known problematic carriers
# Input: carrier_name (cogent, level3, telia, etc.)
# Output: Space-separated ASNs
get_carrier_asns() {
    local carrier_name="$1"
    
    case "${carrier_name,,}" in
        cogent|cogentco)
            echo "174 36561"
            ;;
        level3|lga)
            echo "3356 1"
            ;;
        telia)
            echo "1299"
            ;;
        verizon|verio)
            echo "701 702 AS701"
            ;;
        sprint|centurylink)
            echo "1239"
            ;;
        *)
            return 1
            ;;
    esac
}

# is_problematic_carrier: Check if ASN is known to have peering/routing issues
# Input: ASN (e.g., "174" or "AS174")
# Output: "yes" or "no"
is_problematic_carrier() {
    local asn="$1"
    
    # Normalize ASN format
    asn="${asn##AS}"
    asn="${asn##as}"
    
    # These ASNs are known for:
    # - Aggressive peering policies
    # - Backbone congestion patterns
    # - Rate-limiting on ICMP
    # - Transit provider monopoly behavior
    case "$asn" in
        174|36561)   # Cogent
            echo "yes"
            ;;
        3356|1)      # Level3
            echo "yes"
            ;;
        1299)        # Telia
            echo "yes"
            ;;
        701|702)     # Verizon
            echo "yes"
            ;;
        1239)        # Sprint/CenturyLink
            echo "yes"
            ;;
        *)
            echo "no"
            ;;
    esac
}

# get_carrier_risk_profile: Return risk profile for ASN
# Output: "criticality|historical_issues"
get_carrier_risk_profile() {
    local asn="$1"
    
    # Normalize ASN
    asn="${asn##AS}"
    asn="${asn##as}"
    
    case "$asn" in
        174|36561)   # Cogent - HIGH RISK
            echo "high|Known for backbone congestion, ICMP rate-limiting, aggressive peering. Brazil routes particularly problematic."
            ;;
        3356)        # Level3 - MEDIUM-HIGH RISK
            echo "medium-high|Inconsistent peering, occasional transit saturation. Monitor closely for BRA routes."
            ;;
        701|702)     # Verizon - MEDIUM RISK
            echo "medium|Stable but expensive peering costs drive poor routing decisions. May deprioritize non-customer traffic."
            ;;
        1299)        # Telia - MEDIUM RISK
            echo "medium|European provider, less direct BRA peering. Higher latency variance expected."
            ;;
        *)
            echo "low|No known issues for this ASN."
            ;;
    esac
}

################################################################################
# ROUTE ANALYSIS - Detect international/problematic patterns
################################################################################

# detect_international_route: Check if route crosses international boundaries
# Input: traceroute_output
# Output: "yes" or "no"
detect_international_route() {
    local traceroute_output="$1"
    
    # Check for geographic indicators in hostnames
    # US cities/regions
    if echo "$traceroute_output" | grep -qiE '(\.us-|us-ewr|us-mnh|jfk|atl|mia|dca)\.'; then
        # Check if also has Brazilian indicators
        if echo "$traceroute_output" | grep -qiE '(\.br\.|ctbc|algar|taller|bct|gru1|sao|rj-)'; then
            echo "yes"
            return 0
        fi
    fi
    
    # Check for explicit international patterns
    # HOP progression pattern: starts local/regional, then jumps to another continent
    if echo "$traceroute_output" | grep -qE '(be5576|be5577|be3167|port-channel)' && \
       echo "$traceroute_output" | grep -qE '(gru|jfk|mia|dca)'; then
        echo "yes"
        return 0
    fi
    
    echo "no"
}

# get_transit_providers: Extract all backbone transit providers from traceroute
# Input: traceroute_output
# Output: Space-separated provider names (cogent, level3, etc.)
get_transit_providers() {
    local traceroute_output="$1"
    local providers=""
    
    # Detect by hostname pattern
    if echo "$traceroute_output" | grep -qi 'cogentco\|atlas\.cogentco'; then
        providers="$providers cogent"
    fi
    
    if echo "$traceroute_output" | grep -qi 'level3\|lga\.'; then
        providers="$providers level3"
    fi
    
    if echo "$traceroute_output" | grep -qi 'telia'; then
        providers="$providers telia"
    fi
    
    if echo "$traceroute_output" | grep -qi 'verizon'; then
        providers="$providers verizon"
    fi
    
    echo "${providers}" | xargs
}

# detect_backbone_congestion: Identify signs of backbone transit congestion/policing
# Input: mtr_output traceroute_output
# Output: "yes|no" and reason to stderr
detect_backbone_congestion() {
    local mtr_output="$1"
    local traceroute_output="$2"
    
    # Pattern 1: Partial packet loss on specific hop (not end-to-end)
    # This suggests rate-limiting on that hop, not real degradation
    local hop_loss
    hop_loss=$(echo "$mtr_output" | awk 'NR>1 && /[0-9.]+%/ {
        loss=$NF
        sub(/%.*/, "", loss)
        if (loss > 30 && loss < 100) print loss
    }' | head -1)
    
    if [ -n "$hop_loss" ] && (( $(echo "$hop_loss > 30 && $hop_loss < 100" | bc -l) )); then
        echo "yes"
        echo "Partial packet loss ($hop_loss%) detected on backbone hop - likely ICMP rate-limiting, not end-to-end degradation." >&2
        return 0
    fi
    
    # Pattern 2: 100% loss followed by successful endpoint reach
    # Indicates ICMP block on backbone but route exists
    if echo "$traceroute_output" | grep -q '* * *' && \
       ! echo "$traceroute_output" | tail -5 | grep -q '* * *'; then
        echo "yes"
        echo "Firewall/ICMP rate-limiting detected on backbone transit." >&2
        return 0
    fi
    
    # Pattern 3: Latency spike at specific hop + high stddev
    # Indicates queue buildup or congestion at that point
    local latency_spike
    latency_spike=$(echo "$mtr_output" | awk '
        NR>1 && $NF ~ /[0-9]+/ {
            latency=$(NF-1)
            gsub(/[^0-9.]/, "", latency)
            if (latency > 50 && latency < 1000) print latency
        }
    ' | head -1)
    
    if [ -n "$latency_spike" ] && (( $(echo "$latency_spike > 100" | bc -l 2>/dev/null || echo 0) )); then
        echo "yes"
        echo "Latency spike ($latency_spike ms) suggests temporary congestion on backbone." >&2
        return 0
    fi
    
    echo "no"
}

################################################################################
# RISK ASSESSMENT - Generate risk level based on patterns
################################################################################

# assess_route_risk: Comprehensive risk assessment based on all factors
# Input: traceroute_output mtr_output latency loss hops
# Output: "risk_level|confidence|reasons"
assess_route_risk() {
    local traceroute_output="$1"
    local mtr_output="$2"
    local latency="$3"
    local loss="$4"
    local hops="$5"
    
    local risk_level="low"
    local confidence=0
    local reasons=""
    
    # Check for international route
    if [ "$(detect_international_route "$traceroute_output")" = "yes" ]; then
        risk_level="medium"
        ((confidence += 15))
        reasons="${reasons}International route detected (+latency, +jitter risk). "
    fi
    
    # Check for problematic carriers
    local carriers
    carriers=$(get_transit_providers "$traceroute_output")
    
    for carrier in $carriers; do
        if [ "$(is_problematic_carrier "$carrier")" = "yes" ]; then
            if [ "$risk_level" != "high" ]; then
                risk_level="high"
            fi
            ((confidence += 25))
            local profile
            profile=$(get_carrier_risk_profile "$carrier" | cut -d'|' -f2)
            reasons="${reasons}Problematic carrier detected ($carrier): $profile. "
        fi
    done
    
    # Check for backbone congestion patterns
    if [ "$(detect_backbone_congestion "$mtr_output" "$traceroute_output")" = "yes" ]; then
        if [ "$risk_level" != "high" ]; then
            risk_level="medium-high"
        fi
        ((confidence += 20))
        reasons="${reasons}Backbone transit congestion/policing detected (ICMP rate-limiting). "
    fi
    
    # Check for excessive latency
    if (( $(echo "$latency > 150" | bc -l 2>/dev/null || echo 0) )); then
        if [ "$risk_level" = "low" ]; then
            risk_level="medium"
        fi
        ((confidence += 10))
        reasons="${reasons}High latency (${latency}ms) causes jitter sensitivity. "
    fi
    
    # Check for packet loss > 0.5%
    if (( $(echo "$loss > 0.5" | bc -l 2>/dev/null || echo 0) )); then
        risk_level="high"
        ((confidence += 15))
        reasons="${reasons}Significant packet loss (${loss}%) detected. "
    fi
    
    # Check for excessive hops (>15 suggests poor routing)
    if (( hops > 15 )); then
        if [ "$risk_level" = "low" ]; then
            risk_level="medium"
        fi
        ((confidence += 5))
        reasons="${reasons}Excessive hop count ($hops) suggests suboptimal routing. "
    fi
    
    # Cap confidence at 100
    if (( confidence > 100 )); then
        confidence=100
    fi
    
    echo "${risk_level}|${confidence}|${reasons}"
}

################################################################################
# RECOMMENDATION ENGINE
################################################################################

# get_provider_recommendation: Suggest alternative routing/provider
# Input: risk_level carriers latency
# Output: Recommendation text
get_provider_recommendation() {
    local risk_level="$1"
    local carriers="$2"
    local latency="$3"
    
    case "$risk_level" in
        high)
            if echo "$carriers" | grep -q "cogent"; then
                echo "CRITICAL RECOMMENDATION: Current Cogent routing unsuitable for VoIP. Consider provider migration to:"
                echo "  • AWS São Paulo region (direct peering, lower latency)"
                echo "  • Algar Telecom with AS3352 direct peering"
                echo "  • Alternative carrier with better Brazil peering (Intelig, GVT preferred)"
            else
                echo "CRITICAL: Route quality severely degraded. Recommend immediate carrier evaluation."
            fi
            ;;
        medium-high)
            echo "WARNING: Route has elevated VoIP degradation risk. Recommend:"
            echo "  • Monitor RTP quality metrics closely"
            echo "  • Implement QoS policies (priority for SIP:5060, RTP:18000-20000)"
            echo "  • Consider backup carrier for redundancy"
            ;;
        medium)
            echo "CAUTION: Route acceptable but suboptimal for VoIP. Consider:"
            echo "  • Testing with backup route during peak hours"
            echo "  • Tuning codec to lower bitrate (G.729A vs G.711)"
            ;;
        low)
            echo "Route acceptable for VoIP. Continue monitoring."
            ;;
    esac
}

################################################################################
# EXPORT
################################################################################

# Export all functions to caller
export -f get_carrier_asns
export -f is_problematic_carrier
export -f get_carrier_risk_profile
export -f detect_international_route
export -f get_transit_providers
export -f detect_backbone_congestion
export -f assess_route_risk
export -f get_provider_recommendation
