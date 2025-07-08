#!/bin/bash

# Aranya Cleanup Script
# This script removes all temporary files, keystores, and processes created by the Aranya setup

set -e

echo "=== Aranya Cleanup Script ==="
echo ""

# Function to check if a process is running
check_process() {
    local process_name="$1"
    if pgrep -f "$process_name" > /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to kill a process safely
kill_process() {
    local process_name="$1"
    local display_name="$2"
    
    if check_process "$process_name"; then
        echo "Stopping $display_name..."
        pkill -f "$process_name" || true
        sleep 2
        
        # Force kill if still running
        if check_process "$process_name"; then
            echo "Force killing $display_name..."
            pkill -9 -f "$process_name" || true
        fi
    else
        echo "$display_name is not running"
    fi
}

# Kill Aranya processes
echo "Stopping Aranya processes..."
kill_process "aranya-daemon" "Aranya Daemon"
kill_process "aranya" "Aranya CLI"

# Remove temporary directories
echo ""
echo "Removing temporary directories..."

# Aranya runtime directories
if [ -d "/tmp/aranya" ]; then
    echo "Removing /tmp/aranya..."
    rm -rf /tmp/aranya
fi

# Temporary keystore directories
echo "Removing temporary keystores..."
for keystore in /tmp/aranya_keys_*; do
    if [ -d "$keystore" ]; then
        echo "Removing $keystore..."
        rm -rf "$keystore"
    fi
done

# Remove generated files
echo ""
echo "Removing generated files..."

# CSV file with device info
if [ -f "../devices_with_keys.csv" ]; then
    echo "Removing ../devices_with_keys.csv..."
    rm -f ../devices_with_keys.csv
fi

# Team environment file
if [ -f "../team_env.sh" ]; then
    echo "Removing ../team_env.sh..."
    rm -f ../team_env.sh
fi

# Daemon config file
if [ -f "../daemon_config.json" ]; then
    echo "Removing ../daemon_config.json..."
    rm -f ../daemon_config.json
fi

# Key bundle files
if [ -f "key_bundle.cbor" ]; then
    echo "Removing key_bundle.cbor..."
    rm -f key_bundle.cbor
fi

# Build artifacts (optional)
if [ "$1" = "--clean-build" ]; then
    echo ""
    echo "Removing build artifacts..."
    if [ -d "target" ]; then
        echo "Removing target/ directory..."
        rm -rf target
    fi
    if [ -f "Cargo.lock" ]; then
        echo "Removing Cargo.lock..."
        rm -f Cargo.lock
    fi
fi

# Check for any remaining Aranya processes
echo ""
echo "Checking for remaining Aranya processes..."
if pgrep -f "aranya" > /dev/null; then
    echo "WARNING: Some Aranya processes are still running:"
    pgrep -f "aranya" | xargs ps -p
    echo ""
    echo "You may need to manually stop these processes."
else
    echo "No Aranya processes are running."
fi

# Check for remaining files
echo ""
echo "Checking for remaining Aranya files..."
if [ -d "/tmp/aranya" ] || [ -f "/tmp/aranya" ]; then
    echo "WARNING: /tmp/aranya still exists"
fi

if ls /tmp/aranya_keys_* 2>/dev/null; then
    echo "WARNING: Some keystore directories still exist"
fi

echo ""
echo "=== Cleanup Complete ==="
echo ""
echo "The following have been cleaned up:"
echo "✓ Aranya daemon and CLI processes"
echo "✓ Temporary directories (/tmp/aranya)"
echo "✓ Keystore directories (/tmp/aranya_keys_*)"
echo "✓ Generated files (CSV, env files, configs)"
echo "✓ Key bundle files"
if [ "$1" = "--clean-build" ]; then
    echo "✓ Build artifacts (target/, Cargo.lock)"
fi
echo ""
echo "To start fresh, run: ./complete_setup.sh" 