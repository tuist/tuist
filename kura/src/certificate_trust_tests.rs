use super::*;
use rcgen::{
    BasicConstraints, CertificateParams, DnType, ExtendedKeyUsagePurpose, IsCa, Issuer, KeyPair,
    KeyUsagePurpose,
};

struct Fixture {
    root: CertificateDer<'static>,
    #[cfg(target_os = "linux")]
    root_pem: String,
    spare: CertificateDer<'static>,
    intermediate: CertificateDer<'static>,
    leaf: CertificateDer<'static>,
    identity: Vec<u8>,
}

impl Fixture {
    fn new() -> Self {
        Self::with_leaf(|_| {})
    }

    fn with_leaf(customize: impl FnOnce(&mut CertificateParams)) -> Self {
        let mut root = CertificateParams::new(Vec::<String>::new()).unwrap();
        root.not_before = rcgen::date_time_ymd(2020, 1, 1);
        root.not_after = rcgen::date_time_ymd(2040, 1, 1);
        root.distinguished_name
            .push(DnType::CommonName, "kura-test-root");
        root.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
        root.key_usages = vec![KeyUsagePurpose::KeyCertSign, KeyUsagePurpose::CrlSign];
        let root_key = KeyPair::generate().unwrap();
        let root_cert = root.self_signed(&root_key).unwrap();
        let root_der = root_cert.der().clone();
        #[cfg(target_os = "linux")]
        let root_pem = root_cert.pem();
        let root = Issuer::new(root, root_key);
        let mut intermediate = CertificateParams::new(Vec::<String>::new()).unwrap();
        intermediate.not_before = rcgen::date_time_ymd(2020, 1, 1);
        intermediate.not_after = rcgen::date_time_ymd(2040, 1, 1);
        intermediate
            .distinguished_name
            .push(DnType::CommonName, "kura-test-intermediate");
        intermediate.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
        intermediate.key_usages = vec![KeyUsagePurpose::KeyCertSign, KeyUsagePurpose::CrlSign];
        let intermediate_key = KeyPair::generate().unwrap();
        let intermediate_cert = intermediate.signed_by(&intermediate_key, &root).unwrap();
        let intermediate = Issuer::new(intermediate, intermediate_key);
        let mut leaf = CertificateParams::new(vec!["localhost".into()]).unwrap();
        let now = std::time::SystemTime::now();
        leaf.not_before = (now - std::time::Duration::from_secs(86_400)).into();
        leaf.not_after = (now + std::time::Duration::from_secs(86_400)).into();
        leaf.extended_key_usages = vec![
            ExtendedKeyUsagePurpose::ServerAuth,
            ExtendedKeyUsagePurpose::ClientAuth,
        ];
        customize(&mut leaf);
        let key = KeyPair::generate().unwrap();
        let leaf = leaf.signed_by(&key, &intermediate).unwrap();
        let identity = format!(
            "{}{}{}",
            leaf.pem(),
            intermediate_cert.pem(),
            key.serialize_pem()
        )
        .into_bytes();
        let spare = rcgen::generate_simple_self_signed(vec!["unrelated.test".into()])
            .unwrap()
            .cert
            .der()
            .clone();
        Self {
            root: root_der,
            #[cfg(target_os = "linux")]
            root_pem,
            spare,
            intermediate: intermediate_cert.der().clone(),
            leaf: leaf.der().clone(),
            identity,
        }
    }

    fn roots(&self, native: bool) -> Roots {
        let roots = vec![self.root.clone(), self.spare.clone()];
        if native {
            Roots::Native(roots)
        } else {
            Roots::Explicit(roots)
        }
    }
}

