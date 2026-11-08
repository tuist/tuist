//! Per-session CA loading + leaf certificate minting for the
//! TLS-terminating interception path.
//!
//! We accept the per-session CA (cert + key) from disk at startup,
//! parse it once, and then mint per-host leaf certs on demand as
//! connections arrive. Leaf certs are cached by SNI so repeat
//! connections to the same host don't re-pay the keygen + signing
//! cost.
//!
//! `rcgen` 0.13 exposes leaf signing as
//! `params.signed_by(&public_key, &issuer_cert, &issuer_key)`, where
//! `issuer_cert` is the issuer's `Certificate` wrapper. The wrapper is
//! used only to read the issuer's subject DN / key-identifier extension
//! when serialising the leaf — its signature and serial bytes are
//! ignored. We therefore reconstitute the CA's `Certificate` by
//! self-signing the parsed `CertificateParams` with the loaded key
//! pair. The reconstituted cert is never presented on the wire; the
//! workspace's trust store holds the original CA bytes.

use rcgen::{
    Certificate, CertificateParams, DistinguishedName, DnType, IsCa, KeyPair, KeyUsagePurpose,
    SanType,
};
use rustls::ServerConfig;
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;

#[derive(Debug, thiserror::Error)]
pub enum TlsError {
    #[error("reading CA file {0}: {1}")]
    ReadCa(String, std::io::Error),

    #[error("parsing CA cert: {0}")]
    ParseCaCert(String),

    #[error("parsing CA key: {0}")]
    ParseCaKey(String),

