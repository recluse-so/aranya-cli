#!/bin/bash
cd "$(dirname "$0")/.."

# Aranya env variables
export ARANYA_UDS_PATH=/tmp/aranya/run/uds.sock
export ARANYA_AQC_ADDR=127.0.0.1:7812

# Start the Aranya daemon
echo "Starting Aranya daemon..."

# Create required directories
mkdir -p /tmp/aranya/{run,state,cache,logs,config}

# Build the daemon if not already built
echo "Checking if aranya-daemon exists..."
if [ ! -f "./target/release/aranya-daemon" ]; then
    echo "Building aranya-daemon..."
    cargo build --bin aranya-daemon --release
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to build aranya-daemon!"
        exit 1
    fi
    echo "Build completed successfully!"
else
    echo "aranya-daemon already built."
fi

# Start the daemon with config
echo "Starting daemon with config: scratch/daemon_config.json"

# Check if daemon binary exists
if [ ! -f "./target/release/aranya-daemon" ]; then
    echo "ERROR: aranya-daemon binary not found at ./target/release/aranya-daemon"
    echo "Please build it first with: cargo build --bin aranya-daemon --release"
    exit 1
fi

./target/release/aranya-daemon --config scratch/daemon_config.json > /tmp/aranya/daemon.log 2>&1 &
DAEMON_PID=$!
echo "Daemon started with PID: $DAEMON_PID"

# Wait for daemon to start and create the UDS socket
echo "Waiting for daemon to start..."
echo "Looking for UDS socket at: $ARANYA_UDS_PATH"
echo "Daemon PID: $DAEMON_PID"

# Check if daemon process is still running
if ! kill -0 $DAEMON_PID 2>/dev/null; then
    echo "ERROR: Daemon process died!"
    exit 1
fi

while [ ! -S "$ARANYA_UDS_PATH" ]; do
    echo "Waiting for UDS socket at $ARANYA_UDS_PATH..."
    echo "Checking if daemon is still running..."
    if ! kill -0 $DAEMON_PID 2>/dev/null; then
        echo "ERROR: Daemon process died while waiting!"
        exit 1
    fi
    sleep 1
done
echo "Daemon started successfully!"

# create 32 byte hex string
HEX_STRING=$(openssl rand -hex 32)

# create team as owner (let aranya manage keys)
TEAM_OUTPUT=$(aranya -v create-team --seed-ikm $HEX_STRING)
TEAM_ID=$(echo "$TEAM_OUTPUT" | grep "Team ID:" | cut -d' ' -f3)
echo "Created team with ID: $TEAM_ID"

aranya -v list-teams 

# Get the real owner device ID from list-devices
OWNER_DEVICE_ID=$(aranya list-devices $TEAM_ID | grep Owner | awk '{print $1}')
echo "Owner device ID: $OWNER_DEVICE_ID"

# Generate keys for each additional device (admin, operator, membera, memberb)
chmod +x scratch/generate_keys.sh

echo "Generating keys for test_device_admin..."
ADMIN_KEYS=$(./scratch/generate_keys.sh test_device_admin)
ADMIN_IDENTITY=$(echo "$ADMIN_KEYS" | grep "Identity PK:" | cut -d' ' -f3)
ADMIN_SIGNING=$(echo "$ADMIN_KEYS" | grep "Signing PK:" | cut -d' ' -f3)
ADMIN_ENCODING=$(echo "$ADMIN_KEYS" | grep "Encoding PK:" | cut -d' ' -f3)
ADMIN_DEVICE_ID=$(echo "$ADMIN_KEYS" | grep "Device ID:" | cut -d' ' -f3)

echo "Generating keys for test_device_operator..."
OPERATOR_KEYS=$(./scratch/generate_keys.sh test_device_operator)
OPERATOR_IDENTITY=$(echo "$OPERATOR_KEYS" | grep "Identity PK:" | cut -d' ' -f3)
OPERATOR_SIGNING=$(echo "$OPERATOR_KEYS" | grep "Signing PK:" | cut -d' ' -f3)
OPERATOR_ENCODING=$(echo "$OPERATOR_KEYS" | grep "Encoding PK:" | cut -d' ' -f3)
OPERATOR_DEVICE_ID=$(echo "$OPERATOR_KEYS" | grep "Device ID:" | cut -d' ' -f3)

