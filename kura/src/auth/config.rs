//! How a node is told to authorize.
//!
//! Authorization is on when the node is given Tuist's URL. Everything else has
//! a default, so a self-hosted deployment sets one variable plus whichever
//! credentials it has.

use std::str::FromStr;
use std::time::Duration;

use tracing::warn;

use jsonwebtoken::Algorithm;

use super::tuist::{IntrospectionCredentials, JwtVerifier};

const ENABLED: &str = "KURA_AUTH_ENABLED";
const TUIST_URL: &str = "KURA_AUTH_TUIST_URL";
const CONNECT_TIMEOUT_MS: &str = "KURA_AUTH_TUIST_CONNECT_TIMEOUT_MS";
const REQUEST_TIMEOUT_MS: &str = "KURA_AUTH_TUIST_REQUEST_TIMEOUT_MS";
const JWT_SECRET: &str = "KURA_AUTH_JWT_SECRET";
const JWT_PUBLIC_KEY: &str = "KURA_AUTH_JWT_PUBLIC_KEY";
const JWT_ALGORITHM: &str = "KURA_AUTH_JWT_ALGORITHM";
const JWT_ISSUER: &str = "KURA_AUTH_JWT_ISSUER";
const JWT_AUDIENCES: &str = "KURA_AUTH_JWT_AUDIENCES";
const CACHE_MAX_ENTRIES: &str = "KURA_AUTH_CACHE_MAX_ENTRIES";
const CLIENT_ID: &str = "KURA_CONTROL_PLANE_CLIENT_ID";
const CLIENT_SECRET: &str = "KURA_CONTROL_PLANE_CLIENT_SECRET";

const DEFAULT_CACHE_MAX_ENTRIES: usize = 100_000;
// Each key kind has the algorithm it is actually used with, so neither has to
// be spelled out alongside the key. The secret default is what self-hosted
// manifests already rely on and cannot change.
const DEFAULT_SECRET_ALGORITHM: &str = "HS256";
const DEFAULT_PUBLIC_KEY_ALGORITHM: &str = "ES256";
// What the managed provisioner renders. A node that is not rendered by it —
// self-hosted, or a manifest that predates those variables — used to fall back
// to 500/1500, where one dropped SYN (first retransmit at ~1s) fails the
// connect outright.
const DEFAULT_CONNECT_TIMEOUT_MS: u64 = 3000;
const DEFAULT_REQUEST_TIMEOUT_MS: u64 = 4000;
// reqwest's request timeout spans the connect, so a connect budget at or above
// it can never be reached and the node gives up on the handshake early.
const _: () = assert!(DEFAULT_CONNECT_TIMEOUT_MS < DEFAULT_REQUEST_TIMEOUT_MS);

/// The invariant the constants above are asserted against holds for what an
/// operator sets too, and a connect budget that can never be reached is worth
/// saying out loud rather than starting with quietly.
fn reachable_connect_timeout_ms(connect_timeout_ms: u64, request_timeout_ms: u64) -> u64 {
    if connect_timeout_ms < request_timeout_ms {
        return connect_timeout_ms;
    }

    warn!(
        "{} ({}ms) is not below {} ({}ms), which spans it; using {}ms for the connect.",
        CONNECT_TIMEOUT_MS,
        connect_timeout_ms,
        REQUEST_TIMEOUT_MS,
        request_timeout_ms,
        request_timeout_ms
    );
    request_timeout_ms
}

#[derive(Clone, Debug)]
pub struct AuthConfig {
    pub base_url: String,
    pub connect_timeout: Duration,
    pub request_timeout: Duration,
    pub verifier: Option<JwtVerifier>,
    pub introspection: Option<IntrospectionCredentials>,
    pub cache_max_entries: usize,
}

impl AuthConfig {
    pub fn from_env() -> Result<Option<Self>, String> {
        // Being told which server to authorize against is itself the decision to
        // authorize: a node that has one and stays open would serve the cache to
        // anyone who can reach it. An explicit `false` does not override that,
        // but it is not ignored quietly either — the managed chart always sets
        // the URL, so an operator turning this off there would otherwise get
        // authorization with nothing saying why.
        let asked_to_disable = env_truthy(ENABLED) == Some(false);
        let has_url = env_value(TUIST_URL).is_some();
        if asked_to_disable && has_url {
            warn!(
                "{ENABLED} is set false but {TUIST_URL} is set; authorization stays on. \
                 Unset {TUIST_URL} to run without it."
            );
        }

        if !(env_truthy(ENABLED).unwrap_or(false) || has_url) {
            return Ok(None);
        }

        // Refusing to start beats starting without authorization: an
        // unconfigured node serves the cache to anyone who asks.
        let base_url = env_value(TUIST_URL)
            .ok_or_else(|| format!("{TUIST_URL} is required when authorization is enabled"))?;

        let cache_max_entries =
            optional_parse(CACHE_MAX_ENTRIES)?.unwrap_or(DEFAULT_CACHE_MAX_ENTRIES);
        if cache_max_entries == 0 {
            return Err(format!("{CACHE_MAX_ENTRIES} must be greater than 0"));
        }

        let request_timeout_ms =
            optional_parse(REQUEST_TIMEOUT_MS)?.unwrap_or(DEFAULT_REQUEST_TIMEOUT_MS);
        let configured_connect_timeout_ms =
            optional_parse(CONNECT_TIMEOUT_MS)?.unwrap_or(DEFAULT_CONNECT_TIMEOUT_MS);
        let connect_timeout_ms =
            reachable_connect_timeout_ms(configured_connect_timeout_ms, request_timeout_ms);

        Ok(Some(Self {
            base_url,
            connect_timeout: Duration::from_millis(connect_timeout_ms),
            request_timeout: Duration::from_millis(request_timeout_ms),
            verifier: jwt_verifier_from_env()?,
            introspection: introspection_from_env(),
            cache_max_entries,
        }))
    }
}

