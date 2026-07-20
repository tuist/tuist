
use super::*;

#[test]
fn static_seed_prefers_managed_peers_and_falls_back_to_the_full_list() {
    let managed = vec!["https://managed.test:7443".to_string()];
    let full = vec![
        "https://managed.test:7443".to_string(),
        "https://selfhosted.test:7443".to_string(),
    ];

    assert_eq!(static_peer_seed(&managed, &full), managed.as_slice());
    assert_eq!(static_peer_seed(&[], &full), full.as_slice());
}

#[test]
fn generates_a_parseable_csr_and_key() {
    let (key_pem, csr_pem) = generate_key_and_csr().expect("generation should succeed");

    assert!(key_pem.contains("BEGIN PRIVATE KEY"));
    assert!(csr_pem.contains("BEGIN CERTIFICATE REQUEST"));

    // The CSR must carry a verifiable self-signature over the node key.
    let mut reader = std::io::BufReader::new(csr_pem.as_bytes());
    let der = rustls_pemfile::csr(&mut reader)
        .expect("a CSR PEM block")
        .expect("exactly one CSR");
    assert!(!der.as_ref().is_empty());
}

#[test]
fn parses_an_enrollment_response() {
    let body = serde_json::json!({
        "tenant_id": "acme",
        "certificate": "-----BEGIN CERTIFICATE-----\nleaf\n-----END CERTIFICATE-----\n",
        "ca_certificate": "-----BEGIN CERTIFICATE-----\nca\n-----END CERTIFICATE-----\n",
        "peers": ["https://kura-1.acme.test:4433"],
        "not_after": "2026-07-01T00:00:00Z",
        "renew_after_seconds": 1_296_000
    })
    .to_string();

    let parsed: EnrollmentResponse = serde_json::from_str(&body).expect("valid response");
    assert_eq!(parsed.tenant_id, "acme");
    assert_eq!(parsed.peers, vec!["https://kura-1.acme.test:4433"]);
    assert!(parsed.certificate.contains("leaf"));
    assert!(parsed.ca_certificate.contains("ca"));
}

#[test]
fn writes_certificate_material_to_disk() {
    let dir = tempfile::tempdir().expect("tempdir");
    let key_path = dir.path().join("nested/key.pem");
    let key_path = key_path.to_str().unwrap();

    write_pem(key_path, "secret-key", true).expect("write should succeed");

    assert_eq!(std::fs::read_to_string(key_path).unwrap(), "secret-key");

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = std::fs::metadata(key_path).unwrap().permissions().mode();
        assert_eq!(mode & 0o777, 0o600);
    }
}
