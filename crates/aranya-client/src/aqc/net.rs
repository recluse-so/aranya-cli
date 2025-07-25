#![warn(missing_docs)]

//! The AQC network implementation.

use std::{
    collections::HashMap,
    net::{Ipv4Addr, SocketAddr},
    sync::Arc,
    task::{Context, Poll, Waker},
};

use aranya_crypto::aqc::{BidiChannelId, UniChannelId};
use aranya_daemon_api::{
    AqcBidiPsks, AqcCtrl, AqcPsks, AqcUniPsks, DaemonApiClient, LabelId, TeamId,
};
use aranya_util::rustls::{NoCertResolver, SkipServerVerification};
use buggy::{Bug, BugExt as _};
use bytes::{Bytes, BytesMut};
use channels::AqcPeerChannel;
use s2n_quic::{
    self,
    client::Connect,
    provider::{
        congestion_controller::Bbr,
        tls::rustls::{
            self as rustls_provider,
            rustls::{server::PresharedKeySelection, ClientConfig, ServerConfig},
        },
    },
    stream::BidirectionalStream,
    Client, Connection, Server,
};
use tarpc::context;
use tokio::sync::mpsc;
use tracing::{debug, error, warn};

use super::crypto::{ClientPresharedKeys, ServerPresharedKeys, CTRL_PSK, PSK_IDENTITY_CTRL};
use crate::error::{aranya_error, AqcError, IpcError};

pub mod channels;

/// ALPN protocol identifier for Aranya QUIC Channels
const ALPN_AQC: &[u8] = b"aqc-v1";

/// An AQC client. Used to create and receive channels.
#[derive(Debug)]
pub(crate) struct AqcClient {
    /// Quic client used to create channels with peers.
    quic_client: Client,
    /// Key provider for `quic_client`.
    ///
    /// Modifying this will change the keys used by `quic_client`.
    client_keys: Arc<ClientPresharedKeys>,

    /// Quic server used to accept channels from peers.
    quic_server: Server,
    /// Key provider for `quic_server`.
    ///
    /// Inserting to this will add keys which the `server` will accept.
    server_keys: Arc<ServerPresharedKeys>,
    /// Receives latest selected PSK for accepted channel from server PSK provider.
    identity_rx: mpsc::Receiver<PskIdentity>,

    /// Map of PSK identity to channel type
    channels: HashMap<PskIdentity, AqcChannelInfo>,

    daemon: DaemonApiClient,
}

/// Identity of a preshared key.
type PskIdentity = Vec<u8>;

impl AqcClient {
    pub async fn new(server_addr: SocketAddr, daemon: DaemonApiClient) -> Result<Self, AqcError> {
        let client_keys = Arc::new(ClientPresharedKeys::new(CTRL_PSK.clone()));

        // Create Client Config (INSECURE: Skips server cert verification)
        let mut client_config = ClientConfig::builder()
            .dangerous()
            .with_custom_certificate_verifier(SkipServerVerification::new())
            .with_no_client_auth();
        client_config.alpn_protocols = vec![ALPN_AQC.to_vec()]; // Set field directly
        client_config.preshared_keys = client_keys.clone(); // Pass the Arc<ClientPresharedKeys>

        // TODO(jdygert): enable after rustls upstream fix.
        // client_config.psk_kex_modes = vec![PskKexMode::PskOnly];

        let (server_keys, identity_rx) = ServerPresharedKeys::new();
        server_keys.insert(CTRL_PSK.clone());
        let server_keys = Arc::new(server_keys);

        // Create Server Config
        let mut server_config = ServerConfig::builder()
            .with_no_client_auth()
            .with_cert_resolver(Arc::new(NoCertResolver::default()));
        server_config.alpn_protocols = vec![ALPN_AQC.to_vec()]; // Set field directly
        server_config.preshared_keys =
            PresharedKeySelection::Required(Arc::clone(&server_keys) as _);

        #[allow(deprecated)]
        let tls_client_provider = rustls_provider::Client::new(client_config);
        #[allow(deprecated)]
        let tls_server_provider = rustls_provider::Server::new(server_config);

        // Use the rustls server provider
        let server = Server::builder()
            .with_tls(tls_server_provider)? // Use the wrapped server config
            .with_io(server_addr)
            .assume("can set aqc server addr")?
            .with_congestion_controller(Bbr::default())?
            .start()?;

        let quic_client = Client::builder()
            .with_tls(tls_client_provider)?
            .with_io((Ipv4Addr::UNSPECIFIED, 0))
            .assume("can set aqc client addr")?
            .start()?;

        Ok(AqcClient {
            quic_client,
            client_keys,
            server_keys,
            channels: HashMap::new(),
            quic_server: server,
            daemon,
            identity_rx,
        })
    }

