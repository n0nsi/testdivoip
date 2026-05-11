# TESTDIVOIP - Project Structure & Deployment Guide

## Complete Project Structure

```
testdivoip/
│
├── 📄 testdivoip.sh              # Main application script (ENTRY POINT)
├── 📄 install.sh                 # Automated installation & dependency setup
├── 📄 README.md                  # Complete documentation
├── 📄 QUICK_REFERENCE.md         # Quick reference guide
├── 📄 .gitignore                 # Git ignore patterns
│
├── 📁 functions/                 # Reusable function modules
│   ├── colors.sh                 # Terminal colors and UI formatting
│   ├── logging.sh                # Logging and validation functions
│   ├── network.sh                # Network testing functions
│   ├── analysis.sh               # VoIP quality analysis logic
│   ├── reporting.sh              # Report generation functions
│   └── utils.sh                  # General utilities and helpers
│
├── 📁 config/                    # Configuration files
│   └── example.conf              # Example configuration template
│
├── 📁 reports/                   # Generated reports (auto-created)
│   └── [CLIENT]_[DATE]_[TIME].txt
│
├── 📁 logs/                      # Application logs (auto-created)
│   └── testdivoip_[DATE]_[TIME].log
│
└── 📁 temp/                      # Temporary files (auto-created)
    └── mtr_*, traceroute_* (working files)
```

## Installation Procedures

### Method 1: Automated Installation (RECOMMENDED)

```bash
# Navigate to project directory
cd ~/testdivoip

# Run installation script (installs all dependencies)
sudo bash install.sh

# Script will:
# ✓ Detect OS (Debian/Ubuntu)
# ✓ Check bash version
# ✓ Install all required packages
# ✓ Create directories
# ✓ Set permissions
# ✓ Create symlink in /usr/local/bin
```

### Method 2: Manual Installation

```bash
# Install dependencies
sudo apt-get update
sudo apt-get install -y \
    mtr-tiny \
    dnsutils \
    whois \
    curl \
    jq \
    bc \
    net-tools \
    iproute2

# Create installation directory
mkdir -p ~/testdivoip/{functions,config,reports,logs,temp}

# Copy files
cp testdivoip.sh ~/testdivoip/
cp install.sh ~/testdivoip/
cp functions/*.sh ~/testdivoip/functions/
cp config/*.conf ~/testdivoip/config/
cp README.md QUICK_REFERENCE.md ~/testdivoip/

# Make executable
chmod +x ~/testdivoip/*.sh
chmod +x ~/testdivoip/functions/*.sh

# Optional: Create symlink
sudo ln -sf ~/testdivoip/testdivoip.sh /usr/local/bin/testdivoip
```

### Method 3: Container Deployment (Docker)

```dockerfile
FROM debian:12

RUN apt-get update && apt-get install -y \
    bash \
    mtr-tiny \
    dnsutils \
    whois \
    curl \
    jq \
    bc \
    net-tools \
    iproute2

WORKDIR /opt/testdivoip
COPY . .

RUN chmod +x testdivoip.sh functions/*.sh

ENTRYPOINT ["./testdivoip.sh"]
```

Build: `docker build -t testdivoip:latest .`
Run: `docker run -it testdivoip:latest`

## Deployment Scenarios

### Scenario 1: Production Pre-deployment Validation

```bash
# 1. Create configuration for production environment
cp config/example.conf config/production.conf
# Edit production.conf with real IPs

# 2. Run comprehensive analysis
./testdivoip.sh --config config/production.conf

# 3. Review report in detail
./testdivoip.sh --show-report reports/YourClient_*.txt

# 4. Address any CRÍTICO or ATENÇÃO findings

# 5. Approve deployment when score ≥ 70 (BOM or EXCELENTE)
```

### Scenario 2: Ongoing Monitoring

