#!/bin/bash

################################################################################
# NETWORK TESTS - testdivoip
# Funções para testes de rede, MTR, traceroute, ping, etc.
################################################################################

################################################################################
# PING TEST
################################################################################

ping_test() {
    local target="$1"
    local count="${2:-10}"
    local timeout="${3:-5}"
    
    log_command "ping -c $count -W $timeout $target"
    
    ping -c "$count" -W "$timeout" "$target" 2>/dev/null
}

get_ping_stats() {
    local target="$1"
    local count="${2:-10}"
    
    local output
    output=$(ping_test "$target" "$count" 2>/dev/null | tail -n 1)
    
    if [ -z "$output" ]; then
        echo "ERROR"
        return 1
    fi
    
    # Extrair: min/avg/max/stddev
    local stats
    stats=$(echo "$output" | grep -oP 'min=\K[0-9.]+|avg=\K[0-9.]+|max=\K[0-9.]+|stddev=\K[0-9.]+')
    
    echo "$stats"
}

get_packet_loss() {
    local target="$1"
    local count="${2:-10}"
    
    local output
    output=$(ping -c "$count" "$target" 2>&1)
    
    if [ -z "$output" ]; then
        echo "100"
        return 1
    fi
    
    echo "$output" | grep -oP '\K[0-9]+(?=% packet loss)'
}

################################################################################
# MTR TEST
################################################################################

mtr_test() {
    local target="$1"
    local count="${2:-100}"
    local report_file="$TEMP_DIR/mtr_${target//\./\_}_$$.txt"
    
    print_info "Running MTR test ($count packets) to $target..."
    
    log_command "mtr -rwzc $count $target"
    
    # Executar MTR em report mode
    mtr -rwzc "$count" "$target" > "$report_file" 2>&1
    
    cat "$report_file"
}

# Analisar output do MTR
parse_mtr_output() {
    local mtr_output="$1"
    
    local loss=0
    local avg=0
    local best=0
    local worst=0
    local stddev=0
    
    loss=$(echo "$mtr_output" | grep -oP 'Loss%\s+\K[0-9.]+' | head -1)
    avg=$(echo "$mtr_output" | grep -oP 'Avg\s+\K[0-9.]+' | head -1)
    best=$(echo "$mtr_output" | grep -oP 'Best\s+\K[0-9.]+' | head -1)
    worst=$(echo "$mtr_output" | grep -oP 'Wrst\s+\K[0-9.]+' | head -1)
    stddev=$(echo "$mtr_output" | grep -oP 'Stdev\s+\K[0-9.]+' | head -1)
    
    # Se não encontrar via parsing, tentar com formato alternativo
    if [ -z "$loss" ]; then
        loss=$(echo "$mtr_output" | awk 'NR>1 {loss=$2} END {print loss}' | grep -oP '[0-9.]+')
    fi
    
    echo "loss=${loss:-0} avg=${avg:-0} best=${best:-0} worst=${worst:-0} stddev=${stddev:-0}"
}

calculate_jitter() {
    local stddev="$1"
    local avg="$2"
    
    # Jitter = stddev da latência
    if (( $(echo "$stddev > 0" | bc -l) )); then
        echo "$stddev"
    else
        echo "0"
    fi
}

################################################################################
# TRACEROUTE TEST
################################################################################

traceroute_test() {
    local target="$1"
    local max_hops="${2:-30}"
    
    print_info "Running traceroute to $target..."
    
    log_command "traceroute -m $max_hops -n $target"
    
    traceroute -m "$max_hops" -n "$target" 2>&1
}

count_hops() {
    local traceroute_output="$1"
    
    # Contar linhas com IPs (não contar headers e linhas sem resposta)
    echo "$traceroute_output" | grep -E '^\s+[0-9]+' | wc -l
}

