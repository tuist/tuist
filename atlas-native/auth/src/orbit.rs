use crate::transport::{Body, Network, Transport};
use crate::{Result, Session, error, invalid, now, validate_registration};
use reqwest::Method;
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use serde_json::json;

#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum Action {
    List {
        page: u32,
    },
    Private,
    Create {
        title: String,
        participant_ids: Vec<String>,
    },
    Messages {
        id: String,
        page: u32,
    },
    Send {
        id: String,
        body: String,
        client_id: String,
        address_agent: bool,
    },
}

#[derive(Clone, Deserialize, Serialize)]
pub(super) struct Assistant {
    pub name: String,
    pub configured: bool,
}

#[derive(Clone, Deserialize, Serialize)]
pub(super) struct Person {
    pub id: String,
    pub name: String,
}

#[derive(Clone, Deserialize, Serialize)]
pub(super) struct Thread {
    pub id: String,
    pub title: String,
    pub kind: String,
    pub status: String,
    #[serde(default)]
    pub summary: String,
    #[serde(default)]
    pub origin: String,
    pub owner_id: Option<String>,
    #[serde(default)]
    pub participants: Vec<Person>,
    pub updated_at: String,
    #[serde(default)]
    pub agent_status: Option<AgentStatus>,
}

#[derive(Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(super) enum AgentStatus {
    Idle,
    Queued,
    Running,
    Compacting,
    Unconfigured,
    #[serde(other)]
    Unknown,
}

#[derive(Deserialize, Serialize)]
pub(super) struct Page<T> {
    pub items: Vec<T>,
    pub page: u32,
    pub total_pages: u32,
    pub total_count: u32,
}

#[derive(Deserialize, Serialize)]
pub(super) struct Overview {
    pub assistant: Assistant,
    pub threads: Page<Thread>,
}

#[derive(Clone, Deserialize, Serialize)]
pub(super) struct Message {
    pub id: String,
    #[serde(default)]
    pub seq: u64,
    pub kind: String,
    pub body: String,
    pub author_id: Option<String>,
    pub author_name: String,
    pub inserted_at: String,
    pub tool_name: Option<String>,
    pub tool_status: Option<String>,
    #[serde(default)]
    pub tool_input: String,
    #[serde(default)]
    pub tool_output: String,
    #[serde(default, deserialize_with = "crate::orbit_components::deserialize")]
    pub component: Option<crate::orbit_components::Component>,
}

#[derive(Deserialize, Serialize)]
pub(super) struct History {
    pub thread: Thread,
    pub messages: Page<Message>,
}

#[derive(Deserialize, Serialize)]
pub(super) struct Created {
    pub thread: Thread,
}

#[derive(Deserialize, Serialize)]
pub(super) struct Sent {
    message: Message,
}

pub(super) fn request<T: DeserializeOwned>(session: Session, action: Action) -> Result<T> {
    request_using(&Network, session, action)
}

pub(super) fn request_using<T: DeserializeOwned>(
    network: &impl Transport,
    session: Session,
    action: Action,
) -> Result<T> {
    let server = validate_registration(&session.registration)?;
    if session.expires_at <= now() || session.access_token.is_empty() {
        return Err(error("sign_in_required", "Sign in to Atlas again."));
    }
    let mut url = server
        .join("api/native/orbit/threads")
        .map_err(|_| invalid())?;
    let (method, payload) = match &action {
        Action::List { page } => {
            validate_page(*page)?;
            url.query_pairs_mut().append_pair("page", &page.to_string());
            (Method::GET, None)
        }
        Action::Private => {
            url.path_segments_mut()
                .map_err(|_| invalid())?
                .push("private");
            (Method::POST, Some(json!({})))
        }
        Action::Create {
            title,
            participant_ids,
        } => {
            validate_text(title, 200)?;
            if participant_ids.len() > 30 {
                return Err(invalid());
            }
            for id in participant_ids {
                crate::time_off::validate_id(id)?;
            }
            (
                Method::POST,
                Some(json!({"title":title,"participant_ids":participant_ids})),
            )
        }
        Action::Messages { id, page } => {
            crate::time_off::validate_id(id)?;
            validate_page(*page)?;
            url.path_segments_mut()
                .map_err(|_| invalid())?
                .extend([id.as_str(), "messages"]);
            url.query_pairs_mut().append_pair("page", &page.to_string());
            (Method::GET, None)
        }
        Action::Send {
            id,
            body,
            client_id,
            address_agent,
        } => {
            crate::time_off::validate_id(id)?;
            crate::time_off::validate_id(client_id)?;
            validate_text(body, 16000)?;
            url.path_segments_mut()
                .map_err(|_| invalid())?
                .extend([id.as_str(), "messages"]);
            (
                Method::POST,
                Some(json!({"body":body,"client_id":client_id,"address_agent":address_agent})),
            )
        }
    };
    let body = Body::Api {
        method,
        token: &session.access_token,
        payload,
        failure: response_failure,
    };
    network.request(&url, body)
}

fn validate_page(page: u32) -> Result<()> {
    if page == 0 || page > 100_000 {
        Err(invalid())
    } else {
        Ok(())
    }
}

fn validate_text(value: &str, max: usize) -> Result<()> {
    if value.trim().is_empty() || value.len() > max {
        Err(invalid())
    } else {
        Ok(())
    }
}

fn response_failure(status: u16, _bytes: &[u8]) -> crate::AuthError {
    let (kind, message) = match status {
        401 => ("sign_in_required", "Sign in to Atlas again."),
        403 | 404 => (
            "unavailable",
            "This thread is unavailable or you no longer have access.",
        ),
        409 => ("conflict", "This thread changed. Refresh it and try again."),
        422 => ("invalid_request", "Check the thread details and try again."),
        429 => (
            "rate_limited",
            "Too many requests. Wait a moment and try again.",
        ),
        501 => (
            "unsupported",
            "Orbit is not available on this Atlas server yet.",
        ),
        _ => (
            "server",
            "Atlas could not load this thread. Try again later.",
        ),
    };
    error(kind, message)
}

#[cfg(test)]
#[path = "orbit_tests.rs"]
mod tests;
