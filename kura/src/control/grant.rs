//! Authorization for mutating control-surface operations.
//!
//! Reads are authorized by reaching the socket at all: it is `0600` inside the
//! data directory, so a reader already has host or container access. Writes
//! need more, because that access is a single coarse permission and the socket
//! cannot tell one human from another (every process in the container shares a
//! uid).
//!
//! So a mutating request carries a short-lived **grant**: an EdDSA (Ed25519)
//! JWS minted by whatever authority the deployment trusts, which the node
//! verifies **offline** against a configured public key. Kura does not care
//! what that authority is. It can be an SSO-fronted elevation bot, a PAM-style
//! break-glass tool, a CI job, or a one-line script an individual runs against
//! a key they hold; the node only checks the signature and the claims. Nothing
//! here is specific to any one deployment, matching the deliberately
//! control-plane-agnostic shape of `registration.rs`.
//!
//! The defensive choices are the interesting part:
//!
//! - **EdDSA-strict.** The token's own `alg` header is never honoured. That is
//!   the classic JWT confusion attack (`none`, or `HS256` signed with the
//!   public key as the HMAC secret), and this grants mutation.
//! - **Asymmetric, not a shared secret.** The node holds only a public key, so
//!   a compromised node cannot mint a grant for itself or for a peer.
//! - **No callback to the issuer.** Verification is local, so the node and the
//!   granting authority stay on separate failure domains. An outage of the
//!   latter must never be able to take the cache mesh with it.
//! - **Fail closed.** No configured key, wrong algorithm, bad signature,
//!   missing claim, expired, future-dated, over-long TTL, or a wrong
//!   `iss`/`aud` all reject.
//!
//! Revocation is by short TTL plus signing-key rotation as the break-glass.
//! There is deliberately no revocation list, and no network dependency.

use jsonwebtoken::{Algorithm, DecodingKey, Validation, decode};
use serde::{Deserialize, Serialize};

use crate::config::ControlGrantConfig;

/// Tolerance for clock drift between the signer and this node.
const CLOCK_SKEW_SECONDS: i64 = 60;

/// The only tier that authorizes mutation. Present as a claim rather than
/// implied so that a future read-only tier can share the same token shape.
const WRITE_TIER: &str = "write";

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct GrantClaims {
    pub iss: String,
    pub aud: String,
    /// Who the grant was minted for. Free-form: an email, a service account,
    /// whatever identity the issuing authority works in. It is recorded in the
    /// audit log, not interpreted.
    pub sub: String,
    pub tier: String,
    /// Optional justification, carried so it lands in the audit log next to
    /// the operation it authorized.
    #[serde(default)]
    pub reason: Option<String>,
    /// Optional issuer-side identifier, the join key for auditing.
    #[serde(default)]
    pub jti: Option<String>,
    pub iat: i64,
    pub exp: i64,
}

#[derive(Debug, PartialEq, Eq)]
pub enum GrantError {
    /// No public key configured. Writes are unavailable rather than open.
    NotConfigured,
    MalformedKey,
    InvalidSignature,
    BadIssuer,
    BadAudience,
    NotAWriteGrant,
    IssuedInFuture,
    TtlTooLong {
        seconds: i64,
        max_seconds: i64,
    },
    Expired,
}

impl GrantError {
    /// Operator-facing text. Deliberately says which check failed: the holder
    /// of a rejected grant is a colleague debugging their elevation, not an
    /// attacker learning anything they could not learn by reading this file.
    pub fn message(&self) -> String {
        match self {
            Self::NotConfigured => "this node does not accept grants, so write \
                 operations are unavailable. Set KURA_CONTROL_GRANT_PUBLIC_KEY, \
                 KURA_CONTROL_GRANT_ISSUER, and KURA_CONTROL_GRANT_AUDIENCE to enable them."
                .to_string(),
            Self::MalformedKey => {
                "the configured grant public key could not be parsed, so write operations \
                 are unavailable."
                    .to_string()
            }
            Self::InvalidSignature => {
                "the grant is not a valid EdDSA token signed by the configured issuer.".to_string()
            }
            Self::BadIssuer => {
                "the grant was not issued by the issuer this node trusts.".to_string()
            }
            Self::BadAudience => {
                "the grant was minted for a different audience than this node's.".to_string()
            }
            Self::NotAWriteGrant => "the grant does not carry write elevation.".to_string(),
            Self::IssuedInFuture => "the grant is dated in the future.".to_string(),
            Self::TtlTooLong {
                seconds,
                max_seconds,
            } => format!(
                "the grant is valid for {seconds}s, longer than the {max_seconds}s this \
                 node accepts."
            ),
            Self::Expired => "the grant has expired. Request a fresh one.".to_string(),
        }
    }
}

