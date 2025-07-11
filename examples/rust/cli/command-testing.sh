#!/bin/bash

echo "🔧 Testing CLI Commands Against All Daemons"
echo "==========================================="

# Try to source environment variables from the file created by main.rs
if [ -f "/tmp/aranya-env-vars.sh" ]; then
    echo "📁 Found environment variables file, sourcing..."
    source "/tmp/aranya-env-vars.sh"
    echo "✅ Environment variables loaded from /tmp/aranya-env-vars.sh"
else
    echo "⚠️  No environment variables file found at /tmp/aranya-env-vars.sh"
    echo "   Run the Rust example first to generate it"
fi

# Check if environment variables are set
if [ -z "$OWNER_UDS" ] || [ -z "$ADMIN_UDS" ] || [ -z "$OPERATOR_UDS" ] || [ -z "$MEMBERA_UDS" ] || [ -z "$MEMBERB_UDS" ]; then
    echo "❌ Error: UDS environment variables not set!"
    echo "Run: ./cli-testing-daemons.sh --test first"
    exit 1
fi

# Array of daemon names and their UDS paths
DAEMON_NAMES=("Owner" "Admin" "Operator" "MemberA" "MemberB")
DAEMON_PATHS=("$OWNER_UDS" "$ADMIN_UDS" "$OPERATOR_UDS" "$MEMBERA_UDS" "$MEMBERB_UDS")

# Test function for each daemon
test_daemon() {
    local name=$1
    local uds_path=$2
    
    echo ""
    echo "🧪 Testing $name daemon at: $uds_path"
    echo "----------------------------------------"
    
    # Test 1: Get device ID
    echo -e "\n========== CLI TEST: aranya --uds-path '$uds_path' get-device-id =========="
    aranya --uds-path "$uds_path" get-device-id
    if [ $? -eq 0 ]; then
        echo "✅ $name: Device ID retrieved successfully"
    else
        echo "❌ $name: Failed to get device ID"
    fi
    
    # Test 2: Get key bundle
    echo -e "\n========== CLI TEST: aranya --uds-path '$uds_path' get-key-bundle =========="
    aranya --uds-path "$uds_path" get-key-bundle
    if [ $? -eq 0 ]; then
        echo "✅ $name: Key bundle retrieved successfully"
    else
        echo "❌ $name: Failed to get key bundle"
    fi
    
    # Test 3: Query devices on team (using actual team ID)
    echo -e "\n========== CLI TEST: aranya --uds-path '$uds_path' query-devices-on-team '$TEAM_ID' =========="
    aranya --uds-path "$uds_path" query-devices-on-team "$TEAM_ID"
    if [ $? -eq 0 ]; then
        echo "✅ $name: Devices on team queried successfully"
    else
        echo "❌ $name: Failed to query devices on team"
    fi
    
    # Test 4: Get device info
    echo -e "\n========== CLI TEST: aranya --uds-path '$uds_path' device-info '$TEAM_ID' =========="
    aranya --uds-path "$uds_path" device-info "$TEAM_ID"
    if [ $? -eq 0 ]; then
        echo "✅ $name: Device info retrieved successfully"
    else
        echo "❌ $name: Failed to get device info"
    fi
    
    echo "✅ $name daemon tests completed"
}