```bash
# Set up weekly automated testing via crontab
crontab -e

# Add line (testing every Monday at 8 AM):
0 8 * * 1 /path/to/testdivoip.sh --config /path/to/config/production.conf

# Or monthly:
0 8 1 * * /path/to/testdivoip.sh --config /path/to/config/production.conf
```

### Scenario 3: Multi-datacenter Comparison

```bash
# Create configs for each datacenter
cp config/example.conf config/datacenter_aws.conf
cp config/example.conf config/datacenter_azure.conf
cp config/example.conf config/datacenter_do.conf

# Run tests for all
for dc in config/datacenter_*.conf; do
    ./testdivoip.sh --config "$dc"
done

# Compare results
diff reports/ACME_*_AWS*.txt reports/ACME_*_Azure*.txt
```

### Scenario 4: Post-incident Analysis

```bash
# When voice quality degrades, run analysis immediately
./testdivoip.sh --debug --verbose --config config/production.conf

# Compare with baseline report
./testdivoip.sh --show-report reports/ACME_*_baseline.txt
./testdivoip.sh --show-report reports/ACME_*_incident.txt

# Look for:
# - Increased latency/jitter
# - Packet loss increase
# - Route changes
# - New problematic ASNs
```

## Function Module Reference

### colors.sh - Terminal UI
```bash
print_header "Title"
print_success "Message"
print_error "Message"
print_warning "Message"
print_info "Message"
print_metric "Label" "Value" "Unit"
print_voip_score "EXCELENTE" "95"
print_loading "Analyzing..." $PID
```

### logging.sh - Logging & Validation
```bash
init_logging
log_info "Message"
log_error "Message"
log_debug "Message"
is_valid_ip "203.0.113.1"
is_number "42"
check_dependency "mtr"
check_all_dependencies
error_exit "Error message" 1
```

### network.sh - Network Tests
```bash
ping_test "203.0.113.1" 10
get_ping_stats "203.0.113.1"
mtr_test "203.0.113.1" 100
parse_mtr_output "$mtr_output"
traceroute_test "203.0.113.1"
count_hops "$traceroute_output"
get_asn_from_ip "203.0.113.1"
get_asn_name "AS16509"
detect_international_route "$traceroute_output"
```

### analysis.sh - VoIP Analysis
```bash
calculate_voip_score $lat $jit $loss $hops $asn_susp $intl
classify_voip_score 75
is_asn_suspicious "AS174"
analyze_route_quality "$target" "$tr_out" "$mtr_out"
analyze_asn_chain "$traceroute_output"
generate_quality_assessment ...
```

### reporting.sh - Reporting
```bash
init_report "ClientName"
add_report_section "Title"
add_report_metric "Label" "Value"
add_general_information ...
add_office_analysis ...
add_findings_section
add_recommendation "HIGH" "Text"
add_conclusion_section $score $category
print_report_path
```

### utils.sh - Utilities
```bash
read_input "Prompt" "Default" var_name
read_ip "Enter IP"
read_number "Enter count" "default"
read_menu "Choose" "opt1" "opt2"
format_number 3.14159 2
get_timestamp
cleanup_old_files /path 7
```

## Testing the Installation

```bash
# 1. Verify scripts are executable
ls -la testdivoip.sh functions/*.sh

# 2. Check dependencies
bash -c "source functions/logging.sh; check_all_dependencies"

# 3. Test basic functionality
./testdivoip.sh --help

# 4. Run a quick test
./testdivoip.sh --debug --verbose

# 5. Verify report generation
ls -la reports/
cat reports/test_*.txt
```

## Troubleshooting Deployment

### Issue: "Permission denied"
```bash
# Fix: Make scripts executable
chmod +x testdivoip.sh install.sh
chmod +x functions/*.sh
```

### Issue: "Command not found: mtr"
```bash
# Fix: Install dependencies
sudo bash install.sh
# OR
sudo apt-get install mtr-tiny dnsutils whois curl jq bc net-tools
```