    #[error("rcgen: {0}")]
    Rcgen(#[from] rcgen::Error),

    #[error("rustls: {0}")]
    Rustls(#[from] rustls::Error),
}

pub struct CaContext {
    issuer_cert: Certificate,
    issuer_key: KeyPair,
    leaf_cache: Mutex<HashMap<String, Arc<ServerConfig>>>,
}

impl CaContext {
    /// Load the per-session CA from PEM files on disk.
    pub async fn load(cert_path: &str, key_path: &str) -> Result<Self, TlsError> {
        let cert_pem = tokio::fs::read_to_string(cert_path)
            .await
            .map_err(|e| TlsError::ReadCa(cert_path.into(), e))?;
        let key_pem = tokio::fs::read_to_string(key_path)
            .await
            .map_err(|e| TlsError::ReadCa(key_path.into(), e))?;

        Self::from_pem(&cert_pem, &key_pem)
    }

    /// Build the CA context from in-memory PEM. `load` is a thin file
    /// wrapper over this; tests construct CA material directly.
    pub fn from_pem(cert_pem: &str, key_pem: &str) -> Result<Self, TlsError> {
        let issuer_key =
            KeyPair::from_pem(key_pem).map_err(|e| TlsError::ParseCaKey(e.to_string()))?;

        let issuer_params = CertificateParams::from_ca_cert_pem(cert_pem)
            .map_err(|e| TlsError::ParseCaCert(e.to_string()))?;

        // See module-level comment: the reconstituted cert is only used
        // by rcgen's signer to read the issuer's DN / extensions. Its
        // bytes are never presented on the wire.
        let issuer_cert = issuer_params.self_signed(&issuer_key)?;

        Ok(CaContext {
            issuer_cert,
            issuer_key,
            leaf_cache: Mutex::new(HashMap::new()),
        })
    }

    pub async fn server_config_for(&self, host: &str) -> Result<Arc<ServerConfig>, TlsError> {
        if let Some(cfg) = self.leaf_cache.lock().await.get(host) {
            return Ok(Arc::clone(cfg));
        }

        // Mint outside the lock so a slow keygen for one host does not
        // stall every other host. A concurrent caller may have inserted
        // `host` in the meantime; `entry().or_insert` keeps the first
        // config so every caller for a host shares exactly one.
        let fresh = Arc::new(self.mint(host)?);
        let mut cache = self.leaf_cache.lock().await;
        let cfg = cache.entry(host.to_string()).or_insert(fresh);
        Ok(Arc::clone(cfg))
    }

    fn mint(&self, host: &str) -> Result<ServerConfig, TlsError> {
        let (leaf_der, leaf_key) = self.build_leaf(host)?;

        let mut cfg = ServerConfig::builder()
            .with_no_client_auth()
            .with_single_cert(vec![leaf_der], PrivateKeyDer::Pkcs8(leaf_key))?;

        // ALPN: advertise both h2 and http/1.1 so clients can negotiate
        // whichever they prefer. The conn handler routes on the
        // negotiated protocol post-handshake.
        cfg.alpn_protocols = vec![b"h2".to_vec(), b"http/1.1".to_vec()];

        Ok(cfg)
    }

    /// Mint a fresh leaf cert + key for `host`, signed by the session CA.
    /// Split out from `mint` so it can be asserted on directly in tests.
    fn build_leaf(
        &self,
        host: &str,
    ) -> Result<(CertificateDer<'static>, PrivatePkcs8KeyDer<'static>), TlsError> {
        let params = Self::leaf_params(host)?;
        let leaf_key = KeyPair::generate()?;
        let leaf_cert = params.signed_by(&leaf_key, &self.issuer_cert, &self.issuer_key)?;

        Ok((
            leaf_cert.der().clone(),
            PrivatePkcs8KeyDer::from(leaf_key.serialize_der()),
        ))
    }

    fn leaf_params(host: &str) -> Result<CertificateParams, TlsError> {
        let mut params = CertificateParams::new(vec![host.to_string()])?;

        let mut dn = DistinguishedName::new();
        dn.push(DnType::CommonName, host);
        params.distinguished_name = dn;

        params.is_ca = IsCa::NoCa;
        params.key_usages = vec![
            KeyUsagePurpose::DigitalSignature,
            KeyUsagePurpose::KeyEncipherment,
        ];
        params.subject_alt_names = vec![SanType::DnsName(host.try_into()?)];

        Ok(params)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rcgen::{BasicConstraints, CertificateParams, DistinguishedName, DnType, KeyPair};
    use x509_parser::pem::parse_x509_pem;
    use x509_parser::prelude::*;

    // A self-signed CA, returned as (cert_pem, key_pem), standing in for
    // the per-session CA the BEAM normally writes into the pod Secret.
    fn test_ca() -> (String, String) {
        let key = KeyPair::generate().unwrap();
        let mut params = CertificateParams::new(Vec::<String>::new()).unwrap();
        let mut dn = DistinguishedName::new();
        dn.push(DnType::CommonName, "Condukt Test Session CA");
        params.distinguished_name = dn;
        params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
        params.key_usages = vec![KeyUsagePurpose::KeyCertSign, KeyUsagePurpose::CrlSign];
        let cert = params.self_signed(&key).unwrap();
        (cert.pem(), key.serialize_pem())
    }

    #[test]
    fn build_leaf_mints_a_cert_for_the_sni_host_issued_by_the_ca() {
        let (ca_cert, ca_key) = test_ca();
        let ca = CaContext::from_pem(&ca_cert, &ca_key).unwrap();

        let (leaf_der, _key) = ca.build_leaf("api.example.com").unwrap();
        let (_, leaf) = X509Certificate::from_der(leaf_der.as_ref()).unwrap();

        // Subject CN and SAN both name the SNI host. webpki matches on
        // the SAN, so that one is load-bearing.
        let cn = leaf
            .subject()
            .iter_common_name()
            .next()
            .unwrap()
            .as_str()
            .unwrap();
        assert_eq!(cn, "api.example.com");

        let san = leaf.subject_alternative_name().unwrap().unwrap();
        let dns: Vec<&str> = san
            .value
            .general_names
            .iter()
            .filter_map(|g| match g {
                GeneralName::DNSName(d) => Some(*d),
                _ => None,
            })
            .collect();
        assert_eq!(dns, vec!["api.example.com"]);

        // Issued by the session CA (issuer == CA subject), not self-signed,
        // and not itself a CA.
        let (_, ca_pem) = parse_x509_pem(ca_cert.as_bytes()).unwrap();
        let ca_x509 = ca_pem.parse_x509().unwrap();
        assert_eq!(leaf.issuer().to_string(), ca_x509.subject().to_string());
        assert_ne!(leaf.issuer().to_string(), leaf.subject().to_string());
        assert!(!leaf.is_ca());
    }

    #[tokio::test]
    async fn server_config_advertises_h2_and_http11_alpn() {
        let (ca_cert, ca_key) = test_ca();
        let ca = CaContext::from_pem(&ca_cert, &ca_key).unwrap();

        let cfg = ca.server_config_for("example.com").await.unwrap();

        assert_eq!(
            cfg.alpn_protocols,
            vec![b"h2".to_vec(), b"http/1.1".to_vec()]
        );
    }

    #[tokio::test]
    async fn caches_one_config_per_host() {
        let (ca_cert, ca_key) = test_ca();
        let ca = CaContext::from_pem(&ca_cert, &ca_key).unwrap();

        let a1 = ca.server_config_for("a.example.com").await.unwrap();
        let a2 = ca.server_config_for("a.example.com").await.unwrap();
        let b = ca.server_config_for("b.example.com").await.unwrap();

        assert!(
            Arc::ptr_eq(&a1, &a2),
            "repeat host must reuse the cached config"
        );
        assert!(
            !Arc::ptr_eq(&a1, &b),
            "distinct hosts must get distinct configs"
        );
    }

    #[test]
    fn from_pem_rejects_a_bogus_ca_key() {
        let (ca_cert, _) = test_ca();
        assert!(matches!(
            CaContext::from_pem(
                &ca_cert,
                "-----BEGIN PRIVATE KEY-----\nnope\n-----END PRIVATE KEY-----"
            ),
            Err(TlsError::ParseCaKey(_))
        ));
    }
}