/// Without key material the node cannot read a token itself and asks the server
/// about every request, which works but costs a round trip.
///
/// Two shapes, and which one a node is given is a trust decision rather than a
/// preference. A shared secret signs as well as it verifies, so a node holding
/// one can mint the tokens it checks; that is only tenable where the node and
/// the server are the same trust boundary. The public half of a dedicated
/// cache-token keypair verifies and nothing else, which is what an
/// internet-facing node is given.
fn jwt_verifier_from_env() -> Result<Option<JwtVerifier>, String> {
    let secret = env_value(JWT_SECRET);
    let public_key = env_value(JWT_PUBLIC_KEY);

    let (keys, algorithm) = match (secret.as_deref(), public_key.as_deref()) {
        // Which one a node verifies with decides what it could forge, so a
        // manifest naming both is a question rather than a preference to
        // resolve quietly.
        (Some(_), Some(_)) => {
            return Err(format!(
                "{JWT_SECRET} and {JWT_PUBLIC_KEY} are both set; a node verifies with one or the other"
            ));
        }
        (None, None) => return Ok(None),
        (Some(secret), None) => {
            let algorithm = algorithm_from_env(DEFAULT_SECRET_ALGORITHM)?;
            if algorithm == Algorithm::ES256 {
                return Err(format!(
                    "{JWT_ALGORITHM} is ES256, which reads a key from {JWT_PUBLIC_KEY} rather than {JWT_SECRET}"
                ));
            }
            (JwtVerifier::secret_keys(secret), algorithm)
        }
        (None, Some(public_key)) => {
            let algorithm = algorithm_from_env(DEFAULT_PUBLIC_KEY_ALGORITHM)?;
            if algorithm != Algorithm::ES256 {
                return Err(format!(
                    "{JWT_ALGORITHM} is {algorithm:?}, which reads a key from {JWT_SECRET} rather than {JWT_PUBLIC_KEY}"
                ));
            }
            (JwtVerifier::public_keys(public_key)?, algorithm)
        }
    };

    Ok(Some(JwtVerifier {
        algorithm,
        keys,
        issuer: env_value(JWT_ISSUER),
        audiences: env_value(JWT_AUDIENCES)
            .map(|audiences| {
                audiences
                    .split(',')
                    .map(str::trim)
                    .filter(|audience| !audience.is_empty())
                    .map(ToOwned::to_owned)
                    .collect()
            })
            .unwrap_or_default(),
    }))
}

fn algorithm_from_env(default: &str) -> Result<Algorithm, String> {
    JwtVerifier::parse_algorithm(&env_value(JWT_ALGORITHM).unwrap_or_else(|| default.into()))
}

fn introspection_from_env() -> Option<IntrospectionCredentials> {
    Some(IntrospectionCredentials {
        client_id: env_value(CLIENT_ID)?,
        client_secret: env_value(CLIENT_SECRET)?,
    })
}

fn env_value(key: &str) -> Option<String> {
    configured(std::env::var(key).ok())
}

/// Blank reads as unset, so a variable rendered empty by a manifest does not
/// count as configuration. This decides whether a node authorizes at all, so it
/// is kept separate from reading the environment in order to stay testable.
fn configured(raw: Option<String>) -> Option<String> {
    raw.map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
}

fn optional_parse<T>(key: &str) -> Result<Option<T>, String>
where
    T: FromStr,
    T::Err: std::fmt::Display,
{
    env_value(key)
        .map(|value| {
            value
                .parse::<T>()
                .map_err(|error| format!("{key} is not a valid value: {error}"))
        })
        .transpose()
}

fn env_truthy(key: &str) -> Option<bool> {
    match env_value(key)?.to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" | "on" => Some(true),
        "0" | "false" | "no" | "off" => Some(false),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // A variable rendered empty is not configuration. It decides whether
    // `from_env` answers `Some` or `None`, and a node that answers `None`
    // serves the cache to anyone who reaches it.
    #[test]
    fn treats_a_blank_value_as_unset() {
        assert_eq!(
            configured(Some("https://tuist.dev".into())),
            Some("https://tuist.dev".into())
        );
        assert_eq!(
            configured(Some("  https://tuist.dev  ".into())),
            Some("https://tuist.dev".into())
        );
        assert_eq!(configured(Some("".into())), None);
        assert_eq!(configured(Some("   ".into())), None);
        assert_eq!(configured(None), None);
    }

    #[test]
    fn parses_the_algorithms_the_server_signs_with() {
        assert!(JwtVerifier::parse_algorithm("hs512").is_ok());
        assert!(JwtVerifier::parse_algorithm(" HS256 ").is_ok());
        assert_eq!(JwtVerifier::parse_algorithm("es256"), Ok(Algorithm::ES256));
        assert!(JwtVerifier::parse_algorithm("RS256").is_err());
    }

    // A connect budget at or above the request budget is exactly the
    // configuration the assertion on the defaults exists to prevent, and
    // nothing stops an operator setting one.
    #[test]
    fn a_connect_budget_the_request_budget_spans_is_brought_back_within_it() {
        assert_eq!(reachable_connect_timeout_ms(3000, 4000), 3000);
        assert_eq!(reachable_connect_timeout_ms(6000, 4000), 4000);
        assert_eq!(reachable_connect_timeout_ms(4000, 4000), 4000);
    }
}
