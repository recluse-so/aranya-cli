#!/bin/bash

# Aranya CLI and Daemon Troubleshooting Script
# This script helps diagnose and fix common Aranya issues

set -e

echo "=== Aranya Troubleshooting Script ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status="$1"
    local message="$2"
    case $status in
        "OK")
            echo -e "${GREEN}✅ $message${NC}"
            ;;
        "WARN")
            echo -e "${YELLOW}⚠️  $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}❌ $message${NC}"
            ;;
        "INFO")
            echo -e "${BLUE}ℹ️  $message${NC}"
            ;;
    esac
}

# Function to check if daemon is running
check_daemon_process() {
    echo "=== Checking Daemon Process ==="
    
    if pgrep -f "aranya-daemon" > /dev/null; then
        local pid=$(pgrep -f "aranya-daemon")
        print_status "OK" "Daemon is running with PID: $pid"
        ps aux | grep aranya-daemon | grep -v grep
    else
        print_status "ERROR" "Daemon is not running"
        return 1
    fi
    echo ""
}

# Function to check UDS socket
check_uds_socket() {
    echo "=== Checking UDS Sockets (all daemons) ==="
    sleep 5
    local sockets=(/tmp/aranya*/run/uds.sock)
    local found=false

    for sock in "${sockets[@]}"; do
        if [ -S "$sock" ]; then
            print_status "OK" "Found UDS socket at: $sock"
            ls -la "$sock"
            found=true
            UDS_PATH="$sock"
        else
            print_status "WARN" "No UDS socket at: $sock"
        fi
    done

    if [ "$found" = false ]; then
        print_status "ERROR" "No UDS sockets found in /tmp/aranya*/run/"
        return 1
    fi
    echo ""
}

# Function to check daemon logs
check_daemon_logs() {
    echo "=== Checking Daemon Logs ==="
    
    local log_paths=("/tmp/aranya/daemon.log" "/var/log/aranya/daemon.log")
    
    for log_path in "${log_paths[@]}"; do
        if [ -f "$log_path" ]; then
            print_status "OK" "Found daemon log at: $log_path"
            echo "Last 10 lines of daemon log:"
            tail -10 "$log_path"
        else
            print_status "WARN" "No daemon log found at: $log_path"
        fi
    done
    echo ""
}

# Function to test CLI connection
test_cli_connection() {
    echo "=== Testing CLI Connection ==="
    
    if [ -z "$UDS_PATH" ]; then
        print_status "ERROR" "No UDS path available for testing"
        return 1
    fi
    
    print_status "INFO" "Testing connection to daemon at: $UDS_PATH"
    
    if aranya --uds-path "$UDS_PATH" list-teams > /dev/null 2>&1; then
        print_status "OK" "CLI successfully connected to daemon"
        echo "Available teams:"
        aranya --uds-path "$UDS_PATH" list-teams
    else
        print_status "ERROR" "CLI failed to connect to daemon"
        echo "Error output:"
        aranya --uds-path "$UDS_PATH" list-teams 2>&1 || true
    fi
    echo ""
}

# Function to check keystore
check_keystore() {
    echo "=== Checking Keystore ==="
    
    local keystore_paths=("/tmp/aranya/state/keystore/aranya" "/var/lib/aranya/keystore/aranya")
    
    for keystore_path in "${keystore_paths[@]}"; do
        if [ -d "$keystore_path" ]; then
            print_status "OK" "Found keystore at: $keystore_path"
            echo "Keystore contents:"
            ls -la "$keystore_path" 2>/dev/null || echo "Cannot list keystore contents"
        else
            print_status "WARN" "No keystore found at: $keystore_path"
        fi
    done
    echo ""
}

