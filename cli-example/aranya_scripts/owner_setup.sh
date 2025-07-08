#!/bin/bash
cd "$(dirname "$0")/../.."

export ARANYA_UDS_PATH=/tmp/aranya/run/uds.sock
export ARANYA_AQC_ADDR=127.0.0.1:7812

mkdir -p /tmp/aranya/{run,state,cache,logs,config}

# Build daemon if needed
if [ ! -f "./target/release/aranya-daemon" ]; then
    cargo build --bin aranya-daemon --release || exit 1
fi

# Start daemon
./target/release/aranya-daemon --config scratch/daemon_config.json > /tmp/aranya/daemon.log 2>&1 &
DAEMON_PID=$!
sleep 2

# Wait for UDS
while [ ! -S "$ARANYA_UDS_PATH" ]; do sleep 1; done

HEX_STRING=$(openssl rand -hex 32)
TEAM_OUTPUT=$(aranya -v create-team --seed-ikm $HEX_STRING)
TEAM_ID=$(echo "$TEAM_OUTPUT" | grep "Team ID:" | cut -d' ' -f3)
echo "Created team with ID: $TEAM_ID"

# Get owner device ID
OWNER_DEVICE_ID=$(aranya list-devices $TEAM_ID | grep Owner | awk '{print $1}')
echo "Owner device ID: $OWNER_DEVICE_ID"

chmod +x scratch/aranya_scripts/generate_keys.sh

# Generate and add other devices
for ROLE in admin operator membera memberb; do
    KEYS=$(./scratch/aranya_scripts/generate_keys.sh "test_device_$ROLE")
    IDENTITY=$(echo "$KEYS" | grep "Identity PK:" | cut -d' ' -f3)
    SIGNING=$(echo "$KEYS" | grep "Signing PK:" | cut -d' ' -f3)
    ENCODING=$(echo "$KEYS" | grep "Encoding PK:" | cut -d' ' -f3)
    echo "Adding device $ROLE: $IDENTITY $SIGNING $ENCODING"
    aranya -v add-device "$TEAM_ID" "$IDENTITY" "$SIGNING" "$ENCODING"
    echo "$ROLE,$IDENTITY,$SIGNING,$ENCODING" >> scratch/aranya_scripts/devices.csv
done

aranya -v assign-role "$TEAM_ID" "$OWNER_DEVICE_ID" "Owner"
aranya -v list-devices $TEAM_ID

echo "TEAM_ID=$TEAM_ID" > scratch/aranya_scripts/team_env.sh
echo "OWNER_DEVICE_ID=$OWNER_DEVICE_ID" >> scratch/aranya_scripts/team_env.sh

# Output device keys for use in the next script
echo "Device keys saved to scratch/aranya_scripts/devices.csv:"
cat scratch/aranya_scripts/devices.csv

# Stop daemon
kill $DAEMON_PID 