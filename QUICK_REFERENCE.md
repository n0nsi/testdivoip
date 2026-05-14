# TESTDIVOIP - Quick Reference Guide

## One-Minute Quickstart

```bash
# 1. Install
sudo bash install.sh

# 2. Run
testdivoip

# 3. Follow the prompts
# - Enter client name
# - Enter cloud provider
# - Enter PABX IP
# - Add office locations
# - Add SIP trunks
# - Watch analysis run
# - Check report

# 4. View report
testdivoip --list-reports
testdivoip --show-report reports/CLIENT_*.txt
```

## Common Tasks

### Run Complete Analysis
```bash
./testdivoip.sh
```

### Verbose Output
```bash
./testdivoip.sh --verbose
```

### Debug Mode
```bash
./testdivoip.sh --debug
```

### Use Configuration File
```bash
./testdivoip.sh --config config/production.conf
```

### List All Reports
```bash
./testdivoip.sh --list-reports
```

### View Report
```bash
./testdivoip.sh --show-report reports/ACME_20240315_143022.txt
```

## VoIP Quality Scores Explained

### EXCELENTE (Score ≥ 85)
✅ **Excellent for VoIP**
- Latency: <50ms
- Jitter: <20ms
- Loss: 0%
- Action: Deploy to production

### BOM (Score ≥ 70)
✅ **Good for VoIP**
- Latency: <100ms
- Jitter: <50ms
- Loss: <0.5%
- Action: Monitor performance

### ATENÇÃO (Score ≥ 50)
⚠️ **Needs Attention**
- Latency: <150ms
- Jitter: <100ms
- Loss: <1%
- Action: Fix issues before deployment

### CRÍTICO (Score < 50)
❌ **Not Suitable for VoIP**
- One or more critical metrics exceeded
- Action: Do not deploy - resolve issues

## Network Metrics Guide

| Metric | Ideal | Acceptable | Critical |
|--------|-------|-----------|----------|
| **Latency** | <50ms | <100ms | >150ms |
| **Jitter** | <20ms | <50ms | >100ms |
| **Packet Loss** | 0% | <0.5% | >1% |
| **Hops** | <10 | <15 | >20 |

## Testing What Gets Measured

### Ping Test
- Average round-trip time (RTT)
- Packet loss percentage
- Min/max latency
- Standard deviation (jitter proxy)

### MTR Test
- Loss percentage per hop
- Average, best, worst latency
- Standard deviation (actual jitter)
- Path stability

### Traceroute Test
- Number of hops
- Route intermediaries
- First unresponsive hop (target reached)

### ASN Analysis
- Autonomous System of each hop
- Carrier name identification
- Known problematic carriers
- International route detection

## Configuration File Quick Template

```bash
#!/bin/bash
# Save as: config/mycompany.conf

export CLIENT_NAME="My Company"
export SCENARIO_NAME="Production VoIP"
export CLOUD_PROVIDER="AWS eu-central-1"
export PABX_IP="203.0.113.100"

declare -a OFFICE_NAMES=("HQ" "Branch-1")
declare -a OFFICE_IPS=("203.0.113.10" "203.0.113.20")

declare -a TRUNK_NAMES=("Carrier-1" "Carrier-2")
declare -a TRUNK_IPS=("198.51.100.10" "198.51.100.20")
```

Then run:
```bash
./testdivoip.sh --config config/mycompany.conf
```

## Troubleshooting Quick Fixes

### "Command not found" for mtr, dig, etc.
```bash
# Install dependencies
sudo bash install.sh
```

### "Permission denied"
```bash
# Make scripts executable
chmod +x *.sh functions/*.sh
```

### "Target unreachable"
```bash
# Test connectivity
ping -c 3 <your_target_ip>
traceroute <your_target_ip>
```

### "No space left on device"
```bash
# Clean old reports (>7 days)
find reports/ -mtime +7 -delete
find logs/ -mtime +7 -delete
find temp/ -mtime +7 -delete
```

## Understanding the Report

### Executive Summary
- Overall quality score
- Production readiness recommendation
- Key findings highlight

### Metrics Per Target
- **RTT Average**: One-way + return trip time
- **Jitter**: Latency variation (bad for voice)
- **Loss**: % of packets not arriving
- **Hops**: Route length/complexity

