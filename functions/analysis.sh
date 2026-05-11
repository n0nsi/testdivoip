#!/bin/bash

################################################################################
# ANALYSIS & SCORING - testdivoip
# Funções para análise de qualidade VoIP e cálculo de scores
################################################################################

################################################################################
# QUALITY SCORING
################################################################################

# Calcular score VoIP baseado em múltiplos critérios
calculate_voip_score() {
    local latency="$1"
    local jitter="$2"
    local loss="$3"
    local hops="$4"
    local asn_suspicious="$5"
    local international="$6"
    
    local score=100
    local details=""
    
    # Latência: ideal < 50ms, aceitável < 100ms, crítico > 150ms
    if (( $(echo "$latency > 150" | bc -l) )); then
        score=$((score - 30))
        details="${details}\n    ✗ High latency (${latency}ms) - unacceptable for VoIP"
    elif (( $(echo "$latency > 100" | bc -l) )); then
        score=$((score - 15))
        details="${details}\n    ⚠ Elevated latency (${latency}ms) - impacts call quality"
    elif (( $(echo "$latency > 50" | bc -l) )); then
        score=$((score - 5))
        details="${details}\n    ◇ Moderate latency (${latency}ms) - acceptable"
    else
        details="${details}\n    ✓ Excellent latency (${latency}ms)"
    fi
    
    # Jitter: ideal < 20ms, aceitável < 50ms, crítico > 100ms
    if (( $(echo "$jitter > 100" | bc -l) )); then
        score=$((score - 25))
        details="${details}\n    ✗ Critical jitter (${jitter}ms) - RTP will degrade"
    elif (( $(echo "$jitter > 50" | bc -l) )); then
        score=$((score - 15))
        details="${details}\n    ⚠ High jitter (${jitter}ms) - voice artifacts expected"
    elif (( $(echo "$jitter > 20" | bc -l) )); then
        score=$((score - 5))
        details="${details}\n    ◇ Moderate jitter (${jitter}ms) - acceptable"
    else
        details="${details}\n    ✓ Excellent jitter (${jitter}ms)"
    fi
    
    # Packet Loss: ideal 0%, aceitável < 0.5%, crítico > 1%
    if (( $(echo "$loss > 1" | bc -l) )); then
        score=$((score - 30))
        details="${details}\n    ✗ Unacceptable packet loss (${loss}%) - voice quality severely impacted"
    elif (( $(echo "$loss > 0.5" | bc -l) )); then
        score=$((score - 15))
        details="${details}\n    ⚠ Packet loss detected (${loss}%) - quality degradation"
    elif (( $(echo "$loss > 0" | bc -l) )); then
        score=$((score - 5))
        details="${details}\n    ◇ Minor packet loss (${loss}%) - acceptable"
    else
        details="${details}\n    ✓ Zero packet loss"
    fi
    
    # Hops: ideal < 10, aceitável < 15, crítico > 20
    if (( hops > 20 )); then
        score=$((score - 10))
        details="${details}\n    ✗ Excessive hop count ($hops) - indicates poor routing"
    elif (( hops > 15 )); then
        score=$((score - 5))
        details="${details}\n    ⚠ High hop count ($hops) - some routing complexity"
    else
        details="${details}\n    ✓ Good hop count ($hops)"
    fi
    
    # ASN suspeito
    if [ "$asn_suspicious" = "1" ]; then
        score=$((score - 10))
        details="${details}\n    ⚠ Suspicious ASN detected - review peering"
    fi
    
    # Rota internacional
    if [ "$international" = "1" ]; then
        score=$((score - 5))
        details="${details}\n    ◇ International route detected - monitor performance"
    fi
    
    # Garantir que score fica entre 0 e 100
    if (( score < 0 )); then
        score=0
    fi
    
    echo "$score|$details"
}

