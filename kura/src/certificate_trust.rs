//! Restricts Kura's original native/explicit trust without replacing it with bundled roots.
use std::sync::Arc;

use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::pki_types::{CertificateDer, PrivateKeyDer, ServerName, UnixTime, pem::PemObject};
use rustls::{
    CertificateError, DigitallySignedStruct, DistinguishedName, Error, RootCertStore,
    SignatureScheme,
};
use sha2::{Digest, Sha256};

pub const POLICY_ID: &str = "emudhra-2026-10-19-v2";
pub const BLOCKED_SPKI_HASHES: &[&str] = &[
    "8d417db2dd8bf5e3084d1e3f196d583849d81bdd4c00c70b9d39369e96b8c782",
    "bd153ed7b0434f6886b17bce8bbe84ed340c7132d702a8f4fa318f756ecbd6f3",
    "ebed6475c2c2d80fcb199f3fe8dd6e6b3ce60b77eb15d4e42c3dec0c6f5b5105",
    "49dd353dc2b919a3770645117d0e60c16115e7d1bc259eefe734b00ea434fe5f",
    "e0254c7fcdc265e2f0f8a428dabb75ab4ae039b4872d62f5ee57f0877d5a8a41",
    "5c0660a2b164910d8ff589c18e14552e9e0ec237dcefe2cb736d41a4811f81a0",
    "43bffa19d6ef651451f6841e019931e96f6f2eaeff28ab4b6f1ce4576de2717b",
    "63ecefee431d49523bc1136c4e72d0206a477086caf606cd5cf025686c109cf8",
    "ec4ffa1ad0ac88081314b7aaffef6a91f97cd57291bb5ba686c5415f5eb4f6b6",
    "92c063d67e8f14db71d288e11266ffdaf69cbf115f7bab14f3bc2f68d25e0e30",
    "c619e4780ed8e0abeda24ad732567de4383a7ea941338f6d1a7d1b49ac792fe9",
    "0a6c2b2ca5b364207954171987ac9d2178561569d8205457e77ca90c32ede282",
];

#[derive(Debug, Default)]
pub struct Policy {
    additional: Vec<String>,
}

impl Policy {
    pub fn new(additional: Vec<String>) -> Self {
        Self { additional }
    }

    fn blocked(&self, hash: &str) -> bool {
        BLOCKED_SPKI_HASHES.contains(&hash) || self.additional.iter().any(|item| item == hash)
    }

    pub fn check(&self, certificate: &CertificateDer<'_>) -> Result<(), Error> {
        if self.blocked(&spki_hash(certificate)?) {
            return Err(Error::InvalidCertificate(
                CertificateError::ApplicationVerificationFailure,
            ));
        }
        Ok(())
    }

    pub fn filter_roots(&self, roots: &mut RootCertStore) {
        roots.roots.retain(|anchor| {
            !self.blocked(&spki_contents_hash(anchor.subject_public_key_info.as_ref()))
        });
    }
}

fn spki_contents_hash(contents: &[u8]) -> String {
    let mut hash = Sha256::new();
    hash.update([0x30]);
    if contents.len() < 128 {
        hash.update([contents.len() as u8]);
    } else {
        let length = contents.len().to_be_bytes();
        let first = length.iter().position(|byte| *byte != 0).unwrap();
        hash.update([0x80 | (length.len() - first) as u8]);
        hash.update(&length[first..]);
    }
    hash.update(contents);
    format!("{:x}", hash.finalize())
}

pub fn spki_hash(certificate: &CertificateDer<'_>) -> Result<String, Error> {
    let anchor = webpki::anchor_from_trusted_cert(certificate)
        .map_err(|_| Error::InvalidCertificate(CertificateError::BadEncoding))?;
    Ok(spki_contents_hash(anchor.subject_public_key_info.as_ref()))
}

