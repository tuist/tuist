use std::{
    future::Future,
    io::BufReader,
    net::SocketAddr,
    pin::Pin,
    sync::Arc,
    task::{Context, Poll},
    time::Duration,
};

use arc_swap::ArcSwapOption;
use axum_server::{
    accept::Accept,
    tls_rustls::{RustlsAcceptor, RustlsConfig},
};
use reqwest::{Certificate, Client, Identity};
use rustls::pki_types::{CertificateDer, PrivateKeyDer};
use rustls::{RootCertStore, ServerConfig, server::WebPkiClientVerifier};
use sha2::{Digest, Sha256};
use tokio::{
    fs,
    io::{AsyncRead, AsyncWrite},
};
use tokio_rustls::server::TlsStream;

use crate::config::{Config, PeerTlsConfig, PublicTlsConfig};

struct PeerIdentity {
    identity_pem: Vec<u8>,
    ca_pem: Vec<u8>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum PeerClientTimeouts {
    Download,
    Upload,
}

/// Builds outbound peer HTTP clients with the current peer mTLS identity. The
/// identity is held behind an atomic swap so a renewal task can rotate the
/// certificate in place: clients built afterwards (and `state.client` once it is
/// rebuilt) pick up the new identity without a restart.
#[derive(Clone)]
pub struct PeerClientFactory {
    identity: Arc<ArcSwapOption<PeerIdentity>>,
}

impl PeerClientFactory {
    pub fn plain() -> Self {
        Self {
            identity: Arc::new(ArcSwapOption::const_empty()),
        }
    }

    pub async fn from_config(config: &Config) -> Result<Self, String> {
        let factory = Self::plain();
        if config.peer_tls.is_some() {
            factory.reload_from_config(config).await?;
        }
        Ok(factory)
    }

    /// Re-reads the peer identity from the configured `KURA_INTERNAL_TLS_*` paths
    /// and atomically swaps it. A no-op when peer TLS is disabled.
    pub async fn reload_from_config(&self, config: &Config) -> Result<(), String> {
        let Some(peer_tls) = &config.peer_tls else {
            return Ok(());
        };

        let ca_pem = fs::read(&peer_tls.ca_cert_path).await.map_err(|error| {
            format!(
                "failed to read peer CA certificate {}: {error}",
                peer_tls.ca_cert_path.display()
            )
        })?;
        let cert_pem = fs::read(&peer_tls.cert_path).await.map_err(|error| {
            format!(
                "failed to read peer certificate {}: {error}",
                peer_tls.cert_path.display()
            )
        })?;
        let key_pem = fs::read(&peer_tls.key_path).await.map_err(|error| {
            format!(
                "failed to read peer private key {}: {error}",
                peer_tls.key_path.display()
            )
        })?;

        let mut identity_pem = cert_pem;
        if !identity_pem.ends_with(b"\n") {
            identity_pem.push(b'\n');
        }
        identity_pem.extend_from_slice(&key_pem);

        self.identity.store(Some(Arc::new(PeerIdentity {
            identity_pem,
            ca_pem,
        })));
        Ok(())
    }

    pub fn build(&self) -> Result<Client, String> {
        self.builder(PeerClientTimeouts::Download)?
            .build()
            .map_err(|error| format!("failed to build peer HTTP client: {error}"))
    }

    /// A client for streaming request BODIES to a peer (outbox artifact
    /// replication). It carries no `read_timeout`: while a request body
    /// uploads, the response read side is silent by design — the receiver
    /// sends nothing until the whole body has been consumed — so the
    /// download client's 30s read timeout acts as a hard ceiling on total
    /// upload time and permanently fails any artifact that streams longer
    /// (observed in production as an outbox message retrying for hours).
    /// Stall protection is the caller's byte-progress watchdog, which keys
    /// on the upload actually moving instead of on response silence.
    pub fn build_upload(&self) -> Result<Client, String> {
        self.builder(PeerClientTimeouts::Upload)?
            .build()
            .map_err(|error| format!("failed to build peer upload HTTP client: {error}"))
    }

    pub fn build_resolving(&self, host: &str, address: SocketAddr) -> Result<Client, String> {
        self.builder(PeerClientTimeouts::Download)?
            .resolve_to_addrs(host, &[address])
            .build()
            .map_err(|error| format!("failed to build peer HTTP client for {host}: {error}"))
    }

