use anyhow::{Context, Result};
use aranya_client::{
    Client, QuicSyncConfig, TeamConfig,
};
use aranya_daemon_api::{DeviceId, KeyBundle, Role, TeamId, LabelId, NetIdentifier, ChanOp};
use aranya_util::Addr;
use clap::{Parser, Subcommand};
use std::path::PathBuf;
use std::str::FromStr;
use std::time::Duration;
use bytes::Bytes;

#[derive(Parser)]
#[command(name = "aranya")]
#[command(author, version, about = "Aranya CLI tool for team and device management", long_about = None)]
struct Cli {
    /// Path to daemon's Unix Domain Socket
    #[arg(short = 'u', long, env = "ARANYA_UDS_PATH", default_value = "/var/run/aranya/uds.sock")]
    uds_path: PathBuf,

    /// Daemon's AQC address
    #[arg(short = 'a', long, env = "ARANYA_AQC_ADDR", default_value = "127.0.0.1:0")]
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
    /// List all teams
    ListTeams,
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
    /// Create an AQC label for data channels
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
    /// Send data via AQC bidirectional channel
    SendData {
        /// Team ID
        team_id: String,
        /// Peer network identifier
        peer_net_id: String,
        /// Label ID for the channel
        label_id: String,
        /// Data to send (as text)
        data: String,
    },
    /// Listen for incoming AQC data
    ListenData {
        /// Team ID
        team_id: String,
        /// Timeout in seconds (optional)
        #[arg(long, default_value = "30")]
        timeout_secs: u64,
    },
    /// Show active AQC channels and their PSK identities (DEMO ONLY - INSECURE)
    ShowChannels {
        /// Team ID
        team_id: String,
    },
    /// Show PSK details for demonstration (DEMO ONLY - INSECURE)
    ShowChannelPsks {
        /// Team ID
        team_id: String,
        /// Channel ID (hex)
        channel_id: String,
    },
    /// List all PSKs for demonstration (DEMO ONLY - INSECURE)
    ShowAllPsks {
        /// Team ID
        team_id: String,
    },
    /// List label assignments
    ListLabelAssignments {
        /// Team ID
        team_id: String,
    },
    /// List AQC network assignments
    ListAqcAssignments {
        /// Team ID
        team_id: String,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    // Initialize tracing
    let filter = if cli.verbose {
        "aranya_cli=debug,aranya_client=debug"
    } else {
        "aranya_cli=info"
    };
    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .init();

    // Connect to daemon
    let mut client = connect_to_daemon(&cli.uds_path, &cli.aqc_addr).await?;

    match cli.command {
        Commands::CreateTeam { seed_ikm } => {
            let mut ikm = [0u8; 32];
            if let Some(hex_ikm) = seed_ikm {
                let bytes = hex::decode(&hex_ikm)
                    .context("Invalid hex for seed IKM")?;
                if bytes.len() != 32 {
                    anyhow::bail!("Seed IKM must be exactly 32 bytes");
                }
                ikm.copy_from_slice(&bytes);
            } else {
                client.rand(&mut ikm).await;
            }

            let team_config = TeamConfig::builder()
                .quic_sync(QuicSyncConfig::builder().seed_ikm(ikm).build()?)
                .build()?;

            let team = client.create_team(team_config).await
                .context("Failed to create team")?;
            
            println!("Team created successfully");
            println!("Team ID: {}", team.team_id());
            println!("Seed IKM: {}", hex::encode(ikm));
        }

        Commands::AddTeam { team_id, seed_ikm } => {
            let team_id = TeamId::from_str(&team_id)
                .context("Invalid team ID")?;
            
            let ikm_bytes = hex::decode(&seed_ikm)
                .context("Invalid hex for seed IKM")?;
            if ikm_bytes.len() != 32 {
                anyhow::bail!("Seed IKM must be exactly 32 bytes");
            }
            let mut ikm = [0u8; 32];
            ikm.copy_from_slice(&ikm_bytes);

            let team_config = TeamConfig::builder()
                .quic_sync(QuicSyncConfig::builder().seed_ikm(ikm).build()?)
                .build()?;

            client.add_team(team_id, team_config).await
                .context("Failed to add team")?;
            
            println!("Team added successfully");
        }

        Commands::RemoveTeam { team_id } => {
            let team_id = TeamId::from_str(&team_id)
                .context("Invalid team ID")?;
            
            client.remove_team(team_id).await
                .context("Failed to remove team")?;
            
            println!("Team removed successfully");
        }

        Commands::AddDevice { team_id, identity_pk, signing_pk, encoding_pk } => {
            let team_id = TeamId::from_str(&team_id)
                .context("Invalid team ID")?;
            
            let identity_pk_bytes = hex::decode(&identity_pk)
                .context("Invalid hex for identity public key")?;
            let signing_pk_bytes = hex::decode(&signing_pk)
                .context("Invalid hex for signing public key")?;
            let encoding_pk_bytes = hex::decode(&encoding_pk)
                .context("Invalid hex for encoding public key")?;

            let keybundle = KeyBundle {
                identity: identity_pk_bytes,
                signing: signing_pk_bytes,
                encoding: encoding_pk_bytes,
            };

            let mut team = client.team(team_id);
            
            team.add_device_to_team(keybundle).await
                .context("Failed to add device to team")?;
            
            println!("Device added successfully");
            println!("Note: The device ID will be visible once the device joins the team");
        }

        Commands::RemoveDevice { team_id, device_id } => {
            let team_id = TeamId::from_str(&team_id)
                .context("Invalid team ID")?;
            let device_id = DeviceId::from_str(&device_id)
                .context("Invalid device ID")?;
            
            let mut team = client.team(team_id);
            
            team.remove_device_from_team(device_id).await
                .context("Failed to remove device from team")?;
            
            println!("Device removed successfully");
        }

        Commands::AssignRole { team_id, device_id, role } => {
            let team_id = TeamId::from_str(&team_id)
                .context("Invalid team ID")?;
            let device_id = DeviceId::from_str(&device_id)
                .context("Invalid device ID")?;
            
            let role = match role.to_lowercase().as_str() {
                "owner" => Role::Owner,
                "admin" => Role::Admin,
                "operator" => Role::Operator,
                "member" => Role::Member,
                _ => anyhow::bail!("Invalid role. Must be: Owner, Admin, Operator, or Member"),
            };
            
            let mut team = client.team(team_id);
            
            team.assign_role(device_id, role).await
                .context("Failed to assign role")?;
            
            println!("Role assigned successfully");
        }

        Commands::ListDevices { team_id } => {
            let team_id = TeamId::from_str(&team_id)
                .context("Invalid team ID")?;
            
            let mut team = client.team(team_id);
            
            let devices = team.queries().devices_on_team().await
                .context("Failed to list devices")?;
            
            println!("Devices on team {}:", team_id);
            println!("{:<66} {:<10}", "Device ID", "Role");
            println!("{}", "-".repeat(76));
            
            for device_id in devices.iter() {
                let role = match team.queries().device_role(*device_id).await {
                    Ok(role) => format!("{:?}", role),
                    Err(_) => "Unknown".to_string(),
                };
                
                println!("{:<66} {:<10}", device_id, role);
            }
        }

        Commands::ListTeams => {
            // Note: The API doesn't provide a way to list all teams
            // This would need to be implemented in the daemon
            println!("Listing teams is not yet implemented in the daemon API");
        }

        Commands::DeviceInfo { team_id, device_id } => {
            let team_id = TeamId::from_str(&team_id)
                .context("Invalid team ID")?;
            
            let device_id = if let Some(id) = device_id {
                DeviceId::from_str(&id).context("Invalid device ID")?
            } else {
                // Get current device ID from the client before creating team reference
                client.get_device_id().await
                    .context("Failed to get current device ID")?
            };
            
            let mut team = client.team(team_id);
            
            let keybundle = team.queries().device_keybundle(device_id).await
                .context("Failed to get device keybundle")?;
            let role = team.queries().device_role(device_id).await
                .context("Failed to get device role")?;
            
            println!("Device Information:");
            println!("  Device ID: {}", device_id);
            println!("  Role: {:?}", role);
            println!("  Keys:");
            println!("    Identity:  {}", hex::encode(&keybundle.identity));
            println!("    Signing:   {}", hex::encode(&keybundle.signing));
            println!("    Encoding:  {}", hex::encode(&keybundle.encoding));
        }

        Commands::AddSyncPeer { team_id, peer_addr, interval_secs } => {
            let team_id = TeamId::from_str(&team_id)
                .context("Invalid team ID")?;
            
            let mut team = client.team(team_id);
            
            let sync_config = aranya_client::SyncPeerConfig::builder()
                .interval(Duration::from_secs(interval_secs))
                .build()?;
            
            team.add_sync_peer(peer_addr.parse()?, sync_config).await
                .context("Failed to add sync peer")?;
            
            println!("Sync peer added successfully");
            println!("Peer will be synced every {} seconds", interval_secs);
        }

        Commands::SyncNow { team_id, peer_addr } => {
            let team_id = TeamId::from_str(&team_id)
                .context("Invalid team ID")?;
            
            let mut team = client.team(team_id);
            
            team.sync_now(peer_addr.parse()?, None).await
                .context("Failed to sync with peer")?;
            
            println!("Sync completed successfully");
        }

        Commands::CreateLabel { team_id, label_name } => {
            let team_id = TeamId::from_str(&team_id)
                .context("Invalid team ID")?;
            
            let mut team = client.team(team_id);
            let label_name = label_name.try_into()
                .context("Invalid label name")?;
            let label_id = team.create_label(label_name).await
                .context("Failed to create label")?;
            
            println!("Label created successfully");
            println!("Label ID: {}", hex::encode(label_id.as_bytes()));
        }

        Commands::AssignLabel { team_id, device_id, label_id, operation } => {
            let team_id = TeamId::from_str(&team_id)
                .context("Invalid team ID")?;
            let device_id = DeviceId::from_str(&device_id)
                .context("Invalid device ID")?;
            let label_id = LabelId::from_str(&label_id)
                .context("Invalid label ID")?;
            
            let operation = match operation.to_lowercase().as_str() {
                "sendonly" => ChanOp::SendOnly,
                "recvonly" => ChanOp::RecvOnly,
                "sendrecv" => ChanOp::SendRecv,
                _ => anyhow::bail!("Invalid channel operation. Must be: SendOnly, RecvOnly, or SendRecv"),
            };

            let mut team = client.team(team_id);
            
            team.assign_label(device_id, label_id, operation).await
                .context("Failed to assign label")?;
            
            println!("Label assigned successfully");
        }

        Commands::AssignAqcNetId { team_id, device_id, net_id } => {
            let team_id = TeamId::from_str(&team_id)
                .context("Invalid team ID")?;
            let device_id = DeviceId::from_str(&device_id)
                .context("Invalid device ID")?;
            
            let net_identifier = NetIdentifier(net_id.try_into()
                .context("Invalid network identifier")?);

            let mut team = client.team(team_id);
            
            team.assign_aqc_net_identifier(device_id, net_identifier).await
                .context("Failed to assign network identifier")?;
            
            println!("Network identifier assigned successfully");
        }

        Commands::SendData { team_id, peer_net_id, label_id, data } => {
            let team_id = TeamId::from_str(&team_id)
                .context("Invalid team ID")?;
            
            let peer_net_id = NetIdentifier(peer_net_id.try_into()
                .context("Invalid peer network identifier")?);
            let label_id = LabelId::from_str(&label_id)
                .context("Invalid label ID")?;
            
            // Create AQC bidirectional channel and send data
            let mut aqc = client.aqc();
            let mut bidi_channel = aqc.create_bidi_channel(team_id, peer_net_id, label_id).await
                .context("Failed to create bidirectional channel")?;
            
            // Create a stream and send data
            let mut stream = bidi_channel.create_bidi_stream().await
                .context("Failed to create bidirectional stream")?;
            
            let data_bytes = Bytes::from(data.into_bytes());
            stream.send(data_bytes).await
                .context("Failed to send data")?;
            
            stream.close().await
                .context("Failed to close stream")?;
            
            println!("Data sent successfully");
        }

        Commands::ListenData { team_id, timeout_secs } => {
            let _team_id = TeamId::from_str(&team_id)
                .context("Invalid team ID")?;
            
            println!("Listening for incoming AQC channels (timeout: {} seconds)...", timeout_secs);
            
            let mut aqc = client.aqc();
            
            // Set up timeout
            let timeout = Duration::from_secs(timeout_secs);
            let listen_result = tokio::time::timeout(timeout, async {
                // Wait for incoming channel
                let peer_channel = aqc.receive_channel().await?;
                
                match peer_channel {
                    aranya_client::aqc::AqcPeerChannel::Bidi(mut bidi_channel) => {
                        println!("Received bidirectional channel from peer");
                        
                        // Wait for incoming stream
                        let peer_stream = bidi_channel.receive_stream().await?;
                        
                        match peer_stream {
                            aranya_client::aqc::AqcPeerStream::Bidi(mut bidi_stream) => {
                                // Receive data
                                if let Some(data) = bidi_stream.receive().await? {
                                    let data_str = String::from_utf8(data.to_vec())
                                        .context("Failed to decode received data")?;
                                    println!("Received data: {}", data_str);
                                } else {
                                    println!("No data received (stream closed)");
                                }
                            }
                            aranya_client::aqc::AqcPeerStream::Receive(mut recv_stream) => {
                                if let Some(data) = recv_stream.receive().await? {
                                    let data_str = String::from_utf8(data.to_vec())
                                        .context("Failed to decode received data")?;
                                    println!("Received data: {}", data_str);
                                } else {
                                    println!("No data received (stream closed)");
                                }
                            }
                        }
                    }
                    aranya_client::aqc::AqcPeerChannel::Receive(mut recv_channel) => {
                        println!("Received unidirectional channel from peer");
                        
                        // Wait for incoming stream
                        let mut recv_stream = recv_channel.receive_uni_stream().await?;
                        
                        // Receive data
                        if let Some(data) = recv_stream.receive().await? {
                            let data_str = String::from_utf8(data.to_vec())
                                .context("Failed to decode received data")?;
                            println!("Received data: {}", data_str);
                        } else {
                            println!("No data received (stream closed)");
                        }
                    }
                }
                
                Ok::<(), anyhow::Error>(())
            }).await;
            
            match listen_result {
                Ok(Ok(())) => {
                    println!("Data received successfully");
                }
                Ok(Err(e)) => {
                    return Err(e.context("Failed to receive data"));
                }
                Err(_) => {
                    println!("Timeout reached. No data received.");
                }
            }
        }

        Commands::ListAqcAssignments { team_id } => {
            let team_id = TeamId::from_str(&team_id)
                .context("Invalid team ID")?;
            
            let mut team = client.team(team_id);
            let devices = team.queries().devices_on_team().await
                .context("Failed to get devices on team")?;
            
            println!("AQC Network Assignments for Team {}", hex::encode(team_id.as_bytes()));
            println!("┌─────────────────────────────────────────────────┬──────────────────────────────────────┐");
            println!("│ Device ID                                       │ Network Identifier                  │");
            println!("├─────────────────────────────────────────────────┼──────────────────────────────────────┤");
            
            for device in devices.iter() {
                let net_id = team.queries().aqc_net_identifier(*device).await
                    .context("Failed to get AQC network identifier")?;
                let net_id_str = net_id.map(|n| n.to_string()).unwrap_or_else(|| "None".to_string());
                println!("│ {:47} │ {:36} │", 
                    hex::encode(device.as_bytes()), 
                    net_id_str);
            }
            println!("└─────────────────────────────────────────────────┴──────────────────────────────────────┘");
        }

        Commands::ShowChannels { team_id } => {
            let _team_id = TeamId::from_str(&team_id)
                .context("Invalid team ID")?;

            // For demonstration, we'll show that this would require internal daemon access
            println!("Active AQC Channels for Team {}", hex::encode(_team_id.as_bytes()));
            println!("┌────────────────────────────────────────┬──────────────────┬─────────────────────────────────────┐");
            println!("│ Channel ID                             │ Type             │ PSK Identity (truncated)           │");
            println!("├────────────────────────────────────────┼──────────────────┼─────────────────────────────────────┤");
            
            // Note: This would require additional daemon APIs to list active channels
            // For now, we'll show a message about the limitation
            println!("│ (Feature requires additional daemon   │                  │                                     │");
            println!("│  APIs for listing active channels)    │                  │                                     │");
            println!("└────────────────────────────────────────┴──────────────────┴─────────────────────────────────────┘");
            
            println!("\n💡 To see PSKs in action:");
            println!("   1. Create a label: aranya create-label <team-id> <label-name>");
            println!("   2. Assign network IDs to devices: aranya assign-aqc-net-id <team-id> <device-id> <address>");
            println!("   3. Send data and observe PSK generation: aranya send-data <team-id> <peer-net-id> <label-id> <message>");
        }

        Commands::ShowChannelPsks { team_id, channel_id } => {
            println!("⚠️  CRITICAL SECURITY WARNING!");
            println!("⚠️  This command exposes actual PSK secrets for demonstration purposes ONLY!");
            println!("⚠️  PSK secrets should NEVER be displayed in production environments!");
            println!("⚠️  This demonstrates the ephemeral nature of Aranya's key management.\n");
            
            let _team_id = TeamId::from_str(&team_id)
                .context("Invalid team ID")?;
            
            println!("PSK Details for Channel {}", channel_id);
            println!("Team: {}", hex::encode(_team_id.as_bytes()));
            println!("\n📝 Note: This feature requires additional daemon APIs to retrieve channel PSKs.");
            println!("         In a real implementation, you would:");
            println!("         1. Query the daemon for channel information");
            println!("         2. Retrieve PSK identities and secrets per cipher suite");
            println!("         3. Display cipher suite mappings and PSK rotation information");
            
            println!("\n🔑 PSK Structure (Example):");
            println!("   • Identity: 34-byte identifier (channel_id + cipher_suite + direction)");
            println!("   • Secret: 32-byte cryptographic key material");
            println!("   • Cipher Suite: TLS_AES_256_GCM_SHA384, TLS_CHACHA20_POLY1305_SHA256, etc.");
            println!("   • Direction: Bidirectional or Unidirectional (Send/Recv)");
        }

        Commands::ShowAllPsks { team_id } => {
            println!("⚠️  EXTREME SECURITY WARNING!");
            println!("⚠️  This command would expose ALL PSK secrets for a team!");
            println!("⚠️  This is for demonstration purposes ONLY to show key lifecycle!");
            println!("⚠️  NEVER use this in production - it compromises all channel security!\n");
            
            let team_id = TeamId::from_str(&team_id)
                .context("Invalid team ID")?;
            
            println!("All PSKs for Team {}", hex::encode(team_id.as_bytes()));
            println!("\n🔐 Demonstrating Aranya's Ephemeral Key Management:");
            println!("   ✓ Each channel gets unique PSKs per cipher suite");
            println!("   ✓ PSKs are generated on-demand when channels are created");
            println!("   ✓ PSKs are automatically rotated/destroyed when channels close");
            println!("   ✓ No persistent storage of channel secrets");
            
            println!("\n📊 Expected PSK Categories:");
            println!("   • Bidirectional Channel PSKs: For two-way data streams");
            println!("   • Unidirectional Channel PSKs: For one-way data streams (Send/Recv)");
            println!("   • Control Channel PSKs: For AQC protocol control messages");
            
            println!("\n💡 To observe real PSK generation:");
            println!("   1. Enable debug logging on the daemon");
            println!("   2. Create channels between two devices");
            println!("   3. Watch PSK generation in daemon logs");
            println!("   4. Close channels and observe PSK cleanup");
            
            println!("\n🎯 This demonstrates Aranya's 'zero-knowledge' approach:");
            println!("   • Keys exist only during active communication");
            println!("   • No long-term secret storage");
            println!("   • Perfect forward secrecy through ephemeral keys");
        }

        Commands::ListLabelAssignments { team_id } => {
            let team_id = TeamId::from_str(&team_id)
                .context("Invalid team ID")?;
            
            let mut team = client.team(team_id);
            let devices = team.queries().devices_on_team().await
                .context("Failed to get devices on team")?;
            
            println!("Label Assignments for Team {}", hex::encode(team_id.as_bytes()));
            println!("┌─────────────────────────────────────────────────┬──────────────────────────────────────┐");
            println!("│ Device ID                                       │ Assigned Labels                      │");
            println!("├─────────────────────────────────────────────────┼──────────────────────────────────────┤");
            
            for device in devices.iter() {
                let labels = team.queries().device_label_assignments(*device).await
                    .context("Failed to get device label assignments")?;
                
                let label_str = if labels.iter().count() == 0 {
                    "None".to_string()
                } else {
                    labels.iter()
                        .map(|label| format!("{}:{}", label.name, hex::encode(label.id.as_bytes())[..8].to_string()))
                        .collect::<Vec<_>>()
                        .join(", ")
                };
                
                println!("│ {:47} │ {:36} │", 
                    hex::encode(device.as_bytes()), 
                    label_str);
            }
            println!("└─────────────────────────────────────────────────┴──────────────────────────────────────┘");
        }
    }

    Ok(())
}

async fn connect_to_daemon(uds_path: &PathBuf, aqc_addr: &str) -> Result<Client> {
    let addr = aqc_addr.parse::<Addr>()
        .context("Invalid AQC address")?;
    
    let mut attempts = 0;
    let max_attempts = 5;
    let mut delay = Duration::from_millis(100);

    loop {
        match Client::builder()
            .with_daemon_uds_path(uds_path)
            .with_daemon_aqc_addr(&addr)
            .connect()
            .await
        {
            Ok(client) => return Ok(client),
            Err(e) if attempts < max_attempts => {
                tracing::debug!("Connection attempt {} failed: {}. Retrying in {:?}...", 
                    attempts + 1, e, delay);
                tokio::time::sleep(delay).await;
                delay *= 2;
                attempts += 1;
            }
            Err(e) => {
                return Err(anyhow::anyhow!("Failed to connect to daemon after {} attempts: {}", 
                    max_attempts, e));
            }
        }
    }
}