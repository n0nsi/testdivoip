# TESTDIVOIP - Professional VoIP Route Quality Analysis Tool

![VoIP Quality Analysis](https://img.shields.io/badge/VoIP-Quality%20Testing-brightgreen)
![Shell Script](https://img.shields.io/badge/Language-Shell%20Script-blue)
![License](https://img.shields.io/badge/License-MIT-orange)

## Overview

**TESTDIVOIP** is a professional-grade shell script automation tool designed for SRE engineers, VoIP specialists, and network administrators to validate cloud infrastructure quality for VoIP deployments.

### Purpose

The tool provides comprehensive analysis of network routes between:
- Cloud-hosted PABX systems
- Multiple office/remote locations
- Multiple SIP Trunk carriers

It identifies critical issues that could impact voice quality:
- **Latency & Jitter** - RTP sensitivity analysis
- **Packet Loss** - Voice quality degradation detection
- **Route Stability** - BGP flapping and path oscillation
- **ASN Analysis** - Carrier peering quality assessment
- **International Routing** - Transit path analysis

## Key Features

✅ **Comprehensive Network Testing**
- ICMP ping analysis with statistical collection
- MTR (My Traceroute) for path analysis with jitter/loss metrics
- Traceroute with hop counting and AS path tracing
- DNS resolution and reverse DNS lookup
- Network connectivity verification

✅ **Intelligent ASN Analysis**
- Automatic ASN identification for all hops
- Carrier name resolution
- Detection of suspicious/problematic ASNs
- International route identification
- Peering quality assessment

✅ **VoIP Quality Scoring**
- Multi-criteria scoring system
- Categories: EXCELENTE | BOM | ATENÇÃO | CRÍTICO
- Detailed quality breakdowns
- Production readiness assessment

✅ **Professional Reporting**
- Comprehensive text reports with analysis
- Executive summaries
- Detailed technical findings
- Actionable recommendations
- Timestamped history

✅ **Enterprise-Grade Implementation**
- Modular, reusable function library
- Error handling and retry logic
- Dependency checking and validation
- Debug and verbose modes
- Structured logging

## System Requirements

### Operating System
- **Debian 12** or later
- **Ubuntu 20.04** or later
- Other Linux distributions (may require adjustment)

### Software Dependencies

```bash
# Essential packages
mtr              # Network path analysis
dnsutils         # dig for DNS queries
whois            # ASN lookup
curl             # IP information retrieval
jq               # JSON parsing
bc               # Floating-point arithmetic
net-tools        # netstat and networking tools
iproute2         # Advanced routing utilities
bash >= 4.0      # Shell scripting engine
```

### Network Requirements
- Network connectivity to target IP addresses
- ICMP ping allowed (not firewalled)
- Access to public WHOIS servers
- Access to ipinfo.io API (for IP information)

## Installation

### Quick Install

```bash
# Clone or extract the repository
cd testdivoip

# Run installation script (installs dependencies)
sudo bash install.sh

# For non-root installation
bash install.sh
```

### Manual Installation

```bash
# Install dependencies
sudo apt-get update
sudo apt-get install -y mtr-tiny dnsutils whois curl jq bc net-tools iproute2

# Create directory structure
mkdir -p ~/testdivoip/{functions,config,reports,logs,temp}

# Copy files
cp testdivoip.sh ~/testdivoip/
cp functions/*.sh ~/testdivoip/functions/

# Make executable
chmod +x ~/testdivoip/testdivoip.sh
chmod +x ~/testdivoip/functions/*.sh

# Optional: create symlink
sudo ln -s ~/testdivoip/testdivoip.sh /usr/local/bin/testdivoip
```

## Quick Start

### Interactive Mode (Recommended for First Run)

```bash
# Start interactive analysis
./testdivoip.sh

# With verbose output
./testdivoip.sh --verbose

# With debug information
./testdivoip.sh --debug
```

The tool will guide you through:
1. Client information entry
2. Cloud provider selection
3. PABX IP configuration
4. Office location(s) collection
5. SIP Trunk carrier configuration
6. Comprehensive network analysis
7. Professional report generation

### Configuration File Mode

```bash
# Using pre-defined configuration
./testdivoip.sh --config config/mycompany.conf

# List available reports
./testdivoip.sh --list-reports

# View specific report
./testdivoip.sh --show-report reports/MyCompany_20240101_120000.txt
```

## Command Reference

### Basic Usage

```bash
./testdivoip.sh [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Display help message |
| `-v, --verbose` | Enable verbose output during tests |
| `-d, --debug` | Enable debug mode with detailed logging |
| `-c, --config FILE` | Load configuration from file |
| `-s, --scenario FILE` | Load pre-defined scenario |
| `--list-reports` | Show all generated reports |
| `--show-report FILE` | Display specific report |

### Examples

```bash
# Interactive mode
./testdivoip.sh

# Verbose testing
./testdivoip.sh --verbose

# Debug mode
./testdivoip.sh --debug

# Load configuration
./testdivoip.sh --config config/production.conf

# List all reports
./testdivoip.sh --list-reports
```

## Configuration Files

### Configuration File Format

The repository ships with a single tracked template: `config/example.conf`.

For real customer deployments, copy that template to a local file under `config/` and keep it out of git. The repository `.gitignore` is configured to ignore customer-specific `.conf` files while keeping the example template available.

Recommended workflow:

```bash
cp config/example.conf config/mycompany.conf
```

Then edit only the local copy and run:

```bash
./testdivoip.sh --config config/mycompany.conf
```

Do not commit customer-specific names, IPs, office locations, or trunk details into tracked files.

Create a `.conf` file in the `config/` directory only for local use:

```bash
#!/bin/bash
# Example: config/production.conf

# Client Information
export CLIENT_NAME="ACME Corporation"
export SCENARIO_NAME="Production Deployment"
export CLOUD_PROVIDER="AWS eu-central-1"
export PABX_IP="203.0.113.100"

# Office Locations
declare -a OFFICE_NAMES=("HQ" "Branch-1" "Branch-2")
declare -a OFFICE_IPS=("203.0.113.10" "203.0.113.20" "203.0.113.30")

# SIP Trunk Carriers
declare -a TRUNK_NAMES=("Carrier-Primary" "Carrier-Backup")
declare -a TRUNK_IPS=("198.51.100.10" "198.51.100.20")

# Testing Options
export MTR_PACKETS=100
export VERBOSE=1
export DEBUG=0
```

## Test Analysis Details

### Ping Test
- **Count**: 10 packets per target
- **Timeout**: 5 seconds per packet
- **Metrics**: RTT average, min, max, packet loss
- **Output**: Statistical analysis

### MTR Analysis
- **Packets**: 100 by default (configurable)
- **Mode**: Report mode (-rwz flags)
- **Metrics**: Loss %, latency average/best/worst, jitter (stddev)
- **Purpose**: Path stability and hop-by-hop analysis

### Traceroute
- **Max Hops**: 30 by default
- **Mode**: Numeric IP addresses only
- **Analysis**: 
  - Hop counting
  - ASN identification per hop
  - International route detection
  - Route stability detection

### ASN Analysis
- **Lookup Service**: WHOIS via cymru.com
- **Information**:
  - Autonomous System Number
  - Carrier/Provider name
  - Known issues/warnings
  - Peering quality assessment

### VoIP Quality Scoring

#### Criteria & Thresholds

| Metric | Excellent | Good | Warning | Critical |
|--------|-----------|------|---------|----------|
| **Latency (RTT)** | <50ms | <100ms | <150ms | >150ms |
| **Jitter** | <20ms | <50ms | <100ms | >100ms |
| **Packet Loss** | 0% | <0.5% | <1% | >1% |
| **Hops** | <10 | <15 | <20 | >20 |

#### Quality Categories

- **EXCELENTE**: Score ≥ 85 - Production ready
- **BOM**: Score ≥ 70 - Good, monitor regularly
- **ATENÇÃO**: Score ≥ 50 - Needs attention before deployment
- **CRÍTICO**: Score < 50 - Not recommended for VoIP

### VoIP Quality Factors

The tool analyzes factors that specifically impact VoIP:

1. **Latency (RTT)**
   - One-way latency should be < 100ms
   - Recommended < 50ms for best user experience
   - > 150ms causes noticeable delays

2. **Jitter (Latency Variation)**
   - Caused by route instability, congestion
   - Ideal: < 20ms
   - Unacceptable: > 100ms
   - Requires jitter buffer adjustment

3. **Packet Loss**
   - Even 1% loss severely impacts voice
   - RTP is extremely sensitive
   - Loss > 0.5% requires investigation

4. **Route Stability**
   - BGP flapping indicates peering issues
   - Multiple IP changes per hop = instability
   - International routes = higher latency/loss risk

5. **ASN Analysis**
   - Some carriers known for poor peering
   - Cogent, Level3, GTT: common transit issues
   - Multiple ASN changes = routing complexity

## Output Files

### Shareable TXT Summary

The main deliverable is a plain TXT file that can be sent to a client or attached to a ticket.

It includes:

1. **Execution Summary**
   - Client, scenario, cloud provider, PABX IP
   - Overall VoIP score and classification

2. **Office Analysis**
   - Per-office scores and route metrics

3. **SIP Trunk Analysis**
   - Per-trunk scores and route metrics

4. **Findings & Recommendations**
   - Human-readable summary for operational review

5. **Technical Details**
   - Link to the internal audit log

### Audit Log

The internal audit log is separate from the TXT summary and captures line-by-line evidence.

It includes:

1. **Execution Metadata**
   - Run timestamp and execution context
   - Local-only operational metadata

2. **Ping Evidence**
   - One log line per packet/sequence
   - Reply time, TTL, source IP, and timeout status

3. **Traceroute Evidence**
   - One log line per hop
   - Hop number, observed IPs, RTT samples, and raw hop line

4. **MTR Evidence**
   - Aggregate path-quality snapshot for the target

5. **Risk Summary**
   - Numeric VoIP score
   - Risk level and confidence
   - Final audit summary for contesting decisions later

### File Locations

Shareable TXT summaries are saved to: `reports/CLIENT_YYYYMMDD_HHMMSS.txt`

Audit logs are saved to: `logs/testdivoip_audit_YYYYMMDD_HHMMSS.log`

Both paths are intentionally local-only and excluded from version control.

## Troubleshooting

### Missing Dependencies

```bash
# Install missing packages
sudo apt-get install -y mtr-tiny dnsutils whois curl jq bc net-tools iproute2

# Or use the install script
sudo bash install.sh
```

### Target Unreachable

```bash
# Check if target is reachable
ping -c 5 <target_ip>

# Check firewall
traceroute -m 5 <target_ip>

# Check DNS resolution
nslookup <target_hostname>
```

### WHOIS Lookup Failures

```bash
# Test WHOIS directly
whois -h whois.asn.cymru.com -- -v 203.0.113.1

# If cymru fails, try alternative
whois 203.0.113.1
```

### High Packet Loss in MTR

- Network congestion
- Firewall rate limiting MTR probes
- Distant target or poor connectivity
- Try increasing MTR packet count

### Permission Denied Errors

```bash
# Make scripts executable
chmod +x testdivoip.sh
chmod +x functions/*.sh

# Verify permissions
ls -la testdivoip.sh
ls -la functions/
```

## Performance Considerations

### Test Duration

- **Ping Test**: ~10 seconds
- **MTR (100 packets)**: ~30-60 seconds
- **Traceroute**: ~10-20 seconds
- **ASN Lookups**: ~5-10 seconds (depends on WHOIS server)
- **Total per target**: ~60-120 seconds

### For Multiple Targets

- 3 offices: ~5-10 minutes
- 5 SIP trunks: ~10-15 minutes
- **Total analysis**: ~15-25 minutes

## Security Considerations

- **No passwords stored** - configuration files use environment variables
- **No sensitive data** - only uses public WHOIS/DNS services
- **Local logging** - all data stays in ignored local log files under logs/
- **Root not required** - runs as regular user
- **Firewall friendly** - uses standard ICMP and DNS protocols

## Advanced Usage

### Batch Testing (Future Feature)

```bash
# Planned: Load multiple scenarios from batch file
./testdivoip.sh --batch scenarios.csv
```

### JSON Export (Future Feature)

```bash
# Planned: Export results as JSON
./testdivoip.sh --config test.conf --export-json results.json
```

### IPv6 Support (Future Feature)

```bash
# Planned: IPv6 address analysis
./testdivoip.sh --ipv6
```

### Dashboard Integration (Future Feature)

```bash
# Planned: Real-time dashboard
./testdivoip.sh --dashboard
```

## Function Library

The tool is built with modular functions for reuse:

### Available Modules

1. **colors.sh** - Terminal colors and formatting
2. **logging.sh** - Logging and validation
3. **network.sh** - Network testing functions
4. **analysis.sh** - VoIP quality analysis
5. **reporting.sh** - Report generation
6. **utils.sh** - General utilities

### Using Functions in Scripts

```bash
#!/bin/bash
source functions/colors.sh
source functions/network.sh

print_header "My VoIP Analysis"
result=$(ping_test "203.0.113.1" 10)
echo "$result"
```

## Logging

### Log Files

Logs are created in: `logs/testdivoip_YYYYMMDD_HHMMSS.log`

Audit evidence is created in: `logs/testdivoip_audit_YYYYMMDD_HHMMSS.log`

Shareable TXT summaries are created in: `reports/CLIENT_YYYYMMDD_HHMMSS.txt`

Both paths are ignored by git and must never be committed.

### Log Levels

- **INFO**: General information
- **ERROR**: Errors and failures
- **DEBUG**: Detailed debugging information (when --debug enabled)

### Enable Debug Logging

```bash
DEBUG=1 ./testdivoip.sh
```

## Contributing

### Code Style

- Shellcheck compliance
- Clear variable naming
- Consistent indentation (4 spaces)
- Commented sections

### Testing

Before submitting:

```bash
# Verify syntax
bash -n testdivoip.sh

# Run shellcheck
shellcheck testdivoip.sh functions/*.sh

# Test on clean system
```

## License

MIT License - See LICENSE file for details

## Support & Issues

- Documentation: See README.md and function comments
- Bug reports: Check logs in logs/ directory
- Examples: See config/example.conf

## Version History

### v1.0 (2024)
- Initial release
- Core VoIP analysis functionality
- Professional reporting
- ASN identification
- Quality scoring system

## Roadmap

- [ ] JSON export format
- [ ] CSV export for spreadsheet analysis
- [ ] Batch mode for multiple scenarios
- [ ] IPv6 support
- [ ] Real-time dashboard
- [ ] Web UI for reporting
- [ ] Database backend for trend analysis
- [ ] Automated alert system

## FAQ

**Q: Why is my latency high?**
A: Check for international routes, packet loss, or congestion. See ASN analysis in report.

**Q: How often should I run tests?**
A: Monthly for stable environments, weekly before production deployment.

**Q: Can I test IPv6?**
A: Not in v1.0. IPv6 support planned for future release.

**Q: What if MTR shows 100% loss?**
A: Target may not respond to UDP. Try increasing MTR packet count or use ICMP mode.

**Q: How do I interpret the VoIP score?**
A: EXCELENTE = production ready, BOM = good, ATENÇÃO = needs improvement, CRÍTICO = not suitable.

## Author

VoIP Engineering Team - Professional SRE/VoIP Network Diagnostics

---

**Last Updated**: 2024-03-15  
**Version**: 1.0  
**Status**: Production Ready