    /// Get the client address.
    pub fn client_addr(&self) -> Result<SocketAddr, Bug> {
        self.quic_client.local_addr().assume("can get local addr")
    }

    /// Get the server address.
    pub fn server_addr(&self) -> Result<SocketAddr, Bug> {
        self.quic_server.local_addr().assume("can get local addr")
    }

    /// Creates a new unidirectional channel to the given address.
    pub async fn create_uni_channel(
        &mut self,
        addr: SocketAddr,
        label_id: LabelId,
        psks: AqcUniPsks,
    ) -> Result<channels::AqcSendChannel, AqcError> {
        let channel_id = UniChannelId::from(*psks.channel_id());
        self.client_keys.load_psks(AqcPsks::Uni(psks));
        let mut conn = self
            .quic_client
            .connect(Connect::new(addr).with_server_name(addr.ip().to_string()))
            .await?;
        conn.keep_alive(true)?;
        Ok(channels::AqcSendChannel::new(
            label_id,
            channel_id,
            conn.handle(),
        ))
    }

    /// Creates a new bidirectional channel to the given address.
    pub async fn create_bidi_channel(
        &mut self,
        addr: SocketAddr,
        label_id: LabelId,
        psks: AqcBidiPsks,
    ) -> Result<channels::AqcBidiChannel, AqcError> {
        let channel_id = BidiChannelId::from(*psks.channel_id());
        self.client_keys.load_psks(AqcPsks::Bidi(psks));
        let mut conn = self
            .quic_client
            .connect(Connect::new(addr).with_server_name(addr.ip().to_string()))
            .await?;
        conn.keep_alive(true)?;
        Ok(channels::AqcBidiChannel::new(label_id, channel_id, conn))
    }

    /// Receive the next available channel.
    pub async fn receive_channel(&mut self) -> crate::Result<AqcPeerChannel> {
        loop {
            // Accept a new connection
            let mut conn = self
                .quic_server
                .accept()
                .await
                .ok_or(AqcError::ServerConnectionTerminated)?;
            // Receive a PSK identity hint.
            // TODO: Instead of receiving the PSK identity hint here, we should
            // pull it directly from the connection.
            let identity = self
                .identity_rx
                .try_recv()
                .assume("identity received after accepting connection")?;
            debug!(
                "Processing connection accepted after seeing PSK identity hint: {:02x?}",
                identity
            );
            // If the PSK identity hint is the control PSK, receive a control message.
            // This will update the channel map with the PSK and associate it with an
            // AqcChannel.
            if identity == PSK_IDENTITY_CTRL {
                self.receive_ctrl_message(&mut conn).await?;
                continue;
            }
            // If the PSK identity hint is not the control PSK, check if it's in the channel map.
            // If it is, create a channel of the appropriate type. We should have already received
            // the control message for this PSK, if we don't we can't create a channel.
            let channel_info = self.channels.get(&identity).ok_or_else(|| {
                warn!(
                    "No channel info found in map for identity hint {:02x?}",
                    identity
                );
                AqcError::NoChannelInfoFound
            })?;
            return Ok(AqcPeerChannel::new(
                channel_info.label_id,
                channel_info.channel_id,
                conn,
            ));
        }
    }