pub enum Roots {
    Native(Vec<CertificateDer<'static>>),
    Explicit(Vec<CertificateDer<'static>>),
}

fn provider() -> Arc<rustls::crypto::CryptoProvider> {
    rustls::crypto::CryptoProvider::get_default()
        .cloned()
        .unwrap_or_else(|| Arc::new(rustls::crypto::aws_lc_rs::default_provider()))
}

fn webpki_verifier(
    mut roots: RootCertStore,
    policy: &Policy,
    provider: Arc<rustls::crypto::CryptoProvider>,
) -> Result<Arc<dyn ServerCertVerifier>, Error> {
    policy.filter_roots(&mut roots);
    rustls::client::WebPkiServerVerifier::builder_with_provider(Arc::new(roots), provider)
        .build()
        .map(|verifier| verifier as Arc<dyn ServerCertVerifier>)
        .map_err(|_| Error::General("no allowed TLS trust anchors".into()))
}

pub fn verifier(
    roots: Roots,
    policy: Arc<Policy>,
    provider: Arc<rustls::crypto::CryptoProvider>,
) -> Result<Arc<dyn ServerCertVerifier>, Error> {
    let inner = match roots {
        Roots::Explicit(certificates) => {
            let mut roots = RootCertStore::empty();
            for certificate in certificates {
                roots.add(certificate)?;
            }
            webpki_verifier(roots, &policy, provider)?
        }
        Roots::Native(extra) => native_verifier(extra, policy.clone(), provider)?,
    };
    Ok(Arc::new(PolicyVerifier { inner, policy }))
}

#[cfg(not(target_vendor = "apple"))]
fn native_verifier(
    extra: Vec<CertificateDer<'static>>,
    policy: Arc<Policy>,
    provider: Arc<rustls::crypto::CryptoProvider>,
) -> Result<Arc<dyn ServerCertVerifier>, Error> {
    // Matches platform-verifier 0.6.2's Unix backend: strict extras, best-effort
    // system roots with warnings, empty-store failure, and a fresh per-build load.
    #[cfg(not(all(unix, not(target_os = "android"), not(target_arch = "wasm32"))))]
    compile_error!("native TLS qualification required on this platform");
    #[cfg(all(unix, not(target_os = "android"), not(target_arch = "wasm32")))]
    {
        let mut roots = RootCertStore::empty();
        for certificate in extra {
            roots.add(certificate)?;
        }
        let result = rustls_native_certs::load_native_certs();
        let (_, ignored) = roots.add_parsable_certificates(result.certs);
        if ignored > 0 {
            tracing::warn!(ignored, "ignored unparsable native CA certificates");
        }
        for _ in result.errors {
            tracing::warn!("native CA certificate loading error");
        }
        if roots.is_empty() {
            return Err(Error::General("no native TLS trust anchors".into()));
        }
        webpki_verifier(roots, &policy, provider)
    }
}

#[cfg(target_vendor = "apple")]
#[path = "certificate_trust_apple.rs"]
mod apple;
#[cfg(target_vendor = "apple")]
use apple::native_verifier;

pub fn config(
    roots: Roots,
    identity: Option<&[u8]>,
    additional: Vec<String>,
) -> Result<rustls::ClientConfig, Error> {
    tracing::debug!(policy = POLICY_ID, "configuring restrictive TLS trust");
    let provider = provider();
    let verifier = verifier(roots, Arc::new(Policy::new(additional)), provider.clone())?;
    let builder = rustls::ClientConfig::builder_with_provider(provider)
        .with_protocol_versions(rustls::ALL_VERSIONS)?
        .dangerous()
        .with_custom_certificate_verifier(verifier);
    let mut config = if let Some(pem) = identity {
        let (certificates, key) = parse_identity(pem)?;
        builder.with_client_auth_cert(certificates, key)?
    } else {
        builder.with_no_client_auth()
    };
    // reqwest's preconfigured route skips these settings. Preserve its default
    // TLS1.2/1.3, SNI and HTTP2/HTTP1 negotiation, without sharing peer identities.
    config.enable_sni = true;
    config.alpn_protocols = vec![b"h2".to_vec(), b"http/1.1".to_vec()];
    Ok(config)
}

pub fn client_builder() -> Result<reqwest::ClientBuilder, String> {
    Ok(reqwest::Client::builder().tls_backend_preconfigured(native_config()?))
}

pub fn native_config() -> Result<rustls::ClientConfig, String> {
    config(Roots::Native(Vec::new()), None, Vec::new())
        .map_err(|_| "failed to configure native TLS trust".to_string())
}

pub fn certificates(pem: &[u8]) -> Result<Vec<CertificateDer<'static>>, String> {
    CertificateDer::pem_slice_iter(pem)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|_| "invalid TLS certificate PEM".to_string())
}

fn parse_identity(
    pem: &[u8],
) -> Result<(Vec<CertificateDer<'static>>, PrivateKeyDer<'static>), Error> {
    use rustls::pki_types::pem::SectionKind;
    let invalid = || Error::General("invalid TLS identity PEM".into());
    let mut reader = std::io::Cursor::new(pem);
    let mut certificates = Vec::new();
    let mut key = None;
    // Keep reqwest 0.13's order, supported key sections, last-key selection and
    // refusal of other recognized sections; do not use a first-key parser here.
    while let Some((kind, bytes)) =
        rustls::pki_types::pem::from_buf(&mut reader).map_err(|_| invalid())?
    {
        match kind {
            SectionKind::Certificate => certificates.push(bytes.into()),
            SectionKind::PrivateKey => key = Some(PrivateKeyDer::Pkcs8(bytes.into())),
            SectionKind::RsaPrivateKey => key = Some(PrivateKeyDer::Pkcs1(bytes.into())),
            SectionKind::EcPrivateKey => key = Some(PrivateKeyDer::Sec1(bytes.into())),
            _ => return Err(invalid()),
        }
    }
    if certificates.is_empty() {
        return Err(invalid());
    }
    Ok((certificates, key.ok_or_else(invalid)?))
}