get_last_hop_asn() {
    local traceroute_output="$1"
    
    # Pegar último IP respondendo
    local last_ip
    last_ip=$(echo "$traceroute_output" | grep -E '^\s+[0-9]+' | tail -1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    
    if [ -n "$last_ip" ]; then
        get_asn_from_ip "$last_ip"
    fi
}

################################################################################
# ROUTE DETECTION
################################################################################

detect_international_route() {
    local traceroute_output="$1"
    
    # Buscar por padrões que indicam rota internacional
    # Level3, GTT, NTT, HE, Cogent - geralmente transporte internacional
    
    if echo "$traceroute_output" | grep -iqE '(level3|lumen|gtt|ntt|cogent|hurricane|telia|telefonica|ipxo)'; then
        return 0  # true - rota internacional detectada
    fi
    
    return 1  # false
}

# Contar ASNs únicos na rota
count_asn_changes() {
    local traceroute_output="$1"
    
    local ips=()
    while IFS= read -r line; do
        local ip
        ip=$(echo "$line" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        [ -n "$ip" ] && ips+=("$ip")
    done <<< "$traceroute_output"
    
    local asn_count=0
    local last_asn=""
    
    for ip in "${ips[@]}"; do
        local asn
        asn=$(get_asn_from_ip "$ip")
        if [ "$asn" != "$last_asn" ]; then
            ((asn_count++))
            last_asn="$asn"
        fi
    done
    
    echo "$asn_count"
}

################################################################################
# ROUTE ANALYSIS
################################################################################

detect_route_instability() {
    local mtr_output="$1"
    
    # Procurar por múltiplas entradas do mesmo hop com IPs diferentes
    # Isto indica mudança de rota (instabilidade)
    
    local unstable_count=0
    local hop_ips=()
    
    while IFS= read -r line; do
        if [[ $line =~ ^\ +[0-9]+ ]]; then
            local hop
            hop=$(echo "$line" | awk '{print $1}')
            local ip
            ip=$(echo "$line" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            
            if [ -n "$ip" ]; then
                hop_ips+=("${hop}:${ip}")
            fi
        fi
    done <<< "$mtr_output"
    
    # Verificar se mesmo hop tem IPs diferentes
    declare -A seen_hops
    for entry in "${hop_ips[@]}"; do
        local hop=${entry%:*}
        local ip=${entry#*:}
        
        if [ -n "${seen_hops[$hop]}" ] && [ "${seen_hops[$hop]}" != "$ip" ]; then
            ((unstable_count++))
        fi
        seen_hops[$hop]="$ip"
    done
    
    echo "$unstable_count"
}

################################################################################
# IP INFORMATION
################################################################################

get_ipinfo() {
    local ip="$1"
    
    # Usar ipinfo.io para informações do IP
    log_command "curl -s https://ipinfo.io/$ip"
    
    curl -s "https://ipinfo.io/$ip" 2>/dev/null
}

get_country_from_ip() {
    local ip="$1"
    
    if ! check_dependency "jq"; then
        return 1
    fi
    
    local info
    info=$(get_ipinfo "$ip")
    
    echo "$info" | jq -r '.country // "UNKNOWN"' 2>/dev/null
}

get_asn_from_ip() {
    local ip="$1"
    
    if ! check_dependency "whois"; then
        return 1
    fi
    
    log_command "whois -h whois.asn.cymru.com -- '-v $ip'"
    
    local result
    result=$(whois -h whois.asn.cymru.com -- "-v $ip" 2>/dev/null | grep -oP 'AS\K[0-9]+' | head -1)
    
    if [ -n "$result" ]; then
        echo "AS$result"
    else
        echo "UNKNOWN"
    fi
}

get_asn_name() {
    local asn="$1"
    
    if ! check_dependency "whois"; then
        return 1
    fi
    
    log_command "whois -h whois.asn.cymru.com $asn"
    
    whois -h whois.asn.cymru.com "$asn" 2>/dev/null | head -1 | awk '{print $4, $5, $6, $7}'
}

get_asn_info() {
    local asn="$1"
    
    # Extrair informações mais completas sobre ASN
    log_command "whois AS${asn#AS}"
    
    whois "AS${asn#AS}" 2>/dev/null
}

################################################################################
# DNS RESOLUTION
################################################################################

dns_lookup() {
    local hostname="$1"
    
    if ! check_dependency "dig"; then
        return 1
    fi
    
    log_command "dig +short $hostname"
    
    dig +short "$hostname" 2>/dev/null
}

reverse_dns() {
    local ip="$1"
    
    if ! check_dependency "dig"; then
        return 1
    fi
    
    log_command "dig -x $ip +short"
    
    dig -x "$ip" +short 2>/dev/null | head -1
}

################################################################################
# NETWORK CONNECTIVITY
################################################################################

test_connectivity() {
    local target="$1"
    local port="${2:-80}"
    
    if ! check_dependency "nc"; then
        # Usar bash native timeout com /dev/tcp
        timeout 3 bash -c "</dev/tcp/$target/$port" 2>/dev/null && return 0 || return 1
    else
        nc -zw3 "$target" "$port" 2>/dev/null && return 0 || return 1
    fi
}

test_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"
    
    log_command "curl -s -m $timeout http://$host:$port"
    
    curl -s -m "$timeout" "http://$host:$port" &>/dev/null && return 0 || return 1
}

