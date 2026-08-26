//! Talking to Tuist's server: verifying the tokens it signs and asking it about
//! the ones this node cannot verify itself.

use std::time::{Duration, Instant};

use jsonwebtoken::{Algorithm, DecodingKey, Validation, decode};
use reqwest::{Client, Method};
use serde_json::{Value, json};

use crate::metrics::Metrics;

/// How far past its own `exp` a credential is still taken as current, matching
/// jsonwebtoken's own default. It absorbs the clock skew between the issuer and
/// this node.
pub const EXPIRY_LEEWAY: Duration = Duration::from_secs(60);

#[derive(Clone, Debug)]
pub struct JwtVerifier {
    pub algorithm: Algorithm,
    /// What the token is read with. More than one only while a key is being
    /// rotated: the server and the nodes roll independently, so for a window
    /// both keys are in use and a token is tried against each.
    pub keys: Vec<DecodingKey>,
    pub issuer: Option<String>,
    pub audiences: Vec<String>,
}

impl JwtVerifier {
    pub fn parse_algorithm(value: &str) -> Result<Algorithm, String> {
        match value.trim().to_ascii_uppercase().as_str() {
            "HS256" => Ok(Algorithm::HS256),
            "HS384" => Ok(Algorithm::HS384),
            "HS512" => Ok(Algorithm::HS512),
            "ES256" => Ok(Algorithm::ES256),
            other => Err(format!("unsupported JWT algorithm '{other}'")),
        }
    }

    /// A shared secret verifies and signs alike, so a node holding one could
    /// mint the tokens it verifies. Only a deployment whose nodes and server
    /// are the same trust boundary should use this.
    pub fn secret_keys(secret: &str) -> Vec<DecodingKey> {
        vec![DecodingKey::from_secret(secret.as_bytes())]
    }

    /// The public halves of the cache-token keypair, as one or more
    /// concatenated PEM blocks. A node given these can read a cache token and
    /// cannot mint one, which is what lets an internet-facing node hold them.
    pub fn public_keys(bundle: &str) -> Result<Vec<DecodingKey>, String> {
        let keys = pem_blocks(bundle)
            .iter()
            .map(|block| {
                DecodingKey::from_ec_pem(block.as_bytes())
                    .map_err(|error| format!("JWT public key is not a readable PEM: {error}"))
            })
            .collect::<Result<Vec<_>, _>>()?;

        if keys.is_empty() {
            return Err("JWT public key contains no PEM block".into());
        }
        Ok(keys)
    }

    pub fn verify(&self, token: &str) -> Result<Value, String> {
        let mut validation = Validation::new(self.algorithm);
        // Pinned rather than inherited from jsonwebtoken's default, because the
        // policy refuses a credential past its expiry before asking the server
        // and has to refuse it over exactly the window this accepts it over.
        validation.leeway = EXPIRY_LEEWAY.as_secs();
        if let Some(issuer) = self.issuer.as_deref() {
            validation.set_issuer(&[issuer]);
        }
        if self.audiences.is_empty() {
            validation.validate_aud = false;
        } else {
            let audiences = self
                .audiences
                .iter()
                .map(String::as_str)
                .collect::<Vec<_>>();
            validation.set_audience(&audiences);
        }

        // The first key that reads the token answers. A key that does not is
        // not a verdict on the token, so the last failure is only reported
        // once every key has been tried.
        let mut failure = None;
        for key in &self.keys {
            match decode::<Value>(token, key, &validation) {
                Ok(token) => return Ok(token.claims),
                Err(error) => failure = Some(error),
            }
        }

        Err(match failure {
            Some(error) => format!("JWT verification failed: {error}"),
            None => "JWT verification failed: no key is configured".into(),
        })
    }
}

/// Splits a PEM bundle into its blocks. Concatenation is how a rotation
/// publishes the next key alongside the current one through a single value.
fn pem_blocks(bundle: &str) -> Vec<String> {
    bundle
        .split("-----BEGIN")
        .skip(1)
        .map(|block| format!("-----BEGIN{}", block.trim_end()))
        .collect()
}

