#!/bin/bash
cd "$(dirname "$0")/.."

# Check if devices.csv exists
if [ ! -f "scratch/devices.csv" ]; then
    echo "ERROR: scratch/devices.csv not found!"
    echo "Please run the startup script first to create the team and generate device keys."
    exit 1
fi

# Check if team_env.sh exists
if [ ! -f "scratch/team_env.sh" ]; then
    echo "ERROR: scratch/team_env.sh not found!"
    echo "Please run the startup script first to create the team."
    exit 1
fi

# Source team environment variables
source scratch/team_env.sh

echo "Setting up devices for team: $TEAM_ID"
echo "Owner device ID: $OWNER_DEVICE_ID"
echo ""

# Read devices.csv and set up each device
while IFS=',' read -r role identity_pk signing_pk encoding_pk; do
    echo "Setting up $role device..."
    echo "Identity PK: $identity_pk"
    echo "Signing PK: $signing_pk" 
    echo "Encoding PK: $encoding_pk"
    echo ""
    
    # Run the device setup script
    ./scratch/aranya_scripts/device_setup.sh "$TEAM_ID" "$identity_pk" "$signing_pk" "$encoding_pk" "$(echo $role | sed 's/membera/Member/; s/memberb/Member/; s/admin/Admin/; s/operator/Operator/')"
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully set up $role device"
    else
        echo "❌ Failed to set up $role device"
    fi
    echo ""
    echo "---"
    echo ""
    
done < scratch/devices.csv

echo "Device setup complete!"
echo ""
echo "To verify all devices are set up correctly, run:"
echo "aranya list-devices $TEAM_ID"