/// Verifies a grant against the node's configuration.
///
/// `now_unix` is passed in so the time-based checks are testable without
/// touching the clock.
pub fn verify(
    token: &str,
    config: Option<&ControlGrantConfig>,
    now_unix: i64,
) -> Result<GrantClaims, GrantError> {
    let config = config.ok_or(GrantError::NotConfigured)?;

    let key = DecodingKey::from_ed_pem(config.public_key_pem.as_bytes())
        .map_err(|_| GrantError::MalformedKey)?;

    // The allowlist is exactly EdDSA. Never widen this: the token's own `alg`
    // must not be able to select the verification algorithm.
    let mut validation = Validation::new(Algorithm::EdDSA);
    validation.algorithms = vec![Algorithm::EdDSA];
    validation.set_issuer(&[config.issuer.as_str()]);
    validation.set_audience(&[config.audience.as_str()]);
    validation.set_required_spec_claims(&["iss", "aud", "sub", "exp", "iat"]);
    validation.validate_aud = true;
    // Presence of `exp` is still required above, but its comparison happens
    // below against the caller's clock rather than the library's read of the
    // wall clock. One clock, one skew allowance, and the whole time policy
    // (expiry, future-dating, TTL ceiling) reads in one place.
    validation.validate_exp = false;

    let claims = decode::<GrantClaims>(token, &key, &validation)
        .map_err(classify)?
        .claims;

    // Re-check the pinned fields rather than trusting the library alone, so a
    // future change to its defaults cannot silently widen what is accepted.
    if claims.iss != config.issuer {
        return Err(GrantError::BadIssuer);
    }
    if claims.aud != config.audience {
        return Err(GrantError::BadAudience);
    }
    if claims.tier != WRITE_TIER {
        return Err(GrantError::NotAWriteGrant);
    }
    if claims.exp <= now_unix {
        return Err(GrantError::Expired);
    }
    // A future-dated `iat` would otherwise sail past the TTL ceiling: `exp -
    // iat` stays small while `exp` is pushed far out, yielding a long-lived
    // grant. Pinning `iat` to now also bounds absolute expiry to
    // `now + skew + max_ttl`.
    if claims.iat > now_unix + CLOCK_SKEW_SECONDS {
        return Err(GrantError::IssuedInFuture);
    }
    let ttl = claims.exp - claims.iat;
    if ttl > config.max_ttl_seconds {
        return Err(GrantError::TtlTooLong {
            seconds: ttl,
            max_seconds: config.max_ttl_seconds,
        });
    }

    Ok(claims)
}

fn classify(error: jsonwebtoken::errors::Error) -> GrantError {
    use jsonwebtoken::errors::ErrorKind;

    match error.kind() {
        ErrorKind::ExpiredSignature => GrantError::Expired,
        ErrorKind::InvalidIssuer => GrantError::BadIssuer,
        ErrorKind::InvalidAudience => GrantError::BadAudience,
        _ => GrantError::InvalidSignature,
    }
}

/// Records an authorized mutation. Every write goes through here, so the audit
/// trail is a property of the gate rather than of each call site remembering.
pub fn audit(claims: &GrantClaims, operation: &str, detail: &str) {
    tracing::warn!(
        subject = %claims.sub,
        grant_id = claims.jti.as_deref().unwrap_or("unknown"),
        reason = claims.reason.as_deref().unwrap_or("(none given)"),
        operation,
        detail,
        expires_at = claims.exp,
        "grant-authorized mutation"
    );
}

#[cfg(test)]
mod tests {
    use jsonwebtoken::{EncodingKey, Header};

    use super::*;

    // Deterministic Ed25519 test pair. Test-only material, never deployed.
    const PRIVATE_KEY_PEM: &str = "-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEIEw0VgZ6qDz6frcjXUxn1UmbhH6PjatJ82aq4WHHwypa\n-----END PRIVATE KEY-----\n";
    const PUBLIC_KEY_PEM: &str = "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAZ26hfh68Bvdeuq95ilrLWlen0eMOI8l1mZbwMECoeV8=\n-----END PUBLIC KEY-----\n";

    fn config() -> ControlGrantConfig {
        ControlGrantConfig {
            public_key_pem: PUBLIC_KEY_PEM.to_string(),
            issuer: "grants.example".to_string(),
            audience: "kura.production".to_string(),
            max_ttl_seconds: 3_600,
        }
    }

    fn claims(now: i64) -> GrantClaims {
        GrantClaims {
            iss: "grants.example".to_string(),
            aud: "kura.production".to_string(),
            sub: "operator@example.com".to_string(),
            tier: WRITE_TIER.to_string(),
            reason: Some("draining a wedged node".to_string()),
            jti: Some("42".to_string()),
            iat: now,
            exp: now + 900,
        }
    }

    fn sign(claims: &GrantClaims) -> String {
        let key = EncodingKey::from_ed_pem(PRIVATE_KEY_PEM.as_bytes()).expect("test signing key");
        jsonwebtoken::encode(&Header::new(Algorithm::EdDSA), claims, &key).expect("sign")
    }