/// A throwaway pair, and its rotation successor. Shared with the policy
/// tests so both sign with the same key the verifier is given.
#[cfg(test)]
pub(crate) mod test_keys {
    // A throwaway pair, and its rotation successor. Fixed rather than generated
    // so a failure is about the code under test.
    pub(crate) const SIGNING_KEY: &str = "\
    -----BEGIN PRIVATE KEY-----
    MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgiZOW2KwtxzHEuc6N
    M9Tn1vhXrMIJ4A4ND5S708b5sNKhRANCAAR49ecP/fwb8LDSXBb33jquLIwO3Q7c
    hQxqtQyHuT+BDLvd8598RL76YWLq0ddUa+kzlasiak5gz4CZPPRl/JQr
    -----END PRIVATE KEY-----
    ";

    pub(crate) const PUBLIC_KEY: &str = "\
    -----BEGIN PUBLIC KEY-----
    MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEePXnD/38G/Cw0lwW9946riyMDt0O
    3IUMarUMh7k/gQy73fOffES++mFi6tHXVGvpM5WrImpOYM+AmTz0ZfyUKw==
    -----END PUBLIC KEY-----
    ";

    pub(crate) const ROTATED_SIGNING_KEY: &str = "\
    -----BEGIN PRIVATE KEY-----
    MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg1pleNy6ZhrdrUQIW
    MTDQBwPmgY9S4qEwoDYrRXEdjkahRANCAAReoaVWopRByBUayj4u2l7zYUSEUvKL
    No1ZGehfODZohf4vw4hxHRHOWuwsN3Y444f/4qZQQA6HQtLBaziX9QVk
    -----END PRIVATE KEY-----
    ";

    pub(crate) const ROTATED_PUBLIC_KEY: &str = "\
    -----BEGIN PUBLIC KEY-----
    MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEXqGlVqKUQcgVGso+Ltpe82FEhFLy
    izaNWRnoXzg2aIX+L8OIcR0RzlrsLDd2OOOH/+KmUEAOh0LSwWs4l/UFZA==
    -----END PUBLIC KEY-----
    ";
}

/// Credentials for the introspection endpoint. Absent when the node was not
/// given any, which is what makes the node fall back to the cache-access route.
#[derive(Clone, Debug)]
pub struct IntrospectionCredentials {
    pub client_id: String,
    pub client_secret: String,
}

#[derive(Clone, Debug)]
pub struct Response {
    pub status: u16,
    pub body: Value,
}

#[derive(Clone)]
pub struct TuistBackend {
    base_url: String,
    client: Client,
    verifier: Option<JwtVerifier>,
    introspection: Option<IntrospectionCredentials>,
    metrics: Metrics,
}

impl TuistBackend {
    pub fn new(
        base_url: String,
        connect_timeout: Duration,
        request_timeout: Duration,
        verifier: Option<JwtVerifier>,
        introspection: Option<IntrospectionCredentials>,
        metrics: Metrics,
    ) -> Result<Self, String> {
        let client = Client::builder()
            .connect_timeout(connect_timeout)
            .timeout(request_timeout)
            .build()
            .map_err(|error| format!("failed to build the Tuist HTTP client: {error}"))?;

        Ok(Self {
            base_url,
            client,
            verifier,
            introspection,
            metrics,
        })
    }

    /// Tokens Tuist signs carry their grants, so most requests never touch the
    /// network. `None` when this node holds no verification key.
    ///
    /// A key that cannot read the token is reported rather than only returned:
    /// the policy falls back to the server on it, so a node given the wrong key
    /// keeps answering correctly and would otherwise announce nothing at all.
    pub fn verify_token(&self, token: &str) -> Option<Result<Value, String>> {
        let verifier = self.verifier.as_ref()?;

        let start = Instant::now();
        let result = verifier.verify(token);
        self.metrics.record_auth_decision(
            "verify",
            if result.is_ok() {
                "readable"
            } else {
                "unreadable"
            },
            start.elapsed(),
        );

        Some(result)
    }

    pub fn introspection_configured(&self) -> bool {
        self.introspection.is_some()
    }

    pub async fn introspect(&self, token: &str) -> Result<Response, String> {
        let Some(credentials) = self.introspection.as_ref() else {
            return Err("introspection credentials are not configured".into());
        };

        self.request(
            Method::POST,
            "/oauth2/introspect",
            "introspect",
            &[],
            Some(json!({
                "client_id": credentials.client_id,
                "client_secret": credentials.client_secret,
                "token": token,
            })),
        )
        .await
    }

    /// The route that predates token-carried grants. Older CLIs hold tokens
    /// whose grants cannot cover a project created after the token was minted,
    /// and the server still answers for those.
    pub async fn cache_access(&self, authorization: &str) -> Result<Response, String> {
        self.request(
            Method::GET,
            "/api/cache/access",
            "cache_access",
            &[("authorization", authorization)],
            None,
        )
        .await
    }

