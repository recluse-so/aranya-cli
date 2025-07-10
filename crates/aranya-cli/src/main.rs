use anyhow::{Context, Result};
use aranya_client::{
    Client, QuicSyncConfig, TeamConfig,
};
use aranya_daemon_api::{DeviceId, KeyBundle, Role, TeamId, LabelId, NetIdentifier, ChanOp, Text};
use aranya_util::Addr;
use clap::{Parser, Subcommand};
use std::path::PathBuf;
use std::str::FromStr;
use std::time::Duration;
use bytes::Bytes;
use spideroak_base58::ToBase58;

#[derive(Parser)]
#[command(name = "aranya")]
#[command(author, version, about = "Aranya CLI tool for team and device management", long_about = None)]
struct Cli {
    /// Path to daemon's Unix Domain Socket
    #[arg(short = 'u', long, default_value = "/var/run/aranya/uds.sock")]
    uds_path: PathBuf,

    /// Daemon's AQC address
    #[arg(short = 'a', long, default_value = "127.0.0.1:0")]
    aqc_addr: String,

    /// Enable verbose logging
    #[arg(short, long)]
    verbose: bool,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Create a new team
    CreateTeam {
        /// Optional seed IKM in hex (32 bytes). If not provided, generates random.
        #[arg(long)]
        seed_ikm: Option<String>,
    },
    /// Add an existing team to this device
    AddTeam {
        /// Team ID to add
        team_id: String,
        /// Seed IKM in hex (32 bytes)
        seed_ikm: String,
    },
    /// Remove a team from this device
    RemoveTeam {
        /// Team ID to remove
        team_id: String,
    },
    /// Add a device to a team
    AddDevice {
        /// Team ID
        team_id: String,
        /// Device's identity public key in hex
        identity_pk: String,
        /// Device's signing public key in hex
        signing_pk: String,
        /// Device's encoding public key in hex
        encoding_pk: String,
    },
    /// Remove a device from a team
    RemoveDevice {
        /// Team ID
        team_id: String,
        /// Device ID to remove
        device_id: String,
    },
    /// Assign a role to a device
    AssignRole {
        /// Team ID
        team_id: String,
        /// Device ID
        device_id: String,
        /// Role (Owner, Admin, Operator, Member)
        role: String,
    },
    /// List all devices on a team
    ListDevices {
        /// Team ID
        team_id: String,
    },
    /// Get device information
    DeviceInfo {
        /// Team ID
        team_id: String,
        /// Device ID (optional, shows current device if not provided)
        device_id: Option<String>,
    },
    /// Add a sync peer for automatic synchronization
    AddSyncPeer {
        /// Team ID
        team_id: String,
        /// Peer address (e.g., "192.168.1.100:7812")
        peer_addr: String,
        /// Sync interval in seconds
        #[arg(long, default_value = "1")]
        interval_secs: u64,
    },
    /// Sync with a peer immediately
    SyncNow {
        /// Team ID
        team_id: String,
        /// Peer address (e.g., "192.168.1.100:7812")
        peer_addr: String,
    },
    /// Create a label for data channels
    CreateLabel {
        /// Team ID
        team_id: String,
        /// Label name
        label_name: String,
    },
    /// Assign a label to a device with channel operations
    AssignLabel {
        /// Team ID
        team_id: String,
        /// Device ID
        device_id: String,
        /// Label ID
        label_id: String,
        /// Channel operation (SendOnly, RecvOnly, SendRecv)
        operation: String,
    },
    /// Assign network identifier to device for AQC
    AssignAqcNetId {
        /// Team ID
        team_id: String,
        /// Device ID
        device_id: String,
        /// Network identifier (e.g., "192.168.1.100:5050")
        net_id: String,
    },
    /// List label assignments
    ListLabelAssignments {
        /// Team ID
        team_id: String,
        /// Device ID
        device_id: String,
    },
    /// List AQC network assignments
    ListAqcAssignments {
        /// Team ID
        team_id: String,
    },
    /// Send data with PSK rotation (creates new channel for each send)
    SendData {
        /// Team ID
        team_id: String,
        /// Target device ID
        device_id: String,
        /// Label ID for the channel
        label_id: String,
        /// Message to send
        message: String,
    },
    /// Listen for data with PSK rotation (creates new channel for each receive)
    ListenData {
        /// Team ID
        team_id: String,
        /// Source device ID
        device_id: String,
        /// Label ID for the channel
        label_id: String,
        /// Timeout in seconds (0 for infinite)
        #[arg(long, default_value = "30")]
        timeout: u64,
    },
    /// Show active AQC channels
    ShowChannels {
        /// Team ID
        team_id: String,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    // Initialize tracing
    let filter = if cli.verbose {
        "debug"
    } else {
        "info"
    };
    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .init();

    // Connect to daemon
    let mut client = connect_to_daemon(&cli.uds_path, &cli.aqc_addr).await?;

    match cli.command {
        Commands::CreateTeam { seed_ikm } => {
            let cfg = if let Some(ikm_hex) = seed_ikm {
                let ikm = hex::decode(ikm_hex).context("Invalid hex for seed IKM")?;
                if ikm.len() != 32 {
                    anyhow::bail!("Seed IKM must be exactly 32 bytes");
                }
                let mut ikm_array = [0u8; 32];
                ikm_array.copy_from_slice(&ikm);
                let sync_cfg = QuicSyncConfig::builder()
                    .seed_ikm(ikm_array)
                    .build()?;
                TeamConfig::builder()
                    .quic_sync(sync_cfg)
                    .build()?
            } else {
                let sync_cfg = QuicSyncConfig::builder().build()?;
                TeamConfig::builder()
                    .quic_sync(sync_cfg)
                    .build()?
            };

            let team = client.create_team(cfg).await?;
            println!("Team created: {}", team.team_id());
        }
        Commands::AddTeam { team_id, seed_ikm } => {
            let team_id = TeamId::from_str(&team_id)?;
            let ikm = hex::decode(seed_ikm).context("Invalid hex for seed IKM")?;
            if ikm.len() != 32 {
                anyhow::bail!("Seed IKM must be exactly 32 bytes");
            }
            let mut ikm_array = [0u8; 32];
            ikm_array.copy_from_slice(&ikm);
            
            let sync_cfg = QuicSyncConfig::builder()
                .seed_ikm(ikm_array)
                .build()?;
            let cfg = TeamConfig::builder()
                .quic_sync(sync_cfg)
                .build()?;

            client.add_team(team_id, cfg).await?;
            println!("Team added: {}", team_id);
        }
        Commands::RemoveTeam { team_id } => {
            let team_id = TeamId::from_str(&team_id)?;
            client.remove_team(team_id).await?;
            println!("Team removed: {}", team_id);
        }
        Commands::AddDevice { team_id, identity_pk, signing_pk, encoding_pk } => {
            let team_id = TeamId::from_str(&team_id)?;
            let identity = hex::decode(identity_pk).context("Invalid hex for identity key")?;
            let signing = hex::decode(signing_pk).context("Invalid hex for signing key")?;
            let encoding = hex::decode(encoding_pk).context("Invalid hex for encoding key")?;

            let key_bundle = KeyBundle {
                identity,
                signing,
                encoding,
            };

            let mut team = client.team(team_id);
            team.add_device_to_team(key_bundle).await?;
            println!("Device added to team {}", team_id);
        }
        Commands::RemoveDevice { team_id, device_id } => {
            let team_id = TeamId::from_str(&team_id)?;
            let device_id = DeviceId::from_str(&device_id)?;

            let mut team = client.team(team_id);
            team.remove_device_from_team(device_id).await?;
            println!("Device {} removed from team {}", device_id, team_id);
        }
        Commands::AssignRole { team_id, device_id, role } => {
            let team_id = TeamId::from_str(&team_id)?;
            let device_id = DeviceId::from_str(&device_id)?;
            let role = match role.as_str() {
                "Owner" => Role::Owner,
                "Admin" => Role::Admin,
                "Operator" => Role::Operator,
                "Member" => Role::Member,
                _ => anyhow::bail!("Invalid role: {}. Use Owner, Admin, Operator, or Member", role),
            };

            let mut team = client.team(team_id);
            team.assign_role(device_id, role).await?;
            println!("Role {:?} assigned to device {} on team {}", role, device_id, team_id);
        }
        Commands::ListDevices { team_id } => {
            let team_id = TeamId::from_str(&team_id)?;
            let mut team = client.team(team_id);
            let devices = team.queries().devices_on_team().await?;

            println!("Devices on team {}:", team_id);
            for device_id in devices.iter() {
                let role = team.queries().device_role(*device_id).await?;
                println!("  {} (Role: {:?})", device_id, role);
            }
        }
        Commands::DeviceInfo { team_id, device_id } => {
            let team_id = TeamId::from_str(&team_id)?;
            let device_id = if let Some(id) = device_id {
                DeviceId::from_str(&id)?
            } else {
                client.get_device_id().await?
            };

            let mut team = client.team(team_id);
            let role = team.queries().device_role(device_id).await?;
            let key_bundle = team.queries().device_keybundle(device_id).await?;
            let labels = team.queries().device_label_assignments(device_id).await?;
            let net_id = team.queries().aqc_net_identifier(device_id).await?;

            println!("Device Info for {} on team {}:", device_id, team_id);
            println!("  Role: {:?}", role);
            println!("  Identity Key: {}", hex::encode(&key_bundle.identity));
            println!("  Signing Key: {}", hex::encode(&key_bundle.signing));
            println!("  Encoding Key: {}", hex::encode(&key_bundle.encoding));
            println!("  Labels assigned: {}", labels.iter().count());
            for label in labels.iter() {
                println!("    {} ({})", label.id, label.name);
            }
            if let Some(net_id) = net_id {
                println!("  AQC Network ID: {}", net_id);
            } else {
                println!("  AQC Network ID: Not assigned");
            }
        }
        Commands::AddSyncPeer { team_id, peer_addr, interval_secs } => {
            let team_id = TeamId::from_str(&team_id)?;
            let addr = Addr::from_str(&peer_addr)?;
            let config = aranya_client::SyncPeerConfig::builder()
                .interval(Duration::from_secs(interval_secs))
                .build()?;

            let mut team = client.team(team_id);
            team.add_sync_peer(addr, config).await?;
            println!("Sync peer {} added to team {} with interval {}s", peer_addr, team_id, interval_secs);
        }
        Commands::SyncNow { team_id, peer_addr } => {
            let team_id = TeamId::from_str(&team_id)?;
            let addr = Addr::from_str(&peer_addr)?;

            let mut team = client.team(team_id);
            team.sync_now(addr, None).await?;
            println!("Sync completed with peer {} on team {}", peer_addr, team_id);
        }
        Commands::CreateLabel { team_id, label_name } => {
            let team_id = TeamId::from_str(&team_id)?;
            let mut team = client.team(team_id);
            let label_text: Text = label_name.clone().try_into()?;
            let label_id = team.create_label(label_text).await?;
            println!("Label '{}' created successfully", label_name);
            // Print the label ID in base58 format using the Display trait
            println!("Label ID: {}", label_id);
        }
        Commands::AssignLabel { team_id, device_id, label_id, operation } => {
            let team_id = TeamId::from_str(&team_id)?;
            let device_id = DeviceId::from_str(&device_id)?;
            
            // Try to parse the label ID with better error handling
            let label_id = match LabelId::from_str(&label_id) {
                Ok(id) => id,
                Err(e) => {
                    println!("Failed to parse label ID '{}': {}", label_id, e);
                    println!("Label ID should be a 32-byte hex string (64 characters)");
                    return Err(anyhow::anyhow!("Invalid label ID format: {}", e));
                }
            };
            
            let op = match operation.as_str() {
                "SendOnly" => ChanOp::SendOnly,
                "RecvOnly" => ChanOp::RecvOnly,
                "SendRecv" => ChanOp::SendRecv,
                _ => anyhow::bail!("Invalid operation: {}. Use SendOnly, RecvOnly, or SendRecv", operation),
            };

            let mut team = client.team(team_id);
            
            // Add debug information
            println!("Attempting to assign label {} to device {} on team {} with operation {:?}", 
                    label_id, device_id, team_id, op);
            
            team.assign_label(device_id, label_id, op).await?;
            println!("Label {} assigned to device {} with operation {:?}", label_id, device_id, op);
        }
        Commands::AssignAqcNetId { team_id, device_id, net_id } => {
            let team_id = TeamId::from_str(&team_id)?;
            let device_id = DeviceId::from_str(&device_id)?;
            let net_text: Text = net_id.clone().try_into()?;
            let net_identifier = NetIdentifier(net_text);

            let mut team = client.team(team_id);
            team.assign_aqc_net_identifier(device_id, net_identifier).await?;
            println!("AQC network identifier {} assigned to device {}", net_id, device_id);
        }
        Commands::ListLabelAssignments { team_id, device_id } => {
            let team_id = TeamId::from_str(&team_id)?;
            let device_id = DeviceId::from_str(&device_id)?;

            let mut team = client.team(team_id);
            let labels = team.queries().device_label_assignments(device_id).await?;

            println!("Label assignments for device {} on team {}:", device_id, team_id);
            for label in labels.iter() {
                println!("  {} ({})", label.id, label.name);
            }
        }
        Commands::ListAqcAssignments { team_id } => {
            let team_id = TeamId::from_str(&team_id)?;
            let mut team = client.team(team_id);
            let devices = team.queries().devices_on_team().await?;

            println!("AQC network assignments for team {}:", team_id);
            for device_id in devices.iter() {
                if let Ok(Some(net_id)) = team.queries().aqc_net_identifier(*device_id).await {
                    println!("  {}: {}", device_id, net_id);
                }
            }
        }
        Commands::SendData { team_id, device_id, label_id, message } => {
            let team_id = TeamId::from_str(&team_id)?;
            let device_id = DeviceId::from_str(&device_id)?;
            let label_id = LabelId::from_str(&label_id)?;
            
            // Get the target device's network identifier
            let mut team = client.team(team_id);
            let net_id = team.queries().aqc_net_identifier(device_id).await?
                .ok_or_else(|| anyhow::anyhow!("Device {} has no AQC network identifier assigned", device_id))?;
            
            // Create a new bidirectional channel (fresh PSKs)
            let mut aqc = client.aqc();
            let mut channel = aqc.create_bidi_channel(team_id, net_id, label_id).await?;
            
            // Send data through the channel
            let mut stream = channel.create_uni_stream().await?;
            let message_bytes = Bytes::from(message.clone().into_bytes());
            stream.send(message_bytes).await?;
            stream.close().await?;
            
            // Close the channel to ensure PSKs are destroyed
            aqc.delete_bidi_channel(channel).await?;
            
            println!("Data sent to device {} with label {} (Channel closed, PSKs destroyed)", device_id, label_id);
        }
        Commands::ListenData { team_id, device_id, label_id, timeout } => {
            let team_id = TeamId::from_str(&team_id)?;
            let device_id = DeviceId::from_str(&device_id)?;
            let label_id = LabelId::from_str(&label_id)?;

            println!("Listening for data from device {} with label {} (timeout: {}s)...", device_id, label_id, timeout);
            
            // Create a new channel for receiving (fresh PSKs)
            let mut aqc = client.aqc();
            let mut channel = aqc.receive_channel().await?;
            
            // Set up timeout
            let timeout_duration = if timeout == 0 {
                Duration::from_secs(u64::MAX)
            } else {
                Duration::from_secs(timeout)
            };
            
            // Wait for data with timeout
            let start = std::time::Instant::now();
            let mut received_data = Vec::new();
            
            while start.elapsed() < timeout_duration {
                match channel {
                    aranya_client::aqc::AqcPeerChannel::Bidi(ref mut bidi_channel) => {
                        match bidi_channel.try_receive_stream() {
                            Ok(stream) => {
                                match stream {
                                    aranya_client::aqc::AqcPeerStream::Receive(mut recv_stream) => {
                                        while let Ok(data) = recv_stream.receive().await {
                                            if let Some(chunk) = data {
                                                received_data.extend_from_slice(&chunk);
                                            } else {
                                                break; // Stream closed
                                            }
                                        }
                                        let message = String::from_utf8(received_data)?;
                                        println!("Data received from device {} with label {}: {}", device_id, label_id, message);
                                        return Ok(());
                                    }
                                    aranya_client::aqc::AqcPeerStream::Bidi(mut bidi_stream) => {
                                        while let Ok(data) = bidi_stream.receive().await {
                                            if let Some(chunk) = data {
                                                received_data.extend_from_slice(&chunk);
                                            } else {
                                                break; // Stream closed
                                            }
                                        }
                                        let message = String::from_utf8(received_data)?;
                                        println!("Data received from device {} with label {}: {}", device_id, label_id, message);
                                        return Ok(());
                                    }
                                }
                            }
                            Err(aranya_client::aqc::TryReceiveError::Empty) => {
                                // No data available, continue waiting
                                tokio::time::sleep(Duration::from_millis(100)).await;
                                continue;
                            }
                            Err(aranya_client::aqc::TryReceiveError::Closed) => {
                                println!("Channel closed while waiting for data");
                                return Ok(());
                            }
                            Err(aranya_client::aqc::TryReceiveError::Error(e)) => {
                                return Err(anyhow::anyhow!("Error receiving data: {:?}", e));
                            }
                        }
                    }
                    aranya_client::aqc::AqcPeerChannel::Receive(ref mut recv_channel) => {
                        match recv_channel.try_receive_uni_stream() {
                            Ok(mut recv_stream) => {
                                while let Ok(data) = recv_stream.receive().await {
                                    if let Some(chunk) = data {
                                        received_data.extend_from_slice(&chunk);
                                    } else {
                                        break; // Stream closed
                                    }
                                }
                                let message = String::from_utf8(received_data)?;
                                println!("Data received from device {} with label {}: {}", device_id, label_id, message);
                                return Ok(());
                            }
                            Err(aranya_client::aqc::TryReceiveError::Empty) => {
                                // No data available, continue waiting
                                tokio::time::sleep(Duration::from_millis(100)).await;
                                continue;
                            }
                            Err(aranya_client::aqc::TryReceiveError::Closed) => {
                                println!("Channel closed while waiting for data");
                                return Ok(());
                            }
                            Err(aranya_client::aqc::TryReceiveError::Error(e)) => {
                                return Err(anyhow::anyhow!("Error receiving data: {:?}", e));
                            }
                        }
                    }
                }
            }
            
            println!("Timeout reached, no data received");
        }
        Commands::ShowChannels { team_id } => {
            let team_id = TeamId::from_str(&team_id)?;
            println!("Note: AQC channels are ephemeral and automatically closed after use for PSK rotation");
            println!("Active channels cannot be listed as they are created fresh for each communication");
            println!("This ensures perfect forward secrecy through PSK rotation");
        }
    }

    Ok(())
}

async fn connect_to_daemon(uds_path: &PathBuf, aqc_addr: &str) -> Result<Client> {
    let aqc_addr = Addr::from_str(aqc_addr)?;
    
    let client = Client::builder()
        .with_daemon_uds_path(uds_path)
        .with_daemon_aqc_addr(&aqc_addr)
        .connect()
        .await?;

    Ok(client)
}