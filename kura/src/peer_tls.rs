use std::{io::BufReader, sync::Arc, time::Duration};

use axum_server::tls_rustls::RustlsConfig;
use reqwest::{Certificate, Client, Identity};
use rustls::pki_types::{CertificateDer, PrivateKeyDer};
use rustls::{RootCertStore, ServerConfig, server::WebPkiClientVerifier};
use tokio::fs;

use crate::config::{Config, PeerTlsConfig};

pub async fn build_peer_client(config: &Config) -> Result<Client, String> {
    let mut builder = Client::builder().timeout(Duration::from_secs(30));

    if let Some(peer_tls) = &config.peer_tls {
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

        let identity = Identity::from_pem(&identity_pem)
            .map_err(|error| format!("failed to parse peer identity PEM: {error}"))?;
        let ca = Certificate::from_pem(&ca_pem)
            .map_err(|error| format!("failed to parse peer CA PEM: {error}"))?;

        builder = builder.identity(identity).add_root_certificate(ca);
    }

    builder
        .build()
        .map_err(|error| format!("failed to build peer HTTP client: {error}"))
}

pub async fn build_internal_rustls_config(
    peer_tls: &PeerTlsConfig,
) -> Result<RustlsConfig, String> {
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

    Ok(RustlsConfig::from_config(Arc::new(server_config)))
}

fn install_default_crypto_provider() {
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