# Classificar score em categoria
classify_voip_score() {
    local score="$1"
    
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

################################################################################
# ASN ANALYSIS
################################################################################

# Detectar ASNs conhecidos como problemáticos para VoIP
is_asn_suspicious() {
    local asn="$1"
    
    # ASNs conhecidos por problemas de trânsito/peering
    local suspicious_patterns=(
        "AS1299"   # Telia
        "AS174"    # Cogent
        "AS3356"   # Level3
        "AS2914"   # NTT
        "AS3257"   # GTT
        "AS1668"   # AOL
        "AS12389"  # Rostelecom
        "AS5511"   # Orange
    )
    
    for pattern in "${suspicious_patterns[@]}"; do
        if [[ "$asn" == "$pattern" ]]; then
            return 0  # true - suspeito
        fi
    done
    
    return 1  # false
}

# Tentar obter nome da operadora por ASN
get_asn_carrier() {
    local asn="$1"
    
    case "$asn" in
        "AS3356"|"AS1") echo "Level3/Lumen (Transit)" ;;
        "AS174") echo "Cogent (Transit)" ;;
        "AS1299") echo "Telia (Transit)" ;;
        "AS2914") echo "NTT (Transit)" ;;
        "AS3257") echo "GTT (Transit)" ;;
        "AS16509") echo "Amazon AWS" ;;
        "AS14061") echo "DigitalOcean" ;;
        "AS8452") echo "Telemig (BR)" ;;
        "AS27699") echo "Telefonica Brasil" ;;
        *) echo "Unknown (ASN: $asn)" ;;
    esac
}

################################################################################
# DETAILED ANALYSIS
################################################################################

analyze_route_quality() {
    local target="$1"
    local traceroute_output="$2"
    local mtr_output="$3"
    
    local analysis=""
    
    # Análise 1: Quantidade de hops
    local hops
    hops=$(count_hops "$traceroute_output")
    
    if (( hops < 8 )); then
        analysis="${analysis}\n✓ Route is direct and efficient ($hops hops)"
    elif (( hops < 15 )); then
        analysis="${analysis}\n◇ Route has moderate complexity ($hops hops)"
    else
        analysis="${analysis}\n⚠ Route is complex with many intermediaries ($hops hops) - possible congestion risk"
    fi
    
    # Análise 2: Estabilidade da rota
    local instability
    instability=$(detect_route_instability "$mtr_output")
    
    if (( instability > 3 )); then
        analysis="${analysis}\n⚠ Route instability detected ($instability changes) - BGP flapping possible"
    elif (( instability > 0 )); then
        analysis="${analysis}\n◇ Minor route changes detected ($instability) - within normal parameters"
    else
        analysis="${analysis}\n✓ Route is stable and consistent"
    fi
    
    # Análise 3: Rota internacional
    if detect_international_route "$traceroute_output"; then
        analysis="${analysis}\n◇ International route detected - increased latency expected"
    else
        analysis="${analysis}\n✓ Route appears to be domestic/regional"
    fi
    
    # Análise 4: Variacão de latência
    local stddev
    stddev=$(echo "$mtr_output" | grep -oP 'Stdev\s+\K[0-9.]+'  | head -1)
    
    if (( $(echo "$stddev > 0" | bc -l) )); then
        if (( $(echo "$stddev > 50" | bc -l) )); then
            analysis="${analysis}\n⚠ Excessive latency variation ($stddev ms) - indicates path instability or congestion"
        elif (( $(echo "$stddev > 20" | bc -l) )); then
            analysis="${analysis}\n◇ Moderate latency variation ($stddev ms) - some congestion possible"
        fi
    fi
    
    echo -e "$analysis"
}

