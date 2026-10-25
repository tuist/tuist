use crate::transport::{Body, Transport};
use crate::{Result, Session, error, invalid, now, validate_registration};
use base64::{Engine, engine::general_purpose::STANDARD};
use reqwest::Method;
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use serde_json::json;

pub(super) const MAX_ATTACHMENT_BYTES: usize = 5 * 1024 * 1024;
pub(super) const ATTACHMENT_ENVELOPE_BYTES: usize = 7 * 1024 * 1024 + 64 * 1024;

#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum Action {
    List {
        page: u32,
        #[serde(default)]
        kind: Option<String>,
    },
    Private,
    CreatePrivate {
        request_id: String,
    },
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
        attachment_ids: Vec<String>,
    },
    UploadAttachment {
        id: String,
        client_id: String,
        filename: String,
        content_type: String,
        data: String,
    },
    DownloadAttachment {
        id: String,
        attachment_id: String,
    },
    DeleteAttachment {
        id: String,
        attachment_id: String,
    },
}

#[derive(Clone, Deserialize, Serialize, PartialEq, Eq)]
pub(super) struct Attachment {
    pub id: String,
    pub filename: String,
    pub content_type: String,
    pub byte_size: usize,
}

#[derive(Deserialize, Serialize)]
pub(super) struct Attached {
    pub attachment: Attachment,
}

#[derive(Deserialize, Serialize)]
pub(super) struct Downloaded {
    pub attachment: AttachmentData,
}

#[derive(Deserialize, Serialize)]
pub(super) struct AttachmentData {
    #[serde(flatten)]
    pub metadata: Attachment,
    pub data: String,
}

pub(super) fn validate_file(filename: &str, content_type: &str, size: usize) -> Result<()> {
    if filename.trim().is_empty()
        || filename.chars().count() > 255
        || filename.chars().any(|c| {
            c.is_control()
                || matches!(c, '/' | '\\')
                || ('\u{202a}'..='\u{202e}').contains(&c)
                || ('\u{2066}'..='\u{2069}').contains(&c)
        })
        || matches!(filename, "." | "..")
        || size == 0
        || size > MAX_ATTACHMENT_BYTES
        || content_type.len() > 127
        || content_type.split_once('/').is_none_or(|(base, subtype)| {
            base.is_empty() || subtype.is_empty() || subtype.contains('/')
        })
        || !content_type
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || b"!#$&^_-.+/".contains(&c))
    {
        return Err(invalid());
    }
    Ok(())
}

pub(super) fn validate_attachment(value: &Attachment) -> Result<()> {
    crate::time_off::validate_id(&value.id)?;
    if value.filename.chars().count() > 120 {
        return Err(invalid());
    }
    validate_file(&value.filename, &value.content_type, value.byte_size)
}

pub(super) fn decode_attachment(data: &str) -> Result<Vec<u8>> {
    if data.len() > MAX_ATTACHMENT_BYTES.div_ceil(3) * 4 {
        return Err(invalid());
    }
    let bytes = STANDARD.decode(data).map_err(|_| invalid())?;
    if bytes.is_empty() || bytes.len() > MAX_ATTACHMENT_BYTES {
        return Err(invalid());
    }
    Ok(bytes)
}

pub(super) fn validate_attachment_ids(ids: &[String]) -> Result<()> {
    if ids.len() > 4 {
        return Err(invalid());
    }
    for (index, id) in ids.iter().enumerate() {
        crate::time_off::validate_id(id)?;
        if ids[..index].contains(id) {
            return Err(invalid());
        }
    }
    Ok(())
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
    #[serde(default)]
    pub attachments: Vec<Attachment>,
    #[serde(default, deserialize_with = "deserialize_parent")]
    pub parent_message_id: Option<String>,
}

fn deserialize_parent<'de, D: serde::Deserializer<'de>>(
    deserializer: D,
) -> std::result::Result<Option<String>, D::Error> {
    let value = serde_json::Value::deserialize(deserializer)?;
    // Invalid linkage must not hide the original tool evidence.
    Ok(value
        .as_str()
        .filter(|id| crate::time_off::validate_id(id).is_ok())
        .map(str::to_owned))
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
        Action::List { page, kind } => {
            validate_page(*page)?;
            url.query_pairs_mut().append_pair("page", &page.to_string());
            if let Some(kind) = kind {
                if !matches!(kind.as_str(), "private" | "shared") {
                    return Err(invalid());
                }
                url.query_pairs_mut().append_pair("kind", kind);
            }
            (Method::GET, None)
        }
        Action::Private => {
            url.path_segments_mut()
                .map_err(|_| invalid())?
                .push("private");
            (Method::POST, Some(json!({})))
        }
        Action::CreatePrivate { request_id } => {
            crate::time_off::validate_id(request_id)?;
            (
                Method::POST,
                Some(json!({"kind":"private","request_id":request_id})),
            )
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
            attachment_ids,
        } => {
            crate::time_off::validate_id(id)?;
            crate::time_off::validate_id(client_id)?;
            validate_attachment_ids(attachment_ids)?;
            if body.len() > 16000 || (body.trim().is_empty() && attachment_ids.is_empty()) {
                return Err(invalid());
            }
            url.path_segments_mut()
                .map_err(|_| invalid())?
                .extend([id.as_str(), "messages"]);
            (
                Method::POST,
                Some(
                    json!({"body":body,"client_id":client_id,"address_agent":address_agent,"attachment_ids":attachment_ids}),
                ),
            )
        }
        Action::UploadAttachment {
            id,
            client_id,
            filename,
            content_type,
            data,
        } => {
            crate::time_off::validate_id(id)?;
            crate::time_off::validate_id(client_id)?;
            let bytes = decode_attachment(data)?;
            validate_file(filename, content_type, bytes.len())?;
            url.path_segments_mut()
                .map_err(|_| invalid())?
                .extend([id.as_str(), "attachments"]);
            (
                Method::POST,
                Some(
                    json!({"client_id":client_id,"filename":filename,"content_type":content_type,"data":data}),
                ),
            )
        }
        Action::DownloadAttachment { id, attachment_id }
        | Action::DeleteAttachment { id, attachment_id } => {
            crate::time_off::validate_id(id)?;
            crate::time_off::validate_id(attachment_id)?;
            url.path_segments_mut().map_err(|_| invalid())?.extend([
                id.as_str(),
                "attachments",
                attachment_id,
            ]);
            if matches!(action, Action::DownloadAttachment { .. }) {
                return network.request(
                    &url,
                    Body::Attachment {
                        token: &session.access_token,
                        failure: response_failure,
                    },
                );
            }
            (Method::DELETE, None)
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
