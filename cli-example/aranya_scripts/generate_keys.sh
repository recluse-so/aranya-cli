#!/bin/bash

# Generate Aranya device keys using the proper Rust keygen
# Usage: ./generate_keys.sh <prefix>
# Example: ./generate_keys.sh test_device_owner

if [ $# -ne 1 ]; then
    echo "Usage: $0 <prefix>"
    echo "Example: $0 test_device_owner"
    exit 1
fi

PREFIX=$1

# Check if we're in the right directory
if [ ! -f "generate_aranya_keys.rs" ]; then
    echo "ERROR: generate_aranya_keys.rs not found!"
    echo "Please run this script from the scratch/aranya_scripts/ directory"
    exit 1
fi

# Build the key generation binary if not already built
if [ ! -f "target/release/generate_aranya_keys" ]; then
    echo "Building key generation binary..."
    cargo build --release
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to build key generation binary!"
        exit 1
    fi
fi

# Generate keys using the Rust binary
echo "Generating keys for $PREFIX..."
KEYS_OUTPUT=$(./target/release/generate_aranya_keys "$PREFIX")

if [ $? -eq 0 ]; then
    echo "$KEYS_OUTPUT"
else
    echo "ERROR: Failed to generate keys for $PREFIX"
    exit 1
fi 