    #[test]
    fn an_unconfigured_node_refuses_writes_rather_than_allowing_them() {
        let error = verify("anything", None, 1_000).expect_err("should refuse");
        assert_eq!(error, GrantError::NotConfigured);
        assert!(
            error.message().contains("unavailable"),
            "{}",
            error.message()
        );
    }

    #[test]
    fn a_valid_write_grant_is_accepted() {
        let now = 1_700_000_000;
        let token = sign(&claims(now));
        let verified = verify(&token, Some(&config()), now).expect("valid grant");
        assert_eq!(verified.sub, "operator@example.com");
        assert_eq!(verified.jti.as_deref(), Some("42"));
    }

    #[test]
    fn an_expired_grant_is_rejected() {
        let now = 1_700_000_000;
        let mut expired = claims(now);
        expired.iat = now - 1_000;
        expired.exp = now - 100;
        let token = sign(&expired);
        assert_eq!(
            verify(&token, Some(&config()), now).expect_err("expired"),
            GrantError::Expired
        );
    }

    #[test]
    fn a_grant_for_another_environment_is_rejected() {
        let now = 1_700_000_000;
        let mut other = claims(now);
        other.aud = "kura.staging".to_string();
        let token = sign(&other);
        assert_eq!(
            verify(&token, Some(&config()), now).expect_err("wrong audience"),
            GrantError::BadAudience
        );
    }

    #[test]
    fn a_grant_from_another_issuer_is_rejected() {
        let now = 1_700_000_000;
        let mut other = claims(now);
        other.iss = "evil.example".to_string();
        let token = sign(&other);
        assert_eq!(
            verify(&token, Some(&config()), now).expect_err("wrong issuer"),
            GrantError::BadIssuer
        );
    }

    #[test]
    fn a_read_tier_grant_does_not_authorize_mutation() {
        let now = 1_700_000_000;
        let mut read_only = claims(now);
        read_only.tier = "read".to_string();
        let token = sign(&read_only);
        assert_eq!(
            verify(&token, Some(&config()), now).expect_err("read tier"),
            GrantError::NotAWriteGrant
        );
    }

    #[test]
    fn an_over_long_grant_is_rejected_even_when_unexpired() {
        let now = 1_700_000_000;
        let mut long = claims(now);
        long.exp = now + 86_400;
        let token = sign(&long);
        assert!(matches!(
            verify(&token, Some(&config()), now).expect_err("ttl too long"),
            GrantError::TtlTooLong { .. }
        ));
    }

    #[test]
    fn a_future_dated_grant_cannot_smuggle_a_long_ttl() {
        let now = 1_700_000_000;
        let mut future = claims(now);
        // Small `exp - iat`, but both pushed far into the future so the token
        // would stay valid for a day if `iat` were not pinned to now.
        future.iat = now + 86_400;
        future.exp = now + 86_400 + 900;
        let token = sign(&future);
        assert_eq!(
            verify(&token, Some(&config()), now).expect_err("future iat"),
            GrantError::IssuedInFuture
        );
    }

    /// The attack this gate exists to survive: an attacker who has the public
    /// key (it is in the node's configuration, and in the Helm values) forging
    /// an HMAC token with it as the shared secret.
    #[test]
    fn a_token_signed_with_the_public_key_as_an_hmac_secret_is_rejected() {
        let now = 1_700_000_000;
        let forged = jsonwebtoken::encode(
            &Header::new(Algorithm::HS256),
            &claims(now),
            &EncodingKey::from_secret(PUBLIC_KEY_PEM.as_bytes()),
        )
        .expect("forge");

        assert_eq!(
            verify(&forged, Some(&config()), now).expect_err("alg confusion"),
            GrantError::InvalidSignature
        );
    }

    #[test]
    fn a_grant_signed_by_the_wrong_key_is_rejected() {
        let now = 1_700_000_000;
        let other_key = "-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEIPLaO7kPuWvdJpQZPqY8cgAK55FjQvo9qbKRZtcDjeov\n-----END PRIVATE KEY-----\n";
        let key = EncodingKey::from_ed_pem(other_key.as_bytes()).expect("other key");
        let token = jsonwebtoken::encode(&Header::new(Algorithm::EdDSA), &claims(now), &key)
            .expect("sign with other key");

        assert_eq!(
            verify(&token, Some(&config()), now).expect_err("wrong signer"),
            GrantError::InvalidSignature
        );
    }

    #[test]
    fn a_malformed_public_key_fails_closed() {
        let mut broken = config();
        broken.public_key_pem = "not a pem".to_string();
        let token = sign(&claims(1_700_000_000));
        assert_eq!(
            verify(&token, Some(&broken), 1_700_000_000).expect_err("malformed key"),
            GrantError::MalformedKey
        );
    }
}
