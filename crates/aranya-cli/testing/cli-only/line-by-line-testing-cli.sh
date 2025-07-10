mkdir -p /tmp/aranya/{run,state,cache,logs,config}

# Create team
# Run and set environment variables in one command
eval $(aranya --uds-path /tmp/aranya/run/uds.sock --aqc-addr 127.0.0.1:0 -v create-team | grep -E "(Team ID|Seed IKM)" | sed 's/Team ID: /export TEAM_ID=/; s/Seed IKM: /export SEED_IKM=/')

# Now you can use them
echo "Team ID: $TEAM_ID"
echo "Seed IKM: $SEED_IKM"



# list devices
aranya --uds-path /tmp/aranya/run/uds.sock --aqc-addr 127.0.0.1:0 -v list-devices $TEAM_ID

# get device id
DEVICE_ID=$(aranya --uds-path /tmp/aranya/run/uds.sock --aqc-addr 127.0.0.1:0 -v list-devices $TEAM_ID | awk '/^[A-Za-z0-9]{32,}/ {print $1; exit}')
echo "Device ID: $DEVICE_ID"

# device info
aranya --uds-path /tmp/aranya/run/uds.sock --aqc-addr 127.0.0.1:0 -v device-info $TEAM_ID

ROLE=$(aranya --uds-path /tmp/aranya/run/uds.sock --aqc-addr 127.0.0.1:0 -v device-info $TEAM_ID | grep "Role:" | cut -d' ' -f2)
IDENTITY_KEY=$(aranya --uds-path /tmp/aranya/run/uds.sock --aqc-addr 127.0.0.1:0 -v device-info $TEAM_ID | grep "Identity:" | sed 's/.*Identity: *//')
SIGNING_KEY=$(aranya --uds-path /tmp/aranya/run/uds.sock --aqc-addr 127.0.0.1:0 -v device-info $TEAM_ID | grep "Signing:" | sed 's/.*Signing: *//')
ENCODING_KEY=$(aranya --uds-path /tmp/aranya/run/uds.sock --aqc-addr 127.0.0.1:0 -v device-info $TEAM_ID | grep "Encoding:" | sed 's/.*Encoding: *//')

# add device
aranya --uds-path /tmp/aranya/run/uds.sock \
    --aqc-addr 127.0.0.1:0 \
    add-device $DEVICE_ID \
    $IDENTITY_KEY $SIGNING_KEY $ENCODING_KEY



# Create a new team with a different seed
NEW_SEED=$(openssl rand -hex 32)
echo "New seed: $NEW_SEED"

# Create new team (this creates a new device)
NEW_TEAM_OUTPUT=$(aranya --uds-path /tmp/aranya/run/uds.sock --aqc-addr 127.0.0.1:0 -v create-team --seed-ikm $NEW_SEED)
NEW_TEAM_ID=$(echo "$NEW_TEAM_OUTPUT" | grep "Team ID:" | cut -d' ' -f3)
echo "New team ID: $NEW_TEAM_ID"

# Get the new device's keys
NEW_DEVICE_OUTPUT=$(aranya --uds-path /tmp/aranya/run/uds.sock --aqc-addr 127.0.0.1:0 -v device-info $NEW_TEAM_ID)
NEW_DEVICE_ID=$(echo "$NEW_DEVICE_OUTPUT" | grep "Device ID:" | cut -d' ' -f3)
NEW_IDENTITY_KEY=$(echo "$NEW_DEVICE_OUTPUT" | grep "Identity:" | sed 's/.*Identity: *//')
NEW_SIGNING_KEY=$(echo "$NEW_DEVICE_OUTPUT" | grep "Signing:" | sed 's/.*Signing: *//')
NEW_ENCODING_KEY=$(echo "$NEW_DEVICE_OUTPUT" | grep "Encoding:" | sed 's/.*Encoding: *//')

echo "New device ID: $NEW_DEVICE_ID"
echo "New identity key: $NEW_IDENTITY_KEY"


# Now add the new devices to your original team
aranya --uds-path /tmp/aranya/run/uds.sock --aqc-addr 127.0.0.1:0 add-device HJ3fEuapLTRNJ54dtow1GmtrKzcxLzi6iY8hXTyCe21z $NEW_IDENTITY_KEY $NEW_SIGNING_KEY $NEW_ENCODING_KEY

# List all devices in your team
aranya --uds-path /tmp/aranya/run/uds.sock --aqc-addr 127.0.0.1:0 list-devices $TEAM_ID
