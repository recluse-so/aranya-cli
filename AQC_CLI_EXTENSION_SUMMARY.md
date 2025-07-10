# AQC CLI Extension Work Summary

## Context
Extended Aranya CLI to support AQC (Aranya QUIC Channels) data transmission between devices.

## Changes Made
Modified `crates/aranya-cli/src/main.rs` to add new commands:

### New CLI Commands Added:
1. **CreateLabel** - Create AQC labels for data channels
2. **AssignLabel** - Assign labels to devices with channel operations
3. **AssignAqcNetId** - Assign network identifiers to devices  
4. **SendData** - Send data via AQC bidirectional channel
5. **ListenData** - Listen for incoming AQC data

### Key Technical Insights:
- Device keys (identity, signing, encoding) are **immutable by design**
- AQC uses ephemeral PSKs (Pre-Shared Keys) that are discarded when channels close
- Key rotation happens at AQC channel level, not device identity level
- Current API: `create_bidi_channel()`, `send()`, `receive()`

## Multi-Daemon Setup
Working with 5 daemons (ports 5055-5059) for testing data transmission between devices.

## Next Steps
- Implement simpler CLI commands that work with current AQC API
- Test data transmission between daemons in existing setup
- Consider policy extensions needed for key rotation at channel level

## Files Modified
- `crates/aranya-cli/src/main.rs` - Added new commands and imports
- Added imports: `LabelId`, `ChannelOperation`, `NetIdentifier`

## Memory Reference
Saved as memory ID: 2821810 for future reference. 