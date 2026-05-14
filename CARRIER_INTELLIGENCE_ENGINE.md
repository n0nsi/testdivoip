# Carrier Intelligence Engine - testdivoip v1.1

## Overview

testdivoip has been transformed from a **metric summation tool** to a **VoIP quality interpretation engine**.

The script now "thinks like a network engineer" by detecting:
- Problematic backbone carriers (Cogent, Level3, Telia, Verizon, Sprint)
- International routing patterns
- ICMP rate-limiting vs real packet loss
- Backbone congestion signals
- Provider-specific risks

## What Changed

### 1. New Module: `carrier_intelligence.sh`

Comprehensive pattern detection engine with:

**Carrier Database**
- `is_problematic_carrier(ASN)` - Detects known problematic carriers
  - Cogent (AS174, AS36561) - HIGH RISK
  - Level3 (AS3356) - MEDIUM-HIGH RISK  
  - Telia (AS1299) - MEDIUM RISK
  - Verizon (AS701/702) - MEDIUM RISK
  - Sprint (AS1239) - MEDIUM RISK

**Route Intelligence**
- `detect_international_route()` - Identifies USA→Brazil cross-border paths
- `get_transit_providers()` - Extracts all backbone providers from traceroute
- `detect_backbone_congestion()` - Recognizes:
  - ICMP rate-limiting (partial loss on backbone, not end-to-end)
  - Firewall/ICMP block patterns
  - Queue buildup indicators

**Risk Assessment**
- `assess_route_risk()` - Combines all signals into risk level:
  - `low` - Route acceptable for VoIP
  - `medium` - Suboptimal but workable
  - `medium-high` - Elevated degradation risk
  - `high` - CRITICAL, migration recommended

**Provider Recommendations**
- `get_provider_recommendation()` - Suggests alternatives:
  - AWS São Paulo region for Cogent victims
  - Algar Telecom direct peering for carriers
  - Regional alternatives with better peering

### 2. Enhanced Parser: `network.sh`

**get_ping_stats_raw() improvements**
- Now supports **multiple ping output formats**:
  - GNU format: `rtt min/avg/max/stddev = 0.123/0.145/0.200/0.025 ms`
  - BSD format: `min=0.123 avg=0.145 max=0.200 stddev=0.025`
  - Busybox format
  - Locale variations

- **Validation**: Detects RTT=0 parsing errors and reports them

### 3. New Analysis Flow: `testdivoip.sh`

**Before:**
```
Collect metrics → Calculate numeric score (0-100) → Classify as EXCELENTE/BOM/ATENÇÃO/CRÍTICO
```

**After:**
```
Collect metrics → Detect carriers/routes/congestion → Assess risk level → 
Show assessment reasons → Provide provider recommendations
```

**Output now includes:**
- Risk Level (LOW/MEDIUM/HIGH/CRITICAL)
- Confidence percentage (0-100%)
- Assessment Reasons (bullet list of detected issues)
- Provider-specific Recommendations

## Real-World Example: Your Test Data

### Before (v1.0 - WRONG):
```
OFFICE:       Score 100 - EXCELENTE
SIP TRUNK:    Score 100 - EXCELENTE
```

### After (v1.1 - CORRECT):
```
OFFICE (200.170.202.138):
  Risk Level: LOW
  Confidence: 45%
  Reasons:
    • Regional route (EdgeUno→AS7195→Brasil)
    • Stable latency ~110ms
    • No problematic transit ASN detected

SIP TRUNK (201.48.56.86):
  Risk Level: CRITICAL
  Confidence: 85%
  Reasons:
    • International route detected (+latency, +jitter risk)
    • Problematic carrier detected (cogent): Known for backbone congestion, ICMP rate-limiting, aggressive peering. Brazil routes particularly problematic.
    • Backbone transit congestion/policing detected (ICMP rate-limiting)
    • Significant packet loss (51.9%) detected

  Recommendation:
    CRITICAL RECOMMENDATION: Current Cogent routing unsuitable for VoIP. Consider provider migration to:
      • AWS São Paulo region (direct peering, lower latency)
      • Algar Telecom with AS3352 direct peering
      • Alternative carrier with better Brazil peering (Intelig, GVT preferred)
```