#[derive(Debug)]
struct PolicyVerifier {
    inner: Arc<dyn ServerCertVerifier>,
    policy: Arc<Policy>,
}

impl ServerCertVerifier for PolicyVerifier {
    fn verify_server_cert(
        &self,
        leaf: &CertificateDer<'_>,
        intermediates: &[CertificateDer<'_>],
        name: &ServerName<'_>,
        ocsp: &[u8],
        now: UnixTime,
    ) -> Result<ServerCertVerified, Error> {
        let verified = self
            .inner
            .verify_server_cert(leaf, intermediates, name, ocsp, now)?;
        for certificate in std::iter::once(leaf).chain(intermediates) {
            self.policy.check(certificate)?;
        }
        Ok(verified)
    }
    fn verify_tls12_signature(
        &self,
        message: &[u8],
        certificate: &CertificateDer<'_>,
        signature: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        self.inner
            .verify_tls12_signature(message, certificate, signature)
    }
    fn verify_tls13_signature(
        &self,
        message: &[u8],
        certificate: &CertificateDer<'_>,
        signature: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        self.inner
            .verify_tls13_signature(message, certificate, signature)
    }
    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.inner.supported_verify_schemes()
    }
    fn requires_raw_public_keys(&self) -> bool {
        self.inner.requires_raw_public_keys()
    }
    fn root_hint_subjects(&self) -> Option<&[DistinguishedName]> {
        self.inner.root_hint_subjects()
    }
}

pub fn tls_failure(error: &(dyn std::error::Error + 'static)) -> bool {
    failure_category(error).is_some()
}

pub fn failure_category(error: &(dyn std::error::Error + 'static)) -> Option<&'static str> {
    let mut source = Some(error);
    for _ in 0..32 {
        let error = source?;
        if let Some(error) = error.downcast_ref::<Error>() {
            return Some(match error {
                Error::InvalidCertificate(CertificateError::ApplicationVerificationFailure) => {
                    "key_policy"
                }
                Error::InvalidCertificate(_) => "certificate_validation",
                _ => "tls_protocol",
            });
        }
        source = if let Some(io) = error.downcast_ref::<std::io::Error>() {
            io.get_ref()
                .map(|inner| inner as &(dyn std::error::Error + 'static))
                .or_else(|| error.source())
        } else {
            error.source()
        };
    }
    Some("error_chain_limit")
}

pub fn client_auth_verifier(
    mut roots: RootCertStore,
    additional: Vec<String>,
) -> Result<Arc<dyn rustls::server::danger::ClientCertVerifier>, rustls::server::VerifierBuilderError>
{
    let policy = Arc::new(Policy::new(additional));
    policy.filter_roots(&mut roots);
    let inner =
        rustls::server::WebPkiClientVerifier::builder_with_provider(Arc::new(roots), provider())
            .build()?;
    Ok(Arc::new(ClientPolicyVerifier { inner, policy }))
}

#[derive(Debug)]
struct ClientPolicyVerifier {
    inner: Arc<dyn rustls::server::danger::ClientCertVerifier>,
    policy: Arc<Policy>,
}

impl rustls::server::danger::ClientCertVerifier for ClientPolicyVerifier {
    fn offer_client_auth(&self) -> bool {
        self.inner.offer_client_auth()
    }
    fn client_auth_mandatory(&self) -> bool {
        self.inner.client_auth_mandatory()
    }
    fn root_hint_subjects(&self) -> &[DistinguishedName] {
        self.inner.root_hint_subjects()
    }
    fn verify_client_cert(
        &self,
        leaf: &CertificateDer<'_>,
        intermediates: &[CertificateDer<'_>],
        now: UnixTime,
    ) -> Result<rustls::server::danger::ClientCertVerified, Error> {
        let verified = self.inner.verify_client_cert(leaf, intermediates, now)?;
        for certificate in std::iter::once(leaf).chain(intermediates) {
            self.policy.check(certificate)?;
        }
        Ok(verified)
    }
    fn verify_tls12_signature(
        &self,
        message: &[u8],
        certificate: &CertificateDer<'_>,
        signature: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        self.inner
            .verify_tls12_signature(message, certificate, signature)
    }
    fn verify_tls13_signature(
        &self,
        message: &[u8],
        certificate: &CertificateDer<'_>,
        signature: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        self.inner
            .verify_tls13_signature(message, certificate, signature)
    }
    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.inner.supported_verify_schemes()
    }
    fn requires_raw_public_keys(&self) -> bool {
        self.inner.requires_raw_public_keys()
    }
}

#[cfg(test)]
#[path = "certificate_trust_tests.rs"]
mod tests;
