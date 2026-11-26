//! The person's AI subscriptions (Claude, ChatGPT) at
//! `/api/me/ai-subscriptions`, which Tuist keeps and the Luft server forwards:
//! threads run on a connected ChatGPT subscription. Every screen that shows
//! them follows the `ai_subscriptions` live socket (`crate::live`), so a
//! subscription connected anywhere shows at once.
use serde_json::{Value, json};
use tuist_oauth::endpoint;
use url::Url;

use crate::client::{Result, successful, text};
use crate::threads::Transport;

pub(crate) const UNAVAILABLE: &str = "AI subscriptions are not available for this account.";
pub(crate) const CLAUDE_TOKEN_REFUSED: &str =
    "That is not a Claude subscription token. Paste the token `claude setup-token` prints.";

/// Runs `ai_subscriptions`, `connect_claude`, `start_chatgpt_login`,
/// `poll_chatgpt_login`, `cancel_chatgpt_login` or `disconnect_ai_subscription`
/// (see the crate README) on `server`. Changes answer with the whole list, as
/// `ai_subscriptions` does, except the ChatGPT sign-in steps, which answer
/// with the sign-in and its status (`pending`, `connected`, or `failed` once
/// it can't connect anymore).
pub fn call(
    server: &Url,
    operation: &str,
    args: &Value,
    transport: &mut dyn Transport,
) -> Result<Value> {
    let url = |path: &str| endpoint(server, &format!("api/me/ai-subscriptions{path}"));
    let login_id = || {
        text(args, "login_id").and_then(|id| {
            if id.is_empty() || id.len() > 200 {
                Err("Invalid sign-in")
            } else {
                Ok(id)
            }
        })
    };
    let (status, data) = match operation {
        "ai_subscriptions" => transport.send("GET", url(""), None)?,
        "connect_claude" => {
            let token = text(args, "token")?.trim();
            if token.is_empty() {
                return Err(CLAUDE_TOKEN_REFUSED);
            }
            transport.send("PUT", url("/claude"), Some(json!({"token": token})))?
        }
        "start_chatgpt_login" => transport.send("POST", url("/chatgpt/login"), None)?,
        "poll_chatgpt_login" => {
            let body = json!({"login_id": login_id()?});
            transport.send("POST", url("/chatgpt/login/poll"), Some(body))?
        }
        "cancel_chatgpt_login" => {
            let mut cancel = url("/chatgpt/login");
            cancel
                .query_pairs_mut()
                .append_pair("login_id", login_id()?);
            transport.send("DELETE", cancel, None)?
        }
        "disconnect_ai_subscription" => {
            let provider = text(args, "provider")?;
            if !matches!(provider, "claude" | "chatgpt") {
                return Err("Unknown provider");
            }
            transport.send("DELETE", url(&format!("/{provider}")), None)?
        }
        _ => return Err("Unknown operation"),
    };
    match (operation, status) {
        ("connect_claude", 422) => Err(CLAUDE_TOKEN_REFUSED),
        ("start_chatgpt_login", 429) => {
            Err("Too many ChatGPT sign-in attempts. Try again in a few minutes.")
        }
        ("start_chatgpt_login", 503) => Err("ChatGPT sign-in is not available on this server."),
        ("start_chatgpt_login", 502) => Err("OpenAI could not start the sign-in. Try again."),
        // Expired or refused at OpenAI: polling again can't help.
        ("poll_chatgpt_login", 410 | 502) => Ok(json!({"status": "failed"})),
        ("cancel_chatgpt_login", 404) => Ok(Value::Null),
        (_, 404) => Err(UNAVAILABLE),
        _ => successful((status, data)),
    }
}
