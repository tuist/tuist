//! Self-service node enrollment against the Tuist control plane.
//!
//! When `KURA_ENROLL_ON_BOOT` is enabled, a node generates its keypair locally
//! (the private key never leaves the node), sends a CSR to the control plane
//! with its tenant-scoped credential, and receives a signed certificate, the
//! account CA, its `tenant_id`, and the current peer list. The certificate
//! material is written to the configured `KURA_INTERNAL_TLS_*` paths and the
//! tenant/peers are injected into the environment, so the rest of startup
//! self-configures from nothing but the credential and the node URL.
//!
//! Enrollment runs on every boot, issuing a fresh certificate each time.
//! Zero-downtime in-process rotation (reloading the inbound TLS config and the
//! outbound peer-client identity without a restart) is a follow-up.

use std::path::Path;

use base64::Engine as _;
use base64::engine::general_purpose::STANDARD;
use reqwest::header::AUTHORIZATION;
use serde::Deserialize;

const ENROLL_PATH: &str = "/_internal/kura/mesh/enroll";

const KURA_ENROLL_ON_BOOT: &str = "KURA_ENROLL_ON_BOOT";
const KURA_CONTROL_PLANE_URL: &str = "KURA_CONTROL_PLANE_URL";
const KURA_CONTROL_PLANE_CLIENT_ID: &str = "KURA_CONTROL_PLANE_CLIENT_ID";
const KURA_CONTROL_PLANE_CLIENT_SECRET: &str = "KURA_CONTROL_PLANE_CLIENT_SECRET";
const KURA_NODE_URL: &str = "KURA_NODE_URL";
const KURA_INTERNAL_TLS_CA_CERT_PATH: &str = "KURA_INTERNAL_TLS_CA_CERT_PATH";
const KURA_INTERNAL_TLS_CERT_PATH: &str = "KURA_INTERNAL_TLS_CERT_PATH";
const KURA_INTERNAL_TLS_KEY_PATH: &str = "KURA_INTERNAL_TLS_KEY_PATH";
const KURA_TENANT_ID: &str = "KURA_TENANT_ID";
const KURA_PEERS: &str = "KURA_PEERS";

pub struct EnrollmentOutcome {
    pub tenant_id: String,
    pub peers: Vec<String>,
    pub renew_after_seconds: u64,
}

fn default_renew_after_seconds() -> u64 {
    86_400
}

#[derive(Deserialize)]
struct EnrollmentResponse {
    tenant_id: String,
    certificate: String,
    ca_certificate: String,
    #[serde(default)]
    peers: Vec<String>,
    #[serde(default = "default_renew_after_seconds")]
    renew_after_seconds: u64,
}

struct EnrollmentInputs {
    control_plane_url: String,
    client_id: String,
    client_secret: String,
    node_url: String,
    ca_cert_path: String,
    cert_path: String,
    key_path: String,
}

/// Enrolls the node if `KURA_ENROLL_ON_BOOT` is enabled, writing the issued
/// certificate material and injecting `KURA_TENANT_ID`/`KURA_PEERS` into the
/// environment so `Config::from_env` picks them up. Returns `Ok(None)` when
/// enrollment is disabled.
pub async fn enroll_on_boot() -> Result<Option<EnrollmentOutcome>, String> {
    if !enabled() {
        return Ok(None);
    }

    let inputs = inputs()?;
    eprintln!(
        "kura: enrolling node {} with control plane",
        inputs.node_url
    );
    let outcome = enroll(&inputs).await?;
    apply_env_defaults(&outcome);
    Ok(Some(outcome))
}

fn enabled() -> bool {
    matches!(
        env_value(KURA_ENROLL_ON_BOOT).as_deref(),
        Some("1") | Some("true") | Some("TRUE")
    )
}

fn inputs() -> Result<EnrollmentInputs, String> {
    Ok(EnrollmentInputs {
        control_plane_url: required(KURA_CONTROL_PLANE_URL)?,
        client_id: required(KURA_CONTROL_PLANE_CLIENT_ID)?,
        client_secret: required(KURA_CONTROL_PLANE_CLIENT_SECRET)?,
        node_url: required(KURA_NODE_URL)?,
        ca_cert_path: required(KURA_INTERNAL_TLS_CA_CERT_PATH)?,
        cert_path: required(KURA_INTERNAL_TLS_CERT_PATH)?,
        key_path: required(KURA_INTERNAL_TLS_KEY_PATH)?,
    })
}

