# Aranya CLI Scripts

This directory contains scripts for setting up and managing Aranya teams and devices using the CLI.

## Script Overview

### `generate_aranya_keys.rs`
**Purpose**: Generates proper Aranya cryptographic key bundles for devices
- Uses the official `aranya-keygen` crate to create identity, encryption, and signing keys
- Stores private keys securely in a filesystem keystore
- Outputs public keys as hex strings for device registration
- Provides environment variable exports for easy use

### `complete_setup.sh`
**Purpose**: Complete end-to-end setup of an Aranya team with multiple devices
- Builds the daemon and key generation binary
- Creates a team with QUIC sync configuration
- Generates keys for multiple devices (admin, operator, membera, memberb)
- Adds devices to the team using their public keys
- Assigns roles to devices
- Saves device information for later individual setup

### `device_setup.sh`
**Purpose**: Sets up individual devices with their private keys
- Runs the daemon as a specific device using its keystore
- Assigns roles to the device using `aranya assign-role`
- Used after `complete_setup.sh` to configure each device individually

### `owner_setup.sh`
**Purpose**: Sets up the owner device (the one that created the team)
- Similar to `device_setup.sh` but specifically for the owner device
- Assigns the Owner role to the device that created the team

### `generate_keys.sh`
**Purpose**: Legacy OpenSSL-based key generation (not used in current workflow)
- Generates random hex strings for keys
- Used in older versions before proper Aranya key bundles

## Example Usage

### Prerequisites
1. Build the Aranya daemon and CLI:
   ```bash
   cd /path/to/aranya-cli
   cargo build --bin aranya-daemon --release
   cargo build --bin aranya --release
   ```

2. Ensure the scripts are executable:
   ```bash
   chmod +x *.sh
   ```

### Step 1: Complete Team Setup
Run the complete setup script to create a team and generate keys for all devices:

```bash
./complete_setup.sh
```

This script will:
- Build the key generation binary
- Start the daemon
- Create a team with QUIC sync
- Generate keys for 4 devices (admin, operator, membera, memberb)
- Add devices to the team
- Assign the Owner role to the creator device
- Save device information to `../devices_with_keys.csv`

### Step 2: Set Up Individual Devices
For each device, you need to copy its keystore to the daemon's keystore path and run the device setup:

```bash
# For the admin device
cp -r /tmp/aranya_keys_test_device_admin /tmp/aranya/state/keystore/aranya
./device_setup.sh <TEAM_ID> <IDENTITY_PK> <SIGNING_PK> <ENCODING_PK> Admin

# For the operator device  
cp -r /tmp/aranya_keys_test_device_operator /tmp/aranya/state/keystore/aranya
./device_setup.sh <TEAM_ID> <IDENTITY_PK> <SIGNING_PK> <ENCODING_PK> Operator

# For member devices
cp -r /tmp/aranya_keys_test_device_membera /tmp/aranya/state/keystore/aranya
./device_setup.sh <TEAM_ID> <IDENTITY_PK> <SIGNING_PK> <ENCODING_PK> Member
```

Replace `<TEAM_ID>`, `<IDENTITY_PK>`, etc. with the actual values from the CSV file or the script output.

### Step 3: Verify Setup
Check that all devices are properly configured:

```bash
# List all devices on the team
aranya list-devices <TEAM_ID>

# Check device info
aranya device-info <TEAM_ID> <DEVICE_ID>
```

## Key Concepts

### Key Generation
- **Identity Keys**: Used to uniquely identify devices in the team
- **Encryption Keys**: Used for secure data encryption/decryption
- **Signing Keys**: Used for creating and verifying cryptographic signatures
- **Private Keys**: Stored in keystores for device authentication
- **Public Keys**: Shared for device registration and communication

### Device Roles
- **Owner**: Can perform all operations, including team management
- **Admin**: Can manage devices and assign roles
- **Operator**: Can perform day-to-day operations
- **Member**: Basic team member with limited permissions

### Team Synchronization
- Uses QUIC sync for encrypted peer-to-peer synchronization
- PSK (Pre-Shared Key) seeds are generated for team security
- Devices can sync with each other using the team's PSK

## Troubleshooting

### Common Issues
1. **"not authorized" errors**: Only the owner device can assign roles. Make sure you're running the daemon as the correct device.

2. **"UDS socket not found"**: The daemon isn't running or the socket path is incorrect. Check that the daemon started successfully.

3. **"invalid device ID"**: The device ID doesn't match the public keys. Ensure you're using the correct keys for each device.

4. **Build errors**: Make sure all dependencies are built and the workspace is properly configured.

### Debugging
- Check daemon logs: `/tmp/aranya/daemon.log`
- Verify keystore paths: `/tmp/aranya/state/keystore/aranya`
- Use verbose mode: `aranya -v <command>`

## File Locations
- **Daemon binary**: `../../target/release/aranya-daemon`
- **CLI binary**: `../../target/release/aranya`
- **Key generation**: `./target/release/generate_aranya_keys`
- **Daemon config**: `../daemon_config.json`
- **Device info**: `../devices_with_keys.csv`
- **Team environment**: `../team_env.sh`
