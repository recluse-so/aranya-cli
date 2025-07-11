#!/bin/bash

# Parse command line arguments
TEST_MODE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --test)
            TEST_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--test]"
            echo "  --test: Run daemons and automatically test CLI commands"
            echo "  (no args): Run daemons and source env vars for manual testing"
            exit 1
            ;;
    esac
done

echo "🚀 Aranya CLI Testing Script"
echo "============================"

# Build the daemon
echo "🔨 Building daemon..."
cargo build --release --manifest-path "$(dirname "$0")/../../../Cargo.toml" --bin aranya-daemon

# Build the example
echo "🔨 Building example..."
cargo build --release --manifest-path "$(dirname "$0")/../Cargo.toml"

# Get the absolute path to the daemon
daemon="$(cd "$(dirname "$0")/../../../target/release" && pwd)/aranya-daemon"

echo "🔄 Starting daemons and running example..."
echo "   Daemon path: $daemon"

# Run the example and capture output
if [ "$TEST_MODE" = true ]; then
    # Test mode: Do everything from manual mode PLUS run CLI tests
    echo "📋 Running example (test mode)..."
    "$(dirname "$0")/../target/release/aranya-example" "${daemon}"
    
    # Source the environment variables
    if [ -f "/tmp/aranya-env-vars.sh" ]; then
        echo "📁 Sourcing environment variables..."
        source "/tmp/aranya-env-vars.sh"
        echo "✅ Environment variables loaded!"
        
        # Wait for daemons to fully initialize
        echo "⏳ Waiting for daemons to initialize..."
        sleep 3

        # Run command testing script
        echo "🧪 Running CLI tests..."
        "$(dirname "$0")/command-testing.sh"
    else
        echo "❌ Environment file not found at /tmp/aranya-env-vars.sh"
        echo "   The example may have failed to run properly."
        exit 1
    fi
else
    # Manual mode: Run example and source env vars
    echo "📋 Running example (manual mode)..."
    "$(dirname "$0")/../target/release/aranya-example" "${daemon}"
    
    # Source the environment variables
    if [ -f "/tmp/aranya-env-vars.sh" ]; then
        echo "📁 Sourcing environment variables..."
        source "/tmp/aranya-env-vars.sh"
        echo "✅ Environment variables loaded!"
        echo ""
        echo "🎯 Ready for manual CLI testing!"
        echo "   Available commands:"
        echo "   - aranya --uds-path \$OWNER_UDS get-device-id"
        echo "   - aranya --uds-path \$OWNER_UDS query-devices-on-team \$TEAM_ID"
        echo "   - aranya --uds-path \$OWNER_UDS list-devices \$TEAM_ID"
        echo "   - aranya --uds-path \$ADMIN_UDS device-info \$TEAM_ID"
        echo ""
        echo "   Environment variables set:"
        echo "   - OWNER_UDS, ADMIN_UDS, OPERATOR_UDS, MEMBERA_UDS, MEMBERB_UDS"
        echo "   - TEAM_ID, SEED_IKM_HEX"
        echo ""
        echo "   Example: aranya --uds-path \$OWNER_UDS query-devices-on-team \$TEAM_ID"
    else
        echo "❌ Environment file not found at /tmp/aranya-env-vars.sh"
        echo "   The example may have failed to run properly."
    fi
fi

echo "✅ Script completed!" 