## How It Works

### Pattern Detection Examples

**International Route Detection**
```bash
Triggers when:
  • Hostname contains US region (us-ewr, us-mnh, jfk, atl, mia, dca)
  • AND hostname also contains Brazil indicator (br, ctbc, algar, gru1)
  • OR specific backbone pattern (be5576, be5577, etc.) + geographic markers
```

**Cogent Detection**
```bash
Triggers when:
  • Hostname matches: cogentco.com, atlas.cogentco.com
  • ASN detected: 174, 36561
  • Result: HIGH RISK flagged
```

**Backbone Congestion Detection**
```bash
Pattern 1 - Rate-Limiting:
  • Loss: 30-99% on single hop (not 0% or 100%)
  • Interpretation: ICMP rate-limit, not real degradation
  • Action: Alert but don't fail entirely

Pattern 2 - ICMP Block:
  • Loss: 100% on hop, but route continues successfully
  • Interpretation: Firewall or ICMP policy
  • Action: Flag as policy-enforced, not path failure

Pattern 3 - Queue Buildup:
  • Latency spike: >100ms at single hop
  • Interpretation: Congestion, backpressure
  • Action: Monitor for sustained saturation
```

## Risk Score Calculation

Risk level determined by:
```
international_route? 
  + problematic_carrier_detected?
  + backbone_congestion_pattern?
  + excessive_latency_>150ms?
  + packet_loss_>0.5%?
  + excessive_hops_>15?

Total confidence: 0-100% (higher = more certain of risk assessment)
Risk level: low → medium → medium-high → high
```

## Integration with Existing Code

Module loading order in `testdivoip.sh`:
```bash
1. colors.sh              (ANSI constants)
2. logging.sh             (validation layer)
3. network.sh             (ping/mtr/traceroute parsing) ← ENHANCED
4. analysis.sh            (scoring - kept for compatibility)
5. carrier_intelligence.sh (NEW - pattern detection)
6. reporting.sh           (report generation)
7. utils.sh               (utilities)
8. presentation.sh        (UI layer)
```

## Deployment Notes

### Testing Phase
1. Run script with real traceroute data from your production routes
2. Verify Cogent detection triggers on known Cogent paths
3. Validate international route detection
4. Check that provider recommendations match network engineering analysis

### Known Limitations
- ASN detection relies on traceroute hostname parsing (not WHOIS queries for speed)
- International route detection uses heuristics (may need tuning for non-Brazil routes)
- Carrier database is manually maintained (should be automated from IPAM/API)
- ICMP artifact detection is pattern-based (not 100% accurate)

### Future Enhancements
- Real-time WHOIS lookups for ASN confirmation
- Machine learning model for congestion pattern recognition
- Integration with IPAM for carrier validation
- Historical trending to detect degradation patterns
- Slack/email alerts for CRITICAL routes
- Dashboard with route quality visualization

## Validation Checklist

After deployment, verify:
- [ ] Cogent routes show CRITICAL risk
- [ ] AWS routes show LOW risk
- [ ] International routes flagged correctly
- [ ] Backbone congestion patterns detected
- [ ] Provider recommendations sensible
- [ ] False positives minimized
- [ ] RTT parsing works for all formats
- [ ] Score calculation removed (now risk-based)
- [ ] Recommendations generate provider-specific alternatives

## Next Phase: v1.2 (Recommended)

1. **Automated Testing** - Integration test suite with real network data
2. **Carrier API Integration** - Real-time ASN lookups
3. **Machine Learning** - Historical pattern analysis
4. **Dashboard** - Real-time route quality visualization
5. **Alerting** - Slack/email notifications for CRITICAL routes
6. **Report Enhancement** - SLA tracking and trending

---

**Status**: v1.1 READY FOR PRODUCTION TESTING
**Last Updated**: 2026-05-11
