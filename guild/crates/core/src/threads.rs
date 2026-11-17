//! Threads: conversations that run on the server. Each frontend lists them,
//! starts them and replies through these operations; the person never picks a
//! repository, machine or model.
use serde_json::{Value, json};
use tuist_oauth::{Pkce, endpoint};
use url::Url;

use crate::client::{NOT_FOUND, Result, segment, successful, text};

// The server answers 404 when threads are off for the user (the `code` flag)
// or it predates them.
pub const THREADS_UNAVAILABLE: &str = "Threads aren't enabled for this account or server";

/// Sends authorized requests for the signed-in person. The mobile client
/// implements it with its vault and native host; GPUI with its desktop session.
pub trait Transport {
    /// Sends `body` as JSON with the session's bearer token, and returns the
    /// response status and its parsed JSON body (null when empty or invalid).
    fn send(&mut self, method: &str, url: Url, body: Option<Value>) -> Result<(u64, Value)>;
}

/// One person's thread operations. Keep one per process or session: it holds
/// the idempotency key of a request that has not succeeded yet, so that
/// retrying the same text never posts it twice.
#[derive(Default)]
pub struct Threads {
    pending: Option<(String, String)>,
}

impl Threads {
    pub fn new() -> Self {
        Self::default()
    }

    /// Runs `threads`, `start_thread`, `thread` or `send_message` (see the
    /// crate README) in the account `handle` on `server`: the person's own
    /// account or a selected organization. The server lists only the threads
    /// the user owns there, and requires admin rights and the organization's
    /// `guild` flag on an organization.
    pub fn call(
        &mut self,
        server: &Url,
        handle: &str,
        operation: &str,
        args: &Value,
        transport: &mut dyn Transport,
    ) -> Result<Value> {
        if !segment(handle) {
            return Err("Invalid account");
        }
        let url = |path: &str| {
            endpoint(
                server,
                format!("api/accounts/{handle}/threads/{path}").trim_end_matches('/'),
            )
        };
        let request = |transport: &mut dyn Transport, method, url, body| {
            successful(transport.send(method, url, body)?)
        };
        match operation {
            "threads" => {
                let mut url = url("");
                let cursor = args.get("cursor").and_then(Value::as_str);
                if let Some(cursor) = cursor {
                    if cursor.is_empty() {
                        return Err("Invalid cursor");
                    }
                    url.query_pairs_mut().append_pair("cursor", cursor);
                }
                let unavailable = |reason| json!({"available":false,"reason":reason,"threads":[],"next_cursor":null});
                let mut data = match request(transport, "GET", url, None) {
                    Err(NOT_FOUND) => return Ok(unavailable("disabled")),
                    // The server answers missing rights and flags with 404, so a
                    // refusal means this session predates Guild's first-party
                    // client. Signing in again uses it.
                    Err("Access denied") => return Ok(unavailable("sign_in_required")),
                    result => result?,
                };
                data["available"] = json!(true);
                // A server repeating the cursor it was given would page forever.
                if cursor.is_some() && data["next_cursor"].as_str() == cursor {
                    data["next_cursor"] = Value::Null;
                }
                for thread in data["threads"].as_array_mut().ok_or("Invalid threads")? {
                    present(thread);
                }
                Ok(data)
            }
            "start_thread" => {
                let content = message_content(args)?;
                let catalog = match request(transport, "GET", url("models"), None) {
                    Err(NOT_FOUND) => return Err(THREADS_UNAVAILABLE),
                    result => result?,
                };
                let model = catalog["models"]
                    .as_array()
                    .and_then(|models| {
                        models.iter().find(|m| {
                            m["provider"].as_str().is_some_and(|v| !v.is_empty())
                                && m["id"].as_str().is_some_and(|v| !v.is_empty())
                        })
                    })
                    .ok_or("Connect a ChatGPT subscription in your Tuist account settings to start conversations")?;
                let body = json!({
                    "request_id": self.request_id(args, server, handle, "", content)?,
                    "content": content,
                    "provider": model["provider"],
                    "model": model["id"],
                });
                let mut thread = match request(transport, "POST", url(""), Some(body)) {
                    Err(NOT_FOUND) => return Err(THREADS_UNAVAILABLE),
                    result => result?,
                };
                self.pending = None;
                present(&mut thread);
                Ok(thread)
            }
            "thread" => {
                let mut url = url(thread_id(args)?);
                if let Some(before) = args.get("before").and_then(Value::as_u64) {
                    url.query_pairs_mut()
                        .append_pair("before", &before.to_string());
                }
                let mut thread = request(transport, "GET", url, None)?;
                present(&mut thread);
                Ok(thread)
            }
            "send_message" => {
                let id = thread_id(args)?;
                let content = message_content(args)?;
                let body = json!({
                    "request_id": self.request_id(args, server, handle, id, content)?,
                    "content": content,
                });
                let mut thread = request(
                    transport,
                    "POST",
                    url(&format!("{id}/messages")),
                    Some(body),
                )?;
                self.pending = None;
                present(&mut thread);
                Ok(thread)
            }
            _ => Err("Unknown operation"),
        }
    }

