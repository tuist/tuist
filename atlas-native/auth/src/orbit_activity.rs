use crate::transport::{Body, Network, Transport};
use crate::{Result, Session, error, invalid, now, validate_registration};
use reqwest::Method;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

const MAX_TIMESTAMP: u64 = 253_402_300_799;
const MAX_COUNT: u32 = i32::MAX as u32;

#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum Action {
    Status {},
    Register {
        registration_id: String,
        token: String,
        environment: Environment,
    },
    Unregister {
        registration_id: String,
    },
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum Environment {
    Sandbox,
    Production,
}

#[derive(Deserialize, Serialize)]
struct Status {
    available: bool,
    content: Content,
}

#[derive(Deserialize, Serialize)]
struct Content {
    active_count: u32,
    conversations: Vec<Conversation>,
    updated_at: u64,
}

#[derive(Deserialize, Serialize)]
struct Conversation {
    id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    title: Option<String>,
    status: ConversationStatus,
    started_at: u64,
    completed_steps: u32,
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
enum ConversationStatus {
    Queued,
    Running,
    Compacting,
    UsingTools,
}

#[derive(Deserialize, Serialize)]
struct Registered {
    registered: bool,
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
    let path = match &action {
        Action::Status {} => "api/me/orbit-live-activity".into(),
        Action::Register {
            registration_id, ..
        }
        | Action::Unregister { registration_id } => {
            validate_id(registration_id)?;
            format!("api/me/orbit-live-activity/{registration_id}")
        }
    };
    let url = server.join(&path).map_err(|_| invalid())?;
    let (method, payload) = match &action {
        Action::Status {} => (Method::GET, None),
        Action::Register {
            token, environment, ..
        } => {
            if !(32..=512).contains(&token.len())
                || !token.len().is_multiple_of(2)
                || !token.bytes().all(|byte| byte.is_ascii_hexdigit())
            {
                return Err(invalid());
            }
            (
                Method::PUT,
                Some(json!({"token": token, "environment": environment})),
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
        Action::Status {} => {
            let response = network.request::<Status>(&url, body)?;
            let content = &response.content;
            if content.conversations.len() > 3
                || content.active_count > MAX_COUNT
                || (content.active_count as usize) < content.conversations.len()
                || content.updated_at > MAX_TIMESTAMP
            {
                return Err(invalid());
            }
            for (index, conversation) in content.conversations.iter().enumerate() {
                validate_id(&conversation.id)?;
                if conversation.started_at > content.updated_at
                    || conversation.completed_steps > MAX_COUNT
                    || conversation
                        .title
                        .as_ref()
                        .is_some_and(|title| title.chars().count() > 80)
                    || content.conversations[..index]
                        .iter()
                        .any(|previous| previous.id == conversation.id)
                {
                    return Err(invalid());
                }
            }
            serde_json::to_value(response)
        }
        Action::Register { .. } => {
            let response = network.request::<Registered>(&url, body)?;
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
            "Sign in using the Atlas iOS app to use Orbit Live Activity.",
        ),
        404 | 501 | 503 => (
            "unavailable",
            "This Atlas server does not support Orbit Live Activity.",
        ),
        409 => (
            "conflict",
            "This Live Activity registration is no longer available. Start a new Live Activity.",
        ),
        400 | 422 => ("invalid_request", "Could not update Orbit Live Activity."),
        429 => ("rate_limited", "Too many requests. Try again later."),
        _ => (
            "server",
            "Could not update Orbit Live Activity. Try again later.",
        ),
    };
    error(kind, message)
}

#[cfg(test)]
#[path = "orbit_activity_tests.rs"]
mod tests;
