//! How a node is told to authorize.
//!
//! Authorization is on when the node is given Tuist's URL. Everything else has
//! a default, so a self-hosted deployment sets one variable plus whichever
//! credentials it has.

use std::str::FromStr;
use std::time::Duration;

use super::tuist::{IntrospectionCredentials, JwtVerifier};

// Each setting is read from its current name first and its previous name
// second. A node that is unconfigured does not authorize at all, and the image
// rolls before whatever sets its environment does, so a new binary meeting an
// older environment has to keep working. The previous names come out once every
// deployment writes the current ones.
const ENABLED: &[&str] = &["KURA_AUTH_ENABLED", "KURA_EXTENSION_ENABLED"];
const TUIST_URL: &[&str] = &[
    "KURA_AUTH_TUIST_URL",
    "KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL",
];
const CONNECT_TIMEOUT_MS: &[&str] = &[
    "KURA_AUTH_TUIST_CONNECT_TIMEOUT_MS",
    "KURA_EXTENSION_HTTP_CLIENT_TUIST_CONNECT_TIMEOUT_MS",
];
const REQUEST_TIMEOUT_MS: &[&str] = &[
    "KURA_AUTH_TUIST_REQUEST_TIMEOUT_MS",
    "KURA_EXTENSION_HTTP_CLIENT_TUIST_REQUEST_TIMEOUT_MS",
];
const JWT_SECRET: &[&str] = &[
    "KURA_AUTH_JWT_SECRET",
    "KURA_EXTENSION_JWT_VERIFIER_TUIST_SECRET",
];
const JWT_ALGORITHM: &[&str] = &[
    "KURA_AUTH_JWT_ALGORITHM",
    "KURA_EXTENSION_JWT_VERIFIER_TUIST_ALGORITHM",
];
const JWT_ISSUER: &[&str] = &[
    "KURA_AUTH_JWT_ISSUER",
    "KURA_EXTENSION_JWT_VERIFIER_TUIST_ISSUER",
];
const JWT_AUDIENCES: &[&str] = &[
    "KURA_AUTH_JWT_AUDIENCES",
    "KURA_EXTENSION_JWT_VERIFIER_TUIST_AUDIENCES",
];
const CACHE_MAX_ENTRIES: &[&str] = &[
    "KURA_AUTH_CACHE_MAX_ENTRIES",
    "KURA_EXTENSION_CACHE_MAX_ENTRIES",
];
const CLIENT_ID: &[&str] = &[
    "KURA_CONTROL_PLANE_CLIENT_ID",
    "KURA_EXTENSION_TUIST_INTROSPECT_CLIENT_ID",
];
const CLIENT_SECRET: &[&str] = &[
    "KURA_CONTROL_PLANE_CLIENT_SECRET",
    "KURA_EXTENSION_TUIST_INTROSPECT_CLIENT_SECRET",
];

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
            .ok_or_else(|| format!("{} is required when authorization is enabled", TUIST_URL[0]))?;

        let cache_max_entries =
            optional_parse(CACHE_MAX_ENTRIES)?.unwrap_or(DEFAULT_CACHE_MAX_ENTRIES);
        if cache_max_entries == 0 {
            return Err(format!("{} must be greater than 0", CACHE_MAX_ENTRIES[0]));
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

/// The first of these names that is set, so the current name always wins.
fn env_entry(keys: &[&'static str]) -> Option<(&'static str, String)> {
    first_set(keys, |key| std::env::var(key).ok())
}

fn first_set(
    keys: &[&'static str],
    lookup: impl Fn(&str) -> Option<String>,
) -> Option<(&'static str, String)> {
    keys.iter().find_map(|key| {
        lookup(key)
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty())
            .map(|value| (*key, value))
    })
}

fn env_value(keys: &[&'static str]) -> Option<String> {
    env_entry(keys).map(|(_, value)| value)
}

fn optional_parse<T>(keys: &[&'static str]) -> Result<Option<T>, String>
where
    T: FromStr,
    T::Err: std::fmt::Display,
{
    env_entry(keys)
        .map(|(key, value)| {
            value
                .parse::<T>()
                .map_err(|error| format!("{key} is not a valid value: {error}"))
        })
        .transpose()
}

fn env_truthy(keys: &[&'static str]) -> Option<bool> {
    match env_value(keys)?.to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" | "on" => Some(true),
        "0" | "false" | "no" | "off" => Some(false),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::*;

    fn lookup(pairs: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> + use<> {
        let map: HashMap<String, String> = pairs
            .iter()
            .map(|(key, value)| ((*key).to_owned(), (*value).to_owned()))
            .collect();
        move |key: &str| map.get(key).cloned()
    }

    #[test]
    fn prefers_the_current_name_over_the_previous_one() {
        let entry = first_set(
            TUIST_URL,
            lookup(&[
                ("KURA_AUTH_TUIST_URL", "https://tuist.dev"),
                (
                    "KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL",
                    "https://old.example",
                ),
            ]),
        );

        assert_eq!(entry.expect("a value").1, "https://tuist.dev");
    }

    // A node whose environment still carries only the previous names has to
    // keep authorizing: unconfigured means it authorizes nothing at all.
    #[test]
    fn still_reads_the_previous_name() {
        let entry = first_set(
            TUIST_URL,
            lookup(&[(
                "KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL",
                "https://old.example",
            )]),
        );

        let (key, value) = entry.expect("a value");
        assert_eq!(key, "KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL");
        assert_eq!(value, "https://old.example");
    }

    #[test]
    fn treats_a_blank_value_as_unset() {
        assert!(first_set(TUIST_URL, lookup(&[("KURA_AUTH_TUIST_URL", "   ")])).is_none());
    }
}