analyze_asn_chain() {
    local traceroute_output="$1"
    
    local analysis=""
    local asn_count=0
    local last_asn=""
    local asn_changes=0
    
    analysis="${analysis}\n╔═ ASN Path Analysis ═╗\n"
    
    # Extrair IPs e seus ASNs
    local ips=()
    while IFS= read -r line; do
        if [[ $line =~ ^\ +[0-9]+ ]]; then
            local ip
            ip=$(echo "$line" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            [ -n "$ip" ] && ips+=("$ip")
        fi
    done <<< "$traceroute_output"
    
    for ip in "${ips[@]}"; do
        local asn
        asn=$(get_asn_from_ip "$ip")
        
        ((asn_count++))
        
        if [ "$asn" != "$last_asn" ]; then
            ((asn_changes++))
            local carrier
            carrier=$(get_asn_carrier "$asn")
            analysis="${analysis}\n  $((asn_count)). $asn ($carrier)"
            
            if is_asn_suspicious "$asn"; then
                analysis="${analysis} ⚠ SUSPICIOUS"
            fi
            
            last_asn="$asn"
        fi
    done
    
    analysis="${analysis}\n  Total ASN changes: $asn_changes"
    
    echo -e "$analysis"
}

################################################################################
# COMPREHENSIVE REPORT ANALYSIS
################################################################################

generate_quality_assessment() {
    local target="$1"
    local latency="$2"
    local jitter="$3"
    local loss="$4"
    local hops="$5"
    local asn_suspicious="$6"
    local international="$7"
    
    local assessment=""
    
    assessment="${assessment}\n╔═ VoIP Quality Assessment for $target ═╗\n"
    
    # RTT Assessment
    assessment="${assessment}\n[Latency]\n"
    if (( $(echo "$latency <= 50" | bc -l) )); then
        assessment="${assessment}  Status: EXCELLENT - Ideal for any VoIP application\n"
        assessment="${assessment}  Latency: ${latency}ms (target < 50ms)\n"
    elif (( $(echo "$latency <= 100" | bc -l) )); then
        assessment="${assessment}  Status: GOOD - Acceptable for most VoIP applications\n"
        assessment="${assessment}  Latency: ${latency}ms (acceptable < 100ms)\n"
    elif (( $(echo "$latency <= 150" | bc -l) )); then
        assessment="${assessment}  Status: FAIR - May impact user experience\n"
        assessment="${assessment}  Latency: ${latency}ms (warning > 100ms)\n"
    else
        assessment="${assessment}  Status: POOR - Significant impact on voice quality\n"
        assessment="${assessment}  Latency: ${latency}ms (critical > 150ms)\n"
    fi
    
    # Jitter Assessment
    assessment="${assessment}\n[Jitter]\n"
    if (( $(echo "$jitter <= 20" | bc -l) )); then
        assessment="${assessment}  Status: EXCELLENT - Stable for high-quality VoIP\n"
        assessment="${assessment}  Jitter: ${jitter}ms (target < 20ms)\n"
    elif (( $(echo "$jitter <= 50" | bc -l) )); then
        assessment="${assessment}  Status: GOOD - Acceptable with modern codecs\n"
        assessment="${assessment}  Jitter: ${jitter}ms (acceptable < 50ms)\n"
    elif (( $(echo "$jitter <= 100" | bc -l) )); then
        assessment="${assessment}  Status: FAIR - May require jitter buffer adjustment\n"
        assessment="${assessment}  Jitter: ${jitter}ms (warning > 50ms)\n"
    else
        assessment="${assessment}  Status: POOR - Voice quality will suffer\n"
        assessment="${assessment}  Jitter: ${jitter}ms (critical > 100ms)\n"
    fi
    
    # Loss Assessment
    assessment="${assessment}\n[Packet Loss]\n"
    if (( $(echo "$loss == 0" | bc -l) )); then
        assessment="${assessment}  Status: EXCELLENT - No packet loss detected\n"
        assessment="${assessment}  Loss: ${loss}%\n"
    elif (( $(echo "$loss <= 0.5" | bc -l) )); then
        assessment="${assessment}  Status: GOOD - Minimal impact on voice\n"
        assessment="${assessment}  Loss: ${loss}% (acceptable < 0.5%)\n"
    elif (( $(echo "$loss <= 1" | bc -l) )); then
        assessment="${assessment}  Status: FAIR - Some voice quality degradation expected\n"
        assessment="${assessment}  Loss: ${loss}% (warning > 0.5%)\n"
    else
        assessment="${assessment}  Status: POOR - Significant voice quality issues\n"
        assessment="${assessment}  Loss: ${loss}% (critical > 1%)\n"
    fi
    
    echo -e "$assessment"
}

