//! MCP servers that threads call tools on, which the Luft server keeps: the
//! person's own at `/api/me/mcp-servers`, offered in every thread they write
//! in, or an organization's at `/api/accounts/{account_handle}/mcp-servers`,
//! offered in its threads, which every member sees and only admins change.
//!
//! Signing in to a server is OAuth in the browser: `authorize_mcp_server`
//! returns the URL to open, the server's callback hands the answer to
//! `luft://mcp-callback`, and the edge passes that URL to
//! `complete_mcp_server`. The core remembers which list the sign-in belongs
//! to, so the edge needs no state between the two.
use serde_json::{Value, json};
use tuist_oauth::endpoint;
use url::Url;

use crate::client::{Result, is_uuid, segment, successful, text};
use crate::threads::Transport;

pub(crate) const UNAVAILABLE: &str = "MCP servers are not available for this account.";
pub(crate) const ADMINS_ONLY: &str = "Only organization admins can change these servers.";
pub(crate) const CANCELLED: &str = "The sign-in was cancelled.";
const NO_SIGN_IN: &str = "No sign-in to an MCP server is pending.";

/// Runs `mcp_servers`, `add_mcp_server`, `remove_mcp_server`,
/// `authorize_mcp_server` or `complete_mcp_server` (see the crate README) on
/// `server`. `pending` holds the list a started sign-in belongs to (`None`
/// inside for the person's own) until `complete_mcp_server` consumes it.
pub fn call(
    server: &Url,
    operation: &str,
    args: &Value,
    pending: &mut Option<Option<String>>,
    transport: &mut dyn Transport,
) -> Result<Value> {
    let base = |handle: &Option<String>, path: &str| match handle {
        Some(handle) => endpoint(server, &format!("api/accounts/{handle}/mcp-servers{path}")),
        None => endpoint(server, &format!("api/me/mcp-servers{path}")),
    };
    let handle = match args.get("account_handle").and_then(Value::as_str) {
        None | Some("") => None,
        Some(handle) if segment(handle) => Some(handle.to_string()),
        Some(_) => return Err("Invalid account"),
    };
    let id = || {
        text(args, "id").and_then(|id| {
            if is_uuid(id) {
                Ok(id)
            } else {
                Err("Invalid server")
            }
        })
    };
    let answer = match operation {
        "mcp_servers" => transport.send("GET", base(&handle, ""), None)?,
        "add_mcp_server" => {
            let body = json!({
                "url": text(args, "url")?.trim(),
                "name": args.get("name").and_then(Value::as_str).unwrap_or("").trim(),
            });
            transport.send("POST", base(&handle, ""), Some(body))?
        }
        "remove_mcp_server" => {
            transport.send("DELETE", base(&handle, &format!("/{}", id()?)), None)?
        }
        "authorize_mcp_server" => {
            let path = format!("/{}/authorize", id()?);
            let answer = transport.send("POST", base(&handle, &path), None)?;
            if (200..300).contains(&answer.0) {
                let url = answer.1["url"]
                    .as_str()
                    .and_then(|url| Url::parse(url).ok())
                    .filter(|url| url.scheme() == "https")
                    .ok_or("Server request failed")?;
                *pending = Some(handle);
                return Ok(json!({"url": url.as_str(), "callback_scheme": "luft"}));
            }
            answer
        }
        "complete_mcp_server" => {
            // Consume before parsing or networking, so a callback is used once.
            let handle = pending.take().ok_or(NO_SIGN_IN)?;
            let body = callback(text(args, "url")?)?;
            transport.send("POST", base(&handle, "/complete"), Some(body))?
        }
        _ => return Err("Unknown operation"),
    };
    match answer {
        (403, _) => Err(ADMINS_ONLY),
        (404, _) if operation == "remove_mcp_server" => Ok(Value::Null),
        (404, _) if operation == "complete_mcp_server" => Err("That sign-in expired. Try again."),
        (404, _) => Err(UNAVAILABLE),
        (status, data) if (400..500).contains(&status) => Err(refusal(&data)),
        (204, _) => Ok(Value::Null),
        answer => successful(answer),
    }
}

/// The state, code and issuer `luft://mcp-callback` carries, each at most once.
fn callback(url: &str) -> Result<Value> {
    let url = Url::parse(url).map_err(|_| "Invalid callback")?;
    if url.scheme() != "luft"
        || url.host_str() != Some("mcp-callback")
        || !url.path().is_empty()
        || url.fragment().is_some()
    {
        return Err("Invalid callback");
    }
    let pairs: Vec<_> = url.query_pairs().collect();
    let one = |name: &str| -> Result<Option<String>> {
        match pairs.iter().filter(|(k, _)| k == name).collect::<Vec<_>>()[..] {
            [] => Ok(None),
            [(_, value)] if !value.is_empty() => Ok(Some(value.to_string())),
            _ => Err("Invalid callback"),
        }
    };
    let state = one("state")?.ok_or("Invalid callback")?;
    if pairs.iter().any(|(k, _)| k == "error") {
        return Err(CANCELLED);
    }
    let code = one("code")?.ok_or("Invalid callback")?;
    let mut body = json!({"state": state, "code": code});
    if let Some(iss) = one("iss")? {
        body["iss"] = json!(iss);
    }
    Ok(body)
}

fn refusal(data: &Value) -> &'static str {
    match data["code"].as_str() {
        Some("invalid_url") => "Enter the server's HTTPS URL.",
        Some("invalid_name") => "Enter a name of at most 64 characters.",
        Some("too_many_servers") => "You can add up to 25 servers.",
        Some("rate_limited") => "Too many sign-ins to this server. Try again in a few minutes.",
        Some("access_denied") => CANCELLED,
        Some("oauth_not_supported" | "registration_not_supported") => {
            "This server doesn't support signing in from Luft."
        }
        _ => "The server refused the request",
    }
}
