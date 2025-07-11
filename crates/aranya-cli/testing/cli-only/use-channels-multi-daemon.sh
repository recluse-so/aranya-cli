#!/bin/bash
set -e

echo "=== ARANYA AQC CHANNELS MULTI-DAEMON FLOW (FOLLOWING MAIN.RS) ==="

# Check if daemons are running
for i in {1..5}; do
    if [ ! -S /tmp/aranya$i/run/uds.sock ]; then
        echo "ERROR: Daemon $i not running. Please start daemons first."
        exit 1
    fi
done

# Helper for sleep interval (match Rust example)
SYNC_INTERVAL=1
SLEEP_INTERVAL=$((SYNC_INTERVAL * 6))

# STEP 1: Owner creates team
echo "=== STEP 1: Owner creates team ==="
TEAM_OUTPUT=$(aranya --uds-path /tmp/aranya1/run/uds.sock -v create-team)
MAIN_TEAM_ID=$(echo "$TEAM_OUTPUT" | grep "Team created:" | awk '{print $3}')
SEED_IKM=$(echo "$TEAM_OUTPUT" | grep "Seed IKM:" | awk '{print $3}')
echo "Main Team ID: $MAIN_TEAM_ID"
echo "Seed IKM: $SEED_IKM"

# Get device info for all
get_device_id() {
    aranya --uds-path "$1" -v get-device-id
}

get_key_bundle() {
    aranya --uds-path "$1" -v get-key-bundle
}

OWNER_DEVICE_ID=$(get_device_id /tmp/aranya1/run/uds.sock | grep "Device ID:" | awk '{print $3}')
OWNER_KEY_BUNDLE=$(get_key_bundle /tmp/aranya1/run/uds.sock)

# STEP 2: Other devices join the team
echo "=== STEP 2: Other devices join the team ==="
for idx in 2 3 4 5; do
    echo "Daemon $idx joining team..."
    aranya --uds-path /tmp/aranya${idx}/run/uds.sock -v add-team $MAIN_TEAM_ID $SEED_IKM
done

# STEP 3: Get device keys and IDs
echo "=== STEP 3: Get device keys and IDs ==="
extract_key_bundle() {
    local output="$1"
    echo "$(echo "$output" | grep "Identity Key:" | sed 's/.*Identity Key: //') \
$(echo "$output" | grep "Signing Key:" | sed 's/.*Signing Key: //') \
$(echo "$output" | grep "Encoding Key:" | sed 's/.*Encoding Key: //')"
}

ADMIN_DEVICE_ID=$(get_device_id /tmp/aranya2/run/uds.sock | grep "Device ID:" | awk '{print $3}')
ADMIN_KEY_BUNDLE=$(get_key_bundle /tmp/aranya2/run/uds.sock)
read ADMIN_IDENTITY_KEY ADMIN_SIGNING_KEY ADMIN_ENCODING_KEY <<< $(extract_key_bundle "$ADMIN_KEY_BUNDLE")

OPERATOR_DEVICE_ID=$(get_device_id /tmp/aranya3/run/uds.sock | grep "Device ID:" | awk '{print $3}')
OPERATOR_KEY_BUNDLE=$(get_key_bundle /tmp/aranya3/run/uds.sock)
read OPERATOR_IDENTITY_KEY OPERATOR_SIGNING_KEY OPERATOR_ENCODING_KEY <<< $(extract_key_bundle "$OPERATOR_KEY_BUNDLE")

MEMBER_A_DEVICE_ID=$(get_device_id /tmp/aranya4/run/uds.sock | grep "Device ID:" | awk '{print $3}')
MEMBER_A_KEY_BUNDLE=$(get_key_bundle /tmp/aranya4/run/uds.sock)
read MEMBER_A_IDENTITY_KEY MEMBER_A_SIGNING_KEY MEMBER_A_ENCODING_KEY <<< $(extract_key_bundle "$MEMBER_A_KEY_BUNDLE")

MEMBER_B_DEVICE_ID=$(get_device_id /tmp/aranya5/run/uds.sock | grep "Device ID:" | awk '{print $3}')
MEMBER_B_KEY_BUNDLE=$(get_key_bundle /tmp/aranya5/run/uds.sock)
read MEMBER_B_IDENTITY_KEY MEMBER_B_SIGNING_KEY MEMBER_B_ENCODING_KEY <<< $(extract_key_bundle "$MEMBER_B_KEY_BUNDLE")

