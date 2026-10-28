use crate::transport::{Body, Network, Transport};
use crate::{Result, Session, error, invalid, now, validate_registration};
use reqwest::Method;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum Action {
    Suggest {
        url: String,
        content: String,
    },
    Capture {
        request_id: String,
        attributes: Attributes,
    },
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Attributes {
    title: String,
    url: String,
    content: String,
    description: String,
    tags: Vec<String>,
}

#[derive(Deserialize, Serialize)]
struct Suggestions {
    title: String,
    description: String,
    tags: Vec<String>,
    generated: bool,
}

#[derive(Deserialize, Serialize)]
struct Suggested {
    suggestions: Suggestions,
}

#[derive(Deserialize, Serialize)]
struct Captured {
    saved: bool,
    resource_id: String,
}

pub(crate) fn execute(session: Session, action: Action) -> Result<Value> {
    execute_using(&Network, session, action)
}

fn bounded(value: &str, limit: usize) -> bool {
    !value.contains('\0') && value.chars().count() <= limit
}

fn validate_source(url: &str, content: &str) -> Result<()> {
    if !bounded(url, 2048)
        || !bounded(content, 20_000)
        || (url.is_empty() && content.trim().is_empty())
    {
        return Err(error(
            "invalid_capture",
            "Share one HTTPS link or text within the Moodboard limits.",
        ));
    }
    if !url.is_empty() {
        let parsed = url::Url::parse(url).map_err(|_| invalid())?;
        if parsed.scheme() != "https"
            || parsed.host_str().is_none()
            || !parsed.username().is_empty()
            || parsed.password().is_some()
            || parsed.port_or_known_default() != Some(443)
        {
            return Err(error(
                "invalid_capture",
                "Share a public HTTPS link without credentials.",
            ));
        }
    }
    Ok(())
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
    let (method, path, payload) = match &action {
        Action::Suggest { url, content } => {
            validate_source(url, content)?;
            (
                Method::POST,
                "api/native/moodboard/suggestions".to_string(),
                json!({"url": url, "content": content}),
            )
        }
        Action::Capture {
            request_id,
            attributes,
        } => {
            crate::time_off::validate_id(request_id)?;
            validate_source(&attributes.url, &attributes.content)?;
            if attributes.title.trim().is_empty()
                || !bounded(&attributes.title, 200)
                || !bounded(&attributes.description, 2000)
                || attributes.tags.len() > 10
                || attributes.tags.iter().any(|tag| !bounded(tag, 40))
            {
                return Err(error(
                    "invalid_capture",
                    "Check the title, description and tags before saving.",
                ));
            }
            (
                Method::PUT,
                format!("api/native/moodboard/captures/{request_id}"),
                serde_json::to_value(attributes).map_err(|_| invalid())?,
            )
        }
    };
    let url = server.join(&path).map_err(|_| invalid())?;
    let body = Body::Api {
        method,
        token: &session.access_token,
        payload: Some(payload),
        failure: response_failure,
    };
    match action {
        Action::Suggest { .. } => {
            let result: Suggested = network.request(&url, body)?;
            let fields = &result.suggestions;
            if fields.title.trim().is_empty()
                || !bounded(&fields.title, 200)
                || !bounded(&fields.description, 2000)
                || fields.tags.len() > 10
                || fields.tags.iter().any(|tag| !bounded(tag, 40))
            {
                return Err(invalid());
            }
            serde_json::to_value(result)
        }
        Action::Capture { .. } => {
            let result: Captured = network.request(&url, body)?;
            if !result.saved {
                return Err(invalid());
            }
            crate::time_off::validate_id(&result.resource_id)?;
            serde_json::to_value(result)
        }
    }
    .map_err(|_| invalid())
}

fn response_failure(status: u16, _body: &[u8]) -> crate::AuthError {
    match status {
        401 => error(
            "sign_in_required",
            "Sign in to Atlas again. Your share is still saved on this device.",
        ),
        404 | 501 => error(
            "unsupported",
            "Update the Atlas server to enable Moodboard sharing.",
        ),
        409 => error(
            "capture_conflict",
            "This share was already submitted with different fields. Open Moodboard to check it.",
        ),
        422 => error(
            "invalid_capture",
            "Check the fields. This link may already be in Moodboard.",
        ),
        429 => error(
            "rate_limited",
            "Too many suggestion requests. Wait a minute or save without suggestions.",
        ),
        _ => error(
            "unavailable",
            "Could not save to Moodboard. Your share is still saved on this device.",
        ),
    }
}

#[cfg(test)]
#[path = "moodboard_tests.rs"]
mod tests;