    /// The idempotency key `start_thread` or `send_message` will send with
    /// `args`, chosen before the request so a caller that queues the write
    /// after a lost response replays it under the same key.
    pub(crate) fn request_key(
        &mut self,
        server: &Url,
        handle: &str,
        operation: &str,
        args: &Value,
    ) -> Result<String> {
        let thread = match operation {
            "send_message" => thread_id(args)?,
            _ => "",
        };
        self.request_id(args, server, handle, thread, message_content(args)?)
    }

    /// Forgets the in-memory key once its write is sent or queued, so the
    /// same text written again is a new message.
    pub(crate) fn settle(&mut self) {
        self.pending = None;
    }

    /// The caller's `request_id` when it gives one (the local store's outbox
    /// does, so a retry after a restart replays the same write), otherwise a
    /// key kept in memory until the request succeeds.
    fn request_id(
        &mut self,
        args: &Value,
        server: &Url,
        handle: &str,
        thread: &str,
        content: &str,
    ) -> Result<String> {
        if let Some(id) = args.get("request_id") {
            let id = id.as_str().ok_or("Invalid request")?;
            if id.len() != 36 || !id.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
                return Err("Invalid request");
            }
            return Ok(id.to_string());
        }
        Ok(self.memory_request_id(server, handle, thread, content))
    }

    fn memory_request_id(
        &mut self,
        server: &Url,
        handle: &str,
        thread: &str,
        content: &str,
    ) -> String {
        let key = format!("{server}\n{handle}\n{thread}\n{content}");
        match &self.pending {
            Some((pending, id)) if *pending == key => id.clone(),
            _ => {
                let id = new_request_id();
                self.pending = Some((key, id.clone()));
                id
            }
        }
    }
}

/// Adds what a thread means to the person: `state` from the server's agent
/// status, its inbox `section`, and whether it is still `working`, which
/// frontends use to keep an open conversation current.
fn present(thread: &mut Value) {
    // A run that ended (`idle`) is ready to review, and one that stopped
    // early (`interrupted`) needs attention like a failure.
    let state = match thread["status"].as_str() {
        Some("queued") => Some("queued"),
        Some("running" | "compacting" | "shipping") => Some("running"),
        Some("idle") => Some("completed"),
        Some("failed" | "interrupted") => Some("failed"),
        Some("outcome_unknown") => Some("outcome_unknown"),
        _ => None,
    };
    let archived = thread["archive_status"] == "archived";
    let working = matches!(state, Some("queued" | "running"));
    let section = if archived {
        "archived"
    } else if working {
        "in_progress"
    } else {
        "recent"
    };
    thread["state"] = json!(state);
    thread["section"] = json!(section);
    thread["working"] = json!(working && !archived);
}

fn thread_id(args: &Value) -> Result<&str> {
    let id = text(args, "id")?;
    if id.len() == 36 && id.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
        Ok(id)
    } else {
        Err("Invalid thread")
    }
}

fn message_content(args: &Value) -> Result<&str> {
    let content = text(args, "content")?;
    if content.len() > 16_000 {
        return Err("Message is too long");
    }
    Ok(content)
}

/// A random version 4 UUID, which the server requires for idempotency keys.
pub(crate) fn new_request_id() -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    const HEX: &[u8] = b"0123456789abcdef";
    // Each base64url character of the verifier carries six random bits; keep four.
    let mut digits: Vec<u8> = Pkce::generate()
        .verifier
        .bytes()
        .take(32)
        .map(|b| ALPHABET.iter().position(|a| *a == b).unwrap_or(0) as u8 & 15)
        .collect();
    digits[12] = 4;
    digits[16] = 8 | (digits[16] & 3);
    let hex: String = digits.iter().map(|d| HEX[*d as usize] as char).collect();
    format!(
        "{}-{}-{}-{}-{}",
        &hex[0..8],
        &hex[8..12],
        &hex[12..16],
        &hex[16..20],
        &hex[20..32]
    )
}
