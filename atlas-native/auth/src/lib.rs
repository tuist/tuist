mod api;
mod bridge;
mod form;
mod transport;

use transport::{Body, Network, Transport};

use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::time::{SystemTime, UNIX_EPOCH};
use url::Url;

pub const REDIRECT_URI: &str = "dev.tuist.atlas://oauth-callback";

#[derive(Serialize, Deserialize, Clone)]
pub struct Registration {
    server: String,
    authorization_endpoint: String,
    token_endpoint: String,
    client_id: String,
}

// Intentionally no Debug on credentials or pending grants: neither belongs in logs.
#[derive(Serialize, Deserialize)]
pub struct PendingLogin {
    registration: Registration,
    verifier: String,
    state: String,
    created_at: u64,
}

#[derive(Serialize, Deserialize)]
pub struct Session {
    registration: Registration,
    access_token: String,
    refresh_token: String,
    expires_at: u64,
}

#[derive(Serialize)]
pub struct Login {
    authorization_url: String,
    pending: PendingLogin,
    registration: Registration,
}

#[derive(Deserialize)]
struct Discovery {
    issuer: String,
    authorization_endpoint: String,
    token_endpoint: String,
    registration_endpoint: String,
    code_challenge_methods_supported: Vec<String>,
}

#[derive(Deserialize)]
struct RegisteredClient {
    client_id: String,
    token_endpoint_auth_method: String,
}

#[derive(Deserialize)]
struct Tokens {
    access_token: String,
    refresh_token: Option<String>,
    token_type: String,
    expires_in: u64,
}

#[derive(Serialize, Debug)]
pub struct AuthError {
    pub kind: &'static str,
    pub message: &'static str,
}

type Result<T> = std::result::Result<T, AuthError>;

fn error(kind: &'static str, message: &'static str) -> AuthError {
    AuthError { kind, message }
}

fn invalid() -> AuthError {
    error(
        "invalid_response",
        "The server returned an invalid OAuth response.",
    )
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

pub fn server_url(input: &str) -> Result<Url> {
    let mut url = Url::parse(input.trim()).map_err(|_| invalid())?;
    if url.scheme() != "https"
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || !matches!(url.path(), "" | "/")
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return Err(error(
            "invalid_server",
            "Enter an HTTPS server address without a path, query, or credentials.",
        ));
    }
    url.set_path("/");
    Ok(url)
}

fn endpoint(server: &Url, input: &str) -> Result<Url> {
    let url = Url::parse(input).map_err(|_| invalid())?;
    if url.origin() != server.origin()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.fragment().is_some()
    {
        return Err(error(
            "invalid_endpoint",
            "OAuth endpoints must be on the selected server's HTTPS origin.",
        ));
    }
    Ok(url)
}

fn validate_registration(registration: &Registration) -> Result<Url> {
    let server = server_url(&registration.server)?;
    endpoint(&server, &registration.authorization_endpoint)?;
    endpoint(&server, &registration.token_endpoint)?;
    if registration.client_id.is_empty() {
        return Err(invalid());
    }
    Ok(server)
}

pub fn begin(server: &str, saved: Option<Registration>) -> Result<Login> {
    begin_using(&Network, server, saved)
}

fn begin_using(
    network: &impl Transport,
    server: &str,
    saved: Option<Registration>,
) -> Result<Login> {
    let server = server_url(server)?;
    let registration = match saved.filter(|saved| saved.server == server.as_str()) {
        Some(saved) => {
            validate_registration(&saved)?;
            saved
        }
        None => {
            let discovery: Discovery = network.request(
                &server
                    .join(".well-known/oauth-authorization-server")
                    .unwrap(),
                Body::Get,
            )?;
            if server_url(&discovery.issuer)? != server
                || !discovery
                    .code_challenge_methods_supported
                    .iter()
                    .any(|method| method == "S256")
            {
                return Err(invalid());
            }
            let authorization_endpoint = endpoint(&server, &discovery.authorization_endpoint)?;
            let token_endpoint = endpoint(&server, &discovery.token_endpoint)?;
            let registration_endpoint = endpoint(&server, &discovery.registration_endpoint)?;
            let registered: RegisteredClient = network.request(
                &registration_endpoint,
                Body::Json(serde_json::json!({
                    "client_name": "Atlas Native",
                    "redirect_uris": [REDIRECT_URI],
                    "grant_types": ["authorization_code", "refresh_token"],
                    "response_types": ["code"],
                    "token_endpoint_auth_method": "none"
                })),
            )?;
            if registered.client_id.is_empty() || registered.token_endpoint_auth_method != "none" {
                return Err(invalid());
            }
            Registration {
                server: server.to_string(),
                authorization_endpoint: authorization_endpoint.to_string(),
                token_endpoint: token_endpoint.to_string(),
                client_id: registered.client_id,
            }
        }
    };
    let verifier = random_string()?;
    let state = random_string()?;
    let pending = PendingLogin {
        registration: registration.clone(),
        verifier,
        state,
        created_at: now(),
    };
    let mut authorization_url =
        Url::parse(&registration.authorization_endpoint).map_err(|_| invalid())?;
    authorization_url.query_pairs_mut().extend_pairs([
        ("response_type", "code"),
        ("client_id", &registration.client_id),
        ("redirect_uri", REDIRECT_URI),
        ("scope", "mcp"),
        ("state", &pending.state),
        (
            "code_challenge",
            &URL_SAFE_NO_PAD.encode(Sha256::digest(pending.verifier.as_bytes())),
        ),
        ("code_challenge_method", "S256"),
    ]);
    Ok(Login {
        authorization_url: authorization_url.to_string(),
        pending,
        registration,
    })
}

