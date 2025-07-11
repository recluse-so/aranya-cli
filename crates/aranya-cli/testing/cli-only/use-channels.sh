#!/bin/bash

set -e

# Minimal AQC channel test: new channel per message, PSK rotation visible

echo "=========================================="
echo "=== ARANYA AQC CHANNELS KEY ROTATION TEST ==="
echo "=========================================="

# 1. Setup: create team, add devices, assign roles, assign network IDs, create labels
# (Reuse the setup logic from the current script, but trim debug/summary/polling)

OWNER_OUTPUT=$(aranya --uds-path /tmp/aranya1/run/uds.sock -v create-team)
MAIN_TEAM_ID=$(echo "$OWNER_OUTPUT" | grep "Team created:" | awk '{print $3}')
SEED_IKM=$(echo "$OWNER_OUTPUT" | grep "Seed IKM:" | awk '{print $3}')

if [ -z "$MAIN_TEAM_ID" ] || [ -z "$SEED_IKM" ]; then
    echo "ERROR: Failed to extract team ID or seed IKM from output: $OWNER_OUTPUT"
    exit 1
fi

echo "Main team ID: $MAIN_TEAM_ID"
echo "Seed IKM: $SEED_IKM"

aranya --uds-path /tmp/aranya2/run/uds.sock add-team $MAIN_TEAM_ID $SEED_IKM
aranya --uds-path /tmp/aranya3/run/uds.sock add-team $MAIN_TEAM_ID $SEED_IKM

aranya --uds-path /tmp/aranya1/run/uds.sock add-sync-peer $MAIN_TEAM_ID 127.0.0.1:5052 --interval-secs 1
aranya --uds-path /tmp/aranya1/run/uds.sock add-sync-peer $MAIN_TEAM_ID 127.0.0.1:5053 --interval-secs 1
aranya --uds-path /tmp/aranya2/run/uds.sock add-sync-peer $MAIN_TEAM_ID 127.0.0.1:5051 --interval-secs 1
aranya --uds-path /tmp/aranya2/run/uds.sock add-sync-peer $MAIN_TEAM_ID 127.0.0.1:5053 --interval-secs 1
aranya --uds-path /tmp/aranya3/run/uds.sock add-sync-peer $MAIN_TEAM_ID 127.0.0.1:5051 --interval-secs 1
aranya --uds-path /tmp/aranya3/run/uds.sock add-sync-peer $MAIN_TEAM_ID 127.0.0.1:5052 --interval-secs 1

sleep 5

OWNER_DEVICE_OUTPUT=$(aranya --uds-path /tmp/aranya1/run/uds.sock -v device-info $MAIN_TEAM_ID)
OWNER_DEVICE_ID=$(echo "$OWNER_DEVICE_OUTPUT" | grep "Device Info for" | awk '{print $4}')

DAEMON2_OUTPUT=$(aranya --uds-path /tmp/aranya2/run/uds.sock -v create-team)
DAEMON2_TEAM_ID=$(echo "$DAEMON2_OUTPUT" | grep "Team created:" | awk '{print $3}')
DAEMON3_OUTPUT=$(aranya --uds-path /tmp/aranya3/run/uds.sock -v create-team)
DAEMON3_TEAM_ID=$(echo "$DAEMON3_OUTPUT" | grep "Team created:" | awk '{print $3}')

ADMIN_OUTPUT=$(aranya --uds-path /tmp/aranya2/run/uds.sock -v device-info $DAEMON2_TEAM_ID)
ADMIN_IDENTITY_KEY=$(echo "$ADMIN_OUTPUT" | grep "Identity Key:" | sed 's/.*Identity Key: //')
ADMIN_SIGNING_KEY=$(echo "$ADMIN_OUTPUT" | grep "Signing Key:" | sed 's/.*Signing Key: //')
ADMIN_ENCODING_KEY=$(echo "$ADMIN_OUTPUT" | grep "Encoding Key:" | sed 's/.*Encoding Key: //')

OPERATOR_OUTPUT=$(aranya --uds-path /tmp/aranya3/run/uds.sock -v device-info $DAEMON3_TEAM_ID)
OPERATOR_IDENTITY_KEY=$(echo "$OPERATOR_OUTPUT" | grep "Identity Key:" | sed 's/.*Identity Key: //')
OPERATOR_SIGNING_KEY=$(echo "$OPERATOR_OUTPUT" | grep "Signing Key:" | sed 's/.*Signing Key: //')
OPERATOR_ENCODING_KEY=$(echo "$OPERATOR_OUTPUT" | grep "Encoding Key:" | sed 's/.*Encoding Key: //')

aranya --uds-path /tmp/aranya1/run/uds.sock add-device $MAIN_TEAM_ID $ADMIN_IDENTITY_KEY $ADMIN_SIGNING_KEY $ADMIN_ENCODING_KEY
aranya --uds-path /tmp/aranya1/run/uds.sock add-device $MAIN_TEAM_ID $OPERATOR_IDENTITY_KEY $OPERATOR_SIGNING_KEY $OPERATOR_ENCODING_KEY

sleep 3

TEAM_DEVICES_OUTPUT=$(aranya --uds-path /tmp/aranya1/run/uds.sock list-devices $MAIN_TEAM_ID)
DEVICE_LINES=$(echo "$TEAM_DEVICES_OUTPUT" | grep -E "^  [A-Za-z0-9]+ \(Role:" | head -3)
DEVICE_IDS=($(echo "$DEVICE_LINES" | awk '{print $1}'))
OWNER_DEVICE_ID=${DEVICE_IDS[0]}
ADMIN_DEVICE_ID=${DEVICE_IDS[1]}
OPERATOR_DEVICE_ID=${DEVICE_IDS[2]}

