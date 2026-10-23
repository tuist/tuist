//! Authenticated, allowlisted native Automation requests. No credentials in URLs or errors.
use crate::{Result, Session, error, now, validate_registration};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use serde::Deserialize;
use serde_json::{Value, json};
use std::io::Read;
use std::net::{TcpStream, ToSocketAddrs};
use std::time::{Duration, Instant};
use tungstenite::{Message, client::IntoClientRequest};

#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum Request {
    Workflows {
        page: Option<u32>,
    },
    Workflow {
        id: String,
    },
    Executions {
        page: Option<u32>,
    },
    Execution {
        id: String,
    },
    Result {
        id: String,
    },
    Approvals {
        page: Option<u32>,
    },
    Approval {
        id: String,
    },
    Run {
        id: String,
        revision_id: String,
        request_id: String,
        input: Value,
    },
    Control {
        id: String,
        command: String,
    },
    Decide {
        id: String,
        decision: String,
        payload_digest: String,
    },
    Watch {
        id: String,
        after_sequence: u64,
    },
}

fn invalid() -> crate::AuthError {
    error("invalid_input", "The native request is invalid.")
}
fn network() -> crate::AuthError {
    error("network", "Could not connect securely to Atlas. Try again.")
}
fn response_error() -> crate::AuthError {
    error("invalid_response", "Atlas returned an invalid response.")
}
fn identifier(value: &str) -> Result<&str> {
    if value.len() == 36
        && value.bytes().enumerate().all(|(i, c)| {
            if [8, 13, 18, 23].contains(&i) {
                c == b'-'
            } else {
                c.is_ascii_hexdigit()
            }
        })
    {
        Ok(value)
    } else {
        Err(invalid())
    }
}

pub(crate) fn execute(session: Session, request: Request) -> Result<Value> {
    let mut url = validate_registration(&session.registration)?;
    if session.expires_at <= now() || session.access_token.is_empty() {
        return Err(error(
            "unauthorized",
            "Refresh your Atlas session and try again.",
        ));
    }
    if let Request::Watch { id, after_sequence } = request {
        return watch(&session, &id, after_sequence);
    }
    let (path, body) = match request {
        Request::Workflows { page } => (
            format!("workflows?page={}", page.unwrap_or(1).clamp(1, 100_000)),
            None,
        ),
        Request::Executions { page } => (
            format!("executions?page={}", page.unwrap_or(1).clamp(1, 100_000)),
            None,
        ),
        Request::Approvals { page } => (
            format!("approvals?page={}", page.unwrap_or(1).clamp(1, 100_000)),
            None,
        ),
        Request::Workflow { id } => (format!("workflows/{}", identifier(&id)?), None),
        Request::Execution { id } => (format!("executions/{}", identifier(&id)?), None),
        Request::Approval { id } => (format!("approvals/{}", identifier(&id)?), None),
        Request::Result { id } => (format!("executions/{}/result", identifier(&id)?), None),
        Request::Run {
            id,
            revision_id,
            request_id,
            input,
        } => {
            identifier(&revision_id)?;
            identifier(&request_id)?;
            if !input.is_object() || input.to_string().len() > 65_536 {
                return Err(invalid());
            }
            (
                format!("workflows/{}/run", identifier(&id)?),
                Some(json!({"revision_id":revision_id,"request_id":request_id,"input":input})),
            )
        }
        Request::Control { id, command } => {
            if !["retry", "cancel"].contains(&command.as_str()) {
                return Err(invalid());
            }
            (
                format!("executions/{}/control", identifier(&id)?),
                Some(json!({"command":command})),
            )
        }
        Request::Decide {
            id,
            decision,
            payload_digest,
        } => {
            if !["approved", "rejected"].contains(&decision.as_str()) || payload_digest.len() != 64
            {
                return Err(invalid());
            }
            (
                format!("approvals/{}/decision", identifier(&id)?),
                Some(json!({"decision":decision,"payload_digest":payload_digest})),
            )
        }
        Request::Watch { .. } => unreachable!(),
    };
    url.set_path("/api/native/automation/");
    let url = url.join(&path).map_err(|_| invalid())?;
    let client = crate::transport::client()?;
    let request = if let Some(body) = body {
        client.post(url).json(&body)
    } else {
        client.get(url)
    };
    let response = request
        .bearer_auth(&session.access_token)
        .send()
        .map_err(|_| network())?;
    let status = response.status().as_u16();
    let mut bytes = Vec::new();
    response
        .take(1_048_577)
        .read_to_end(&mut bytes)
        .map_err(|_| response_error())?;
    if bytes.len() > 1_048_576 {
        return Err(response_error());
    }
    if !(200..300).contains(&status) {
        return Err(match status {
            401 => error("unauthorized", "Your Atlas session needs to be refreshed."),
            403 => error(
                "forbidden",
                "You do not have permission for this operation.",
            ),
            404 => error("not_found", "This Atlas item is no longer available."),
            409 => {
                let code = serde_json::from_slice::<Value>(&bytes).ok();
                match code.as_ref().and_then(|v| v["error"].as_str()) {
                    Some("revision_changed") => error(
                        "revision_changed",
                        "This workflow changed. Reopen it to review the new version.",
                    ),
                    Some("idempotency_conflict") => error(
                        "idempotency_conflict",
                        "This launch request was already used with different inputs.",
                    ),
                    _ => error(
                        "conflict",
                        "This operation is no longer available. Refresh and review the current state.",
                    ),
                }
            }
            413 => error(
                "result_too_large",
                "Results are too large for native display. Open this execution in Atlas on the web.",
            ),
            422 => error(
                "invalid_input",
                "Check the workflow inputs against its contract.",
            ),
            _ => error(
                "server",
                "Atlas could not complete the request. Try again later.",
            ),
        });
    }
    let mut value: Value = serde_json::from_slice(&bytes).map_err(|_| response_error())?;
    if value.get("input_schema").is_some() {
        value["form"] = crate::form::project(&value["input_schema"]);
    }
    Ok(value)
}