# Test function for advanced CLI commands
test_advanced_commands() {
    echo ""
    echo "🧪 Testing Advanced CLI Commands"
    echo "================================="
    
    # Test 1: Assign role to device
    echo -e "\n========== CLI TEST: aranya --uds-path '$OPERATOR_UDS' assign-role '$TEAM_ID' '$MEMBERA_DEVICE_ID' 'Member' =========="
    aranya --uds-path "$OPERATOR_UDS" assign-role "$TEAM_ID" "$MEMBERA_DEVICE_ID" "Member"
    if [ $? -eq 0 ]; then
        echo "✅ assign-role succeeded"
    else
        echo "❌ assign-role failed"
    fi
    
    # Test 2: Query device role
    echo -e "\n========== CLI TEST: aranya --uds-path '$MEMBERA_UDS' query-device-role '$TEAM_ID' '$MEMBERA_DEVICE_ID' =========="
    aranya --uds-path "$MEMBERA_UDS" query-device-role "$TEAM_ID" "$MEMBERA_DEVICE_ID"
    if [ $? -eq 0 ]; then
        echo "✅ query-device-role succeeded"
    else
        echo "❌ query-device-role failed"
    fi
    
    # Test 3: Query device keybundle
    echo -e "\n========== CLI TEST: aranya --uds-path '$MEMBERA_UDS' query-device-keybundle '$TEAM_ID' '$MEMBERA_DEVICE_ID' =========="
    aranya --uds-path "$MEMBERA_UDS" query-device-keybundle "$TEAM_ID" "$MEMBERA_DEVICE_ID"
    if [ $? -eq 0 ]; then
        echo "✅ query-device-keybundle succeeded"
    else
        echo "❌ query-device-keybundle failed"
    fi
    
    # Test 4: Assign AQC network ID
    echo -e "\n========== CLI TEST: aranya --uds-path '$OPERATOR_UDS' assign-aqc-net-id '$TEAM_ID' '$MEMBERA_DEVICE_ID' '$MEMBERA_AQC_NET_ID' =========="
    aranya --uds-path "$OPERATOR_UDS" assign-aqc-net-id "$TEAM_ID" "$MEMBERA_DEVICE_ID" "$MEMBERA_AQC_NET_ID"
    if [ $? -eq 0 ]; then
        echo "✅ assign-aqc-net-id succeeded"
    else
        echo "❌ assign-aqc-net-id failed"
    fi
    
    # Test 5: Query AQC network identifier
    echo -e "\n========== CLI TEST: aranya --uds-path '$MEMBERA_UDS' query-aqc-net-identifier '$TEAM_ID' '$MEMBERA_DEVICE_ID' =========="
    aranya --uds-path "$MEMBERA_UDS" query-aqc-net-identifier "$TEAM_ID" "$MEMBERA_DEVICE_ID"
    if [ $? -eq 0 ]; then
        echo "✅ query-aqc-net-identifier succeeded"
    else
        echo "❌ query-aqc-net-identifier failed"
    fi
    
    # Test 6: List AQC assignments
    echo -e "\n========== CLI TEST: aranya --uds-path '$OPERATOR_UDS' list-aqc-assignments '$TEAM_ID' =========="
    aranya --uds-path "$OPERATOR_UDS" list-aqc-assignments "$TEAM_ID"
    if [ $? -eq 0 ]; then
        echo "✅ list-aqc-assignments succeeded"
    else
        echo "❌ list-aqc-assignments failed"
    fi
    
    # Test 7: Add sync peer
    echo -e "\n========== CLI TEST: aranya --uds-path '$OWNER_UDS' add-sync-peer '$TEAM_ID' '$ADMIN_SYNC_ADDR' =========="
    aranya --uds-path "$OWNER_UDS" add-sync-peer "$TEAM_ID" "$ADMIN_SYNC_ADDR"
    if [ $? -eq 0 ]; then
        echo "✅ add-sync-peer succeeded"
    else
        echo "❌ add-sync-peer failed"
    fi
    
    # Test 8: Sync now
    echo -e "\n========== CLI TEST: aranya --uds-path '$ADMIN_UDS' sync-now '$TEAM_ID' =========="
    aranya --uds-path "$ADMIN_UDS" sync-now "$TEAM_ID"
    if [ $? -eq 0 ]; then
        echo "✅ sync-now succeeded"
    else
        echo "❌ sync-now failed"
    fi
    
    # Test 9: Create label
    echo -e "\n========== CLI TEST: aranya --uds-path '$OPERATOR_UDS' create-label '$TEAM_ID' 'test_label' =========="
    aranya --uds-path "$OPERATOR_UDS" create-label "$TEAM_ID" "test_label"
    if [ $? -eq 0 ]; then
        echo "✅ create-label succeeded"
    else
        echo "❌ create-label failed"
    fi
    
    # Test 10: List label assignments
    echo -e "\n========== CLI TEST: aranya --uds-path '$OPERATOR_UDS' list-label-assignments '$TEAM_ID' =========="
    aranya --uds-path "$OPERATOR_UDS" list-label-assignments "$TEAM_ID"
    if [ $? -eq 0 ]; then
        echo "✅ list-label-assignments succeeded"
    else
        echo "❌ list-label-assignments failed"
    fi
    
    # Test 11: Show channels
    echo -e "\n========== CLI TEST: aranya --uds-path '$MEMBERA_UDS' show-channels =========="
    aranya --uds-path "$MEMBERA_UDS" show-channels
    if [ $? -eq 0 ]; then
        echo "✅ show-channels succeeded"
    else
        echo "❌ show-channels failed"
    fi
    
    # Test 12: List active channels
    echo -e "\n========== CLI TEST: aranya --uds-path '$MEMBERA_UDS' list-active-channels =========="
    aranya --uds-path "$MEMBERA_UDS" list-active-channels
    if [ $? -eq 0 ]; then
        echo "✅ list-active-channels succeeded"
    else
        echo "❌ list-active-channels failed"
    fi
}