    async fn request(
        &self,
        method: Method,
        path: &str,
        route: &'static str,
        headers: &[(&str, &str)],
        body: Option<Value>,
    ) -> Result<Response, String> {
        let url = format!("{}{path}", self.base_url.trim_end_matches('/'));

        let mut attempt = 0;
        let response = loop {
            attempt += 1;
            let start = Instant::now();

            let mut builder = self.client.request(method.clone(), &url);
            for (name, value) in headers {
                builder = builder.header(*name, *value);
            }
            if let Some(body) = &body {
                builder = builder.json(body);
            }

            match builder.send().await {
                Ok(response) => {
                    self.metrics.record_auth_backend(
                        route,
                        "ok",
                        status_class(response.status().as_u16()),
                        "none",
                        start.elapsed(),
                    );
                    break response;
                }
                Err(error) => {
                    let error_kind = classify_reqwest_error(&error);
                    self.metrics.record_auth_backend(
                        route,
                        "error",
                        "none",
                        error_kind,
                        start.elapsed(),
                    );
                    // One retry, and only for the errors where the request
                    // provably never reached the server.
                    if attempt < 2 && retryable_reqwest_error(error_kind) {
                        tokio::time::sleep(Duration::from_millis(100)).await;
                        continue;
                    }
                    return Err(format!(
                        "Tuist {route} request failed after {attempt} attempt(s): {}",
                        format_reqwest_error(&error)
                    ));
                }
            }
        };

        let status = response.status().as_u16();
        let body = response
            .json::<Value>()
            .await
            .map_err(|error| format!("Tuist {route} returned invalid JSON: {error}"))?;

        Ok(Response { status, body })
    }
}

fn status_class(status: u16) -> &'static str {
    match status {
        100..=199 => "1xx",
        200..=299 => "2xx",
        300..=399 => "3xx",
        400..=499 => "4xx",
        _ => "5xx",
    }
}

fn classify_reqwest_error(error: &reqwest::Error) -> &'static str {
    let chain = error_chain_string(error);
    if error.is_timeout() {
        "timeout"
    } else if chain.contains("dns") {
        "dns"
    } else if chain.contains("tls") || chain.contains("certificate") {
        "tls"
    } else if chain.contains("connection closed")
        || chain.contains("closed for writing")
        || chain.contains("server closed")
    {
        "closed"
    } else if error.is_connect() {
        "connect"
    } else if error.is_request() {
        "request"
    } else if error.is_body() {
        "body"
    } else if error.is_decode() {
        "decode"
    } else {
        "unknown"
    }
}

fn error_chain_string(error: &reqwest::Error) -> String {
    let mut chain = vec![error.to_string()];
    let mut source = std::error::Error::source(error);
    while let Some(cause) = source {
        chain.push(cause.to_string());
        source = cause.source();
    }
    chain.join(": ").to_lowercase()
}

/// Everything except a response that arrived but could not be read: both calls
/// are reads, so a second attempt is safe and covers a slow first one.
fn retryable_reqwest_error(error_kind: &str) -> bool {
    matches!(
        error_kind,
        "timeout" | "dns" | "tls" | "closed" | "connect" | "request" | "unknown"
    )
}

fn format_reqwest_error(error: &reqwest::Error) -> String {
    let mut chain = vec![error.to_string()];
    let mut source = std::error::Error::source(error);
    while let Some(cause) = source {
        chain.push(cause.to_string());
        source = cause.source();
    }
    chain.join(": ")
}

#[cfg(test)]
mod tests {
    use jsonwebtoken::{EncodingKey, Header, encode};

    use super::test_keys::*;
    use serde_json::json;

    use super::*;

    fn cache_token(signing_key: &str) -> String {
        encode(
            &Header::new(Algorithm::ES256),
            &json!({
                "sub": "1",
                "iss": "tuist",
                "typ": "cache",
                "exp": 4_000_000_000u64,
                "cache_grants": { "project": { "write": ["acme/ios"] } },
            }),
            &EncodingKey::from_ec_pem(signing_key.as_bytes()).expect("a readable signing key"),
        )
        .expect("a signed cache token")
    }

    fn verifier(bundle: &str) -> JwtVerifier {
        JwtVerifier {
            algorithm: Algorithm::ES256,
            keys: JwtVerifier::public_keys(bundle).expect("a readable public key"),
            issuer: Some("tuist".into()),
            audiences: Vec::new(),
        }
    }

