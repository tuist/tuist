use crate::certificate_trust::{self, spki_hash, verifier, BLOCKED_SPKI_HASHES};
use bazel_remote_apis::build::bazel::remote::execution::v2 as api;
use rcgen::{BasicConstraints, CertificateParams, IsCa, Issuer, KeyPair};
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{CertificateError, Error, RootCertStore};
use std::sync::Arc;
use std::time::{Duration, SystemTime};
use tonic::transport::{Endpoint, Identity, Server, ServerTlsConfig};

fn pem(bytes: &[u8]) -> Vec<CertificateDer<'static>> {
    rustls_pemfile::certs(&mut std::io::Cursor::new(bytes))
        .collect::<Result<_, _>>()
        .unwrap()
}

fn roots(certificates: &[CertificateDer<'_>]) -> RootCertStore {
    let mut roots = RootCertStore::empty();
    roots.add_parsable_certificates(certificates.iter().cloned());
    // Keep an unrelated anchor when additionally denying the fixture's only CA.
    roots.add_parsable_certificates(pem(include_bytes!(
        "../tests/fixtures/certificate-trust/positive-isrg-root-x1.pem"
    )));
    roots
}

#[test]
fn all_twelve_real_policy_keys_and_anchor_contents_match() {
    let certificates = pem(include_bytes!(
        "../tests/fixtures/certificate-trust/issuer-roots.pem"
    ))
    .into_iter()
    .chain(pem(include_bytes!(
        "../tests/fixtures/certificate-trust/distrusted-intermediates.pem"
    )))
    .collect::<Vec<_>>();
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
    assert_eq!(certificates.len(), 12);
    let mut blocked_only = RootCertStore::empty();
    blocked_only.add_parsable_certificates(certificates.iter().cloned());
    assert!(
        verifier(blocked_only, Vec::new()).is_err(),
        "blocked keys must never survive as anchors"
    );
    let checked = verifier(roots(&certificates), Vec::new()).unwrap();
    // Supplemental native negatives, not application proof: these CAs are not valid
    // localhost leaves. The empty filtered anchor set above proves removal.
    for certificate in certificates {
        let result = checked.verify_server_cert(
            &certificate,
            &[],
            &ServerName::try_from("localhost").unwrap(),
            &[],
            UnixTime::now(),
        );
        assert!(
            matches!(result, Err(Error::InvalidCertificate(_))),
            "policy control accepted"
        );
    }
    assert!(spki_hash(&CertificateDer::from(vec![0x30, 0x80])).is_err());
}

struct Fixture {
    root: CertificateDer<'static>,
    leaf: CertificateDer<'static>,
    leaf_pem: String,
    key_pem: String,
}

impl Fixture {
    fn new() -> Self {
        let mut ca = CertificateParams::new(Vec::<String>::new()).unwrap();
        ca.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
        ca.not_before = time::OffsetDateTime::now_utc() - time::Duration::days(1);
        ca.not_after = time::OffsetDateTime::now_utc() + time::Duration::days(1);
        let ca_key = KeyPair::generate().unwrap();
        let root = ca.self_signed(&ca_key).unwrap().der().clone();
        let issuer = Issuer::new(ca, ca_key);
        let mut leaf = CertificateParams::new(vec!["localhost".to_owned()]).unwrap();
        leaf.not_before = time::OffsetDateTime::now_utc() - time::Duration::days(1);
        leaf.not_after = time::OffsetDateTime::now_utc() + time::Duration::days(1);
        let key = KeyPair::generate().unwrap();
        let leaf = leaf.signed_by(&key, &issuer).unwrap();
        Self {
            root,
            leaf: leaf.der().clone(),
            leaf_pem: leaf.pem(),
            key_pem: key.serialize_pem(),
        }
    }
}

#[test]
fn restrictive_verifier_preserves_native_checks_and_rejects_accepted_leaf_and_anchor() {
    let fixture = Fixture::new();
    let normal = verifier(roots(&[fixture.root.clone()]), Vec::new()).unwrap();
    let name = ServerName::try_from("localhost").unwrap();
    assert!(normal
        .verify_server_cert(&fixture.leaf, &[], &name, &[], UnixTime::now())
        .is_ok());
    for certificate in [&fixture.leaf, &fixture.root] {
        let denied = verifier(
            roots(&[fixture.root.clone()]),
            vec![spki_hash(certificate).unwrap()],
        )
        .unwrap();
        assert!(matches!(
            denied.verify_server_cert(&fixture.leaf, &[], &name, &[], UnixTime::now()),
            Err(Error::InvalidCertificate(_))
        ));
    }
    assert!(normal
        .verify_server_cert(
            &fixture.leaf,
            &[],
            &ServerName::try_from("wrong.example").unwrap(),
            &[],
            UnixTime::now()
        )
        .is_err());
    let unknown = verifier(roots(&[]), Vec::new()).unwrap();
    assert!(matches!(
        unknown.verify_server_cert(&fixture.leaf, &[], &name, &[], UnixTime::now()),
        Err(Error::InvalidCertificate(CertificateError::UnknownIssuer))
    ));
    let future = UnixTime::since_unix_epoch(
        SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            + Duration::from_secs(3 * 86400),
    );
    assert!(normal
        .verify_server_cert(&fixture.leaf, &[], &name, &[], future)
        .is_err());
    let mut corrupt = fixture.leaf.as_ref().to_vec();
    *corrupt.last_mut().unwrap() ^= 1;
    assert!(normal
        .verify_server_cert(
            &CertificateDer::from(corrupt),
            &[],
            &name,
            &[],
            UnixTime::now()
        )
        .is_err());
}

#[derive(Default)]
struct Capabilities;
#[tonic::async_trait]
impl api::capabilities_server::Capabilities for Capabilities {
    async fn get_capabilities(
        &self,
        _: tonic::Request<api::GetCapabilitiesRequest>,
    ) -> Result<tonic::Response<api::ServerCapabilities>, tonic::Status> {
        Ok(tonic::Response::new(api::ServerCapabilities::default()))
    }
}

#[test]
fn actual_tonic_factory_preserves_private_ca_and_rejects_added_denies() {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let fixture = Fixture::new();
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let port = listener.local_addr().unwrap().port();
            let (stop, stopped) = tokio::sync::oneshot::channel::<()>();
            let server = tokio::spawn(
                Server::builder()
                    .tls_config(
                        ServerTlsConfig::new()
                            .identity(Identity::from_pem(&fixture.leaf_pem, &fixture.key_pem)),
                    )
                    .unwrap()
                    .add_service(api::capabilities_server::CapabilitiesServer::new(
                        Capabilities,
                    ))
                    .serve_with_incoming_shutdown(
                        tonic::transport::server::TcpIncoming::from(listener),
                        async {
                            let _ = stopped.await;
                        },
                    ),
            );
            let endpoint = || {
                Endpoint::from_shared(format!("https://localhost:{port}"))
                    .unwrap()
                    .connect_timeout(Duration::from_secs(5))
            };
            let trusted = || roots(&[fixture.root.clone()]);
            let channel = crate::reapi::secure_endpoint(endpoint(), trusted(), Vec::new())
                .unwrap()
                .connect()
                .await
                .unwrap();
            api::capabilities_client::CapabilitiesClient::new(channel)
                .get_capabilities(api::GetCapabilitiesRequest::default())
                .await
                .unwrap();
            for certificate in [&fixture.leaf, &fixture.root] {
                let error = crate::reapi::secure_endpoint(
                    endpoint(),
                    trusted(),
                    vec![spki_hash(certificate).unwrap()],
                )
                .unwrap()
                .connect()
                .await
                .unwrap_err();
                assert!(
                    certificate_failure(&error),
                    "failure must have a typed certificate cause: {error:?}"
                );
                assert!(certificate_trust::tls_failure(&error));
            }
            let _ = stop.send(());
            server.await.unwrap().unwrap();
        });
}

