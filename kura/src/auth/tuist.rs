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
    pub secret: String,
    pub issuer: Option<String>,
    pub audiences: Vec<String>,
}

impl JwtVerifier {
    pub fn parse_algorithm(value: &str) -> Result<Algorithm, String> {
        match value.trim().to_ascii_uppercase().as_str() {
            "HS256" => Ok(Algorithm::HS256),
            "HS384" => Ok(Algorithm::HS384),
            "HS512" => Ok(Algorithm::HS512),
            other => Err(format!("unsupported JWT algorithm '{other}'")),
        }
    }

    pub fn verify(&self, token: &str) -> Result<Value, String> {
        let key = DecodingKey::from_secret(self.secret.as_bytes());
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

        decode::<Value>(token, &key, &validation)
            .map(|token| token.claims)
            .map_err(|error| format!("JWT verification failed: {error}"))
    }
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
    pub fn verify_token(&self, token: &str) -> Option<Result<Value, String>> {
        self.verifier
            .as_ref()
            .map(|verifier| verifier.verify(token))
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