SENSOR_LABEL_OUTPUT=$(aranya --uds-path /tmp/aranya1/run/uds.sock -v create-label $MAIN_TEAM_ID "sensor-data")
SENSOR_LABEL_ID=$(echo "$SENSOR_LABEL_OUTPUT" | grep "Label ID (base58):" | sed 's/.*Label ID (base58): //')
CONTROL_LABEL_OUTPUT=$(aranya --uds-path /tmp/aranya1/run/uds.sock -v create-label $MAIN_TEAM_ID "control-commands")
CONTROL_LABEL_ID=$(echo "$CONTROL_LABEL_OUTPUT" | grep "Label ID (base58):" | sed 's/.*Label ID (base58): //')

# Assign roles first (from Owner)
aranya --uds-path /tmp/aranya1/run/uds.sock assign-role $MAIN_TEAM_ID $ADMIN_DEVICE_ID Admin
aranya --uds-path /tmp/aranya1/run/uds.sock assign-role $MAIN_TEAM_ID $OPERATOR_DEVICE_ID Operator

sleep 3

# Assign labels from Owner (like old-use-channels.sh does)
aranya --uds-path /tmp/aranya1/run/uds.sock assign-label $MAIN_TEAM_ID $ADMIN_DEVICE_ID $SENSOR_LABEL_ID SendRecv
aranya --uds-path /tmp/aranya1/run/uds.sock assign-label $MAIN_TEAM_ID $OPERATOR_DEVICE_ID $SENSOR_LABEL_ID SendRecv
aranya --uds-path /tmp/aranya1/run/uds.sock assign-label $MAIN_TEAM_ID $ADMIN_DEVICE_ID $CONTROL_LABEL_ID SendOnly
aranya --uds-path /tmp/aranya1/run/uds.sock assign-label $MAIN_TEAM_ID $OPERATOR_DEVICE_ID $CONTROL_LABEL_ID RecvOnly

sleep 5

# Ensure main team is active on all daemons before assigning network IDs
echo "Ensuring main team is active on all daemons..."
aranya --uds-path /tmp/aranya2/run/uds.sock add-team $MAIN_TEAM_ID $SEED_IKM || true
aranya --uds-path /tmp/aranya3/run/uds.sock add-team $MAIN_TEAM_ID $SEED_IKM || true

sleep 5

echo "Verifying main team is active on daemon 3..."
DAEMON3_TEAM_CHECK=$(aranya --uds-path /tmp/aranya3/run/uds.sock device-info $MAIN_TEAM_ID 2>&1 || echo "TEAM_NOT_FOUND")
if echo "$DAEMON3_TEAM_CHECK" | grep -q "TEAM_NOT_FOUND\|no such storage"; then
    echo "WARNING: Daemon 3 does not have main team as active storage. Skipping AQC network ID assignment."
    SKIP_AQC_NETWORK_ASSIGNMENT=true
else
    echo "Main team is active on daemon 3"
    SKIP_AQC_NETWORK_ASSIGNMENT=false
fi

if [ "$SKIP_AQC_NETWORK_ASSIGNMENT" != "true" ]; then
    aranya --uds-path /tmp/aranya1/run/uds.sock assign-aqc-net-id $MAIN_TEAM_ID $ADMIN_DEVICE_ID "127.0.0.1:6002"
    aranya --uds-path /tmp/aranya1/run/uds.sock assign-aqc-net-id $MAIN_TEAM_ID $OPERATOR_DEVICE_ID "127.0.0.1:6003"
else
    echo "Skipping AQC network ID assignment due to storage issues"
fi

sleep 5

# === Minimal channel/key rotation test ===

for i in 1 2 3; do
    echo ""
    echo "🔄 TEST $i: Sensor Data Channel (new channel each time)"
    echo "==============================================="
    echo "Starting listener on admin device (timeout: 10 seconds)..."
    (aranya --uds-path /tmp/aranya2/run/uds.sock listen-data --timeout 10 $MAIN_TEAM_ID $ADMIN_DEVICE_ID $SENSOR_LABEL_ID) &
    LISTENER_PID=$!
    sleep 2
    echo "Sending sensor data from operator to admin..."
    aranya --uds-path /tmp/aranya3/run/uds.sock send-data $MAIN_TEAM_ID $OPERATOR_DEVICE_ID $SENSOR_LABEL_ID "Temperature: $((20 + i)).0°C, Humidity: $((60 + i))% (run $i)"
    wait $LISTENER_PID
    echo "Sensor data channel test $i completed. Capturing PSKs..."
    aranya --uds-path /tmp/aranya1/run/uds.sock show-all-psks $MAIN_TEAM_ID > /tmp/psks_run${i}.txt 2>&1
    echo "PSK capture for run $i completed. File size: $(wc -c < /tmp/psks_run${i}.txt) bytes"
done

echo ""
echo "=== PSK Comparison Across Runs ==="
for i in 1 2 3; do
    for j in 1 2 3; do
        if [ $i -lt $j ]; then
            echo "Comparing PSKs: Run $i vs Run $j"
            if diff /tmp/psks_run${i}.txt /tmp/psks_run${j}.txt > /dev/null; then
                echo "   ⚠️  SAME PSKs detected - may indicate key reuse"
            else
                echo "   ✅ DIFFERENT PSKs detected - key rotation working"
            fi
        fi
    done
done

echo ""
echo "=========================================="
echo "=== END AQC CHANNELS KEY ROTATION TEST ==="
echo "=========================================="