    #[test]
    fn reads_a_token_the_public_half_answers_for() {
        let claims = verifier(PUBLIC_KEY)
            .verify(&cache_token(SIGNING_KEY))
            .expect("the token to verify");

        assert_eq!(claims["cache_grants"]["project"]["write"][0], "acme/ios");
    }

    // The point of the bundle: the server and the nodes roll independently, so
    // for a window tokens signed by either key are in flight.
    #[test]
    fn reads_a_token_signed_by_either_key_while_one_is_being_rotated() {
        let bundle = format!("{PUBLIC_KEY}{ROTATED_PUBLIC_KEY}");

        for signing_key in [SIGNING_KEY, ROTATED_SIGNING_KEY] {
            assert!(verifier(&bundle).verify(&cache_token(signing_key)).is_ok());
        }
    }

    // The node holds only public halves, so it cannot mint what it reads, and a
    // token signed by anything else is simply not readable here.
    #[test]
    fn does_not_read_a_token_signed_by_a_key_it_does_not_hold() {
        assert!(
            verifier(PUBLIC_KEY)
                .verify(&cache_token(ROTATED_SIGNING_KEY))
                .is_err()
        );
    }

    #[test]
    fn splits_a_bundle_into_the_keys_it_carries() {
        assert_eq!(pem_blocks(PUBLIC_KEY).len(), 1);
        assert_eq!(
            pem_blocks(&format!("{PUBLIC_KEY}\n{ROTATED_PUBLIC_KEY}")).len(),
            2
        );
        assert!(pem_blocks("   ").is_empty());
    }

    // A value that carries no key is not configuration, and a node that took it
    // as one would hold a verifier that can never read anything.
    #[test]
    fn refuses_a_bundle_that_carries_no_key() {
        assert!(JwtVerifier::public_keys("not a pem").is_err());
        assert!(JwtVerifier::public_keys("").is_err());
    }
    // Minted by the server's own signer rather than by this crate, so the two
    // stacks stay pinned to the same ES256 encoding: JWS wants a raw r||s
    // signature and a DER one would verify nowhere. It also pins the grant
    // shape the server writes against the parser that reads it back.
    #[test]
    fn reads_a_token_the_server_itself_minted() {
        const SERVER_PUBLIC_KEY: &str = "\
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEizhQjBYwbIf85hZQXluHGaPPeiH2
6NMcqWG9Bf1oo5kJHChifcdQYTD58jcmnefL63lVG/MTYPO6dCQe3a/XgQ==
-----END PUBLIC KEY-----
";
        // Expires in 2126, so it does not rot.
        const SERVER_MINTED_TOKEN: &str = concat!(
            "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJ0dWlzdCIsImNhY2hlX2dyYW50",
            "cyI6eyJhY2NvdW50Ijp7InJlYWQiOltdLCJ3cml0ZSI6W119LCJwcm9qZWN0Ijp7InJlYWQiOl",
            "siYWNtZS9pb3MiXSwid3JpdGUiOlsiYWNtZS9pb3MiXX19LCJleHAiOjQ5NDA4NDU2NTksImlh",
            "dCI6MTc4NzI0NTY1OSwiaXNzIjoidHVpc3QiLCJqdGkiOiIwYjcxN2ZkNy1iODNhLTQ5YWUtOT",
            "cyZS02NjcyMThlM2E3NjciLCJuYmYiOjE3ODcyNDU2NTgsInN1YiI6IjEiLCJ0eXAiOiJjYWNo",
            "ZSJ9.YJfvgZ-aa7SB5zMbvoyqxON20YJrea-z7NEzIltV6a-PE6h59q9fZa8db_MFibyjHpc4",
            "Mc0ECaR46oM4LXG2Cg"
        );

        let verifier = JwtVerifier {
            algorithm: Algorithm::ES256,
            keys: JwtVerifier::public_keys(SERVER_PUBLIC_KEY).expect("a readable public key"),
            issuer: Some("tuist".into()),
            audiences: vec!["tuist".into()],
        };

        let claims = verifier
            .verify(SERVER_MINTED_TOKEN)
            .expect("the server's own token to verify");

        assert_eq!(claims["typ"], "cache");
        assert_eq!(
            crate::auth::grants::CacheGrants::from_body(&claims)
                .project
                .write,
            ["acme/ios"]
        );
    }
}