// Bounded subscriptions keep FFI ownership simple: return at the next snapshot,
// or after the deadline. Foreground clients reconnect with their last sequence.
// Each wait owns a socket; no process-global network/session lock is held.
fn watch(session: &Session, id: &str, after_sequence: u64) -> Result<Value> {
    identifier(id)?;
    let mut url = validate_registration(&session.registration)?;
    url.set_scheme("wss").map_err(|_| invalid())?;
    url.set_path("/native/socket/websocket");
    url.query_pairs_mut()
        .append_pair("vsn", "2.0.0")
        .append_pair("run_id", id);
    let host = url.host_str().ok_or_else(invalid)?;
    let port = url.port_or_known_default().ok_or_else(invalid)?;
    let deadline = Instant::now() + Duration::from_secs(10);
    let mut stream = None;
    for address in (host, port)
        .to_socket_addrs()
        .map_err(|_| network())?
        .take(8)
    {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            break;
        }
        if let Ok(socket) =
            TcpStream::connect_timeout(&address, remaining.min(Duration::from_secs(3)))
        {
            stream = Some(socket);
            break;
        }
    }
    let stream = stream.ok_or_else(network)?;
    stream
        .set_read_timeout(Some(Duration::from_secs(20)))
        .map_err(|_| network())?;
    stream
        .set_write_timeout(Some(Duration::from_secs(5)))
        .map_err(|_| network())?;
    let mut request = url.as_str().into_client_request().map_err(|_| invalid())?;
    let protocol = format!(
        "phoenix, base64url.bearer.phx.{}",
        URL_SAFE_NO_PAD.encode(&session.access_token)
    );
    request.headers_mut().insert(
        "sec-websocket-protocol",
        protocol.parse().map_err(|_| invalid())?,
    );
    let config = tungstenite::protocol::WebSocketConfig::default()
        .max_message_size(Some(1_048_576))
        .max_frame_size(Some(1_048_576));
    let (mut socket, _) = tungstenite::client_tls_with_config(request, stream, Some(config), None)
        .map_err(|failure| match failure {
            tungstenite::HandshakeError::Failure(tungstenite::Error::Http(response))
                if matches!(response.status().as_u16(), 401 | 403) =>
            {
                error(
                    "unauthorized",
                    "Access to this execution is no longer available.",
                )
            }
            _ => network(),
        })?;
    let topic = format!("execution:{id}");
    socket
        .send(Message::Text(
            json!(["1", "1", topic, "phx_join", {}]).to_string().into(),
        ))
        .map_err(|_| network())?;
    let started = Instant::now();
    let mut latest = None;
    let result = loop {
        match socket.read() {
            Ok(Message::Text(text)) => {
                let frame: Value = serde_json::from_str(&text).map_err(|_| response_error())?;
                if frame[2] != topic {
                    continue;
                }
                let snapshot = match frame[3].as_str() {
                    Some("phx_reply") if frame[4]["status"] == "ok" => {
                        Some(frame[4]["response"].clone())
                    }
                    Some("snapshot") => Some(frame[4].clone()),
                    Some("access_revoked" | "phx_error" | "phx_close") => {
                        break Err(error(
                            "unauthorized",
                            "Access to this execution is no longer available.",
                        ));
                    }
                    Some("phx_reply") => {
                        break Err(error("forbidden", "You cannot follow this execution."));
                    }
                    _ => None,
                };
                if let Some(snapshot) = snapshot {
                    if snapshot["sequence"].as_u64().is_none() {
                        break Err(response_error());
                    }
                    let changed = snapshot["sequence"].as_u64().unwrap() > after_sequence
                        || frame[3] == "snapshot";
                    latest = Some(snapshot);
                    if changed {
                        break Ok(latest.take().unwrap());
                    }
                }
            }
            Ok(Message::Ping(value)) => {
                socket.send(Message::Pong(value)).map_err(|_| network())?;
            }
            Ok(Message::Close(_)) => break Err(network()),
            Ok(_) => {}
            Err(tungstenite::Error::Io(e))
                if [std::io::ErrorKind::WouldBlock, std::io::ErrorKind::TimedOut]
                    .contains(&e.kind()) =>
            {
                break latest.ok_or_else(network);
            }
            Err(_) => break Err(network()),
        }
        if started.elapsed() >= Duration::from_secs(20) {
            break latest.ok_or_else(network);
        }
    };
    let _ = socket.close(None);
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_path_and_query_injection() {
        for value in [
            "../workflows",
            "x?token=secret",
            "00000000-0000-0000-0000-00000000000/",
        ] {
            assert!(identifier(value).is_err());
        }
        assert!(identifier("00000000-0000-0000-0000-000000000000").is_ok());
    }
    #[test]
    fn rejects_unknown_actions_and_fields() {
        for value in [
            json!({"action":"fetch","url":"https://example.com"}),
            json!({"action":"workflows","token":"secret"}),
        ] {
            assert!(serde_json::from_value::<Request>(value).is_err());
        }
    }
}
