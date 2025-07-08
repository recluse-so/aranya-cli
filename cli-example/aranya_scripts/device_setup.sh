#!/bin/bash
cd "$(dirname "$0")/../.."

if [ $# -ne 5 ]; then
    echo "Usage: $0 <TEAM_ID> <IDENTITY_PK> <SIGNING_PK> <ENCODING_PK> <ROLE>"
    echo "Example: $0 21QoVyYbLdAx4wotn8EVn7fHGLhtPSCTTMoaXXY9t8rC 2f4cc2a1a5f6da9334150b5cc57a58ea8bf61d80180a6e8c5e56aec8a4cead62 125e3232d58f7fb0a6279c2d982d25f730ed0db483979006635a9bafebe0bdd1 213dcc0547c52cbd2e4d6baa2eef0a62124f3097aa11138b6135e0a8a6df9897 Admin"
    exit 1
fi

TEAM_ID="$1"
IDENTITY_PK="$2"
SIGNING_PK="$3"
ENCODING_PK="$4"
ROLE="$5"

export ARANYA_UDS_PATH=/tmp/aranya/run/uds.sock
export ARANYA_AQC_ADDR=127.0.0.1:7812

mkdir -p /tmp/aranya/{run,state,cache,logs,config}

# Build daemon if needed
if [ ! -f "./target/release/aranya-daemon" ]; then
    cargo build --bin aranya-daemon --release || exit 1
fi

echo "Setting up device with role: $ROLE"
echo "Team ID: $TEAM_ID"
echo "Identity PK: $IDENTITY_PK"

# Here you would need to import the device's private keys into the keystore.
# This is a placeholder; actual key import depends on your key management tooling.
echo "NOTE: You need to import the device's private keys into the keystore before running this script."
echo "This script assumes the daemon is running with the correct device identity."

# Start daemon as this device
./target/release/aranya-daemon --config scratch/daemon_config.json > /tmp/aranya/daemon.log 2>&1 &
DAEMON_PID=$!
sleep 2

# Wait for UDS
while [ ! -S "$ARANYA_UDS_PATH" ]; do sleep 1; done

# Get this device's ID (should be the one matching the public key)
DEVICE_ID=$(aranya list-devices $TEAM_ID | grep "$IDENTITY_PK" | awk '{print $1}')
if [ -z "$DEVICE_ID" ]; then
    echo "ERROR: Could not find device with identity PK: $IDENTITY_PK"
    echo "Available devices:"
    aranya list-devices $TEAM_ID
    kill $DAEMON_PID
    exit 1
fi

echo "This device ID: $DEVICE_ID"

# Assign role to self
echo "Assigning role '$ROLE' to device $DEVICE_ID"
aranya -v assign-role "$TEAM_ID" "$DEVICE_ID" "$ROLE"

if [ $? -eq 0 ]; then
    echo "Successfully assigned role '$ROLE' to device $DEVICE_ID"
    aranya -v device-info "$TEAM_ID" "$DEVICE_ID"
else
    echo "Failed to assign role. This device may not be authorized or the role may already be assigned."
fi

# Stop daemon
kill $DAEMON_PID 