    /// Receive the next available channel.
    ///
    /// If there is no channel available, return Empty.
    /// If the channel is closed, return Closed.
    pub fn try_receive_channel(&mut self) -> Result<AqcPeerChannel, TryReceiveError<crate::Error>> {
        let mut cx = Context::from_waker(Waker::noop());
        loop {
            // Accept a new connection
            let mut conn = match self.quic_server.poll_accept(&mut cx) {
                Poll::Ready(Some(conn)) => conn,
                Poll::Ready(None) => {
                    return Err(TryReceiveError::Error(
                        AqcError::ServerConnectionTerminated.into(),
                    ));
                }
                Poll::Pending => {
                    return Err(TryReceiveError::Empty);
                }
            };
            // Receive a PSK identity hint.
            // TODO: Instead of receiving the PSK identity hint here, we should
            // pull it directly from the connection.
            let identity = self
                .identity_rx
                .try_recv()
                .assume("identity received after accepting connection")
                .map_err(|e| TryReceiveError::Error(e.into()))?;
            debug!(
                "Processing connection accepted after seeing PSK identity hint: {:02x?}",
                identity
            );
            // If the PSK identity hint is the control PSK, receive a control message.
            // This will update the channel map with the PSK and associate it with an
            // AqcChannel.
            if identity == PSK_IDENTITY_CTRL {
                // Block on the async function
                let result = futures_lite::future::block_on(self.receive_ctrl_message(&mut conn));

                if let Err(e) = result {
                    // The original function logged an error and returned ControlFlow::Break
                    // which implies the loop should terminate or an error state.
                    // For try_receive_channel, this might mean the connection is unusable for ctrl messages.
                    warn!(
                        "Receiving control message failed: {}, potential issue with connection.",
                        e
                    );
                    // Depending on desired behavior, you might return an error or continue.
                    // For now, let's assume it's an error if control message processing fails critically.
                    return Err(TryReceiveError::Error(e));
                }

                continue;
            }
            // If the PSK identity hint is not the control PSK, check if it's in the channel map.
            // If it is, create a channel of the appropriate type. We should have already received
            // the control message for this PSK, if we don't we can't create a channel.
            let channel_info = self.channels.get(&identity).ok_or_else(|| {
                debug!(
                    "No channel info found in map for identity hint {:02x?}",
                    identity
                );
                TryReceiveError::Error(AqcError::NoChannelInfoFound.into())
            })?;
            return Ok(AqcPeerChannel::new(
                channel_info.label_id,
                channel_info.channel_id,
                conn,
            ));
        }
    }

    /// Send a control message to the given address.
    pub async fn send_ctrl(
        &mut self,
        addr: SocketAddr,
        ctrl: AqcCtrl,
        team_id: TeamId,
    ) -> Result<(), AqcError> {
        self.client_keys.set_key(CTRL_PSK.clone());
        let mut conn = self
            .quic_client
            .connect(Connect::new(addr).with_server_name(addr.ip().to_string()))
            .await?;
        let mut stream = conn.open_bidirectional_stream().await?;

        let msg = AqcCtrlMessage { team_id, ctrl };
        let msg_bytes = postcard::to_stdvec(&msg).assume("can serialize")?;
        stream.send(Bytes::from(msg_bytes)).await?;
        stream.finish()?;

        let ack_bytes = read_to_end(&mut stream).await?;
        let ack = postcard::from_bytes::<AqcAckMessage>(&ack_bytes).map_err(AqcError::Serde)?;
        match ack {
            AqcAckMessage::Success => (),
            AqcAckMessage::Failure(e) => return Err(AqcError::CtrlFailure(e)),
        }

        Ok(())
    }

    async fn receive_ctrl_message(&mut self, conn: &mut Connection) -> crate::Result<()> {
        let mut stream = conn
            .accept_bidirectional_stream()
            .await
            .map_err(AqcError::ConnectionError)?
            .ok_or(AqcError::ConnectionClosed)?;
        let ctrl_bytes = read_to_end(&mut stream).await.map_err(AqcError::from)?;
        match postcard::from_bytes::<AqcCtrlMessage>(&ctrl_bytes) {
            Ok(ctrl) => {
                self.process_ctrl_message(ctrl.team_id, ctrl.ctrl).await?;
                // Send an ACK back
                let ack_msg = AqcAckMessage::Success;
                let ack_bytes = postcard::to_stdvec(&ack_msg).assume("can serialize")?;
                stream
                    .send(Bytes::from(ack_bytes))
                    .await
                    .map_err(AqcError::from)?;
                if let Err(err) = stream.close().await {
                    if !is_close_error(err) {
                        return Err(AqcError::from(err).into());
                    }
                }
            }
            Err(e) => {
                error!("Failed to deserialize AqcCtrlMessage: {}", e);
                let ack_msg =
                    AqcAckMessage::Failure(format!("Failed to deserialize AqcCtrlMessage: {e}"));
                let ack_bytes = postcard::to_stdvec(&ack_msg).assume("can serialize")?;
                stream.send(Bytes::from(ack_bytes)).await.ok();
                if let Err(err) = stream.close().await {
                    if !is_close_error(err) {
                        error!(%err, "error closing stream after ctrl failure");
                    }
                }
                return Err(AqcError::Serde(e).into());
            }
        }
        Ok(())
    }

