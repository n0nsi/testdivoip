#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Sourcing the main file loads the real functions without starting an interactive run.
# shellcheck source=testdivoip.sh
source "$ROOT_DIR/testdivoip.sh"

failures=0
checks=0

pass() {
    checks=$((checks + 1))
    printf '[PASS] %s\n' "$1"
}

fail() {
    checks=$((checks + 1))
    failures=$((failures + 1))
    printf '[FAIL] %s\n' "$1" >&2
}

assert_equal() {
    local name="$1"
    local expected="$2"
    local actual="$3"

    if [ "$actual" = "$expected" ]; then
        pass "$name"
    else
        fail "$name (expected '$expected', got '$actual')"
    fi
}

assert_success() {
    local name="$1"
    shift

    if "$@"; then
        pass "$name"
    else
        fail "$name"
    fi
}

assert_failure() {
    local name="$1"
    shift

    if "$@"; then
        fail "$name"
    else
        pass "$name"
    fi
}

test_ip_validation() {
    assert_success "valid IPv4 is accepted" is_valid_ip "192.0.2.10"
    assert_failure "invalid IPv4 is rejected" is_valid_ip "999.0.2.10"
}

test_ping_parser() {
    local sample stats
    sample='PING 192.0.2.10 (192.0.2.10) 56(84) bytes of data.
64 bytes from 192.0.2.10: icmp_seq=1 ttl=60 time=12.3 ms

--- 192.0.2.10 ping statistics ---
10 packets transmitted, 10 received, 0% packet loss, time 9000ms
rtt min/avg/max/mdev = 11.000/12.300/14.000/1.000 ms'

    stats=$(get_ping_stats_raw "192.0.2.10" 10 5 "$sample")
    assert_equal "ping summary parser" "12.300 0 11.000 14.000 1.000" "$stats"
}

test_mtr_parser() {
    local sample stats
    sample='HOST: lab                         Loss%   Snt   Last   Avg  Best  Wrst StDev
  1.|-- 192.0.2.1                  0.0%    10    1.0   1.1   0.9   1.5   0.2
  2.|-- 198.51.100.10              1.0%    10   20.0  21.0  19.0  25.0   2.0'

    stats=$(parse_mtr_raw "$sample" "198.51.100.10")
    assert_equal "MTR parser uses the requested endpoint" "1.0 21.0 19.0 25.0 2.0" "$stats"

    if parse_mtr_raw "$sample" "203.0.113.50" >/dev/null 2>&1; then
        fail "MTR parser rejects a missing endpoint"
    else
        pass "MTR parser rejects a missing endpoint"
    fi
}

test_config_parser() {
    local config_file
    config_file=$(mktemp)

    cat > "$config_file" <<'EOF'
# Comments live on their own lines.
CLIENT_NAME="Lab #1"
SCENARIO_NAME="Parser test"
CLOUD_PROVIDER="Local fixture"
PABX_IP="203.0.113.100"

OFFICE_NAMES=(
    "Office A"
)
OFFICE_IPS=(
    "192.0.2.20"
)
TRUNK_NAMES=(
)
TRUNK_IPS=(
)
MTR_PACKETS=25
DEBUG=1
EOF

    if load_configuration_file "$config_file"; then
        pass "config file parses"
    else
        fail "config file parses"
    fi

    assert_equal "config keeps # inside quoted values" "Lab #1" "$CLIENT_NAME"
    assert_equal "config loads array names" "Office A" "${OFFICE_NAMES[0]:-}"
    assert_equal "config loads array IPs" "192.0.2.20" "${OFFICE_IPS[0]:-}"
    assert_equal "config loads MTR packet count" "25" "$MTR_PACKETS"
    assert_equal "config loads debug flag" "1" "$DEBUG"

    rm -f "$config_file"
}

test_result_sanitization() {
    assert_equal "result separator is sanitized" "Office-A" "$(sanitize_result_field 'Office|A')"
}

test_score() {
    assert_equal "clean measurements keep full score" "100" "$(calculate_voip_score 50 5 0 10)"

    if calculate_voip_score bad 5 0 10 >/dev/null 2>&1; then
        fail "invalid score input is rejected"
    else
        pass "invalid score input is rejected"
    fi
}

test_cli() {
    local status

    if bash "$ROOT_DIR/testdivoip.sh" --help >/dev/null 2>&1; then
        pass "--help exits successfully"
    else
        fail "--help exits successfully"
    fi

    bash "$ROOT_DIR/testdivoip.sh" --not-a-real-option >/dev/null 2>&1
    status=$?
    assert_equal "unknown option returns exit 2" "2" "$status"

    bash "$ROOT_DIR/testdivoip.sh" --config >/dev/null 2>&1
    status=$?
    assert_equal "missing option value returns exit 2" "2" "$status"
}

main() {
    test_ip_validation
    test_ping_parser
    test_mtr_parser
    test_config_parser
    test_result_sanitization
    test_score
    test_cli

    echo ""
    printf '%d checks, %d failure(s)\n' "$checks" "$failures"

    [ "$failures" -eq 0 ]
}

main "$@"
