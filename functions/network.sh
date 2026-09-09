#!/bin/bash

################################################################################
# NETWORK TESTING & PARSING - network.sh
# Raw checks and parsers only. User-facing text belongs in presentation/reporting.
################################################################################

run_ping_raw() {
    local target="$1"
    local count="${2:-10}"
    local timeout="${3:-5}"

    is_valid_ip "$target" || return 1
    ping -c "$count" -W "$timeout" -n "$target" 2>&1
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
    loss="${loss:-100}"

    stats_line=$(printf '%s\n' "$output" | grep -iE '(rtt|round-trip).*min/avg/max' | tail -1 || true)

    if [ -n "$stats_line" ]; then
        rhs=$(printf '%s\n' "$stats_line" | sed -E 's/.*= *//' | sed -E 's/[[:space:]]*ms$//')
        min=$(printf '%s\n' "$rhs" | awk -F/ '{print $1}')
        avg=$(printf '%s\n' "$rhs" | awk -F/ '{print $2}')
        max=$(printf '%s\n' "$rhs" | awk -F/ '{print $3}')
        stddev=$(printf '%s\n' "$rhs" | awk -F/ '{print $4}')
    else
        avg=$(printf '%s\n' "$output" | sed -nE 's/.*avg=([0-9.]+).*/\1/p' | tail -1)
        min=$(printf '%s\n' "$output" | sed -nE 's/.*min=([0-9.]+).*/\1/p' | tail -1)
        max=$(printf '%s\n' "$output" | sed -nE 's/.*max=([0-9.]+).*/\1/p' | tail -1)
        stddev=$(printf '%s\n' "$output" | sed -nE 's/.*stddev=([0-9.]+).*/\1/p' | tail -1)
    fi

    avg="${avg:-0}"
    min="${min:-0}"
    max="${max:-0}"
    stddev="${stddev:-0}"

    # A zero-ish RTT on a remote target usually means the parser did not understand
    # the local ping output. Fail instead of turning a parsing error into a good score.
    if [ "$target" != "127.0.0.1" ] && (( $(echo "$avg < 0.1" | bc -l 2>/dev/null || echo 0) )); then
        printf 'Could not parse a believable RTT from ping output for %s\n' "$target" >&2
        return 1
    fi

    printf '%s %s %s %s %s\n' "$avg" "$loss" "$min" "$max" "$stddev"
}

get_packet_loss_raw() {
    local target="$1"
    local count="${2:-10}"
    local output

    output=$(run_ping_raw "$target" "$count" 5) || true
    [ -n "$output" ] || {
        echo "100"
        return 1
    }

    printf '%s\n' "$output" | sed -nE 's/.* ([0-9.]+)% packet loss.*/\1/p' | tail -1
}

run_mtr_raw() {
    local target="$1"
    local count="${2:-100}"

    is_valid_ip "$target" || return 1

    # Numeric report output keeps parsing deterministic and avoids DNS delays.
    mtr -rwnc "$count" "$target" 2>/dev/null
}

# Parse the final MTR hop. Columns at the end are stable in report mode:
# Loss%, Snt, Last, Avg, Best, Wrst, StDev
# Output: loss avg best worst stddev
parse_mtr_raw() {
    local mtr_output="$1"
    local final_line

    final_line=$(printf '%s\n' "$mtr_output" | awk '/[0-9.]+%/ {line=$0} END {print line}')
    [ -n "$final_line" ] || return 1

    local loss avg best worst stddev
    loss=$(printf '%s\n' "$final_line" | awk '{print $(NF-6)}' | tr -d '%')
    avg=$(printf '%s\n' "$final_line" | awk '{print $(NF-3)}')
    best=$(printf '%s\n' "$final_line" | awk '{print $(NF-2)}')
    worst=$(printf '%s\n' "$final_line" | awk '{print $(NF-1)}')
    stddev=$(printf '%s\n' "$final_line" | awk '{print $NF}')

    case "$loss $avg $best $worst $stddev" in
        *[!0-9.\ ]*) return 1 ;;
    esac

    printf '%s %s %s %s %s\n' "$loss" "$avg" "$best" "$worst" "$stddev"
}

run_traceroute_raw() {
    local target="$1"
    local max_hops="${2:-30}"

    is_valid_ip "$target" || return 1
    traceroute -m "$max_hops" -n "$target" 2>&1
}

get_hop_count() {
    local traceroute_output="$1"
    printf '%s\n' "$traceroute_output" | awk '/^[[:space:]]*[0-9]+[[:space:]]/ {count++} END {print count+0}'
}

# Preserve route order. Do not sort the IP list before analysing transitions.
extract_ips_from_traceroute() {
    local traceroute_output="$1"

    printf '%s\n' "$traceroute_output" \
        | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' \
        | awk '!seen[$0]++'
}

lookup_asn() {
    local ip="$1"
    local result

    is_valid_ip "$ip" || {
        echo "UNKNOWN"
        return 1
    }

    result=$(whois -h whois.cymru.com -- " -v $ip" 2>/dev/null \
        | awk -F'|' 'NR>1 {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
            if ($1 ~ /^[0-9]+$/) { print "AS" $1; exit }
        }')

    [ -n "$result" ] && echo "$result" || echo "UNKNOWN"
}

lookup_asn_name() {
    local asn="$1"
    local result

    result=$(whois -h whois.cymru.com -- " -v $asn" 2>/dev/null \
        | awk -F'|' 'NR>1 {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $7)
            if ($7 != "") { print $7; exit }
        }')

    [ -n "$result" ] && echo "$result" || echo "UNKNOWN"
}

forward_dns() {
    local hostname="$1"
    local result

    result=$(dig +short "$hostname" A 2>/dev/null | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | head -1)
    [ -n "$result" ] && echo "$result" || echo "UNKNOWN"
}

reverse_dns() {
    local ip="$1"
    local result

    is_valid_ip "$ip" || {
        echo "UNKNOWN"
        return 1
    }

    result=$(dig -x "$ip" +short 2>/dev/null | head -1 | sed 's/\.$//')
    [ -n "$result" ] && echo "$result" || echo "UNKNOWN"
}

# Count ASN transitions in route order. UNKNOWN entries are skipped.
count_asn_changes() {
    local traceroute_output="$1"
    local ip asn last_asn=""
    local transitions=0

    while IFS= read -r ip; do
        is_valid_ip "$ip" || continue
        asn=$(lookup_asn "$ip")
        [ "$asn" = "UNKNOWN" ] && continue

        if [ -n "$last_asn" ] && [ "$asn" != "$last_asn" ]; then
            ((transitions++))
        fi
        last_asn="$asn"
    done < <(extract_ips_from_traceroute "$traceroute_output")

    echo "$transitions"
}

# A single traceroute can show ECMP/multipath. That is not the same thing as BGP
# flapping, so this function only counts hops where multiple addresses were seen.
detect_route_instability() {
    local traceroute_output="$1"
    local multipath_hops=0
    local line ips unique_count

    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*[0-9]+[[:space:]] ]] || continue
        ips=$(printf '%s\n' "$line" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | awk '!seen[$0]++')
        unique_count=$(printf '%s\n' "$ips" | sed '/^$/d' | wc -l)
        (( unique_count > 1 )) && ((multipath_hops++))
    done <<< "$traceroute_output"

    echo "$multipath_hops"
}

# A numeric traceroute alone is not enough to prove route geography.
is_international_route() {
    return 1
}

test_ip_reachable() {
    local target="$1"
    local timeout="${2:-5}"

    is_valid_ip "$target" || return 1
    ping -c 1 -W "$timeout" -n "$target" >/dev/null 2>&1
}