### ASN Analysis
- **Primary ASN**: Main carrier/AS number
- **Suspicious**: Known for poor performance
- **International**: Route crosses borders

### Quality Score Breakdown
- How each metric contributed to score
- What needs improvement
- Comparison to thresholds

## Advanced Tips

### Test Single Target Only
Create minimal config:
```bash
#!/bin/bash
export CLIENT_NAME="Test"
export SCENARIO_NAME="Single Target"
export CLOUD_PROVIDER="AWS"
export PABX_IP="203.0.113.100"

declare -a OFFICE_NAMES=("Test")
declare -a OFFICE_IPS=("203.0.113.1")

declare -a TRUNK_NAMES=()
declare -a TRUNK_IPS=()
```

### Batch Testing Multiple Scenarios
```bash
for config in config/*.conf; do
    ./testdivoip.sh --config "$config"
done
```

### Save Reports for Comparison
```bash
# Create comparison folder
mkdir reports/comparison_2024_q1

# Copy reports
cp reports/CLIENT_* reports/comparison_2024_q1/

# Compare
diff reports/comparison_2024_q1/report1.txt \
     reports/comparison_2024_q1/report2.txt
```

### Monitor Over Time
```bash
# Add to crontab for weekly tests
0 8 * * 1 ~/testdivoip/testdivoip.sh --config config/production.conf

# Analyze trends
tail -20 reports/*.txt | grep "Overall"
```

## Best Practices

### Testing Schedule
- **Pre-deployment**: Full analysis
- **Post-deployment**: Weekly for first month
- **Stable environment**: Monthly
- **After network changes**: Immediate

### Multi-Office Testing
1. Test each office separately first
2. Note any problematic locations
3. Cross-reference with ASN analysis
4. Check for patterns

### SIP Trunk Analysis
1. Primary trunk first
2. Backup/secondary trunk
3. Compare results
4. Ensure failover paths acceptable

### ASN Analysis Interpretation
- **Few hops + same ASN**: Direct peering = good
- **Many hops + multiple ASNs**: Complex routing = higher risk
- **Known suspicious ASN**: May require alternative provider
- **International route**: Expected latency increase

## Emergency Checks

### Quick connectivity test
```bash
# Can I reach the target?
ping -c 5 <target_ip>

# What's the path?
traceroute -m 10 <target_ip>

# What carrier is it?
whois -h whois.asn.cymru.com -- -v <target_ip>
```

### Fast VoIP quality estimate
```bash
# Single ping test (30 packets)
ping -c 30 <target_ip>

# Manual jitter calculation
# Good: std dev < 20ms
# Acceptable: std dev < 50ms
# Poor: std dev > 100ms
```

## File Locations

```
testdivoip/
├── testdivoip.sh         # Main script
├── install.sh            # Installation script
├── README.md             # Full documentation
├── QUICK_REFERENCE.md    # This file
├── functions/            # Function modules
│   ├── colors.sh
│   ├── logging.sh
│   ├── network.sh
│   ├── analysis.sh
│   ├── reporting.sh
│   └── utils.sh
├── config/               # Configuration files
│   └── example.conf
├── reports/              # Generated reports
├── logs/                 # Application logs
└── temp/                 # Temporary files
```

## Important Notes

⚠️ **Requires Network Access**
- Must reach target IP addresses
- ICMP ping not firewalled
- Access to public WHOIS servers

⚠️ **Not a Real-time Monitor**
- One-time snapshot analysis
- For ongoing monitoring, run periodically
- Use cron for automated testing

⚠️ **Interpreter Dependent**
- Requires bash 4.0+
- Not compatible with sh/dash
- Test on target OS first

⚠️ **Data Retention**
- Reports kept in reports/ directory
- Logs kept in logs/ directory
- Old files (>7 days) auto-cleaned
- Backup important reports

## Support Resources

1. **Help Command**
   ```bash
   ./testdivoip.sh --help
   ```

2. **Example Config**
   ```bash
   cat config/example.conf
   ```

3. **View Full Documentation**
   ```bash
   cat README.md
   ```

4. **Check Logs**
   ```bash
   tail -50 logs/*.log
   ```

5. **Debug Mode**
   ```bash
   DEBUG=1 ./testdivoip.sh
   ```

---

**Last Updated**: 2024-03-15  
**Version**: 1.0

