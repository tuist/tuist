//! How a node is told to authorize.
//!
//! Authorization is on when the node is given Tuist's URL. Everything else has
//! a default, so a self-hosted deployment sets one variable plus whichever
//! credentials it has.

use std::str::FromStr;
use std::time::Duration;

use super::tuist::{IntrospectionCredentials, JwtVerifier};

const ENABLED: &str = "KURA_AUTH_ENABLED";
const TUIST_URL: &str = "KURA_AUTH_TUIST_URL";
const CONNECT_TIMEOUT_MS: &str = "KURA_AUTH_TUIST_CONNECT_TIMEOUT_MS";
const REQUEST_TIMEOUT_MS: &str = "KURA_AUTH_TUIST_REQUEST_TIMEOUT_MS";
const JWT_SECRET: &str = "KURA_AUTH_JWT_SECRET";
const JWT_ALGORITHM: &str = "KURA_AUTH_JWT_ALGORITHM";
const JWT_ISSUER: &str = "KURA_AUTH_JWT_ISSUER";
const JWT_AUDIENCES: &str = "KURA_AUTH_JWT_AUDIENCES";
const CACHE_MAX_ENTRIES: &str = "KURA_AUTH_CACHE_MAX_ENTRIES";
const CLIENT_ID: &str = "KURA_CONTROL_PLANE_CLIENT_ID";
const CLIENT_SECRET: &str = "KURA_CONTROL_PLANE_CLIENT_SECRET";

const DEFAULT_CACHE_MAX_ENTRIES: usize = 100_000;

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
        let enabled = env_truthy(ENABLED).unwrap_or(false) || env_value(TUIST_URL).is_some();
        if !enabled {
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

        Ok(Some(Self {
            base_url,
            connect_timeout: Duration::from_millis(
                optional_parse(CONNECT_TIMEOUT_MS)?.unwrap_or(500),
            ),
            request_timeout: Duration::from_millis(
                optional_parse(REQUEST_TIMEOUT_MS)?.unwrap_or(1500),
            ),
            verifier: jwt_verifier_from_env()?,
            introspection: introspection_from_env(),
            cache_max_entries,
        }))
    }
}

/// Without a verification key the node cannot read a token itself and asks the
/// server about every request, which works but costs a round trip.
fn jwt_verifier_from_env() -> Result<Option<JwtVerifier>, String> {
    let Some(secret) = env_value(JWT_SECRET) else {
        return Ok(None);
    };

    Ok(Some(JwtVerifier {
        algorithm: JwtVerifier::parse_algorithm(
            &env_value(JWT_ALGORITHM).unwrap_or_else(|| "HS256".into()),
        )?,
        secret,
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

fn introspection_from_env() -> Option<IntrospectionCredentials> {
    Some(IntrospectionCredentials {
        client_id: env_value(CLIENT_ID)?,
        client_secret: env_value(CLIENT_SECRET)?,
    })
}

/// Blank reads as unset, so a variable set to an empty string in a manifest
/// does not count as configuration.
fn env_value(key: &str) -> Option<String> {
    std::env::var(key)
        .ok()
        .map(|value| value.trim().to_owned())
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

    #[test]
    fn parses_the_algorithms_the_server_signs_with() {
        assert!(JwtVerifier::parse_algorithm("hs512").is_ok());
        assert!(JwtVerifier::parse_algorithm(" HS256 ").is_ok());
        assert!(JwtVerifier::parse_algorithm("RS256").is_err());
    }
}
