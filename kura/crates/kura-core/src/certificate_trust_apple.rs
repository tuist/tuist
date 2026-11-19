//! Native SSL evaluation mirrors platform-verifier 0.6.2, with an evaluated-chain deny.
use super::*;
use core_foundation::date::CFDate;
use security_framework::{
    certificate::SecCertificate, policy::SecPolicy, secure_transport::SslProtocolSide,
    trust::SecTrust,
};
use security_framework_sys::base::{
    errSecCertificateRevoked as ERR_SEC_CERTIFICATE_REVOKED,
    errSecCreateChainFailed as ERR_SEC_CREATE_CHAIN_FAILED,
    errSecHostNameMismatch as ERR_SEC_HOST_NAME_MISMATCH,
};

#[derive(Debug)]
pub(super) struct NativeVerifier {
    pub(super) extra: Vec<SecCertificate>,
    pub(super) policy: Arc<Policy>,
    pub(super) provider: Arc<rustls::crypto::CryptoProvider>,
}

pub(super) fn native_verifier(
    extra: Vec<CertificateDer<'static>>,
    policy: Arc<Policy>,
    provider: Arc<rustls::crypto::CryptoProvider>,
) -> Result<Arc<dyn ServerCertVerifier>, Error> {
    let mut anchors = Vec::new();
    for certificate in extra {
        let native = SecCertificate::from_der(&certificate)
            .map_err(|_| Error::InvalidCertificate(CertificateError::BadEncoding))?;
        match policy.check(&certificate) {
            Ok(()) => anchors.push(native),
            Err(Error::InvalidCertificate(CertificateError::ApplicationVerificationFailure)) => {}
            Err(error) => return Err(error),
        }
    }
    Ok(Arc::new(NativeVerifier {
        extra: anchors,
        policy,
        provider,
    }))
}

#[derive(Debug)]
struct NativeCertificateError(isize);
impl std::fmt::Display for NativeCertificateError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            formatter,
            "native certificate verification failed ({})",
            self.0
        )
    }
}
impl std::error::Error for NativeCertificateError {}

fn native_configuration_error(_: security_framework::base::Error) -> Error {
    Error::General("native TLS trust configuration failed".into())
}

impl ServerCertVerifier for NativeVerifier {
    // Kura supports macOS 11; the replacement chain() API requires macOS 12.
    #[allow(deprecated)]
    fn verify_server_cert(
        &self,
        leaf: &CertificateDer<'_>,
        intermediates: &[CertificateDer<'_>],
        name: &ServerName<'_>,
        ocsp: &[u8],
        now: UnixTime,
    ) -> Result<ServerCertVerified, Error> {
        let certificates = std::iter::once(leaf)
            .chain(intermediates)
            .map(|certificate| {
                SecCertificate::from_der(certificate)
                    .map_err(|_| Error::InvalidCertificate(CertificateError::BadEncoding))
            })
            .collect::<Result<Vec<_>, _>>()?;
        let policy = SecPolicy::create_ssl(SslProtocolSide::SERVER, Some(&name.to_str()));
        let mut trust = SecTrust::create_with_certificates(&certificates, &[policy])
            .map_err(native_configuration_error)?;
        // Apple absolute time starts 2001-01-01; match the locked verifier's
        // checked conversion and Rustls-supplied verification time, not wall time.
        let seconds = now
            .as_secs()
            .checked_sub(978_307_200)
            .ok_or(Error::FailedToGetCurrentTime)?;
        trust
            .set_trust_verify_date(&CFDate::new(seconds as f64))
            .map_err(native_configuration_error)?;
        if !ocsp.is_empty() {
            trust
                .set_trust_ocsp_response(std::iter::once(ocsp))
                .map_err(native_configuration_error)?;
        }
        if !self.extra.is_empty() {
            trust
                .set_anchor_certificates(&self.extra)
                .map_err(native_configuration_error)?;
            trust
                .set_trust_anchor_certificates_only(false)
                .map_err(native_configuration_error)?;
        }
        trust.evaluate_with_error().map_err(|error| {
            let certificate_error = match i32::try_from(error.code()).ok() {
                Some(ERR_SEC_HOST_NAME_MISMATCH) => CertificateError::NotValidForName,
                Some(ERR_SEC_CREATE_CHAIN_FAILED) => CertificateError::UnknownIssuer,
                Some(ERR_SEC_CERTIFICATE_REVOKED) => CertificateError::Revoked,
                _ => CertificateError::Other(rustls::OtherError(Arc::new(NativeCertificateError(
                    error.code(),
                )))),
            };
            Error::InvalidCertificate(certificate_error)
        })?;
        if trust.certificate_count() == 0 {
            return Err(Error::InvalidCertificate(CertificateError::BadEncoding));
        }
        for index in 0..trust.certificate_count() {
            let certificate = trust
                .certificate_at_index(index)
                .ok_or(Error::InvalidCertificate(CertificateError::BadEncoding))?;
            self.policy
                .check(&CertificateDer::from(certificate.to_der()))?;
        }
        Ok(ServerCertVerified::assertion())
    }
    fn verify_tls12_signature(
        &self,
        message: &[u8],
        certificate: &CertificateDer<'_>,
        signature: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        rustls::crypto::verify_tls12_signature(
            message,
            certificate,
            signature,
            &self.provider.signature_verification_algorithms,
        )
    }
    fn verify_tls13_signature(
        &self,
        message: &[u8],
        certificate: &CertificateDer<'_>,
        signature: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        rustls::crypto::verify_tls13_signature(
            message,
            certificate,
            signature,
            &self.provider.signature_verification_algorithms,
        )
    }
    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.provider
            .signature_verification_algorithms
            .supported_schemes()
    }
}