    fn builder(&self, timeouts: PeerClientTimeouts) -> Result<reqwest::ClientBuilder, String> {
        let mut builder = Client::builder().connect_timeout(Duration::from_secs(5));
        if timeouts == PeerClientTimeouts::Download {
            // Idle/read timeout, NOT a total request timeout. A bootstrap
            // artifact streams its whole body over this client; under
            // cold-start load (bandwidth-limited + congested) a large
            // artifact's transfer can exceed any fixed total cap, which
            // aborts it mid-body and surfaces to the peer as an undecodable
            // (incomplete) response — silently wedging bootstrap. read_timeout
            // resets on each chunk, so a slow-but-progressing transfer
            // completes while a genuinely stalled connection still fails fast.
            builder = builder.read_timeout(Duration::from_secs(30));
        }

        if let Some(identity) = self.identity.load_full() {
            let id = Identity::from_pem(&identity.identity_pem)
                .map_err(|error| format!("failed to parse peer identity PEM: {error}"))?;
            let ca = Certificate::from_pem(&identity.ca_pem)
                .map_err(|error| format!("failed to parse peer CA PEM: {error}"))?;

            builder = builder.identity(id).add_root_certificate(ca);
        }

        Ok(builder)
    }
}

/// The verified client-certificate identity of an internal-plane request,
/// inserted as a request extension by [`InternalPeerIdentityAcceptor`]. Absent
/// on the plain-HTTP internal listener (peer TLS disabled), which is only
/// reachable inside the trusted cluster network.
///
/// The identity is a truncated SHA-256 fingerprint of the leaf certificate
/// DER, not a parsed subject name: per-identity policy (the bodies-endpoint
/// concurrency cap, per-peer request metrics) only needs a value that is
/// stable per certificate and distinct across peers, and fingerprinting
/// avoids taking an X.509-parsing dependency. Rotating a peer's certificate
/// rotates its identity, which is harmless for both uses.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct InternalPeerIdentity(pub Arc<str>);

pub fn peer_identity_from_der(certificate_der: &[u8]) -> InternalPeerIdentity {
    let digest = Sha256::digest(certificate_der);
    InternalPeerIdentity(hex::encode(&digest[..8]).into())
}

/// [`RustlsAcceptor`] wrapper for the internal mTLS listener that reads the
/// handshake-verified client certificate off the TLS stream and stamps its
/// [`InternalPeerIdentity`] into every request the connection carries.
#[derive(Clone)]
pub struct InternalPeerIdentityAcceptor {
    inner: RustlsAcceptor,
}

impl InternalPeerIdentityAcceptor {
    pub fn new(config: RustlsConfig) -> Self {
        Self {
            inner: RustlsAcceptor::new(config),
        }
    }
}

impl<I, S> Accept<I, S> for InternalPeerIdentityAcceptor
where
    I: AsyncRead + AsyncWrite + Unpin + Send + 'static,
    S: Send + 'static,
{
    type Stream = TlsStream<I>;
    type Service = AddInternalPeerIdentity<S>;
    type Future =
        Pin<Box<dyn Future<Output = std::io::Result<(Self::Stream, Self::Service)>> + Send>>;

    fn accept(&self, stream: I, service: S) -> Self::Future {
        let inner = self.inner.clone();
        Box::pin(async move {
            let (stream, service) = inner.accept(stream, service).await?;
            let identity = stream
                .get_ref()
                .1
                .peer_certificates()
                .and_then(|certificates| certificates.first())
                .map(|leaf| peer_identity_from_der(leaf.as_ref()));
            Ok((stream, AddInternalPeerIdentity { service, identity }))
        })
    }
}

/// Per-connection service wrapper that inserts the connection's
/// [`InternalPeerIdentity`] into each request's extensions.
#[derive(Clone)]
pub struct AddInternalPeerIdentity<S> {
    service: S,
    identity: Option<InternalPeerIdentity>,
}

impl<S, B> tower::Service<axum::http::Request<B>> for AddInternalPeerIdentity<S>
where
    S: tower::Service<axum::http::Request<B>>,
{
    type Response = S::Response;
    type Error = S::Error;
    type Future = S::Future;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.service.poll_ready(cx)
    }

    fn call(&mut self, mut request: axum::http::Request<B>) -> Self::Future {
        if let Some(identity) = &self.identity {
            request.extensions_mut().insert(identity.clone());
        }
        self.service.call(request)
    }
}

