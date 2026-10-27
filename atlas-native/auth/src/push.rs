use crate::transport::{Body, Network, Transport};
use crate::{Result, Session, error, invalid, now, validate_registration};
use reqwest::Method;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum Action {
    Register {
        installation_id: String,
        platform: Platform,
        token: String,
        environment: Environment,
    },
    Unregister {
        installation_id: String,
    },
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum Platform {
    Ios,
    Android,
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum Environment {
    Sandbox,
    Production,
}

#[derive(Deserialize, Serialize)]
struct Registered {
    registered: bool,
    registration_id: String,
}

#[derive(Deserialize, Serialize)]
struct Deleted {
    deleted: bool,
}

pub(crate) fn execute(session: Session, action: Action) -> Result<Value> {
    execute_using(&Network, session, action)
}

pub(super) fn execute_using(
    network: &impl Transport,
    session: Session,
    action: Action,
) -> Result<Value> {
    let server = validate_registration(&session.registration)?;
    if session.expires_at <= now() || session.access_token.is_empty() {
        return Err(error("sign_in_required", "Sign in to Atlas again."));
    }
    let id = match &action {
        Action::Register {
            installation_id, ..
        }
        | Action::Unregister { installation_id } => installation_id,
    };
    validate_id(id)?;
    let url = server
        .join(&format!("api/me/push-devices/{id}"))
        .map_err(|_| invalid())?;
    let (method, payload) = match &action {
        Action::Register {
            platform,
            token,
            environment,
            ..
        } => {
            let valid_token = match platform {
                Platform::Ios => {
                    (32..=512).contains(&token.len())
                        && token.len().is_multiple_of(2)
                        && token.bytes().all(|byte| byte.is_ascii_hexdigit())
                }
                Platform::Android => {
                    (16..=4096).contains(&token.len())
                        && token.bytes().all(|byte| byte.is_ascii_graphic())
                }
            };
            if !valid_token
                || matches!(
                    (platform, environment),
                    (Platform::Android, Environment::Sandbox)
                )
            {
                return Err(invalid());
            }
            (
                Method::PUT,
                Some(json!({"platform": platform, "token": token, "environment": environment})),
            )
        }
        Action::Unregister { .. } => (Method::DELETE, None),
    };
    let body = Body::Api {
        method,
        token: &session.access_token,
        payload,
        failure: response_failure,
    };
    match action {
        Action::Register { .. } => {
            let response = network.request::<Registered>(&url, body)?;
            validate_id(&response.registration_id)?;
            if !response.registered {
                return Err(invalid());
            }
            serde_json::to_value(response)
        }
        Action::Unregister { .. } => {
            let response = network.request::<Deleted>(&url, body)?;
            if !response.deleted {
                return Err(invalid());
            }
            serde_json::to_value(response)
        }
    }
    .map_err(|_| invalid())
}

fn validate_id(value: &str) -> Result<()> {
    crate::time_off::validate_id(value)?;
    if value.bytes().any(|byte| byte.is_ascii_uppercase()) {
        return Err(invalid());
    }
    Ok(())
}

fn response_failure(status: u16, _bytes: &[u8]) -> crate::AuthError {
    let (kind, message) = match status {
        401 => ("sign_in_required", "Sign in to Atlas again."),
        403 => (
            "unsupported_client",
            "Sign in using the Atlas mobile app to configure notifications.",
        ),
        404 | 501 | 503 => (
            "unavailable",
            "This Atlas server does not support push notifications.",
        ),
        409 => (
            "conflict",
            "This notification registration is no longer available. Disable notifications and try again.",
        ),
        400 | 422 => (
            "invalid_request",
            "Could not register this device for notifications.",
        ),
        429 => ("rate_limited", "Too many requests. Try again later."),
        _ => ("server", "Could not update notifications. Try again later."),
    };
    error(kind, message)
}

#[cfg(test)]
#[path = "push_tests.rs"]
mod tests;