fn random_string() -> Result<String> {
    let mut bytes = [0_u8; 32];
    getrandom::fill(&mut bytes)
        .map_err(|_| error("internal", "Could not generate a secure sign-in challenge."))?;
    Ok(URL_SAFE_NO_PAD.encode(bytes))
}

fn callback_code(pending: &PendingLogin, callback: &str) -> Result<String> {
    let url = Url::parse(callback).map_err(|_| invalid())?;
    let expected = Url::parse(REDIRECT_URI).unwrap();
    if url.scheme() != expected.scheme()
        || url.host_str() != expected.host_str()
        || url.path() != expected.path()
        || url.port().is_some()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.fragment().is_some()
        || now().saturating_sub(pending.created_at) > 600
    {
        return Err(error(
            "invalid_callback",
            "The sign-in callback is invalid or expired.",
        ));
    }
    let pairs: Vec<_> = url.query_pairs().collect();
    let values = |key: &str| -> Vec<String> {
        pairs
            .iter()
            .filter(|(name, _)| name == key)
            .map(|(_, value)| value.to_string())
            .collect()
    };
    if values("state") != [pending.state.clone()] {
        return Err(error(
            "invalid_callback",
            "The sign-in callback did not match this login.",
        ));
    }
    if !values("error").is_empty() {
        return Err(error(
            "denied",
            "Sign-in was declined. Try again when you are ready.",
        ));
    }
    let codes = values("code");
    if codes.len() != 1 || codes[0].is_empty() {
        return Err(invalid());
    }
    Ok(codes[0].clone())
}

fn session(
    registration: Registration,
    tokens: Tokens,
    previous_refresh: Option<String>,
) -> Result<Session> {
    let refresh_token = tokens
        .refresh_token
        .or(previous_refresh)
        .filter(|value| !value.is_empty())
        .ok_or_else(invalid)?;
    if tokens.access_token.is_empty()
        || !tokens.token_type.eq_ignore_ascii_case("bearer")
        || tokens.expires_in == 0
        || tokens.expires_in > 365 * 24 * 60 * 60
    {
        return Err(invalid());
    }
    Ok(Session {
        registration,
        access_token: tokens.access_token,
        refresh_token,
        expires_at: now() + tokens.expires_in,
    })
}

pub fn complete(pending: PendingLogin, callback: &str) -> Result<Session> {
    complete_using(&Network, pending, callback)
}

fn complete_using(
    network: &impl Transport,
    pending: PendingLogin,
    callback: &str,
) -> Result<Session> {
    validate_registration(&pending.registration)?;
    let code = callback_code(&pending, callback)?;
    let tokens = network.request(
        &Url::parse(&pending.registration.token_endpoint).map_err(|_| invalid())?,
        Body::Form(vec![
            ("grant_type", "authorization_code"),
            ("client_id", &pending.registration.client_id),
            ("redirect_uri", REDIRECT_URI),
            ("code", &code),
            ("code_verifier", &pending.verifier),
        ]),
    )?;
    session(pending.registration, tokens, None)
}

pub fn restore(saved: Session) -> Result<Session> {
    restore_using(&Network, saved)
}

fn restore_using(network: &impl Transport, saved: Session) -> Result<Session> {
    validate_registration(&saved.registration)?;
    if saved.access_token.is_empty() || saved.refresh_token.is_empty() {
        return Err(invalid());
    }
    if saved.expires_at > now() + 60 {
        return Ok(saved);
    }
    let tokens = network.request(
        &Url::parse(&saved.registration.token_endpoint).map_err(|_| invalid())?,
        Body::Form(vec![
            ("grant_type", "refresh_token"),
            ("client_id", &saved.registration.client_id),
            ("refresh_token", &saved.refresh_token),
        ]),
    )?;
    session(saved.registration, tokens, Some(saved.refresh_token))
}

#[cfg(test)]
mod tests;
