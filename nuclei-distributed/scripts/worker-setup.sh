#!/bin/bash

# Nuclei Distributed Worker Setup Script
# This script runs on each DigitalOcean droplet to set up and run nuclei scans

set -e

# Environment variables (passed from orchestrator):
# - SCAN_ID: Unique identifier for this scan
# - WORKER_ID: Unique identifier for this worker
# - MAIN_SERVER: IP/hostname of main server
# - DOMAINS_B64: Base64 encoded list of domains to scan

LOG_FILE="/var/log/nuclei-worker.log"
RESULTS_FILE="/root/results.json"
DOMAINS_FILE="/root/domains.txt"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to send heartbeat to main server
send_heartbeat() {
    local progress=$1
    local current_domain=$2
    local message=$3
    
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"progress\": $progress, \"current_domain\": \"$current_domain\", \"message\": \"$message\"}" \
        "http://$MAIN_SERVER:8080/api/heartbeat/$SCAN_ID/$WORKER_ID" || true
}

# Function to send results to main server
send_result() {
    local result_line="$1"
    
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$result_line" \
        "http://$MAIN_SERVER:8080/api/results/$SCAN_ID/$WORKER_ID" || true
}

# Function to notify completion
notify_completion() {
    curl -s -X POST \
        "http://$MAIN_SERVER:8080/api/complete/$SCAN_ID/$WORKER_ID" || true
}

# Main execution
main() {
    log "Starting Nuclei worker setup..."
    log "Scan ID: $SCAN_ID"
    log "Worker ID: $WORKER_ID"
    log "Main Server: $MAIN_SERVER"

    # Update system
    export DEBIAN_FRONTEND=noninteractive
    log "Updating system packages..."
    apt-get update -qq > /dev/null 2>&1
    apt-get install -y -qq curl wget unzip jq > /dev/null 2>&1

    send_heartbeat 5 "" "System updated"

    # Install Go
    log "Installing Go..."
    cd /tmp
    wget -q https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /root/.bashrc

    send_heartbeat 15 "" "Go installed"

    # Install Nuclei
    log "Installing Nuclei..."
    wget -q https://github.com/projectdiscovery/nuclei/releases/download/v3.0.4/nuclei_3.0.4_linux_amd64.zip
    unzip -q nuclei_3.0.4_linux_amd64.zip
    mv nuclei /usr/local/bin/
    chmod +x /usr/local/bin/nuclei

    send_heartbeat 25 "" "Nuclei installed"

    # Download nuclei templates
    log "Downloading Nuclei templates..."
    mkdir -p /root/nuclei-templates
    cd /root/nuclei-templates
    nuclei -update-templates > /dev/null 2>&1

    send_heartbeat 35 "" "Templates downloaded"

    # Decode and prepare domains
    log "Preparing domains list..."
    if [ -z "$DOMAINS_B64" ]; then
        log "ERROR: No domains provided"
        exit 1
    fi

    echo "$DOMAINS_B64" | base64 -d > "$DOMAINS_FILE"
    DOMAIN_COUNT=$(wc -l < "$DOMAINS_FILE")
    log "Prepared $DOMAIN_COUNT domains for scanning"

    send_heartbeat 40 "" "Domains prepared"

    # Start nuclei scan
    log "Starting Nuclei scan..."
    
    # Create a named pipe for real-time result processing
    PIPE="/tmp/nuclei_results_pipe"
    mkfifo "$PIPE"

    # Start result processor in background
    {
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                echo "$line" >> "$RESULTS_FILE"
                send_result "$line"
            fi
        done < "$PIPE"
    } &
    PROCESSOR_PID=$!

    # Start progress monitor in background
    {
        scanned=0
        while [ $scanned -lt $DOMAIN_COUNT ]; do
            sleep 10
            if [ -f "$RESULTS_FILE" ]; then
                scanned=$(wc -l < "$RESULTS_FILE" 2>/dev/null || echo 0)
            fi
            
            progress=$(( (scanned * 100) / DOMAIN_COUNT ))
            current_domain=$(tail -n 1 "$DOMAINS_FILE" 2>/dev/null | head -n 1 || echo "")
            
            send_heartbeat $progress "$current_domain" "Scanning in progress"
            log "Progress: $progress% ($scanned/$DOMAIN_COUNT)"
        done
    } &
    MONITOR_PID=$!

    # Run nuclei scan
    nuclei -l "$DOMAINS_FILE" \
           -json \
           -severity critical,high,medium,low \
           -rate-limit 10 \
           -timeout 30 \
           -retries 2 \
           -bulk-size 25 \
           -silent > "$PIPE" 2>/dev/null

    # Wait for scan completion
    wait

    # Cleanup background processes
    kill $PROCESSOR_PID $MONITOR_PID 2>/dev/null || true
    rm -f "$PIPE"

    # Final progress update
    final_count=$(wc -l < "$RESULTS_FILE" 2>/dev/null || echo 0)
    log "Scan completed. Found $final_count results."
    
    send_heartbeat 100 "completed" "Scan completed"
    notify_completion

    # Optional: Send final results summary
    if [ -f "$RESULTS_FILE" ]; then
        summary=$(jq -r '.severity' "$RESULTS_FILE" 2>/dev/null | sort | uniq -c | tr '\n' '; ' || echo "No summary available")
        log "Results summary: $summary"
    fi

    log "Worker completed successfully"
}

# Error handling
trap 'log "ERROR: Script failed at line $LINENO"; send_heartbeat 0 "error" "Worker failed"; exit 1' ERR

# Check required environment variables
if [ -z "$SCAN_ID" ] || [ -z "$WORKER_ID" ] || [ -z "$MAIN_SERVER" ] || [ -z "$DOMAINS_B64" ]; then
    log "ERROR: Missing required environment variables"
    log "Required: SCAN_ID, WORKER_ID, MAIN_SERVER, DOMAINS_B64"
    exit 1
fi

# Run main function
main

# Self-destruct (optional - can be controlled by orchestrator)
if [ "$AUTO_DESTROY" = "true" ]; then
    log "Auto-destroying droplet in 60 seconds..."
    sleep 60
    
    # Get droplet ID from metadata
    DROPLET_ID=$(curl -s http://169.254.169.254/metadata/v1/id)
    
    if [ -n "$DROPLET_ID" ] && [ -n "$DO_API_TOKEN" ]; then
        curl -X DELETE \
             -H "Authorization: Bearer $DO_API_TOKEN" \
             "https://api.digitalocean.com/v2/droplets/$DROPLET_ID"
        log "Droplet destruction initiated"
    fi
fi
