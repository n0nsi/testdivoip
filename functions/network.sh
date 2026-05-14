#!/bin/bash

################################################################################
# NETWORK TESTING & PARSING LAYER - network.sh
# LOGIC LAYER: Pure parsing, extraction, calculations
# NO presentation, NO ANSI codes, NO decorative output
# Only raw data to stdout, errors to stderr
################################################################################

################################################################################
# PING OPERATIONS
################################################################################

# run_ping_raw: Execute ping and return full output for auditing/parsing
run_ping_raw() {
    local target="$1"
    local count="${2:-10}"
    local timeout="${3:-5}"

    if ! is_valid_ip "$target"; then
        return 1
    fi

    ping -c "$count" -W "$timeout" -n "$target" 2>&1 || return 1
}

# get_ping_stats_raw: returns "avg loss min max stddev" separated by space
# NO stdout contamination, errors to stderr
# Handles multiple ping output formats (GNU, BSD, busybox)
get_ping_stats_raw() {
    local target="$1"
    local count="${2:-10}"
    local timeout="${3:-5}"
    local output="${4:-}"
    
    if ! is_valid_ip "$target"; then
        echo "" >&2
        return 1
    fi
    
    if [ -z "$output" ]; then
        output=$(ping -c "$count" -W "$timeout" -n "$target" 2>&1) || {
            echo "" >&2
            return 1
        }
    fi
    
    # Extract loss first (consistent across formats)
    local loss
    loss=$(echo "$output" | grep -oP '[0-9.]+(?=% packet loss)' | head -1)
    loss=${loss:-0}
    
    # Try GNU format: "rtt min/avg/max/mdev = x/x/x/x ms" (common on Linux)
    local avg min max stddev
    if echo "$output" | grep -qiE 'rtt .*min/avg/max'; then
        local stats_line
        stats_line=$(echo "$output" | grep -iE 'rtt .*min/avg/max' | tail -1)
        # Extract the part after '=' and split by '/'
        # Example: "rtt min/avg/max/mdev = 11.830/13.355/14.082/0.658 ms"
        local rhs
        rhs=$(echo "$stats_line" | sed -E 's/.*= *//i' | sed -E 's/ ms$//i')
        min=$(echo "$rhs" | awk -F'/' '{print $1}')
        avg=$(echo "$rhs" | awk -F'/' '{print $2}')
        max=$(echo "$rhs" | awk -F'/' '{print $3}')
        stddev=$(echo "$rhs" | awk -F'/' '{print $4}')
    else
        # Fallback: BSD/old format with "avg=" syntax
        local last_line
        last_line=$(echo "$output" | tail -n 1)
        avg=$(echo "$last_line" | grep -oP 'avg=\K[0-9.]+' || true)
        min=$(echo "$last_line" | grep -oP 'min=\K[0-9.]+' || true)
        max=$(echo "$last_line" | grep -oP 'max=\K[0-9.]+' || true)
        stddev=$(echo "$last_line" | grep -oP 'stddev=\K[0-9.]+' || true)
    fi
    
    # Ensure values are set
    avg=${avg:-0}
    min=${min:-0}
    max=${max:-0}
    stddev=${stddev:-0}
    
    # VALIDATION: RTT=0 is suspicious on non-localhost; round-trip minimum is ~0.1ms
    # If avg < 0.1 and not localhost, it's probably parsing error
    if (( $(echo "$avg < 0.1 && $target != '127.0.0.1'" | bc -l 2>/dev/null) )); then
        # Try to recover from parsing failure
        # Return raw ping output for manual inspection
        echo "" >&2
        echo "Warning: Suspicious RTT value ($avg ms) for non-localhost target. Ping output may have unexpected format." >&2
        echo "$output" | tail -5 >&2
        return 1
    fi
    
    # Output only raw numbers, space-separated
    printf '%s %s %s %s %s\n' \
        "$avg" \
        "$loss" \
        "$min" \
        "$max" \
        "$stddev"
}

# Aliases for backward compatibility, but cleaner
get_packet_loss_raw() {
    local target="$1"
    local count="${2:-10}"
    
    local output
    output=$(ping -c "$count" "$target" 2>&1) || return 1
    
    echo "$output" | grep -oP '[0-9.]+(?=% packet loss)' | head -1 || echo "100"
}

################################################################################
# MTR OPERATIONS - Parse only raw data
################################################################################

# run_mtr_raw: Execute MTR and return raw output
run_mtr_raw() {
    local target="$1"
    local count="${2:-100}"
    
    if ! is_valid_ip "$target"; then
        return 1
    fi
    
    mtr -rwzc "$count" "$target" 2>/dev/null || return 1
}

# parse_mtr_raw: Extract "loss avg best worst stddev" from MTR output
# Returns only numbers, space-separated
parse_mtr_raw() {
    local mtr_output="$1"
    
    local loss avg best worst stddev
    
    # Try primary parsing format
    loss=$(echo "$mtr_output" | grep -oP 'Loss%\s+\K[0-9.]+' | head -1)
    avg=$(echo "$mtr_output" | grep -oP 'Avg\s+\K[0-9.]+' | head -1)
    best=$(echo "$mtr_output" | grep -oP 'Best\s+\K[0-9.]+' | head -1)
    worst=$(echo "$mtr_output" | grep -oP 'Wrst\s+\K[0-9.]+' | head -1)
    stddev=$(echo "$mtr_output" | grep -oP 'Stdev\s+\K[0-9.]+' | head -1)
    
    # Fallback parsing if no data found
    if [ -z "$loss" ]; then
        loss=$(echo "$mtr_output" | awk 'NR>1 && /^HOST/ {next} NR>1 {loss=$NF} END {print loss}' | grep -oP '[0-9.]+' | head -1)
    fi
    
    # Output only raw numbers
    printf '%s %s %s %s %s\n' \
        "${loss:-0}" \
        "${avg:-0}" \
        "${best:-0}" \
        "${worst:-0}" \
        "${stddev:-0}"
}

