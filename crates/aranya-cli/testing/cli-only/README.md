

# CLI-Only Multi-Daemon Setup

## Issues

### Port Conflict Issue with --aqc-addr Flag

**Problem**: When running multiple Aranya daemons and using the CLI with `--aqc-addr` flags, we encountered "Address already in use" errors.

**Root Cause**: The CLI tries to start its own AQC (Aranya Query Client) server when the `--aqc-addr` parameter is provided, but this conflicts with the daemon's existing AQC server running on the same port.

**Error Message**:
```
Error: Failed to connect to daemon after 5 attempts: AQC error: Server start error: Address already in use (os error 48)
```

**Solution**: Remove all `--aqc-addr` parameters from CLI commands when using Unix Domain Socket (UDS) connections. The UDS connection works perfectly without specifying an AQC address.

**Working Command**:
```bash
# ✅ Works - UDS only
aranya --uds-path /tmp/aranya1/run/uds.sock create-team

# ❌ Fails - UDS + AQC address causes port conflict
aranya --uds-path /tmp/aranya1/run/uds.sock --aqc-addr 127.0.0.1:5055 create-team
```

**Impact**: This allows multiple daemons to run simultaneously on different ports (5055-5059) while CLI commands connect via their respective UDS sockets without port conflicts.

**Files Affected**:
- `build-teams.sh` - Removed all `--aqc-addr` parameters
- `start-daemons.sh` - Updated to use separate aranya directories and correct UDS paths