# Function to check daemon config
check_daemon_config() {
    echo "=== Checking Daemon Configuration ==="
    
    local config_paths=("scratch/daemon_config.json" "/etc/aranya/config.json")
    
    for config_path in "${config_paths[@]}"; do
        if [ -f "$config_path" ]; then
            print_status "OK" "Found daemon config at: $config_path"
            echo "Config contents:"
            cat "$config_path" | jq . 2>/dev/null || cat "$config_path"
        else
            print_status "WARN" "No daemon config found at: $config_path"
        fi
    done
    echo ""
}

# Function to check system resources
check_system_resources() {
    echo "=== Checking System Resources ==="
    
    # Check disk space
    local disk_usage=$(df -h /tmp | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$disk_usage" -lt 90 ]; then
        print_status "OK" "Disk space available: $(df -h /tmp | tail -1 | awk '{print $4}') free"
    else
        print_status "WARN" "Low disk space: $(df -h /tmp | tail -1 | awk '{print $5}') used"
    fi
    
    # Check memory
    local mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    if [ "$mem_usage" -lt 90 ]; then
        print_status "OK" "Memory usage: ${mem_usage}%"
    else
        print_status "WARN" "High memory usage: ${mem_usage}%"
    fi
    
    # Check file descriptors
    local fd_limit=$(ulimit -n)
    print_status "INFO" "File descriptor limit: $fd_limit"
    echo ""
}

# Function to provide fix suggestions
provide_fixes() {
    echo "=== Suggested Fixes ==="
    
    if ! pgrep -f "aranya-daemon" > /dev/null; then
        print_status "INFO" "To start daemon:"
        echo "1. Create config: cat > scratch/daemon_config.json << 'EOF'"
        echo "   {"
        echo "     \"name\": \"test_daemon\","
        echo "     \"runtime_dir\": \"/tmp/aranya/run\","
        echo "     \"state_dir\": \"/tmp/aranya/state\","
        echo "     \"cache_dir\": \"/tmp/aranya/cache\","
        echo "     \"logs_dir\": \"/tmp/aranya/logs\","
        echo "     \"config_dir\": \"/tmp/aranya/config\","
        echo "     \"sync_addr\": \"127.0.0.1:0\","
        echo "     \"quic_sync\": {}"
        echo "   }"
        echo "   EOF"
        echo ""
        echo "2. Create directories: mkdir -p /tmp/aranya/{run,state,cache,logs,config}"
        echo ""
        echo "3. Start daemon: ./target/release/aranya-daemon --config scratch/daemon_config.json &"
        echo ""
    fi
    
    if [ -z "$UDS_PATH" ]; then
        print_status "INFO" "To set UDS path:"
        echo "export ARANYA_UDS_PATH=/tmp/aranya/run/uds.sock"
        echo ""
    fi
    
    print_status "INFO" "Common CLI commands:"
    echo "aranya list-teams"
    echo "aranya create-team --seed-ikm \$(openssl rand -hex 32)"
    echo "aranya list-devices <TEAM_ID>"
    echo "aranya add-device <TEAM_ID> <IDENTITY_PK> <SIGNING_PK> <ENCODING_PK>"
    echo ""
}

# Function to clean up
cleanup() {
    echo "=== Cleanup Options ==="
    print_status "INFO" "To stop daemon: pkill -f aranya-daemon"
    print_status "INFO" "To remove UDS socket: rm -f /tmp/aranya/run/uds.sock /var/run/aranya/uds.sock"
    print_status "INFO" "To clean all temp files: rm -rf /tmp/aranya"
    echo ""
}

# Main troubleshooting flow
main() {
    echo "Starting Aranya troubleshooting..."
    echo ""
    
    # Run all checks
    check_daemon_process
    check_uds_socket
    check_daemon_logs
    test_cli_connection
    check_keystore
    check_daemon_config
    check_system_resources
    
    # Provide fixes
    provide_fixes
    cleanup
    
    echo "=== Troubleshooting Complete ==="
    echo ""
    print_status "INFO" "If issues persist, check the daemon logs for detailed error messages."
}

# Run main function
main "$@"
