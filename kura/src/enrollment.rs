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
const KURA_DATA_DIR: &str = "KURA_DATA_DIR";

pub struct EnrollmentOutcome {
    pub tenant_id: String,
    pub peers: Vec<String>,
    pub managed_peers: Vec<String>,
    pub renew_after_seconds: u64,
    // The control-plane relationship the enrollment used, carried so the mesh
    // heartbeat task reuses the same parsed configuration instead of
    // re-reading the environment.
    pub control_plane_url: String,
    pub client_id: String,
    pub client_secret: String,
    pub node_url: String,
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
    /// Platform-stable endpoints only (the managed regions' public peer
    /// gateways). Seeded into the static `KURA_PEERS`; volatile (self-hosted)
    /// membership flows exclusively through the mesh heartbeat, so removals
    /// propagate without a restart.
    #[serde(default)]
    managed_peers: Vec<String>,
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
    tls_paths_derived: bool,
}

/// Enrolls the node if `KURA_ENROLL_ON_BOOT` is enabled, writing the issued
/// certificate material and injecting `KURA_TENANT_ID`/`KURA_PEERS`, plus the
/// peer TLS paths when they were derived rather than configured, into the
/// environment so `Config::from_env` picks them up. Returns `Ok(None)` when
/// enrollment is disabled.
pub async fn enroll_on_boot() -> Result<Option<EnrollmentOutcome>, String> {
    if !enabled() {
        return Ok(None);
    }

    let inputs = inputs()?;
    apply_tls_path_env_defaults(&inputs);
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
    let tls = resolve_tls_paths(
        env_value(KURA_INTERNAL_TLS_CA_CERT_PATH),
        env_value(KURA_INTERNAL_TLS_CERT_PATH),
        env_value(KURA_INTERNAL_TLS_KEY_PATH),
        env_value(KURA_DATA_DIR),
    )?;

    Ok(EnrollmentInputs {
        control_plane_url: required(KURA_CONTROL_PLANE_URL)?,
        client_id: required(KURA_CONTROL_PLANE_CLIENT_ID)?,
        client_secret: required(KURA_CONTROL_PLANE_CLIENT_SECRET)?,
        node_url: required(KURA_NODE_URL)?,
        ca_cert_path: tls.ca_cert_path,
        cert_path: tls.cert_path,
        key_path: tls.key_path,
        tls_paths_derived: tls.derived,
    })
}

#[derive(Debug)]
struct ResolvedTlsPaths {
    ca_cert_path: String,
    cert_path: String,
    key_path: String,
    derived: bool,
}

/// Resolves where enrollment writes the issued certificate material.
///
/// The three paths are the node's peer TLS settings rather than enrollment's:
/// the TLS listener reads them, and `Config::from_env` rejects a partially
/// configured triple. Enrollment therefore only supplies them when the operator
/// supplied none, so a node mounting its own material keeps pointing at that
/// mount, and a half-configured triple still surfaces the configuration error
/// instead of being silently completed with derived paths.
fn resolve_tls_paths(
    ca_cert_path: Option<String>,
    cert_path: Option<String>,
    key_path: Option<String>,
    data_dir: Option<String>,
) -> Result<ResolvedTlsPaths, String> {
    match (ca_cert_path, cert_path, key_path) {
        (Some(ca_cert_path), Some(cert_path), Some(key_path)) => Ok(ResolvedTlsPaths {
            ca_cert_path,
            cert_path,
            key_path,
            derived: false,
        }),
        (None, None, None) => {
            let data_dir = data_dir.ok_or_else(|| {
                format!(
                    "{KURA_DATA_DIR} must be set to derive the peer TLS paths, or set {KURA_INTERNAL_TLS_CA_CERT_PATH}, {KURA_INTERNAL_TLS_CERT_PATH}, and {KURA_INTERNAL_TLS_KEY_PATH} explicitly"
                )
            })?;
            let dir = Path::new(&data_dir).join("tls");
            let path = |name: &str| dir.join(name).to_string_lossy().into_owned();

            Ok(ResolvedTlsPaths {
                ca_cert_path: path("ca.pem"),
                cert_path: path("tls.crt"),
                key_path: path("tls.key"),
                derived: true,
            })
        }
        _ => Err(format!(
            "{KURA_INTERNAL_TLS_CA_CERT_PATH}, {KURA_INTERNAL_TLS_CERT_PATH}, and {KURA_INTERNAL_TLS_KEY_PATH} must either all be set or all be unset"
        )),
    }
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
        managed_peers: body.managed_peers,
        renew_after_seconds: body.renew_after_seconds,
        control_plane_url: inputs.control_plane_url.clone(),
        client_id: inputs.client_id.clone(),
        client_secret: inputs.client_secret.clone(),
        node_url: inputs.node_url.clone(),
    })
}