/// Builds the rustls `ServerConfig` for the internal mTLS plane, preserving the
/// `WebPkiClientVerifier` (the per-account CA peer-auth check). Exposed so cert
/// rotation can rebuild it and hot-swap via `RustlsConfig::reload_from_config`,
/// which `reload_from_pem*` cannot do (they drop the client verifier).
pub async fn build_internal_server_config(
    peer_tls: &PeerTlsConfig,
) -> Result<Arc<ServerConfig>, String> {
    install_default_crypto_provider();
    let certificates = load_certificates(&peer_tls.cert_path).await?;
    let private_key = load_private_key(&peer_tls.key_path).await?;
    let roots = load_root_store(&peer_tls.ca_cert_path).await?;
    let verifier = WebPkiClientVerifier::builder(Arc::new(roots))
        .build()
        .map_err(|error| format!("failed to build peer client verifier: {error}"))?;

    let mut server_config = ServerConfig::builder()
        .with_client_cert_verifier(verifier)
        .with_single_cert(certificates, private_key)
        .map_err(|error| format!("failed to build peer TLS server config: {error}"))?;
    server_config.alpn_protocols = vec![b"h2".to_vec(), b"http/1.1".to_vec()];

    Ok(Arc::new(server_config))
}

pub async fn build_internal_rustls_config(
    peer_tls: &PeerTlsConfig,
) -> Result<RustlsConfig, String> {
    Ok(RustlsConfig::from_config(
        build_internal_server_config(peer_tls).await?,
    ))
}

pub async fn build_public_rustls_config(
    public_tls: &PublicTlsConfig,
) -> Result<RustlsConfig, String> {
    install_default_crypto_provider();
    let certificates = load_certificates(&public_tls.cert_path).await?;
    let private_key = load_private_key(&public_tls.key_path).await?;

    let mut server_config = ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(certificates, private_key)
        .map_err(|error| format!("failed to build public TLS server config: {error}"))?;
    server_config.alpn_protocols = vec![b"h2".to_vec(), b"http/1.1".to_vec()];

    Ok(RustlsConfig::from_config(Arc::new(server_config)))
}

pub(crate) fn install_default_crypto_provider() {
    let _ = rustls::crypto::aws_lc_rs::default_provider().install_default();
}

async fn load_certificates(path: &std::path::Path) -> Result<Vec<CertificateDer<'static>>, String> {
    let pem = fs::read(path)
        .await
        .map_err(|error| format!("failed to read certificate PEM {}: {error}", path.display()))?;
    let mut reader = BufReader::new(pem.as_slice());
    let certificates = rustls_pemfile::certs(&mut reader)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| {
            format!(
                "failed to parse certificate PEM {}: {error}",
                path.display()
            )
        })?;
    if certificates.is_empty() {
        return Err(format!(
            "certificate PEM {} does not contain any certificates",
            path.display()
        ));
    }
    Ok(certificates)
}

async fn load_private_key(path: &std::path::Path) -> Result<PrivateKeyDer<'static>, String> {
    let pem = fs::read(path)
        .await
        .map_err(|error| format!("failed to read private key PEM {}: {error}", path.display()))?;
    let mut reader = BufReader::new(pem.as_slice());
    rustls_pemfile::private_key(&mut reader)
        .map_err(|error| {
            format!(
                "failed to parse private key PEM {}: {error}",
                path.display()
            )
        })?
        .ok_or_else(|| format!("private key PEM {} does not contain a key", path.display()))
}

async fn load_root_store(path: &std::path::Path) -> Result<RootCertStore, String> {
    let certificates = load_certificates(path).await?;
    let mut roots = RootCertStore::empty();
    let (added, ignored) = roots.add_parsable_certificates(certificates);
    if added == 0 {
        return Err(format!(
            "peer CA certificate PEM {} does not contain any usable CA certificates",
            path.display()
        ));
    }
    if ignored > 0 {
        tracing::warn!(
            "ignored {ignored} unparsable peer CA certificates while loading {}",
            path.display()
        );
    }
    Ok(roots)
}

#[cfg(test)]
mod tests {
    use std::net::{Ipv4Addr, SocketAddr};

    use axum::{Router, routing::get};

    use super::*;

    fn write_pem(dir: &std::path::Path, name: &str, pem: &str) -> std::path::PathBuf {
        let path = dir.join(name);
        std::fs::write(&path, pem).expect("write PEM");
        path
    }

    // A read timeout on the upload client is a hard ceiling on total upload
    // time, because the response side stays silent until the receiver has
    // consumed the whole body: it strands every artifact that streams for
    // longer than the timeout, permanently. Proving that functionally would
    // cost a >30s transfer per run, so this asserts the property directly.
    // reqwest's Debug prints `read_timeout` only when one is configured.
    #[test]
    fn upload_client_has_no_read_timeout_and_download_client_keeps_one() {
        let factory = PeerClientFactory::plain();

        let upload = format!("{:?}", factory.build_upload().expect("build upload client"));
        assert!(
            !upload.contains("read_timeout"),
            "the upload client must carry no read timeout; got {upload}"
        );

        let download = format!("{:?}", factory.build().expect("build download client"));
        assert!(
            download.contains("read_timeout"),
            "the download client's read timeout is load-bearing for bootstrap; got {download}"
        );
    }