echo "Generating keys for test_device_membera..."
MEMBERA_KEYS=$(./scratch/generate_keys.sh test_device_membera)
MEMBERA_IDENTITY=$(echo "$MEMBERA_KEYS" | grep "Identity PK:" | cut -d' ' -f3)
MEMBERA_SIGNING=$(echo "$MEMBERA_KEYS" | grep "Signing PK:" | cut -d' ' -f3)
MEMBERA_ENCODING=$(echo "$MEMBERA_KEYS" | grep "Encoding PK:" | cut -d' ' -f3)
MEMBERA_DEVICE_ID=$(echo "$MEMBERA_KEYS" | grep "Device ID:" | cut -d' ' -f3)

echo "Generating keys for test_device_memberb..."
MEMBERB_KEYS=$(./scratch/generate_keys.sh test_device_memberb)
MEMBERB_IDENTITY=$(echo "$MEMBERB_KEYS" | grep "Identity PK:" | cut -d' ' -f3)
MEMBERB_SIGNING=$(echo "$MEMBERB_KEYS" | grep "Signing PK:" | cut -d' ' -f3)
MEMBERB_ENCODING=$(echo "$MEMBERB_KEYS" | grep "Encoding PK:" | cut -d' ' -f3)
MEMBERB_DEVICE_ID=$(echo "$MEMBERB_KEYS" | grep "Device ID:" | cut -d' ' -f3)

# add additional devices
aranya -v add-device "$TEAM_ID" "$ADMIN_IDENTITY" "$ADMIN_SIGNING" "$ADMIN_ENCODING"
aranya -v add-device "$TEAM_ID" "$OPERATOR_IDENTITY" "$OPERATOR_SIGNING" "$OPERATOR_ENCODING"
aranya -v add-device "$TEAM_ID" "$MEMBERA_IDENTITY" "$MEMBERA_SIGNING" "$MEMBERA_ENCODING"
aranya -v add-device "$TEAM_ID" "$MEMBERB_IDENTITY" "$MEMBERB_SIGNING" "$MEMBERB_ENCODING"

# assign owner role (only owner can do this)
aranya -v assign-role "$TEAM_ID" "$OWNER_DEVICE_ID" "Owner"

# list devices
aranya -v list-devices $TEAM_ID

# device info for owner
aranya -v device-info $TEAM_ID "$OWNER_DEVICE_ID"

# Save device information for individual setup
echo "admin,$ADMIN_IDENTITY,$ADMIN_SIGNING,$ADMIN_ENCODING" > scratch/devices.csv
echo "operator,$OPERATOR_IDENTITY,$OPERATOR_SIGNING,$OPERATOR_ENCODING" >> scratch/devices.csv
echo "membera,$MEMBERA_IDENTITY,$MEMBERA_SIGNING,$MEMBERA_ENCODING" >> scratch/devices.csv
echo "memberb,$MEMBERB_IDENTITY,$MEMBERB_SIGNING,$MEMBERB_ENCODING" >> scratch/devices.csv

echo "Team setup complete!"
echo "Team ID: $TEAM_ID"
echo "Owner device ID: $OWNER_DEVICE_ID"
echo ""
echo "Device keys saved to scratch/devices.csv"
echo "To set up each device individually, run:"
echo "./scratch/aranya_scripts/device_setup.sh <TEAM_ID> <IDENTITY_PK> <SIGNING_PK> <ENCODING_PK> <ROLE>"
echo ""
echo "Example commands:"
echo "./scratch/aranya_scripts/device_setup.sh $TEAM_ID $ADMIN_IDENTITY $ADMIN_SIGNING $ADMIN_ENCODING Admin"
echo "./scratch/aranya_scripts/device_setup.sh $TEAM_ID $OPERATOR_IDENTITY $OPERATOR_SIGNING $OPERATOR_ENCODING Operator"
echo "./scratch/aranya_scripts/device_setup.sh $TEAM_ID $MEMBERA_IDENTITY $MEMBERA_SIGNING $MEMBERA_ENCODING Member"
echo "./scratch/aranya_scripts/device_setup.sh $TEAM_ID $MEMBERB_IDENTITY $MEMBERB_SIGNING $MEMBERB_ENCODING Member"

# add sync peer
aranya -v add-sync-peer $TEAM_ID 127.0.0.1:7812 --interval-secs 5

# list sync peers
aranya -v sync-now $TEAM_ID 127.0.0.1:7812

# Cleanup: Stop the daemon
echo "Stopping Aranya daemon..."
if [ ! -z "$DAEMON_PID" ]; then
    sudo kill $DAEMON_PID
    echo "Daemon stopped."
fi
