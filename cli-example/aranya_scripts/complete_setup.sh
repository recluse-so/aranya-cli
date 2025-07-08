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
echo "=== NEXT STEPS: Individual Device Setup ==="
echo ""
echo "Each device needs to be set up individually with its private keys."
echo "Follow these steps for each device:"
echo ""
echo "1. COPY KEYSTORE: Copy the device's keystore to the daemon's keystore path"
echo "   Example for admin device:"
echo "   cp -r /tmp/aranya_keys_test_device_admin /tmp/aranya/state/keystore/aranya"
echo ""
echo "2. GET PUBLIC KEYS: Extract the public keys from the CSV file or script output"
echo "   The keys are saved in: ../devices_with_keys.csv"
echo "   Format: device_name,identity_pk,signing_pk,encoding_pk,device_id,role"
echo ""
echo "3. RUN DEVICE SETUP: Use the device_setup.sh script with the correct keys"
echo "   Example for admin device:"
echo "   ./device_setup.sh $TEAM_ID <IDENTITY_PK> <SIGNING_PK> <ENCODING_PK> Admin"
echo ""
echo "4. REPEAT FOR EACH DEVICE:"
echo "   - admin: ./device_setup.sh $TEAM_ID <ADMIN_IDENTITY_PK> <ADMIN_SIGNING_PK> <ADMIN_ENCODING_PK> Admin"
echo "   - operator: ./device_setup.sh $TEAM_ID <OPERATOR_IDENTITY_PK> <OPERATOR_SIGNING_PK> <OPERATOR_ENCODING_PK> Operator"
echo "   - membera: ./device_setup.sh $TEAM_ID <MEMBERA_IDENTITY_PK> <MEMBERA_SIGNING_PK> <MEMBERA_ENCODING_PK> Member"
echo "   - memberb: ./device_setup.sh $TEAM_ID <MEMBERB_IDENTITY_PK> <MEMBERB_SIGNING_PK> <MEMBERB_ENCODING_PK> Member"
echo ""
echo "=== VERIFICATION ==="
echo "After setting up all devices, verify the setup:"
echo "aranya list-devices $TEAM_ID"
echo "aranya device-info $TEAM_ID <DEVICE_ID>"
echo ""
echo "=== TROUBLESHOOTING ==="
echo "If you get 'not authorized' errors:"
echo "- Only the owner device can assign roles"
echo "- Make sure you're running the daemon with the correct device's keystore"
echo "- Check that the public keys match the device you're setting up"
echo ""
echo "Useful troubleshooting commands:"
echo "- Check daemon status: ps aux | grep aranya-daemon"
echo "- Check daemon logs: tail -f /tmp/aranya/daemon.log"
echo "- List all devices: aranya list-devices $TEAM_ID"
echo "- Check device info: aranya device-info $TEAM_ID <DEVICE_ID>"
echo "- Verify keystore exists: ls -la /tmp/aranya/state/keystore/aranya/"
echo "- Check UDS socket: ls -la /tmp/aranya/run/uds.sock"
echo "- Clean up and restart: ./cleanup.sh && ./complete_setup.sh"
echo ""
echo "For more detailed instructions, see: ./README.md"

# Stop daemon
echo "Stopping daemon..."
kill $DAEMON_PID
echo "Setup complete!" 