    // End-to-end proof that the internal mTLS listener surfaces the verified
    // client certificate: a request over the acceptor carries the leaf cert's
    // fingerprint identity as a request extension, and two different client
    // certificates yield two different identities.
    #[tokio::test]
    async fn internal_peer_identity_acceptor_stamps_client_cert_fingerprints() {
        install_default_crypto_provider();

        let ca_key = rcgen::KeyPair::generate().expect("generate CA key");
        let mut ca_params = rcgen::CertificateParams::new(Vec::<String>::new()).expect("CA params");
        ca_params.is_ca = rcgen::IsCa::Ca(rcgen::BasicConstraints::Unconstrained);
        ca_params.key_usages = vec![
            rcgen::KeyUsagePurpose::KeyCertSign,
            rcgen::KeyUsagePurpose::CrlSign,
        ];
        let ca = rcgen::CertifiedIssuer::self_signed(ca_params, ca_key).expect("self-sign CA");

        let server_key = rcgen::KeyPair::generate().expect("generate server key");
        let server_cert = rcgen::CertificateParams::new(vec!["localhost".to_string()])
            .expect("server params")
            .signed_by(&server_key, &ca)
            .expect("sign server cert");

        let client_certificate = |name: &str| {
            let key = rcgen::KeyPair::generate().expect("generate client key");
            let mut params =
                rcgen::CertificateParams::new(vec![name.to_string()]).expect("client params");
            params.extended_key_usages = vec![rcgen::ExtendedKeyUsagePurpose::ClientAuth];
            let certificate = params.signed_by(&key, &ca).expect("sign client cert");
            (certificate, key)
        };
        let (client_a_cert, client_a_key) = client_certificate("peer-a");
        let (client_b_cert, client_b_key) = client_certificate("peer-b");

        let dir = tempfile::tempdir().expect("temp dir");
        let peer_tls = PeerTlsConfig {
            ca_cert_path: write_pem(dir.path(), "ca.crt", &ca.pem()),
            cert_path: write_pem(dir.path(), "tls.crt", &server_cert.pem()),
            key_path: write_pem(dir.path(), "tls.key", &server_key.serialize_pem()),
        };
        let tls_config = build_internal_rustls_config(&peer_tls)
            .await
            .expect("build internal rustls config");

        let app = Router::new().route(
            "/identity",
            get(|request: axum::extract::Request| async move {
                request
                    .extensions()
                    .get::<InternalPeerIdentity>()
                    .map(|identity| identity.0.to_string())
                    .unwrap_or_else(|| "none".to_owned())
            }),
        );
        let handle = axum_server::Handle::new();
        let server = tokio::spawn(
            axum_server::bind(SocketAddr::from((Ipv4Addr::LOCALHOST, 0)))
                .acceptor(InternalPeerIdentityAcceptor::new(tls_config))
                .handle(handle.clone())
                .serve(app.into_make_service()),
        );
        let addr = handle.listening().await.expect("server should bind");

        let ca_pem = ca.pem();
        let request_identity = |certificate_pem: String, key_pem: String, ca_pem: String| async move {
            let identity_pem = format!("{certificate_pem}\n{key_pem}");
            reqwest::Client::builder()
                .identity(Identity::from_pem(identity_pem.as_bytes()).expect("client identity"))
                .add_root_certificate(Certificate::from_pem(ca_pem.as_bytes()).expect("trust CA"))
                .resolve("localhost", addr)
                .build()
                .expect("build mTLS client")
                .get(format!("https://localhost:{}/identity", addr.port()))
                .send()
                .await
                .expect("mTLS request should succeed")
                .text()
                .await
                .expect("read identity body")
        };

        let identity_a = request_identity(
            client_a_cert.pem(),
            client_a_key.serialize_pem(),
            ca_pem.clone(),
        )
        .await;
        let identity_b = request_identity(
            client_b_cert.pem(),
            client_b_key.serialize_pem(),
            ca_pem.clone(),
        )
        .await;

        assert_eq!(
            identity_a,
            peer_identity_from_der(client_a_cert.der()).0.as_ref()
        );
        assert_eq!(
            identity_b,
            peer_identity_from_der(client_b_cert.der()).0.as_ref()
        );
        assert_ne!(identity_a, identity_b);

        handle.shutdown();
        let _ = server.await;
    }
}