    /// Receives an AQC ctrl message.
    async fn process_ctrl_message(&mut self, team: TeamId, ctrl: AqcCtrl) -> crate::Result<()> {
        let (label_id, psks) = self
            .daemon
            .receive_aqc_ctrl(context::current(), team, ctrl)
            .await
            .map_err(IpcError::new)?
            .map_err(aranya_error)?;

        self.server_keys.load_psks(psks.clone());

        match psks {
            AqcPsks::Bidi(psks) => {
                for (_suite, psk) in psks {
                    self.channels.insert(
                        psk.identity.as_bytes().to_vec(),
                        AqcChannelInfo {
                            label_id,
                            channel_id: AqcChannelId::Bidi(*psk.identity.channel_id()),
                        },
                    );
                }
            }
            AqcPsks::Uni(psks) => {
                for (_suite, psk) in psks {
                    self.channels.insert(
                        psk.identity.as_bytes().to_vec(),
                        AqcChannelInfo {
                            label_id,
                            channel_id: AqcChannelId::Uni(*psk.identity.channel_id()),
                        },
                    );
                }
            }
        }

        Ok(())
    }
}

/// An error that occurs when trying to receive a channel or stream.
#[derive(Debug, thiserror::Error)]
pub enum TryReceiveError<E = AqcError> {
    /// The channel or stream is empty.
    #[error("channel or stream is empty")]
    Empty,
    /// An error occurred.
    #[error("an error occurred")]
    Error(E),
    /// The channel or stream is closed.
    #[error("channel or stream is closed")]
    Closed,
}

#[derive(Debug)]
struct AqcChannelInfo {
    label_id: LabelId,
    channel_id: AqcChannelId,
}

/// An AQC Channel ID.
#[derive(Copy, Clone, Debug)]
enum AqcChannelId {
    Bidi(BidiChannelId),
    Uni(UniChannelId),
}

/// An AQC control message.
#[derive(serde::Serialize, serde::Deserialize)]
struct AqcCtrlMessage {
    /// The team id.
    team_id: TeamId,
    /// The control message.
    ctrl: AqcCtrl,
}

/// An AQC control message.
#[derive(serde::Serialize, serde::Deserialize)]
enum AqcAckMessage {
    /// The success message.
    Success,
    /// The failure message.
    Failure(String),
}

/// Read all of a stream until it has finished.
///
/// A bit more efficient than going through the `AsyncRead`-based impl,
/// especially if there was only one chunk of data. Also avoids needing to
/// convert/handle an `io::Error`.
async fn read_to_end(stream: &mut BidirectionalStream) -> Result<Bytes, s2n_quic::stream::Error> {
    let Some(first) = stream.receive().await? else {
        return Ok(Bytes::new());
    };
    let Some(mut more) = stream.receive().await? else {
        return Ok(first);
    };
    let mut buf = BytesMut::from(first);
    loop {
        buf.extend_from_slice(&more);
        if let Some(even_more) = stream.receive().await? {
            more = even_more;
        } else {
            break;
        }
    }
    Ok(buf.freeze())
}

/// Indicates whether the stream error is "connection closed without error".
fn is_close_error(err: s2n_quic::stream::Error) -> bool {
    matches!(
        err,
        s2n_quic::stream::Error::ConnectionError {
            error: s2n_quic::connection::Error::Closed { .. },
            ..
        },
    )
}