echo "Device IDs:"
echo "  Owner: $OWNER_DEVICE_ID"
echo "  Admin: $ADMIN_DEVICE_ID"
echo "  Operator: $OPERATOR_DEVICE_ID"
echo "  Member A: $MEMBER_A_DEVICE_ID"
echo "  Member B: $MEMBER_B_DEVICE_ID"

# STEP 4: Owner adds Admin and assigns Admin role
echo "=== STEP 4: Owner adds Admin and assigns Admin role ==="
aranya --uds-path /tmp/aranya1/run/uds.sock add-device $MAIN_TEAM_ID $ADMIN_IDENTITY_KEY $ADMIN_SIGNING_KEY $ADMIN_ENCODING_KEY
aranya --uds-path /tmp/aranya1/run/uds.sock assign-role $MAIN_TEAM_ID $ADMIN_DEVICE_ID Admin

# Sync Admin with Owner to get team state
echo "=== Syncing Admin with Owner ==="
aranya --uds-path /tmp/aranya2/run/uds.sock sync-now $MAIN_TEAM_ID 127.0.0.1:5055
sleep $SLEEP_INTERVAL

# STEP 5: Owner adds Operator device
echo "=== STEP 5: Owner adds Operator device ==="
aranya --uds-path /tmp/aranya1/run/uds.sock add-device $MAIN_TEAM_ID $OPERATOR_IDENTITY_KEY $OPERATOR_SIGNING_KEY $OPERATOR_ENCODING_KEY

# Sync Admin with Owner again to get Operator device
echo "=== Syncing Admin with Owner (for Operator device) ==="
aranya --uds-path /tmp/aranya2/run/uds.sock sync-now $MAIN_TEAM_ID 127.0.0.1:5055
sleep $SLEEP_INTERVAL

# STEP 6: Admin tries to assign Operator role (should fail initially)
echo "=== STEP 6: Admin assigns Operator role (after syncing with Owner) ==="
aranya --uds-path /tmp/aranya2/run/uds.sock assign-role $MAIN_TEAM_ID $OPERATOR_DEVICE_ID Operator

# STEP 7: Setup sync peers (all-to-all as in main.rs)
echo "=== STEP 7: Setup sync peers ==="
for src in 1 2 3 4 5; do
    for dst in 1 2 3 4 5; do
        if [ $src -ne $dst ]; then
            aranya --uds-path /tmp/aranya${src}/run/uds.sock add-sync-peer $MAIN_TEAM_ID 127.0.0.1:505$((4+$dst)) --interval-secs $SYNC_INTERVAL
        fi
    done
done

sleep $SLEEP_INTERVAL

# STEP 8: Owner adds Member devices (since Owner has active storage)
echo "=== STEP 8: Owner adds Member devices ==="
aranya --uds-path /tmp/aranya1/run/uds.sock add-device $MAIN_TEAM_ID $MEMBER_A_IDENTITY_KEY $MEMBER_A_SIGNING_KEY $MEMBER_A_ENCODING_KEY
aranya --uds-path /tmp/aranya1/run/uds.sock add-device $MAIN_TEAM_ID $MEMBER_B_IDENTITY_KEY $MEMBER_B_SIGNING_KEY $MEMBER_B_ENCODING_KEY

sleep $SLEEP_INTERVAL

# STEP 9: Owner assigns network IDs (since Owner has active storage)
echo "=== STEP 9: Owner assigns network IDs ==="
aranya --uds-path /tmp/aranya1/run/uds.sock assign-aqc-net-id $MAIN_TEAM_ID $MEMBER_A_DEVICE_ID "127.0.0.1:6004"
aranya --uds-path /tmp/aranya1/run/uds.sock assign-aqc-net-id $MAIN_TEAM_ID $MEMBER_B_DEVICE_ID "127.0.0.1:6005"