### Issue: "No such file or directory"
```bash
# Fix: Ensure you're in correct directory
pwd  # Should show testdivoip directory
ls functions/  # Should list function files
```

### Issue: "Syntax error"
```bash
# Fix: Check bash version
bash --version  # Should be 4.0+

# Verify script syntax
bash -n testdivoip.sh
bash -n functions/*.sh
```

### Issue: "Network connectivity problems"
```bash
# Debug network issues
ping -c 3 8.8.8.8          # Test basic ping
traceroute 8.8.8.8         # Test routing
dig google.com             # Test DNS
whois -h whois.asn.cymru.com 8.8.8.8  # Test WHOIS
```

## Performance Tuning

### For Large Networks
```bash
# Reduce MTR packet count for faster results
export MTR_PACKETS=50  # Instead of 100

# Run parallel tests (if testing multiple independent targets)
./testdivoip.sh --config config/dc1.conf &
./testdivoip.sh --config config/dc2.conf &
./testdivoip.sh --config config/dc3.conf &
wait
```

### For Limited Resources
```bash
# Reduce verbosity
./testdivoip.sh --config config/production.conf 2>/dev/null

# Skip DNS lookups
# (Edit network.sh to comment out reverse DNS lines)
```

### For Maximum Accuracy
```bash
# Increase MTR packets
export MTR_PACKETS=200  # More samples

# Run multiple times
for i in {1..3}; do
    ./testdivoip.sh --config config/production.conf
    sleep 300  # Wait 5 minutes between runs
done
```

## Integration Points

### CI/CD Pipeline
```bash
# Jenkinsfile example
stage('VoIP Infrastructure Test') {
    steps {
        sh '''
            cd testdivoip
            ./testdivoip.sh --config config/staging.conf
            if [ -f reports/*.txt ]; then
                archiveArtifacts artifacts: 'reports/**'
            fi
        '''
    }
}
```

### Monitoring Dashboard (Future)
```bash
# Planned: Export to monitoring systems
./testdivoip.sh --export-json metrics.json
curl -X POST http://prometheus:9090/api/v1/write \
    -d @metrics.json
```

### Alert Integration (Future)
```bash
# Planned: Trigger alerts on quality degradation
./testdivoip.sh --config config/production.conf
score=$(grep "Overall VoIP Quality" reports/*.txt | awk '{print $NF}')
if [ $score -lt 50 ]; then
    # Send alert
    curl https://alerts.example.com/voip-quality \
        -d "score=$score"
fi
```

## Backup & Recovery

```bash
# Backup entire project
tar -czf testdivoip_backup_$(date +%Y%m%d).tar.gz testdivoip/

# Backup reports only
tar -czf testdivoip_reports_$(date +%Y%m%d).tar.gz testdivoip/reports/

# Restore from backup
tar -xzf testdivoip_backup_20240315.tar.gz

# Keep backups
mkdir -p backups
mv testdivoip_backup_*.tar.gz backups/
```

## Compliance & Audit

```bash
# Generate audit trail
./testdivoip.sh --config config/production.conf
grep "$(date +%Y-%m-%d)" logs/*.log > audit_$(date +%Y%m%d).log

# Archive reports for compliance
cp reports/*.txt compliance/2024_q1/

# Verify data integrity
sha256sum reports/*.txt > SHA256SUMS
sha256sum -c SHA256SUMS
```

## Support & Maintenance

- **Regular Updates**: Check for new versions monthly
- **Dependency Updates**: Keep MTR, whois, curl updated
- **Log Cleanup**: Auto-cleanup logs >7 days old
- **Report Archival**: Archive reports >1 year to backup storage
- **Version Tracking**: Keep upgrade history

## Version & Change Management

```bash
# Current version
head -3 testdivoip.sh | grep -i version

# Check for updates
git pull origin main  # If using git

# View change log (if available)
cat CHANGELOG.md
```

---

**Last Updated**: 2024-03-15  
**Version**: 1.0  
**Deployment Status**: Ready for Production