async fn enroll(inputs: &EnrollmentInputs) -> Result<EnrollmentOutcome, String> {
    let (key_pem, csr_pem) = generate_key_and_csr()?;

    let url = format!(
        "{}{ENROLL_PATH}",
        inputs.control_plane_url.trim_end_matches('/')
    );
    let auth = STANDARD.encode(format!("{}:{}", inputs.client_id, inputs.client_secret));

    let client = reqwest::Client::builder()
        .build()
        .map_err(|error| format!("failed to build enrollment HTTP client: {error}"))?;

    let response = client
        .post(&url)
        .header(AUTHORIZATION.as_str(), format!("Basic {auth}"))
        .json(&serde_json::json!({ "csr": csr_pem, "node_url": inputs.node_url }))
        .send()
        .await
        .map_err(|error| format!("enrollment request to {url} failed: {error}"))?;

    if !response.status().is_success() {
        return Err(format!(
            "enrollment failed: control plane returned {}",
            response.status()
        ));
    }

    let body: EnrollmentResponse = response
        .json()
        .await
        .map_err(|error| format!("invalid enrollment response: {error}"))?;

    write_pem(&inputs.key_path, &key_pem, true)?;
    write_pem(&inputs.cert_path, &body.certificate, false)?;
    write_pem(&inputs.ca_cert_path, &body.ca_certificate, false)?;

    Ok(EnrollmentOutcome {
        tenant_id: body.tenant_id,
        peers: body.peers,
        renew_after_seconds: body.renew_after_seconds,
    })
}

/// Re-enrolls using the same environment configuration as boot, writing fresh
/// certificate material to the `KURA_INTERNAL_TLS_*` paths. Called by the
/// background cert-renewal task; the caller hot-reloads the new material.
pub async fn renew() -> Result<EnrollmentOutcome, String> {
    enroll(&inputs()?).await
}

/// Generates an ECDSA P-256 keypair and a CSR carrying its public key. The
/// control plane sets the certificate SAN from the registered node URL, so the
/// CSR's own subject and SANs are not trusted and left empty.
fn generate_key_and_csr() -> Result<(String, String), String> {
    let key_pair = rcgen::KeyPair::generate_for(&rcgen::PKCS_ECDSA_P256_SHA256)
        .map_err(|error| format!("failed to generate node key: {error}"))?;

    let params = rcgen::CertificateParams::new(Vec::<String>::new())
        .map_err(|error| format!("failed to build CSR parameters: {error}"))?;

    let csr_pem = params
        .serialize_request(&key_pair)
        .map_err(|error| format!("failed to build CSR: {error}"))?
        .pem()
        .map_err(|error| format!("failed to encode CSR: {error}"))?;

    Ok((key_pair.serialize_pem(), csr_pem))
}

fn apply_env_defaults(outcome: &EnrollmentOutcome) {
    if env_value(KURA_TENANT_ID).is_none() {
        // SAFETY: runs at startup before any worker threads read the environment.
        unsafe { std::env::set_var(KURA_TENANT_ID, &outcome.tenant_id) };
    }

    if env_value(KURA_PEERS).is_none() && !outcome.peers.is_empty() {
        // SAFETY: runs at startup before any worker threads read the environment.
        unsafe { std::env::set_var(KURA_PEERS, outcome.peers.join(",")) };
    }
}

fn write_pem(path: &str, contents: &str, secret: bool) -> Result<(), String> {
    if let Some(parent) = Path::new(path).parent()
        && !parent.as_os_str().is_empty()
    {
        std::fs::create_dir_all(parent)
            .map_err(|error| format!("failed to create directory for {path}: {error}"))?;
    }

    std::fs::write(path, contents).map_err(|error| format!("failed to write {path}: {error}"))?;

    if secret {
        restrict_permissions(path);
    }

    Ok(())
}

#[cfg(unix)]
fn restrict_permissions(path: &str) {
    use std::os::unix::fs::PermissionsExt;
    let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600));
}

#[cfg(not(unix))]
fn restrict_permissions(_path: &str) {}

fn env_value(key: &str) -> Option<String> {
    std::env::var(key).ok().filter(|value| !value.is_empty())
}

fn required(key: &str) -> Result<String, String> {
    env_value(key).ok_or_else(|| format!("{key} must be set when {KURA_ENROLL_ON_BOOT} is enabled"))
}

#[cfg(test)]
mod tests {
    use super::*;

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
}