# Sync Member daemons with Owner (network assignments are handled by Owner)
echo "=== Syncing Member daemons with Owner ==="
aranya --uds-path /tmp/aranya4/run/uds.sock sync-now $MAIN_TEAM_ID 127.0.0.1:5055
aranya --uds-path /tmp/aranya5/run/uds.sock sync-now $MAIN_TEAM_ID 127.0.0.1:5055
sleep $SLEEP_INTERVAL  # Allow sync

# Extra sleep to ensure all daemons are fully synced after network assignment
sleep 10

# Verify AQC network assignments before proceeding
echo "=== Verifying AQC network assignments ==="
aranya --uds-path /tmp/aranya4/run/uds.sock query-aqc-net-identifier $MAIN_TEAM_ID $MEMBER_A_DEVICE_ID
aranya --uds-path /tmp/aranya5/run/uds.sock query-aqc-net-identifier $MAIN_TEAM_ID $MEMBER_B_DEVICE_ID

# STEP 10: Owner creates and assigns label (since Owner has active storage)
echo "=== STEP 10: Owner creates and assigns label ==="
# Owner creates label
LABEL_OUTPUT=$(aranya --uds-path /tmp/aranya1/run/uds.sock -v create-label $MAIN_TEAM_ID "test-label")
LABEL_ID=$(echo "$LABEL_OUTPUT" | grep "Label ID (base58):" | sed 's/.*Label ID (base58): //')
echo "Created label: $LABEL_ID"

# Owner assigns label to Member A
aranya --uds-path /tmp/aranya1/run/uds.sock assign-label $MAIN_TEAM_ID $MEMBER_A_DEVICE_ID $LABEL_ID SendRecv
echo "Assigned label to Member A"

# Owner assigns label to Member B  
aranya --uds-path /tmp/aranya1/run/uds.sock assign-label $MAIN_TEAM_ID $MEMBER_B_DEVICE_ID $LABEL_ID SendRecv
echo "Assigned label to Member B"

sleep $SLEEP_INTERVAL
# Extra sleep to ensure all daemons are fully synced after label assignment
sleep 10

# STEP 11: Ensure MemberA and MemberB are fully synced before AQC test
echo "=== STEP 11: Sync MemberA and MemberB with Owner ==="
aranya --uds-path /tmp/aranya4/run/uds.sock sync-now $MAIN_TEAM_ID 127.0.0.1:5055
aranya --uds-path /tmp/aranya5/run/uds.sock sync-now $MAIN_TEAM_ID 127.0.0.1:5055
sleep $SLEEP_INTERVAL

# STEP 12: AQC Communication Test (MemberA to MemberB using new CLI API)
echo "=== STEP 12: AQC Communication Test (MemberA to MemberB, new CLI API) ==="

# MemberA creates a bidirectional channel to MemberB
echo "=== MemberA creating bidirectional channel to MemberB ==="
CHANNEL_OUTPUT=$(aranya --uds-path /tmp/aranya4/run/uds.sock create-bidi-channel $MAIN_TEAM_ID "127.0.0.1:6005" $LABEL_ID)
CHANNEL_ID=$(echo "$CHANNEL_OUTPUT" | grep "Channel ID:" | awk '{print $3}')
echo "MemberA Channel ID: $CHANNEL_ID"

# MemberA creates a bidirectional stream on the channel
echo "=== MemberA creating bidirectional stream ==="
STREAM_OUTPUT=$(aranya --uds-path /tmp/aranya4/run/uds.sock create-bidi-stream $CHANNEL_ID)
STREAM_ID=$(echo "$STREAM_OUTPUT" | grep "Stream ID:" | awk '{print $3}')
echo "MemberA Stream ID: $STREAM_ID"

# MemberA sends data on the stream
echo "=== MemberA sending data ==="
aranya --uds-path /tmp/aranya4/run/uds.sock send-stream-data $STREAM_ID "Hello from MemberA to MemberB via AQC!"

# MemberB receives the channel
echo "=== MemberB receiving channel ==="
RECV_CHAN_OUTPUT=$(aranya --uds-path /tmp/aranya5/run/uds.sock receive-channel --timeout 10)
RECV_CHANNEL_ID=$(echo "$RECV_CHAN_OUTPUT" | grep "Channel ID:" | awk '{print $3}')
echo "MemberB Received Channel ID: $RECV_CHANNEL_ID"

