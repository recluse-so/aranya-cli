#!/bin/bash
cd "$(dirname "$0")/../.."

# Complete Aranya setup script
# This script creates a team, generates proper keys for devices, and sets up each device

export ARANYA_UDS_PATH=/tmp/aranya/run/uds.sock
export ARANYA_AQC_ADDR=127.0.0.1:7812

echo "=== Aranya Complete Setup ==="
echo ""

# Create required directories
mkdir -p /tmp/aranya/{run,state,cache,logs,config}

# Build the daemon if needed
echo "Building aranya-daemon..."
cargo build --bin aranya-daemon --release || exit 1

# Build the key generation binary
echo "Building key generation binary..."
cd scratch/aranya_scripts
cargo build --release || exit 1
cd ../..

# Start the daemon
echo "Starting daemon..."
./target/release/aranya-daemon --config scratch/daemon_config.json > /tmp/aranya/daemon.log 2>&1 &
DAEMON_PID=$!
sleep 3

# Wait for UDS socket
while [ ! -S "$ARANYA_UDS_PATH" ]; do
    echo "Waiting for daemon to start..."
    sleep 1
done

echo "Daemon started successfully!"

# Create team
echo "Creating team..."
HEX_STRING=$(openssl rand -hex 32)
TEAM_OUTPUT=$(aranya -v create-team --seed-ikm $HEX_STRING)
TEAM_ID=$(echo "$TEAM_OUTPUT" | grep "Team ID:" | cut -d' ' -f3)
echo "Created team with ID: $TEAM_ID"

# Get owner device ID
OWNER_DEVICE_ID=$(aranya list-devices $TEAM_ID | grep Owner | awk '{print $1}')
echo "Owner device ID: $OWNER_DEVICE_ID"

# Generate keys for additional devices
echo "Generating keys for additional devices..."
cd scratch/aranya_scripts

DEVICES=("admin" "operator" "membera" "memberb")
ROLES=("Admin" "Operator" "Member" "Member")

for i in "${!DEVICES[@]}"; do
    DEVICE="${DEVICES[$i]}"
    ROLE="${ROLES[$i]}"
    
    echo "Generating keys for $DEVICE..."
    KEYS_OUTPUT=$(./target/release/generate_aranya_keys "test_device_$DEVICE")
    
    # Extract keys from output
    IDENTITY_PK=$(echo "$KEYS_OUTPUT" | grep "Identity PK:" | cut -d' ' -f3)
    SIGNING_PK=$(echo "$KEYS_OUTPUT" | grep "Signing PK:" | cut -d' ' -f3)
    ENCODING_PK=$(echo "$KEYS_OUTPUT" | grep "Encoding PK:" | cut -d' ' -f3)
    DEVICE_ID=$(echo "$KEYS_OUTPUT" | grep "Device ID:" | cut -d' ' -f3)
    
    echo "Adding device $DEVICE to team..."
    aranya -v add-device "$TEAM_ID" "$IDENTITY_PK" "$SIGNING_PK" "$ENCODING_PK"
    
    # Save device info for later setup
    echo "$DEVICE,$IDENTITY_PK,$SIGNING_PK,$ENCODING_PK,$DEVICE_ID,$ROLE" >> ../devices_with_keys.csv
    
    echo "✅ Added $DEVICE device"
done

cd ../..

# Assign owner role
echo "Assigning Owner role..."
aranya -v assign-role "$TEAM_ID" "$OWNER_DEVICE_ID" "Owner"

# List all devices
echo "Current devices:"
aranya list-devices $TEAM_ID

# Save team info
echo "TEAM_ID=$TEAM_ID" > scratch/team_env.sh
echo "OWNER_DEVICE_ID=$OWNER_DEVICE_ID" >> scratch/team_env.sh

echo ""
echo "=== Setup Complete ==="
echo "Team ID: $TEAM_ID"
echo "Owner device ID: $OWNER_DEVICE_ID"
echo ""
echo "Device keys and keystores saved to scratch/devices_with_keys.csv"
echo ""
echo "To set up each device individually:"
echo "1. Copy the keystore from the temp directory to the daemon's keystore"
echo "2. Run the device setup script for each device"
echo ""
echo "Example:"
echo "cp -r /tmp/aranya_keys_test_device_admin /tmp/aranya/state/keystore/aranya"
echo "./scratch/aranya_scripts/device_setup.sh $TEAM_ID <IDENTITY_PK> <SIGNING_PK> <ENCODING_PK> Admin"

# Stop daemon
echo "Stopping daemon..."
kill $DAEMON_PID
echo "Setup complete!" 