#[cfg(target_os = "linux")]
#[test]
fn unix_native_store_override_errors_and_reload_are_process_scoped() {
    let directory = tempfile::tempdir().unwrap();
    let roots = directory.path().join("roots.pem");
    let empty_directory = directory.path().join("empty");
    std::fs::create_dir(&empty_directory).unwrap();
    let module = module_path!().split_once("::").unwrap().1;
    let output = std::process::Command::new(std::env::current_exe().unwrap())
        .args([
            "--ignored",
            "--exact",
            &format!("{module}::unix_native_store_child"),
        ])
        .env("KURA_TRUST_NATIVE_STORE_CHILD", "1")
        .env("SSL_CERT_FILE", roots)
        .env("SSL_CERT_DIR", empty_directory)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "isolated native-store child failed: {} {}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

#[cfg(target_os = "linux")]
#[test]
#[ignore = "owned child of unix_native_store_override_errors_and_reload_are_process_scoped"]
fn unix_native_store_child() {
    assert_eq!(
        std::env::var("KURA_TRUST_NATIVE_STORE_CHILD").as_deref(),
        Ok("1")
    );
    let path = std::env::var_os("SSL_CERT_FILE").unwrap();
    let first = Fixture::new();
    let second = Fixture::new();
    let verify = |verifier: &dyn ServerCertVerifier, fixture: &Fixture| {
        verifier.verify_server_cert(
            &fixture.leaf,
            std::slice::from_ref(&fixture.intermediate),
            &ServerName::try_from("localhost").unwrap(),
            &[],
            UnixTime::now(),
        )
    };
    let native = || {
        verifier(
            Roots::Native(Vec::new()),
            Arc::new(Policy::default()),
            provider(),
        )
    };
    std::fs::write(&path, &first.root_pem).unwrap();
    reqwest::Client::builder().build().unwrap();
    verify(native().unwrap().as_ref(), &first).unwrap();
    assert!(
        config(
            Roots::Native(Vec::new()),
            None,
            vec![spki_hash(&first.root).unwrap()]
        )
        .is_err()
    );
    std::fs::write(&path, &second.root_pem).unwrap();
    let reloaded = native().unwrap();
    verify(reloaded.as_ref(), &second).unwrap();
    assert!(verify(reloaded.as_ref(), &first).is_err());
    std::fs::write(&path, b"invalid native store").unwrap();
    assert!(native().is_err());
    assert!(reqwest::Client::builder().build().is_err());
    let extra = verifier(
        Roots::Native(vec![first.root.clone()]),
        Arc::new(Policy::default()),
        provider(),
    )
    .unwrap();
    verify(extra.as_ref(), &first).unwrap();
    std::fs::write(&path, &second.root_pem).unwrap();
    assert!(
        verifier(
            Roots::Native(vec![CertificateDer::from(vec![0x30, 0])]),
            Arc::new(Policy::default()),
            provider()
        )
        .is_err()
    );
    std::fs::remove_file(path).unwrap();
    assert!(native().is_err());
}

#[tokio::test]
#[ignore = "explicit credential-free public TLS qualification"]
async fn public_controls_fail_for_certificates_and_unrelated_https_succeeds() {
    assert_eq!(std::env::var("TUIST_TRUST_LIVE").as_deref(), Ok("1"));
    let client = client_builder()
        .unwrap()
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(std::time::Duration::from_secs(8))
        .build()
        .unwrap();
    for authority in ["emudhra", "aaa-emudhra"] {
        for kind in ["dv-g3b", "dv-g3c", "ov-g3b", "ov-g3c", "ev-g3b", "ev-g3c"] {
            let host = format!("{kind}-{authority}.we-have-a-problem.com");
            let error = client
                .get(format!("https://{host}/"))
                .send()
                .await
                .expect_err("public negative unexpectedly accepted");
            let mut cause: Option<&(dyn std::error::Error + 'static)> = Some(&error);
            let mut certificate_failure = false;
            for _ in 0..32 {
                let Some(current) = cause else { break };
                if matches!(
                    current.downcast_ref::<Error>(),
                    Some(Error::InvalidCertificate(_))
                ) {
                    certificate_failure = true;
                    break;
                }
                cause = current
                    .downcast_ref::<std::io::Error>()
                    .and_then(std::io::Error::get_ref)
                    .map(|inner| inner as &(dyn std::error::Error + 'static))
                    .or_else(|| current.source());
            }
            assert!(
                certificate_failure,
                "{host}: expected certificate-specific failure, not timeout/DNS/protocol error"
            );
        }
    }
    assert_eq!(
        client
            .get("https://letsencrypt.org/")
            .send()
            .await
            .unwrap()
            .status(),
        reqwest::StatusCode::OK
    );
}

#[test]
fn real_twelve_keys_and_malformed_der() {
    assert_eq!(POLICY_ID, "emudhra-2026-10-19-v2");
    let mut found = std::collections::HashSet::new();
    for pem in [
        include_bytes!("../test/certificate-trust/issuer-roots.pem").as_slice(),
        include_bytes!("../test/certificate-trust/distrusted-intermediates.pem").as_slice(),
    ] {
        for certificate in certificates(pem).unwrap() {
            let hash = spki_hash(&certificate).unwrap();
            if BLOCKED_SPKI_HASHES.contains(&hash.as_str()) {
                found.insert(hash);
                assert!(matches!(
                    Policy::default().check(&certificate),
                    Err(Error::InvalidCertificate(
                        CertificateError::ApplicationVerificationFailure
                    ))
                ));
            }
        }
    }
    assert_eq!(found.len(), 12);
    assert!(spki_hash(&CertificateDer::from(vec![0x30, 0x80])).is_err());
}

#[test]
fn native_and_explicit_paths_restrict_accepted_leaf_intermediate_and_absent_root() {
    let fixture = Fixture::new();
    let name = ServerName::try_from("localhost").unwrap();
    for native in [false, true] {
        let ordinary = verifier(
            fixture.roots(native),
            Arc::new(Policy::default()),
            provider(),
        )
        .unwrap();
        ordinary
            .verify_server_cert(
                &fixture.leaf,
                std::slice::from_ref(&fixture.intermediate),
                &name,
                &[],
                UnixTime::now(),
            )
            .unwrap();
        for certificate in [&fixture.leaf, &fixture.intermediate, &fixture.root] {
            let denied = verifier(
                fixture.roots(native),
                Arc::new(Policy::new(vec![spki_hash(certificate).unwrap()])),
                provider(),
            );
            match denied {
                Ok(denied) => assert!(matches!(
                    denied.verify_server_cert(
                        &fixture.leaf,
                        std::slice::from_ref(&fixture.intermediate),
                        &name,
                        &[],
                        UnixTime::now()
                    ),
                    Err(Error::InvalidCertificate(_))
                )),
                Err(_) => assert_eq!(certificate, &fixture.root),
            }
        }
        assert!(
            ordinary
                .verify_server_cert(
                    &fixture.leaf,
                    std::slice::from_ref(&fixture.intermediate),
                    &ServerName::try_from("wrong.test").unwrap(),
                    &[],
                    UnixTime::now()
                )
                .is_err()
        );
        assert!(
            ordinary
                .verify_server_cert(&fixture.leaf, &[], &name, &[], UnixTime::now())
                .is_err()
        );
        let mut damaged = fixture.leaf.to_vec();
        *damaged.last_mut().unwrap() ^= 1;
        assert!(
            ordinary
                .verify_server_cert(
                    &CertificateDer::from(damaged),
                    std::slice::from_ref(&fixture.intermediate),
                    &name,
                    &[],
                    UnixTime::now()
                )
                .is_err()
        );
        assert!(
            ordinary
                .verify_server_cert(
                    &fixture.leaf,
                    std::slice::from_ref(&fixture.intermediate),
                    &name,
                    &[],
                    UnixTime::since_unix_epoch(std::time::Duration::from_secs(4_102_444_800))
                )
                .is_err()
        );
    }
}

#[cfg(target_vendor = "apple")]
#[test]
fn native_evaluated_chain_deny_checks_an_anchor_absent_from_peers() {
    use security_framework::certificate::SecCertificate;
    let fixture = Fixture::new();
    // Deliberately leave the private test anchor unfiltered to prove the native
    // evaluated-chain check, independently of candidate-anchor filtering.
    for certificate in [&fixture.leaf, &fixture.intermediate, &fixture.root] {
        let verifier = apple::NativeVerifier {
            extra: vec![SecCertificate::from_der(&fixture.root).unwrap()],
            policy: Arc::new(Policy::new(vec![spki_hash(certificate).unwrap()])),
            provider: provider(),
        };
        assert!(matches!(
            verifier.verify_server_cert(
                &fixture.leaf,
                std::slice::from_ref(&fixture.intermediate),
                &ServerName::try_from("localhost").unwrap(),
                &[],
                UnixTime::now()
            ),
            Err(Error::InvalidCertificate(
                CertificateError::ApplicationVerificationFailure
            ))
        ));
    }
}

#[test]
fn ordinary_usage_critical_extensions_and_unknown_ca_still_fail() {
    for fixture in [
        Fixture::with_leaf(|leaf| {
            leaf.extended_key_usages = vec![ExtendedKeyUsagePurpose::ClientAuth];
        }),
        Fixture::with_leaf(|leaf| {
            let mut extension =
                rcgen::CustomExtension::from_oid_content(&[1, 2, 3, 4], vec![0x05, 0x00]);
            extension.set_criticality(true);
            leaf.custom_extensions.push(extension);
        }),
    ] {
        for native in [false, true] {
            let ordinary = verifier(
                fixture.roots(native),
                Arc::new(Policy::default()),
                provider(),
            )
            .unwrap();
            assert!(
                ordinary
                    .verify_server_cert(
                        &fixture.leaf,
                        std::slice::from_ref(&fixture.intermediate),
                        &ServerName::try_from("localhost").unwrap(),
                        &[],
                        UnixTime::now()
                    )
                    .is_err()
            );
        }
    }
    let fixture = Fixture::new();
    let other = Fixture::new();
    for native in [false, true] {
        let ordinary =
            verifier(other.roots(native), Arc::new(Policy::default()), provider()).unwrap();
        assert!(
            ordinary
                .verify_server_cert(
                    &fixture.leaf,
                    std::slice::from_ref(&fixture.intermediate),
                    &ServerName::try_from("localhost").unwrap(),
                    &[],
                    UnixTime::now()
                )
                .is_err()
        );
    }
}

#[test]
fn typed_failure_categories_follow_io_causes_without_rendering_them() {
    for (error, category) in [
        (
            Error::InvalidCertificate(CertificateError::ApplicationVerificationFailure),
            "key_policy",
        ),
        (
            Error::InvalidCertificate(CertificateError::UnknownIssuer),
            "certificate_validation",
        ),
        (Error::DecryptError, "tls_protocol"),
    ] {
        let error = std::io::Error::other(error);
        assert_eq!(failure_category(&error), Some(category));
        assert!(terminal_transport_failure(&error));
    }
    assert_eq!(
        failure_category(&std::io::Error::from(std::io::ErrorKind::NotFound)),
        None
    );
    #[derive(Debug)]
    struct Cycle;
    impl std::fmt::Display for Cycle {
        fn fmt(&self, _: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            panic!("typed classification must not render causes")
        }
    }
    impl std::error::Error for Cycle {
        fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
            Some(self)
        }
    }
    assert_eq!(failure_category(&Cycle), Some("error_chain_limit"));
    assert!(terminal_transport_failure(&Cycle));
}

#[test]
fn inbound_client_auth_is_mandatory_and_restricts_accepted_keys() {
    let fixture = Fixture::new();
    let roots = || {
        let mut roots = RootCertStore::empty();
        roots.add(fixture.root.clone()).unwrap();
        roots.add(fixture.spare.clone()).unwrap();
        roots
    };
    let ordinary = client_auth_verifier(roots(), Vec::new()).unwrap();
    assert!(ordinary.offer_client_auth());
    assert!(ordinary.client_auth_mandatory());
    assert!(!ordinary.root_hint_subjects().is_empty());
    ordinary
        .verify_client_cert(
            &fixture.leaf,
            std::slice::from_ref(&fixture.intermediate),
            UnixTime::now(),
        )
        .unwrap();
    for certificate in [&fixture.leaf, &fixture.intermediate, &fixture.root] {
        let denied = client_auth_verifier(roots(), vec![spki_hash(certificate).unwrap()]).unwrap();
        assert!(
            denied
                .verify_client_cert(
                    &fixture.leaf,
                    std::slice::from_ref(&fixture.intermediate),
                    UnixTime::now()
                )
                .is_err()
        );
    }
}

#[test]
#[ignore = "explicit existing OpenSSL 3 fixture-tool qualification"]
fn valid_pkcs1_and_sec1_identities_match_original_reqwest_validation() {
    let openssl =
        std::env::var("KURA_TRUST_OPENSSL").expect("explicit existing OpenSSL 3 is required");
    let version = std::process::Command::new(&openssl)
        .arg("version")
        .output()
        .unwrap();
    assert!(version.status.success() && version.stdout.starts_with(b"OpenSSL 3."));
    let directory = tempfile::tempdir().unwrap();
    for rsa in [false, true] {
        let pkcs8 = directory.path().join("private.pk8");
        if rsa {
            assert!(
                std::process::Command::new(&openssl)
                    .args([
                        "genpkey",
                        "-algorithm",
                        "RSA",
                        "-pkeyopt",
                        "rsa_keygen_bits:2048",
                        "-out"
                    ])
                    .arg(&pkcs8)
                    .output()
                    .unwrap()
                    .status
                    .success()
            );
        } else {
            std::fs::write(&pkcs8, KeyPair::generate().unwrap().serialize_pem()).unwrap();
        }
        let original = std::fs::read_to_string(&pkcs8).unwrap();
        let key = KeyPair::from_pem(&original).unwrap();
        let certificate = CertificateParams::new(vec!["localhost".into()])
            .unwrap()
            .self_signed(&key)
            .unwrap();
        let traditional = directory.path().join("private.traditional");
        assert!(
            std::process::Command::new(&openssl)
                .args(["pkey", "-traditional", "-in"])
                .arg(&pkcs8)
                .arg("-out")
                .arg(&traditional)
                .output()
                .unwrap()
                .status
                .success()
        );
        let pem = format!(
            "{}{}",
            certificate.pem(),
            std::fs::read_to_string(traditional).unwrap()
        );
        let (_, parsed) = parse_identity(pem.as_bytes()).unwrap();
        assert!(matches!(
            (&parsed, rsa),
            (PrivateKeyDer::Pkcs1(_), true) | (PrivateKeyDer::Sec1(_), false)
        ));
        let identity = reqwest::Identity::from_pem(pem.as_bytes()).unwrap();
        reqwest::Client::builder()
            .identity(identity)
            .tls_certs_only([reqwest::Certificate::from_der(certificate.der()).unwrap()])
            .build()
            .unwrap();
        config(
            Roots::Explicit(vec![certificate.der().clone()]),
            Some(pem.as_bytes()),
            Vec::new(),
        )
        .unwrap();
    }
}

#[test]
fn identity_parsing_and_default_config_match_reqwest() {
    let fixture = Fixture::new();
    let config = config(fixture.roots(false), Some(&fixture.identity), Vec::new()).unwrap();
    assert!(config.enable_sni);
    assert_eq!(
        config.alpn_protocols,
        [b"h2".to_vec(), b"http/1.1".to_vec()]
    );
    let (chain, _) = parse_identity(&fixture.identity).unwrap();
    assert_eq!(chain, [fixture.leaf.clone(), fixture.intermediate.clone()]);
    let second_key = KeyPair::generate().unwrap();
    let mut wrong_last_key = fixture.identity.clone();
    wrong_last_key.extend_from_slice(second_key.serialize_pem().as_bytes());
    let original = reqwest::Identity::from_pem(&wrong_last_key).unwrap();
    assert!(
        reqwest::Client::builder()
            .identity(original)
            .tls_certs_only([reqwest::Certificate::from_der(&fixture.root).unwrap()])
            .build()
            .is_err()
    );
    assert!(super::config(fixture.roots(false), Some(&wrong_last_key), Vec::new()).is_err());
    let mut unsupported = fixture.identity.clone();
    unsupported.extend_from_slice(second_key.public_key_pem().as_bytes());
    assert!(reqwest::Identity::from_pem(&unsupported).is_err());
    assert!(parse_identity(&unsupported).is_err());
    assert!(parse_identity(b"not a key").is_err());
    assert!(reqwest::Identity::from_pem(b"not a key").is_err());
}

async fn read_headers(stream: &mut (impl tokio::io::AsyncRead + Unpin)) -> Option<String> {
    use tokio::io::AsyncReadExt;
    let mut headers = Vec::new();
    while headers.len() < 8192 {
        let byte = stream.read_u8().await.ok()?;
        headers.push(byte);
        if headers.ends_with(b"\r\n\r\n") {
            return String::from_utf8(headers).ok();
        }
    }
    None
}

#[tokio::test]
async fn https_connect_protects_both_pkis_and_keeps_credentials_on_their_leg() {
    use tokio::io::AsyncWriteExt;
    let target = Fixture::new();
    let proxy = Fixture::new();
    for deny in [
        None,
        Some((&proxy.leaf, true)),
        Some((&proxy.root, true)),
        Some((&target.leaf, false)),
        Some((&target.root, false)),
    ] {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let proxy_listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let proxy_address = proxy_listener.local_addr().unwrap();
        let reached_proxy = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let reached_target = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let target_observed = reached_target.clone();
        let make_server = |fixture: &Fixture| {
            let (chain, key) = parse_identity(&fixture.identity).unwrap();
            let mut config = rustls::ServerConfig::builder_with_provider(provider())
                .with_safe_default_protocol_versions()
                .unwrap()
                .with_no_client_auth()
                .with_single_cert(chain, key)
                .unwrap();
            config.alpn_protocols = vec![b"http/1.1".to_vec()];
            tokio_rustls::TlsAcceptor::from(Arc::new(config))
        };
        let target_acceptor = make_server(&target);
        let proxy_acceptor = make_server(&proxy);
        let target_task = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            if let Ok(mut tls) = target_acceptor.accept(stream).await {
                if let Some(headers) = read_headers(&mut tls).await {
                    let headers = headers.to_lowercase();
                    assert!(headers.contains("authorization: bearer fixture-origin-only"));
                    assert!(!headers.contains("proxy-authorization"));
                    target_observed.store(true, std::sync::atomic::Ordering::SeqCst);
                    tls.write_all(
                        b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok",
                    )
                    .await
                    .unwrap();
                }
            }
        });
        let proxy_observed = reached_proxy.clone();
        let proxy_task = tokio::spawn(async move {
            let (stream, _) = proxy_listener.accept().await.unwrap();
            if let Ok(mut tls) = proxy_acceptor.accept(stream).await {
                assert_eq!(tls.get_ref().1.alpn_protocol(), None);
                if let Some(headers) = read_headers(&mut tls).await {
                    let headers = headers.to_lowercase();
                    assert!(headers.starts_with("connect localhost:"));
                    assert!(headers.contains("proxy-authorization: basic "));
                    assert!(!headers.contains("fixture-origin-only"));
                    proxy_observed.store(true, std::sync::atomic::Ordering::SeqCst);
                    let mut target = tokio::net::TcpStream::connect(address).await.unwrap();
                    tls.write_all(b"HTTP/1.1 200 Connection established\r\n\r\n")
                        .await
                        .unwrap();
                    let _ = tokio::io::copy_bidirectional(&mut tls, &mut target).await;
                }
            }
        });
        let roots = Roots::Native(vec![target.root.clone(), proxy.root.clone()]);
        let additional = deny
            .map(|(certificate, _)| vec![spki_hash(certificate).unwrap()])
            .unwrap_or_default();
        let client = reqwest::Client::builder()
            .tls_backend_preconfigured(config(roots, None, additional).unwrap())
            .proxy(
                reqwest::Proxy::https(format!("https://localhost:{}", proxy_address.port()))
                    .unwrap()
                    .basic_auth("fixture-user", "fixture-password"),
            )
            .timeout(std::time::Duration::from_secs(3))
            .build()
            .unwrap();
        let result = client
            .get(format!("https://localhost:{}/", address.port()))
            .bearer_auth("fixture-origin-only")
            .send()
            .await;
        if deny.is_none() {
            assert_eq!(result.unwrap().text().await.unwrap(), "ok");
        } else {
            assert!(terminal_transport_failure(&result.unwrap_err()));
        }
        assert_eq!(
            reached_proxy.load(std::sync::atomic::Ordering::SeqCst),
            !deny.is_some_and(|(_, proxy)| proxy)
        );
        assert_eq!(
            reached_target.load(std::sync::atomic::Ordering::SeqCst),
            deny.is_none()
        );
        target_task.abort();
        proxy_task.abort();
        let _ = target_task.await;
        let _ = proxy_task.await;
    }
}

#[tokio::test]
async fn actual_http2_negotiates_with_both_tls_versions() {
    use hyper_util::rt::{TokioExecutor, TokioIo};
    for version in [&rustls::version::TLS12, &rustls::version::TLS13] {
        let fixture = Fixture::new();
        let (chain, key) = parse_identity(&fixture.identity).unwrap();
        let mut server = rustls::ServerConfig::builder_with_provider(provider())
            .with_protocol_versions(&[version])
            .unwrap()
            .with_no_client_auth()
            .with_single_cert(chain, key)
            .unwrap();
        server.alpn_protocols = vec![b"h2".to_vec()];
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let task = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let tls = tokio_rustls::TlsAcceptor::from(Arc::new(server))
                .accept(stream)
                .await
                .unwrap();
            assert_eq!(tls.get_ref().1.alpn_protocol(), Some(b"h2".as_slice()));
            assert_eq!(tls.get_ref().1.protocol_version(), Some(version.version));
            let service = hyper::service::service_fn(|_| async {
                Ok::<_, std::convert::Infallible>(hyper::Response::new(http_body_util::Full::new(
                    bytes::Bytes::from_static(b"ok"),
                )))
            });
            hyper::server::conn::http2::Builder::new(TokioExecutor::new())
                .serve_connection(TokioIo::new(tls), service)
                .await
                .unwrap();
        });
        let client = reqwest::Client::builder()
            .tls_backend_preconfigured(config(fixture.roots(true), None, Vec::new()).unwrap())
            .no_proxy()
            .timeout(std::time::Duration::from_secs(3))
            .build()
            .unwrap();
        let response = client
            .get(format!("https://localhost:{}/", address.port()))
            .send()
            .await
            .unwrap();
        assert_eq!(response.version(), reqwest::Version::HTTP_2);
        assert_eq!(response.text().await.unwrap(), "ok");
        drop(client);
        tokio::time::timeout(std::time::Duration::from_secs(3), task)
            .await
            .unwrap()
            .unwrap();
    }
}