# MemberB receives the stream
echo "=== MemberB receiving stream ==="
RECV_STREAM_OUTPUT=$(aranya --uds-path /tmp/aranya5/run/uds.sock receive-stream $RECV_CHANNEL_ID --timeout 10)
RECV_STREAM_ID=$(echo "$RECV_STREAM_OUTPUT" | grep "Stream ID:" | awk '{print $3}')
echo "MemberB Received Stream ID: $RECV_STREAM_ID"

# MemberB receives data from the stream
echo "=== MemberB receiving data ==="
aranya --uds-path /tmp/aranya5/run/uds.sock receive-stream-data $RECV_STREAM_ID --timeout 10

# List active channels and streams
echo "=== Listing active channels and streams ==="
aranya --uds-path /tmp/aranya4/run/uds.sock list-active-channels
aranya --uds-path /tmp/aranya5/run/uds.sock list-active-channels

# Close streams and channels
echo "=== Closing streams and channels ==="
aranya --uds-path /tmp/aranya4/run/uds.sock close-stream $STREAM_ID
aranya --uds-path /tmp/aranya4/run/uds.sock close-channel $CHANNEL_ID
aranya --uds-path /tmp/aranya5/run/uds.sock close-stream $RECV_STREAM_ID
aranya --uds-path /tmp/aranya5/run/uds.sock close-channel $RECV_CHANNEL_ID

echo "✅ MemberA to MemberB AQC test (new CLI API) completed!"

# STEP 13: Owner self-send AQC test (new CLI API)
echo "=== STEP 13: AQC Communication Test (Owner self-send, new CLI API) ==="

# Operator assigns AQC network ID to Owner device (since Owner can't assign to itself)
aranya --uds-path /tmp/aranya3/run/uds.sock assign-aqc-net-id $MAIN_TEAM_ID $OWNER_DEVICE_ID "127.0.0.1:6001"

# Create label and assign to Owner device
LABEL_OUTPUT=$(aranya --uds-path /tmp/aranya1/run/uds.sock -v create-label $MAIN_TEAM_ID "owner-self-label")
LABEL_ID=$(echo "$LABEL_OUTPUT" | grep "Label ID (base58):" | sed 's/.*Label ID (base58): //')
aranya --uds-path /tmp/aranya1/run/uds.sock assign-label $MAIN_TEAM_ID $OWNER_DEVICE_ID $LABEL_ID SendRecv

# Owner creates a bidirectional channel to itself
echo "=== Owner creating bidirectional channel to itself ==="
CHANNEL_OUTPUT=$(aranya --uds-path /tmp/aranya1/run/uds.sock create-bidi-channel $MAIN_TEAM_ID "127.0.0.1:6001" $LABEL_ID)
CHANNEL_ID=$(echo "$CHANNEL_OUTPUT" | grep "Channel ID:" | awk '{print $3}')
echo "Owner Channel ID: $CHANNEL_ID"

# Owner creates a bidirectional stream on the channel
echo "=== Owner creating bidirectional stream ==="
STREAM_OUTPUT=$(aranya --uds-path /tmp/aranya1/run/uds.sock create-bidi-stream $CHANNEL_ID)
STREAM_ID=$(echo "$STREAM_OUTPUT" | grep "Stream ID:" | awk '{print $3}')
echo "Owner Stream ID: $STREAM_ID"

# Owner sends data on the stream
echo "=== Owner sending data ==="
aranya --uds-path /tmp/aranya1/run/uds.sock send-stream-data $STREAM_ID "Hello from Owner to itself via AQC!"

# Owner receives data from the stream
echo "=== Owner receiving data ==="
aranya --uds-path /tmp/aranya1/run/uds.sock receive-stream-data $STREAM_ID --timeout 10

# List active channels and streams
echo "=== Listing active channels and streams ==="
aranya --uds-path /tmp/aranya1/run/uds.sock list-active-channels

# Close streams and channels
echo "=== Closing streams and channels ==="
aranya --uds-path /tmp/aranya1/run/uds.sock close-stream $STREAM_ID
aranya --uds-path /tmp/aranya1/run/uds.sock close-channel $CHANNEL_ID

echo "✅ Owner self-send AQC test (new CLI API) completed!"

echo "=== END ARANYA AQC CHANNELS MULTI-DAEMON FLOW ==="