fn policy_failure(error: &(dyn std::error::Error + 'static)) -> bool {
    let mut source = Some(error);
    while let Some(error) = source {
        if let Some(Error::InvalidCertificate(reason)) = error.downcast_ref::<Error>() {
            return match reason {
                CertificateError::ApplicationVerificationFailure => true,
                CertificateError::Other(other) => matches!(
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
fn actual_rustls_public_controls() {
    if std::env::var("TUIST_TRUST_LIVE").as_deref() != Ok("1") {
        eprintln!("SKIP live CAS controls: set TUIST_TRUST_LIVE=1");
        return;
    }
    eprintln!("TUIST_TRUST_LIVE=1: CAS 12-key controls with incident roots deliberately added");
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(async {
            let mut roots = RootCertStore::empty();
            roots.add_parsable_certificates(rustls_native_certs::load_native_certs().certs);
            // Deliberately add the incident roots, so OS root removal cannot hide their reintroduction.
            roots.add_parsable_certificates(pem(include_bytes!(
                "../tests/fixtures/certificate-trust/issuer-roots.pem"
            )));
            let connector = tokio_rustls::TlsConnector::from(Arc::new(
                certificate_trust::client_config(roots, Vec::new()).unwrap(),
            ));
            for issuer in ["emudhra", "aaa-emudhra"] {
                for prefix in ["dv-g3b", "dv-g3c", "ov-g3b", "ov-g3c", "ev-g3b", "ev-g3c"] {
                    let host = format!("{prefix}-{issuer}.we-have-a-problem.com");
                    let tcp = tokio::time::timeout(
                        Duration::from_secs(10),
                        tokio::net::TcpStream::connect((host.as_str(), 443)),
                    )
                    .await
                    .unwrap()
                    .unwrap();
                    let error = tokio::time::timeout(
                        Duration::from_secs(10),
                        connector.connect(ServerName::try_from(host).unwrap(), tcp),
                    )
                    .await
                    .unwrap()
                    .unwrap_err();
                    assert!(
                        policy_failure(&error),
                        "not a policy-specific failure: {error:?}"
                    );
                    eprintln!("CAS control {issuer}/{prefix}: rejected by key deny");
                }
            }
            let tcp = tokio::net::TcpStream::connect(("letsencrypt.org", 443))
                .await
                .unwrap();
            tokio::time::timeout(
                Duration::from_secs(10),
                connector.connect(ServerName::try_from("letsencrypt.org").unwrap(), tcp),
            )
            .await
            .unwrap()
            .unwrap();
        });
}