################################################################################
# TRACEROUTE OPERATIONS - Parse only raw data
################################################################################

# run_traceroute_raw: Execute traceroute and return output
run_traceroute_raw() {
    local target="$1"
    local max_hops="${2:-30}"
    
    if ! is_valid_ip "$target"; then
        return 1
    fi
    
    traceroute -m "$max_hops" -n "$target" 2>&1 || return 1
}

# get_hop_count: Count responsive hops from traceroute output
get_hop_count() {
    local traceroute_output="$1"
    
    # Count lines matching " N  IP" pattern
    echo "$traceroute_output" | grep -E '^\s+[0-9]+\s' | wc -l
}

# extract_ips_from_traceroute: Get all IPs from traceroute output
extract_ips_from_traceroute() {
    local traceroute_output="$1"
    
    echo "$traceroute_output" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u
}

################################################################################
# ASN OPERATIONS - Return only raw ASN data
################################################################################

# lookup_asn: Query WHOIS for ASN of given IP
# Returns: "ASXXXX" or "UNKNOWN"
lookup_asn() {
    local ip="$1"
    
    if ! is_valid_ip "$ip"; then
        echo "UNKNOWN"
        return 1
    fi
    
    local result
    result=$(whois -h whois.asn.cymru.com -- "-v $ip" 2>/dev/null | grep -oP 'AS\K[0-9]+' | head -1)
    
    if [ -n "$result" ]; then
        echo "AS$result"
    else
        echo "UNKNOWN"
    fi
}

# lookup_asn_name: Query WHOIS for ASN name/organization
# Returns: Organization name (may be multiple words)
lookup_asn_name() {
    local asn="$1"
    
    whois -h whois.asn.cymru.com "$asn" 2>/dev/null | head -1 | awk '{print $4, $5, $6, $7}'
}

################################################################################
# DNS OPERATIONS - Return only raw DNS data
################################################################################

# forward_dns: Resolve hostname to IP
# Returns: IP address or "UNKNOWN"
forward_dns() {
    local hostname="$1"
    
    local result
    result=$(dig +short "$hostname" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    
    [ -n "$result" ] && echo "$result" || echo "UNKNOWN"
}

# reverse_dns: Reverse resolve IP to hostname
# Returns: hostname or "UNKNOWN"
reverse_dns() {
    local ip="$1"
    
    if ! is_valid_ip "$ip"; then
        echo "UNKNOWN"
        return 1
    fi
    
    local result
    result=$(dig -x "$ip" +short 2>/dev/null | head -1 | sed 's/\.$//')
    
    [ -n "$result" ] && echo "$result" || echo "UNKNOWN"
}

################################################################################
# ROUTE ANALYSIS - Return only numeric metrics
################################################################################

# count_asn_changes: Count unique ASN transitions in route
# Returns: Number of ASN changes
count_asn_changes() {
    local traceroute_output="$1"
    
    local ips=()
    while IFS= read -r ip; do
        if is_valid_ip "$ip"; then
            ips+=("$ip")
        fi
    done < <(extract_ips_from_traceroute "$traceroute_output")
    
    if [ ${#ips[@]} -eq 0 ]; then
        echo "0"
        return 0
    fi
    
    local asn_count=0
    local last_asn=""
    
    for ip in "${ips[@]}"; do
        local asn
        asn=$(lookup_asn "$ip")
        if [ "$asn" != "$last_asn" ]; then
            ((asn_count++))
            last_asn="$asn"
        fi
    done
    
    echo "$asn_count"
}

# detect_route_instability: Detect BGP flapping/route changes
# Returns: Number of instability indicators
detect_route_instability() {
    local traceroute_output="$1"
    
    local unstable_count=0
    declare -A seen_hops
    
    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]+([0-9]+)[[:space:]]+(.*) ]]; then
            local hop="${BASH_REMATCH[1]}"
            local ips
            ips=$(echo "${BASH_REMATCH[2]}" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
            
            for ip in $ips; do
                if is_valid_ip "$ip"; then
                    if [ -n "${seen_hops[$hop]}" ] && [ "${seen_hops[$hop]}" != "$ip" ]; then
                        ((unstable_count++))
                    fi
                    seen_hops[$hop]="$ip"
                fi
            done
        fi
    done <<< "$traceroute_output"
    
    echo "$unstable_count"
}

# is_international_route: Detect international transit ASNs
# Returns: 0 (international) or 1 (domestic)
is_international_route() {
    local traceroute_output="$1"
    
    # Pattern: known international transit carriers
    local international_patterns="(level3|lumen|gtt|ntt|cogent|hurricane|telia|telefonica|ipxo|gtc|zayo)"
    
    if echo "$traceroute_output" | grep -iqE "$international_patterns"; then
        return 0  # International
    fi
    return 1  # Domestic
}

################################################################################
# CONNECTIVITY TESTS - Return status only
################################################################################

# test_ip_reachable: Check if IP responds to ping
# Returns: 0 (reachable) or 1 (unreachable)
test_ip_reachable() {
    local target="$1"
    local timeout="${2:-5}"
    
    if ! is_valid_ip "$target"; then
        return 1
    fi
    
    ping -c 1 -W "$timeout" "$target" &>/dev/null && return 0 || return 1
}

