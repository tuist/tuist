//! Additive twelve-key policy. Never replaces normal WebPKI or handshake signature checks.
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{
    CertificateError, DigitallySignedStruct, DistinguishedName, Error, RootCertStore,
    SignatureScheme,
};
use sha2::{Digest, Sha256};
use std::sync::Arc;

pub const POLICY_ID: &str = "emudhra-2026-10-19-v2";

// Synchronized with infra/certificate-trust/policy.json; embedded in every TLS artifact.
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

fn spki_contents_hash(contents: &[u8]) -> String {
    // rustls TrustAnchor stores the SPKI SEQUENCE contents. Policy hashes include its DER header.
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
    // This parses only for key extraction, never establishes trust. Native verification
    // below remains authoritative for critical extensions, usage and signatures.
    let anchor = webpki::anchor_from_trusted_cert(certificate)
        .map_err(|_| Error::InvalidCertificate(CertificateError::BadEncoding))?;
    Ok(spki_contents_hash(anchor.subject_public_key_info.as_ref()))
}

fn blocked(hash: &str, additional: &[String]) -> bool {
    BLOCKED_SPKI_HASHES.contains(&hash) || additional.iter().any(|value| value == hash)
}

pub fn verifier(
    mut roots: RootCertStore,
    additional_blocked: Vec<String>,
) -> Result<Arc<dyn ServerCertVerifier>, rustls::client::VerifierBuilderError> {
    // Filter every candidate anchor, not just peer-supplied certificates. The pinned
    // patched WebPKI also rejects the eight intermediate keys while constructing paths.
    roots.roots.retain(|anchor| {
        !blocked(
            &spki_contents_hash(anchor.subject_public_key_info.as_ref()),
            &additional_blocked,
        )
    });
    let inner = rustls::client::WebPkiServerVerifier::builder_with_provider(
        Arc::new(roots),
        Arc::new(rustls::crypto::ring::default_provider()),
    )
    .build()?;
    Ok(Arc::new(PolicyVerifier {
        inner,
        additional_blocked,
    }))
}

pub fn client_config(
    roots: RootCertStore,
    additional_blocked: Vec<String>,
) -> Result<rustls::ClientConfig, String> {
    let verifier =
        verifier(roots, additional_blocked).map_err(|_| "no allowed TLS trust anchors")?;
    Ok(rustls::ClientConfig::builder_with_provider(Arc::new(
        rustls::crypto::ring::default_provider(),
    ))
    .with_safe_default_protocol_versions()
    .map_err(|_| "could not configure TLS protocols")?
    .dangerous()
    .with_custom_certificate_verifier(verifier)
    .with_no_client_auth())
}

/// Classify typed TLS failures without rendering URLs, tokens or transport bodies.
pub fn tls_failure(error: &(dyn std::error::Error + 'static)) -> bool {
    let mut source = Some(error);
    for _ in 0..32 {
        let Some(error) = source else { return false };
        if error.downcast_ref::<rustls::Error>().is_some() {
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
    true
}

#[derive(Debug)]
struct PolicyVerifier {
    inner: Arc<rustls::client::WebPkiServerVerifier>,
    additional_blocked: Vec<String>,
}

impl ServerCertVerifier for PolicyVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        intermediates: &[CertificateDer<'_>],
        server_name: &ServerName<'_>,
        ocsp_response: &[u8],
        now: UnixTime,
    ) -> Result<ServerCertVerified, Error> {
        let verified = self.inner.verify_server_cert(
            end_entity,
            intermediates,
            server_name,
            ocsp_response,
            now,
        )?;
        for certificate in std::iter::once(end_entity).chain(intermediates) {
            if blocked(&spki_hash(certificate)?, &self.additional_blocked) {
                return Err(Error::InvalidCertificate(
                    CertificateError::ApplicationVerificationFailure,
                ));
            }
        }
        Ok(verified)
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        self.inner.verify_tls12_signature(message, cert, dss)
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        self.inner.verify_tls13_signature(message, cert, dss)
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
