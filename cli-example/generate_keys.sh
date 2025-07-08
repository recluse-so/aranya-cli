#!/bin/bash

# Generate Aranya device keys (simplified for testing)
# Usage: ./generate_keys.sh <prefix>
# Example: ./generate_keys.sh test_device_owner

if [ $# -ne 1 ]; then
    echo "Usage: $0 <prefix>"
    echo "Example: $0 test_device_owner"
    exit 1
fi

PREFIX=$1

# Generate random hex strings for testing
IDENTITY_PUB=$(openssl rand -hex 32)
SIGNING_PUB=$(openssl rand -hex 32)
ENCODING_PUB=$(openssl rand -hex 32)

# Generate device ID (hash of identity public key)
DEVICE_ID=$(echo -n "$IDENTITY_PUB" | xxd -r -p | sha256sum | cut -d' ' -f1 | head -c 16)

echo "Generated keys for $PREFIX:"
echo "Device ID: $DEVICE_ID"
echo "Identity PK: $IDENTITY_PUB"
echo "Signing PK: $SIGNING_PUB"
echo "Encoding PK: $ENCODING_PUB"
echo ""
echo "Environment variables:"
echo "export ${PREFIX}_DEVICE_ID=\"$DEVICE_ID\""
echo "export ${PREFIX}_IDENTITY_PK=\"$IDENTITY_PUB\""
echo "export ${PREFIX}_SIGNING_PK=\"$SIGNING_PUB\""
echo "export ${PREFIX}_ENCODING_PK=\"$ENCODING_PUB\""






