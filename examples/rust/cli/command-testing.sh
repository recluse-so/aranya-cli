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
echo "UDS daemon envs you can use with the CLI:"
echo "  OWNER_UDS:    $OWNER_UDS"
echo "  ADMIN_UDS:    $ADMIN_UDS"
echo "  OPERATOR_UDS: $OPERATOR_UDS"
echo "  MEMBERA_UDS:  $MEMBERA_UDS"
echo "  MEMBERB_UDS:  $MEMBERB_UDS"
echo "Other useful env vars:"
echo "  TEAM_ID:       $TEAM_ID"
echo "  SEED_IKM_HEX:  $SEED_IKM_HEX"
echo "==============================================================="