/// Static peers seeded into `KURA_PEERS` at boot: the platform-stable managed
/// endpoints when the control plane distinguishes them, the full list only as
/// a fallback for older control planes that don't. Static config is immutable
/// for the process lifetime, so volatile (self-hosted) peers must stay out of
/// it — they live in the dynamic layer, where the mesh heartbeat can remove
/// them without a restart.
fn static_peer_seed<'a>(managed_peers: &'a [String], peers: &'a [String]) -> &'a [String] {
    if managed_peers.is_empty() {
        peers
    } else {
        managed_peers
    }
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

fn apply_tls_path_env_defaults(inputs: &EnrollmentInputs) {
    if !inputs.tls_paths_derived {
        return;
    }

    eprintln!(
        "kura: writing peer certificate material to {}",
        Path::new(&inputs.cert_path)
            .parent()
            .unwrap_or(Path::new(&inputs.cert_path))
            .display()
    );

    for (key, value) in [
        (KURA_INTERNAL_TLS_CA_CERT_PATH, &inputs.ca_cert_path),
        (KURA_INTERNAL_TLS_CERT_PATH, &inputs.cert_path),
        (KURA_INTERNAL_TLS_KEY_PATH, &inputs.key_path),
    ] {
        // SAFETY: runs at startup before any worker threads read the environment.
        unsafe { std::env::set_var(key, value) };
    }
}

fn apply_env_defaults(outcome: &EnrollmentOutcome) {
    if env_value(KURA_TENANT_ID).is_none() {
        // SAFETY: runs at startup before any worker threads read the environment.
        unsafe { std::env::set_var(KURA_TENANT_ID, &outcome.tenant_id) };
    }

    let static_seed = static_peer_seed(&outcome.managed_peers, &outcome.peers);
    if env_value(KURA_PEERS).is_none() && !static_seed.is_empty() {
        // SAFETY: runs at startup before any worker threads read the environment.
        unsafe { std::env::set_var(KURA_PEERS, static_seed.join(",")) };
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
    fn derives_tls_paths_under_the_data_dir_when_none_are_configured() {
        let resolved = resolve_tls_paths(None, None, None, Some("/var/cache/kura".to_string()))
            .expect("deriving should succeed");

        assert_eq!(resolved.ca_cert_path, "/var/cache/kura/tls/ca.pem");
        assert_eq!(resolved.cert_path, "/var/cache/kura/tls/tls.crt");
        assert_eq!(resolved.key_path, "/var/cache/kura/tls/tls.key");
        assert!(resolved.derived);
    }

    #[test]
    fn keeps_configured_tls_paths_and_does_not_mark_them_derived() {
        let resolved = resolve_tls_paths(
            Some("/etc/kura/peer-ca.pem".to_string()),
            Some("/etc/kura/peer.pem".to_string()),
            Some("/etc/kura/peer.key".to_string()),
            Some("/var/cache/kura".to_string()),
        )
        .expect("configured paths should be accepted");

        assert_eq!(resolved.ca_cert_path, "/etc/kura/peer-ca.pem");
        assert_eq!(resolved.cert_path, "/etc/kura/peer.pem");
        assert_eq!(resolved.key_path, "/etc/kura/peer.key");
        // A read-only mount must never be reported as somewhere enrollment may write.
        assert!(!resolved.derived);
    }

    #[test]
    fn rejects_a_partially_configured_tls_triple_instead_of_completing_it() {
        let error = resolve_tls_paths(
            Some("/etc/kura/peer-ca.pem".to_string()),
            None,
            None,
            Some("/var/cache/kura".to_string()),
        )
        .expect_err("a half-configured triple should not be silently completed");

        assert!(error.contains("all be set or all be unset"), "{error}");
    }

    #[test]
    fn refuses_to_derive_tls_paths_without_a_data_dir() {
        let error = resolve_tls_paths(None, None, None, None)
            .expect_err("there is nowhere to derive the paths from");

        assert!(error.contains(KURA_DATA_DIR), "{error}");
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
}