# Test team commands with Owner daemon
test_team_commands() {
    echo ""
    echo "🔍 Testing team commands with Owner daemon"
    echo "========================================="

    local uds="$OWNER_UDS"
    echo "Using OWNER_UDS: $uds"

    # Test 1: Query devices on team (using known team ID)
    echo -e "\n========== CLI TEST: aranya --uds-path '$uds' query-devices-on-team '$TEAM_ID' =========="
    aranya --uds-path "$uds" query-devices-on-team "$TEAM_ID"
    if [ $? -eq 0 ]; then
        echo "✅ query-devices-on-team succeeded"
    else
        echo "❌ query-devices-on-team failed"
    fi

    # Test 2: List devices on team
    echo -e "\n========== CLI TEST: aranya --uds-path '$uds' list-devices '$TEAM_ID' =========="
    aranya --uds-path "$uds" list-devices "$TEAM_ID"
    if [ $? -eq 0 ]; then
        echo "✅ list-devices succeeded"
    else
        echo "❌ list-devices failed"
    fi

    # Test 3: Get device ID
    echo -e "\n========== CLI TEST: aranya --uds-path '$uds' get-device-id =========="
    aranya --uds-path "$uds" get-device-id
    if [ $? -eq 0 ]; then
        echo "✅ get-device-id succeeded"
    else
        echo "❌ get-device-id failed"
    fi

    # Test 4: Device info without device ID (current device)
    echo -e "\n========== CLI TEST: aranya --uds-path '$uds' device-info '$TEAM_ID' =========="
    aranya --uds-path "$uds" device-info "$TEAM_ID"
    if [ $? -eq 0 ]; then
        echo "✅ device-info <team-id> succeeded"
    else
        echo "❌ device-info <team-id> failed"
    fi

    echo "✅ Team commands tests completed"
}

# Run tests for all daemons
echo "🚀 Starting CLI command tests for all daemons..."
for i in "${!DAEMON_NAMES[@]}"; do
    name="${DAEMON_NAMES[$i]}"
    uds_path="${DAEMON_PATHS[$i]}"
    test_daemon "$name" "$uds_path"
done

# Run team commands test with Owner daemon
test_team_commands

# Test advanced commands
test_advanced_commands

echo ""
echo "🎉 All CLI command tests completed!"
echo "📊 Summary:"
echo "  - Tested 5 daemons (Owner, Admin, Operator, MemberA, MemberB)"
echo "  - Each daemon tested: device-id, key-bundle, query-devices-on-team, device-info"
echo "  - Team commands tested with Owner daemon: query-devices-on-team, list-devices, device-info"
echo ""
echo "💡 Next steps:"
echo "  - Use the UDS paths for manual CLI testing"
echo "  - Test more complex scenarios with the CLI commands"