#[tokio::test]
async fn actual_https_preserves_private_trust_and_denies_before_request_delivery() {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let fixture = Fixture::new();
    let (chain, key) = parse_identity(&fixture.identity).unwrap();
    let mut server = rustls::ServerConfig::builder_with_provider(provider())
        .with_safe_default_protocol_versions()
        .unwrap()
        .with_no_client_auth()
        .with_single_cert(chain, key)
        .unwrap();
    server.alpn_protocols = vec![b"http/1.1".to_vec()];
    let acceptor = tokio_rustls::TlsAcceptor::from(Arc::new(server));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let delivered = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let observed = delivered.clone();
    let task = tokio::spawn(async move {
        loop {
            let (stream, _) = listener.accept().await.unwrap();
            let acceptor = acceptor.clone();
            let observed = observed.clone();
            tokio::spawn(async move {
                if let Ok(mut tls) = acceptor.accept(stream).await {
                    let mut request = [0; 4096];
                    if let Ok(count) = tls.read(&mut request).await {
                        if count > 0 {
                            observed.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                            tls.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok").await.unwrap();
                        }
                    }
                }
            });
        }
    });
    for native in [false, true] {
        for deny in [
            None,
            Some(&fixture.leaf),
            Some(&fixture.intermediate),
            Some(&fixture.root),
        ] {
            let additional = deny
                .map(|certificate| vec![spki_hash(certificate).unwrap()])
                .unwrap_or_default();
            let before = delivered.load(std::sync::atomic::Ordering::SeqCst);
            let result = reqwest::Client::builder()
                .tls_backend_preconfigured(config(fixture.roots(native), None, additional).unwrap())
                .resolve("localhost", address)
                .no_proxy()
                .timeout(std::time::Duration::from_secs(3))
                .build()
                .unwrap()
                .get(format!("https://localhost:{}/", address.port()))
                .bearer_auth("fixture-only-not-a-credential")
                .send()
                .await;
            if deny.is_none() {
                assert_eq!(result.unwrap().text().await.unwrap(), "ok");
                assert_eq!(
                    delivered.load(std::sync::atomic::Ordering::SeqCst),
                    before + 1
                );
            } else {
                let error = result.unwrap_err();
                assert!(terminal_transport_failure(&error));
                assert_eq!(delivered.load(std::sync::atomic::Ordering::SeqCst), before);
            }
        }
    }
    task.abort();
    let _ = task.await;
}
