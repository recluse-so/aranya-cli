# Aranya CLI

Command-line interface for Aranya team and device management operations.

## Prerequisites

- A running `aranya-daemon` instance
- Proper daemon configuration with UDS socket and AQC address

## Installation

```bash
cargo install --path crates/aranya-cli
```

## Usage

The CLI tool connects to a running Aranya daemon to perform operations. You can specify the daemon connection details via command-line options or environment variables:

```bash
aranya --uds-path /var/run/aranya/uds.sock --aqc-addr 127.0.0.1:7812 <command>

# Or using environment variables
export ARANYA_UDS_PATH=/var/run/aranya/uds.sock
export ARANYA_AQC_ADDR=127.0.0.1:7812
aranya <command>
```

## Commands

### Team Management

#### Create a new team
```bash
# Generate random seed IKM
aranya create-team

# Use specific seed IKM (32 bytes hex)
aranya create-team --seed-ikm <hex-string>
```

#### Add an existing team
```bash
aranya add-team <team-id> <seed-ikm-hex>
```

#### Remove a team
```bash
aranya remove-team <team-id>
```

#### List all teams
```bash
aranya list-teams
```

### Device Management

#### Add a device to a team
```bash
aranya add-device <team-id> <identity-pk-hex> <signing-pk-hex> <encoding-pk-hex> [--label <name>]
```

#### Remove a device from a team
```bash
aranya remove-device <team-id> <device-id>
```

#### Assign a role to a device
```bash
aranya assign-role <team-id> <device-id> <role>
# Roles: Owner, Admin, Operator, Member
```

#### List devices on a team
```bash
aranya list-devices <team-id>
```

#### Get device information
```bash
# Current device
aranya device-info <team-id>

# Specific device
aranya device-info <team-id> <device-id>
```

### Synchronization

#### Add a sync peer
```bash
aranya add-sync-peer <team-id> <peer-addr> [--interval-secs <seconds>]
# Example: aranya add-sync-peer abc123 192.168.1.100:7812 --interval-secs 5
```

#### Sync immediately
```bash
aranya sync-now <team-id> <peer-addr>
```

## Examples

### Create a team and add a device

```bash
# Create a new team
aranya create-team
# Output: Team ID: abc123..., Seed IKM: def456...

# On another device, add the team
aranya add-team abc123... def456...

# Add the second device to the team (run on first device)
# First, get the device's keys (run on second device)
aranya device-info abc123...

# Then add it (run on first device with Owner/Admin role)
aranya add-device abc123... <identity-pk> <signing-pk> <encoding-pk> --label "Device 2"

# Assign Admin role
aranya assign-role abc123... <device-id> Admin

# Set up automatic synchronization
aranya add-sync-peer abc123... 192.168.1.100:7812 --interval-secs 1
```

### List team members

```bash
aranya list-devices abc123...
# Output:
# Device ID                                                          Role       Label
# ------------------------------------------------------------------------------------------------
# 00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff  Owner      Device 1
# ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100  Admin      Device 2
```

## Verbose Output

For debugging, use the `-v` or `--verbose` flag to enable detailed logging:

```bash
aranya -v create-team
```


# Issues

In Rust (main.rs):
The Aranya client library (aranya_client) manages "active storage" natively. When you call add_team, it returns a Team handle, and all operations on that handle are always "active" for that client. Each device's process has its own client and its own active team context.
In the CLI:
There is no explicit mechanism to set the active team/storage for a daemon after joining a team.
add-team just adds the team to storage, but does not make it active for subsequent commands.
Only the Owner's daemon (the one that created the team) has the team as active storage by default.
Other daemons (Admin, Operator, MemberA, MemberB) do not have the team as active storage unless the CLI/daemon provides a command to set it (which, as of now, it does not).
Result:
In Rust, every device can operate on the team as "active" because the API enforces it.
In the CLI, only the Owner can, unless you add a feature/command to set the active team for other daemons.
You are 100% correct.
This is the main reason why the CLI-based multi-daemon AQC test can't fully replicate the Rust example's behavior for non-Owner devices.