# At the end, print the env vars for manual CLI testing
echo -e "\n\n================= ENV VARS FOR MANUAL CLI TESTING ================="
echo "🔌 UDS Daemon Paths:"
echo "  OWNER_UDS:    $OWNER_UDS"
echo "  ADMIN_UDS:    $ADMIN_UDS"
echo "  OPERATOR_UDS: $OPERATOR_UDS"
echo "  MEMBERA_UDS:  $MEMBERA_UDS"
echo "  MEMBERB_UDS:  $MEMBERB_UDS"
echo ""
echo "🆔 Device IDs:"
echo "  OWNER_DEVICE_ID:    $OWNER_DEVICE_ID"
echo "  ADMIN_DEVICE_ID:    $ADMIN_DEVICE_ID"
echo "  OPERATOR_DEVICE_ID: $OPERATOR_DEVICE_ID"
echo "  MEMBERA_DEVICE_ID:  $MEMBERA_DEVICE_ID"
echo "  MEMBERB_DEVICE_ID:  $MEMBERB_DEVICE_ID"
echo ""
echo "🌐 Sync Addresses:"
echo "  OWNER_SYNC_ADDR:    $OWNER_SYNC_ADDR"
echo "  ADMIN_SYNC_ADDR:    $ADMIN_SYNC_ADDR"
echo "  OPERATOR_SYNC_ADDR: $OPERATOR_SYNC_ADDR"
echo "  MEMBERA_SYNC_ADDR:  $MEMBERA_SYNC_ADDR"
echo "  MEMBERB_SYNC_ADDR:  $MEMBERB_SYNC_ADDR"
echo ""
echo "🔗 AQC Network IDs:"
echo "  MEMBERA_AQC_NET_ID: $MEMBERA_AQC_NET_ID"
echo "  MEMBERB_AQC_NET_ID: $MEMBERB_AQC_NET_ID"
echo ""
echo "🏷️  Labels:"
echo "  LABEL_ID:           $LABEL_ID"
echo ""
echo "📊 Team Info:"
echo "  TEAM_ID:            $TEAM_ID"
echo "  SEED_IKM_HEX:       $SEED_IKM_HEX"
echo ""
echo "💡 Example Advanced Commands:"
echo "  aranya --uds-path \$OPERATOR_UDS assign-role \$TEAM_ID \$MEMBERA_DEVICE_ID 'Member'"
echo "  aranya --uds-path \$MEMBERA_UDS query-device-role \$TEAM_ID \$MEMBERA_DEVICE_ID"
echo "  aranya --uds-path \$OPERATOR_UDS assign-aqc-net-id \$TEAM_ID \$MEMBERA_DEVICE_ID \$MEMBERA_AQC_NET_ID"
echo "  aranya --uds-path \$OWNER_UDS add-sync-peer \$TEAM_ID \$ADMIN_SYNC_ADDR"
echo "  aranya --uds-path \$OPERATOR_UDS create-label \$TEAM_ID 'my_label'"
echo "  aranya --uds-path \$MEMBERA_UDS show-channels"
echo "  aranya --uds-path \$MEMBERA_UDS query-device-keybundle \$TEAM_ID \$MEMBERA_DEVICE_ID"
echo "  aranya --uds-path \$MEMBERA_UDS query-aqc-net-identifier \$TEAM_ID \$MEMBERA_DEVICE_ID"
echo "  aranya --uds-path \$OPERATOR_UDS list-aqc-assignments \$TEAM_ID"
echo "  aranya --uds-path \$ADMIN_UDS sync-now \$TEAM_ID"
echo "  aranya --uds-path \$OPERATOR_UDS list-label-assignments \$TEAM_ID"
echo "  aranya --uds-path \$MEMBERA_UDS list-active-channels"
echo "==============================================================="
