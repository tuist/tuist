use crate::certificate_trust::{self, BLOCKED_SPKI_HASHES, spki_hash};
use rcgen::{BasicConstraints, CertificateParams, IsCa, Issuer, KeyPair};
use rustls::pki_types::{CertificateDer, PrivatePkcs8KeyDer};
use rustls::{Error, RootCertStore};
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio_tungstenite::tungstenite::{client::IntoClientRequest, protocol::WebSocketConfig};

fn pem(bytes: &[u8]) -> Vec<CertificateDer<'static>> {
    rustls_pemfile::certs(&mut std::io::Cursor::new(bytes))
        .collect::<Result<_, _>>()
        .unwrap()
}

fn roots(certificates: &[CertificateDer<'_>]) -> RootCertStore {
    let mut roots = RootCertStore::empty();
    roots.add_parsable_certificates(certificates.iter().cloned());
    roots.add_parsable_certificates(pem(include_bytes!(
        "../tests/fixtures/certificate-trust/positive-isrg-root-x1.pem"
    )));
    roots
}

fn certificate_failure(error: &(dyn std::error::Error + 'static)) -> bool {
    let mut source = Some(error);
    while let Some(error) = source {
        if matches!(
            error.downcast_ref::<rustls::Error>(),
            Some(Error::InvalidCertificate(_))
        ) {
            return true;
        }
        source = if let Some(io) = error.downcast_ref::<std::io::Error>() {
            io.get_ref()
                .map(|inner| inner as &(dyn std::error::Error + 'static))
                .or_else(|| error.source())
        } else {
            error.source()
        };
    }
    false
}

#[test]
fn real_policy_keys_are_embedded_and_never_retained_as_anchors() {
    let certificates = pem(include_bytes!(
        "../tests/fixtures/certificate-trust/issuer-roots.pem"
    ))
    .into_iter()
    .chain(pem(include_bytes!(
        "../tests/fixtures/certificate-trust/distrusted-intermediates.pem"
    )))
    .collect::<Vec<_>>();
    assert_eq!(certificates.len(), 12);
    let hashes = certificates
        .iter()
        .map(|cert| spki_hash(cert).unwrap())
        .collect::<std::collections::BTreeSet<_>>();
    assert_eq!(
        hashes,
        BLOCKED_SPKI_HASHES
            .iter()
            .map(|hash| hash.to_string())
            .collect()
    );
    let mut only_blocked = RootCertStore::empty();
    only_blocked.add_parsable_certificates(certificates);
    assert!(certificate_trust::verifier(only_blocked, Vec::new()).is_err());
    assert!(spki_hash(&CertificateDer::from(vec![0x30, 0x80])).is_err());
}

struct Fixture {
    root: CertificateDer<'static>,
    leaf: CertificateDer<'static>,
    port: u16,
    stop: Option<tokio::sync::oneshot::Sender<()>>,
    server: Option<std::thread::JoinHandle<()>>,
}

impl Fixture {
    fn new(websocket: bool, expired: bool, corrupt: bool) -> Self {
        let mut ca = CertificateParams::new(Vec::<String>::new()).unwrap();
        ca.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
        ca.not_before = time::OffsetDateTime::now_utc() - time::Duration::days(1);
        ca.not_after = time::OffsetDateTime::now_utc() + time::Duration::days(1);
        let key = KeyPair::generate().unwrap();
        let root = ca.self_signed(&key).unwrap().der().clone();
        let issuer = Issuer::new(ca, key);
        let key = KeyPair::generate().unwrap();
        let mut params = CertificateParams::new(vec!["localhost".to_owned()]).unwrap();
        params.not_before = time::OffsetDateTime::now_utc() - time::Duration::days(3);
        params.not_after =
            time::OffsetDateTime::now_utc() + time::Duration::days(if expired { -1 } else { 1 });
        let mut leaf = params
            .signed_by(&key, &issuer)
            .unwrap()
            .der()
            .as_ref()
            .to_vec();
        if corrupt {
            *leaf.last_mut().unwrap() ^= 1;
        }
        let leaf = CertificateDer::from(leaf);
        let config = rustls::ServerConfig::builder_with_provider(Arc::new(
            rustls::crypto::ring::default_provider(),
        ))
        .with_safe_default_protocol_versions()
        .unwrap()
        .with_no_client_auth()
        .with_single_cert(
            vec![leaf.clone()],
            PrivatePkcs8KeyDer::from(key.serialize_der()).into(),
        )
        .unwrap();
        let acceptor = tokio_rustls::TlsAcceptor::from(Arc::new(config));
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        listener.set_nonblocking(true).unwrap();
        let (stop, mut stopped) = tokio::sync::oneshot::channel();
        let server = std::thread::spawn(move || {
            tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap().block_on(async move {
                let listener = tokio::net::TcpListener::from_std(listener).unwrap();
                loop {
                    tokio::select! {
                        _ = &mut stopped => break,
                        accepted = listener.accept() => {
                            let (socket, _) = accepted.unwrap();
                            let acceptor = acceptor.clone();
                            tokio::spawn(async move {
                                let Ok(mut socket) = acceptor.accept(socket).await else { return };
                                if websocket { let _ = tokio_tungstenite::accept_async(socket).await; }
                                else {
                                    let mut request = [0; 4096];
                                    let _ = socket.read(&mut request).await;
                                    let _ = socket.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}").await;
                                }
                            });
                        }
                    }
                }
            });
        });
        Self {
            root,
            leaf,
            port,
            stop: Some(stop),
            server: Some(server),
        }
    }

    fn config(&self, blocked: Vec<String>) -> rustls::ClientConfig {
        certificate_trust::client_config(roots(std::slice::from_ref(&self.root)), blocked).unwrap()
    }

    fn url(&self) -> String {
        format!("https://localhost:{}/", self.port)
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        if let Some(stop) = self.stop.take() {
            let _ = stop.send(());
        }
        if let Some(server) = self.server.take() {
            server.join().unwrap();
        }
    }
}

#[test]
fn actual_http_factory_enforces_accepted_leaf_and_anchor_denies() {
    let fixture = Fixture::new(false, false, false);
    let factory = crate::transport::build_client;
    let normal = factory(fixture.config(Vec::new())).unwrap();
    assert_eq!(normal.get(fixture.url()).send().unwrap().status(), 200);
    for certificate in [&fixture.root, &fixture.leaf] {
        let blocked = factory(fixture.config(vec![spki_hash(certificate).unwrap()])).unwrap();
        let error = blocked.get(fixture.url()).send().unwrap_err();
        assert!(
            certificate_failure(&error),
            "not a certificate-specific failure: {error:?}"
        );
    }
    assert!(certificate_failure(
        &normal
            .get(format!("https://127.0.0.1:{}/", fixture.port))
            .send()
            .unwrap_err()
    ));
    let unknown =
        factory(certificate_trust::client_config(roots(&[]), Vec::new()).unwrap()).unwrap();
    assert!(certificate_failure(
        &unknown.get(fixture.url()).send().unwrap_err()
    ));
}

#[test]
fn actual_http_factory_preserves_expiry_and_signature_checks() {
    for (expired, corrupt) in [(true, false), (false, true)] {
        let fixture = Fixture::new(false, expired, corrupt);
        let client = crate::transport::build_client(fixture.config(Vec::new())).unwrap();
        assert!(certificate_failure(
            &client.get(fixture.url()).send().unwrap_err()
        ));
    }
}

#[test]
fn actual_presence_connector_enforces_accepted_leaf_and_anchor_denies() {
    let fixture = Fixture::new(true, false, false);
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let request = || {
                format!("wss://localhost:{}/", fixture.port)
                    .into_client_request()
                    .unwrap()
            };
            let connector =
                |blocked| tokio_tungstenite::Connector::Rustls(Arc::new(fixture.config(blocked)));
            crate::presence::connect_tls(
                request(),
                WebSocketConfig::default(),
                connector(Vec::new()),
            )
            .await
            .unwrap();
            for certificate in [&fixture.root, &fixture.leaf] {
                let error = crate::presence::connect_tls(
                    request(),
                    WebSocketConfig::default(),
                    connector(vec![spki_hash(certificate).unwrap()]),
                )
                .await
                .unwrap_err();
                assert!(
                    certificate_failure(&error),
                    "not a certificate-specific failure: {error:?}"
                );
                assert!(certificate_trust::tls_failure(&error));
            }
        });
}

fn incident_config() -> rustls::ClientConfig {
    let mut roots = RootCertStore {
        roots: webpki_roots::TLS_SERVER_ROOTS.to_vec(),
    };
    roots.add_parsable_certificates(pem(include_bytes!(
        "../tests/fixtures/certificate-trust/issuer-roots.pem"
    )));
    certificate_trust::client_config(roots, Vec::new()).unwrap()
}

fn policy_failure(error: &(dyn std::error::Error + 'static)) -> bool {
    let mut source = Some(error);
    while let Some(error) = source {
        if let Some(Error::InvalidCertificate(reason)) = error.downcast_ref::<Error>() {
            return match reason {
                rustls::CertificateError::ApplicationVerificationFailure => true,
                rustls::CertificateError::Other(other) => matches!(
                    other.0.downcast_ref::<webpki::Error>(),
                    Some(webpki::Error::CertDistrusted)
                ),
                _ => false,
            };
        }
        source = if let Some(io) = error.downcast_ref::<std::io::Error>() {
            io.get_ref()
                .map(|inner| inner as &(dyn std::error::Error + 'static))
                .or_else(|| error.source())
        } else {
            error.source()
        };
    }
    false
}

#[test]
fn production_http_and_presence_clients_reject_all_twelve_public_controls() {
    if std::env::var("TUIST_TRUST_LIVE").as_deref() != Ok("1") {
        eprintln!("SKIP live Atlas controls: set TUIST_TRUST_LIVE=1");
        return;
    }
    eprintln!("TUIST_TRUST_LIVE=1: Atlas HTTP/WSS production and incident-root-added controls");
    let injected_auth = crate::transport::build_client(incident_config()).unwrap();
    for issuer in ["emudhra", "aaa-emudhra"] {
        for prefix in ["dv-g3b", "dv-g3c", "ov-g3b", "ov-g3c", "ev-g3b", "ev-g3c"] {
            let host = format!("{prefix}-{issuer}.we-have-a-problem.com");
            for (label, client, injected) in [
                ("HTTP", crate::transport::client().unwrap(), false),
                ("HTTP", &injected_auth, true),
            ] {
                let error = client.get(format!("https://{host}/")).send().unwrap_err();
                assert!(certificate_failure(&error));
                assert!(
                    policy_failure(&error),
                    "not a policy-specific failure: {error:?}"
                );
                eprintln!(
                    "Atlas {label} incident_roots={injected} {issuer}/{prefix}: certificate rejection, key_deny={}",
                    policy_failure(&error)
                );
            }
            tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .unwrap()
                .block_on(async {
                    for (injected, config) in [(false, crate::transport::tls_config().unwrap()), (true, incident_config())] {
                        let connector = tokio_tungstenite::Connector::Rustls(Arc::new(config));
                        let error = tokio::time::timeout(
                            Duration::from_secs(10),
                            crate::presence::connect_tls(
                                format!("wss://{host}/").into_client_request().unwrap(),
                                WebSocketConfig::default(), connector,
                            ),
                        ).await.unwrap().unwrap_err();
                        assert!(certificate_failure(&error));
                        assert!(policy_failure(&error), "not a policy-specific failure: {error:?}");
                        eprintln!("Atlas WSS incident_roots={injected} {issuer}/{prefix}: certificate rejection, key_deny={}", policy_failure(&error));
                    }
                });
        }
    }
    assert_eq!(
        crate::transport::client()
            .unwrap()
            .get("https://letsencrypt.org/")
            .send()
            .unwrap()
            .status(),
        200
    );
}
