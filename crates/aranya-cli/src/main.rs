use anyhow::{Context, Result};
use aranya_client::{
    Client, QuicSyncConfig, TeamConfig,
};
use aranya_daemon_api::{DeviceId, KeyBundle, Role, TeamId};
use aranya_util::Addr;
use clap::{Parser, Subcommand};
use std::path::PathBuf;
use std::str::FromStr;
use std::time::Duration;

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