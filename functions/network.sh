#!/bin/bash

# Raw network checks and the parsers used by the main workflow.

run_ping_raw() {
    local target="$1"
    local count="${2:-10}"
    local timeout="${3:-5}"

    is_valid_ip "$target" || return 1
    LC_ALL=C ping -c "$count" -W "$timeout" -n "$target" 2>&1
}

# Output: avg loss min max stddev
get_ping_stats_raw() {
    local target="$1"
    local count="${2:-10}"
    local timeout="${3:-5}"
    local output="${4:-}"

    is_valid_ip "$target" || return 1

    if [ -z "$output" ]; then
        output=$(run_ping_raw "$target" "$count" "$timeout") || true
    fi

    [ -n "$output" ] || return 1

    local loss avg min max stddev stats_line rhs

    loss=$(printf '%s\n' "$output" | sed -nE 's/.* ([0-9.]+)% packet loss.*/\1/p' | tail -1)
    stats_line=$(printf '%s\n' "$output" | grep -E '(rtt|round-trip).*min/avg/max' | tail -1 || true)

    [ -n "$loss" ] && [ -n "$stats_line" ] || return 1

    rhs=$(printf '%s\n' "$stats_line" | sed -E 's/.*= *//' | sed -E 's/[[:space:]]*ms$//')
    min=$(printf '%s\n' "$rhs" | awk -F/ '{print $1}')
    avg=$(printf '%s\n' "$rhs" | awk -F/ '{print $2}')
    max=$(printf '%s\n' "$rhs" | awk -F/ '{print $3}')
    stddev=$(printf '%s\n' "$rhs" | awk -F/ '{print $4}')

    is_float "$loss" && is_float "$avg" && is_float "$min" && is_float "$max" && is_float "$stddev" || return 1

    # A zero-ish RTT to a remote target is more likely to be a parsing problem than
    # useful data. Refuse it instead of creating an artificially good score.
    if [ "$target" != "127.0.0.1" ] && (( $(echo "$avg < 0.1" | bc -l) )); then
        return 1
    fi

    printf '%s %s %s %s %s\n' "$avg" "$loss" "$min" "$max" "$stddev"
}

run_mtr_raw() {
    local target="$1"
    local count="${2:-100}"

    is_valid_ip "$target" || return 1
    LC_ALL=C mtr -rwnc "$count" "$target" 2>/dev/null
}

# MTR report columns end with: Loss% Snt Last Avg Best Wrst StDev
# Output: loss avg best worst stddev
parse_mtr_raw() {
    local mtr_output="$1"
    local final_line loss avg best worst stddev

    final_line=$(printf '%s\n' "$mtr_output" | awk '/[0-9.]+%/ {line=$0} END {print line}')
    [ -n "$final_line" ] || return 1

    loss=$(printf '%s\n' "$final_line" | awk '{print $(NF-6)}' | tr -d '%')
    avg=$(printf '%s\n' "$final_line" | awk '{print $(NF-3)}')
    best=$(printf '%s\n' "$final_line" | awk '{print $(NF-2)}')
    worst=$(printf '%s\n' "$final_line" | awk '{print $(NF-1)}')
    stddev=$(printf '%s\n' "$final_line" | awk '{print $NF}')

    is_float "$loss" && is_float "$avg" && is_float "$best" && is_float "$worst" && is_float "$stddev" || return 1

    printf '%s %s %s %s %s\n' "$loss" "$avg" "$best" "$worst" "$stddev"
}

run_traceroute_raw() {
    local target="$1"
    local max_hops="${2:-30}"

    is_valid_ip "$target" || return 1
    LC_ALL=C traceroute -m "$max_hops" -n "$target" 2>&1
}

get_hop_count() {
    local traceroute_output="$1"
    printf '%s\n' "$traceroute_output" | awk '/^[[:space:]]*[0-9]+[[:space:]]/ {count++} END {print count+0}'
}

lookup_asn() {
    local ip="$1"
    local result

    is_valid_ip "$ip" || {
        echo "UNKNOWN"
        return 1
    }

    result=$(LC_ALL=C whois -h whois.cymru.com " -v $ip" 2>/dev/null \
        | awk -F'|' 'NR>1 {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
            if ($1 ~ /^[0-9]+$/) { print "AS" $1; exit }
        }')

    [ -n "$result" ] && echo "$result" || echo "UNKNOWN"
}

lookup_asn_name() {
    local asn="$1"
    local result

    [[ "$asn" =~ ^AS[0-9]+$ ]] || {
        echo "UNKNOWN"
        return 1
    }

    # Team Cymru's verbose ASN lookup is:
    # AS | CC | Registry | Allocated | AS Name
    result=$(LC_ALL=C whois -h whois.cymru.com " -v $asn" 2>/dev/null \
        | awk -F'|' 'NR>1 {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $5)
            if ($5 != "") { print $5; exit }
        }')

    [ -n "$result" ] && echo "$result" || echo "UNKNOWN"
}
