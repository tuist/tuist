//! Live threads: the Phoenix channel a frontend keeps open on the thread it
//! shows (`/threads/socket`, topic `threads:{account}:{thread}`), or on the
//! inbox (`threads:{account}:inbox`). The server pushes `snapshot` when the
//! thread, or any of the inbox's threads, changes, and the agent calls the tools
//! the app offers when it joins (`client_tools`), which run here and on the
//! edge. Edges own the WebSocket; the core writes and reads its frames and
//! decides when to heartbeat, when to give up on a socket and how long to
//! wait before opening it again.
use std::collections::HashMap;

use serde_json::{Value, json};
use tuist_oauth::endpoint;
use url::Url;

use crate::client::Result;

const JOIN_REF: &str = "1";
const HEARTBEAT_REF: &str = "heartbeat";
const HEARTBEAT_MS: u64 = 30_000;
const FIRST_RETRY_MS: u64 = 1_000;
const MAX_RETRY_MS: u64 = 30_000;
/// The inbox hears every thread's change, several a second while agents
/// work, and each refresh reloads the whole list, so it refreshes at most
/// this often. A thread's own socket refreshes as it changes.
const INBOX_REFRESH_MS: u64 = 2_000;

/// The `id` that follows the account's whole inbox rather than one thread.
pub const INBOX: &str = "inbox";

/// The tools Luft offers the thread's agent. They change only this device.
pub fn client_tools() -> Value {
    json!([crate::theme::tool()])
}

/// The live sockets an edge keeps open, by the handle it chose for each.
#[derive(Default)]
pub struct Live {
    sockets: HashMap<String, Socket>,
}

#[derive(Default)]
struct Socket {
    /// Connections opened since the last one that joined.
    failures: u32,
    /// A heartbeat went out and the server hasn't answered it yet.
    awaiting_heartbeat: bool,
}

impl Live {
    /// How long to wait before connecting socket `handle`: nothing the first
    /// time and after a connection that joined, then backing off while
    /// attempts fail, whether to connect or to join. Call it before every
    /// `connect`.
    pub fn wait(&mut self, handle: &str) -> u64 {
        let socket = self.sockets.entry(handle.to_string()).or_default();
        let delay = match socket.failures {
            0 => 0,
            failures => (FIRST_RETRY_MS << (failures - 1).min(5)).min(MAX_RETRY_MS),
        };
        // Counted as failed until its join succeeds.
        socket.failures = socket.failures.saturating_add(1);
        delay
    }

    /// How to open socket `handle` on the thread `id` (or [`INBOX`]) in
    /// `account`: its URL, the subprotocols that carry the bearer `access`
    /// (never a URL parameter), the join frame to send first, how often to
    /// call `tick`, and the least time between two refreshes (`refresh_ms`):
    /// the edge folds the refreshes asked for meanwhile into one.
    pub fn connect(
        &mut self,
        handle: &str,
        server: &Url,
        account: &str,
        id: &str,
        access: &str,
    ) -> Result<Value> {
        let mut url = endpoint(server, "threads/socket/websocket");
        let scheme = if url.scheme() == "https" { "wss" } else { "ws" };
        url.set_scheme(scheme).map_err(|_| "Invalid server")?;
        url.query_pairs_mut().append_pair("vsn", "2.0.0");
        self.sockets
            .entry(handle.to_string())
            .or_default()
            .awaiting_heartbeat = false;
        Ok(json!({
            "url": url.as_str(),
            "protocols": ["phoenix", format!("base64url.bearer.phx.{}", base64(access.as_bytes()))],
            "join": frame(Some(JOIN_REF), Some(JOIN_REF), &topic(account, id), "phx_join", json!({"tools": client_tools()})),
            "tick_ms": HEARTBEAT_MS,
            "refresh_ms": if id == INBOX { INBOX_REFRESH_MS } else { 0 },
        }))
    }

    /// Called every `tick_ms` while socket `handle` is open: `send` are
    /// frames to send, and `reconnect` asks to close the socket and connect
    /// again, because the server never answered the last heartbeat, as after
    /// a network change leaves the socket half open.
    pub fn tick(&mut self, handle: &str) -> Value {
        let socket = self.sockets.entry(handle.to_string()).or_default();
        if socket.awaiting_heartbeat {
            return json!({"send": [], "reconnect": true});
        }
        socket.awaiting_heartbeat = true;
        let heartbeat = frame(None, Some(HEARTBEAT_REF), "phoenix", "heartbeat", json!({}));
        json!({"send": [heartbeat], "reconnect": false})
    }

    /// Forgets socket `handle` once its screen is gone.
    pub fn close(&mut self, handle: &str) {
        self.sockets.remove(handle);
    }

    /// Reads one text frame from socket `handle` on the thread `id` in
    /// `account`: `refresh` asks the edge to load the thread again,
    /// `reconnect` to close the socket and connect again, `replies` are
    /// frames to send back, and `theme` is a custom theme to apply and select
    /// before sending them, in the theme catalog's shape.
    pub fn receive(
        &mut self,
        handle: &str,
        account: &str,
        id: &str,
        message: &str,
    ) -> Result<Value> {
        let parsed: Value = serde_json::from_str(message).map_err(|_| "Invalid message")?;
        let [join_ref, reference, topic, event, payload] = parsed
            .as_array()
            .and_then(|parts| <&[Value; 5]>::try_from(parts.as_slice()).ok())
            .ok_or("Invalid message")?;
        let socket = self.sockets.entry(handle.to_string()).or_default();
        let mut out = json!({"refresh": false, "reconnect": false, "replies": [], "theme": null});
        let topic = topic.as_str().ok_or("Invalid message")?;
        if topic == "phoenix" {
            if reference == HEARTBEAT_REF && event == "phx_reply" {
                socket.awaiting_heartbeat = false;
            }
            return Ok(out);
        }
        let expected = self::topic(account, id);
        if topic != expected {
            // The person switched accounts while the socket was open. Answer
            // a call at once rather than letting the agent wait for it, and
            // rejoin under the account shown now.
            if event == "tool_call" {
                let call = payload["id"].as_str().ok_or("Invalid message")?;
                let error = json!({"id": call, "error": "The person switched to another account in the app."});
                out["replies"] = json!([frame(Some(JOIN_REF), None, topic, "tool_result", error)]);
            }
            out["reconnect"] = json!(true);
            return Ok(out);
        }
        match event.as_str() {
            Some("snapshot") => out["refresh"] = json!(true),
            // Joined: what changed before the join only shows in a fresh load.
            Some("phx_reply") if join_ref == JOIN_REF && reference == JOIN_REF => {
                if payload["status"] == "ok" {
                    socket.failures = 0;
                    out["refresh"] = json!(true);
                } else {
                    out["reconnect"] = json!(true);
                }
            }
            Some("phx_error" | "phx_close") => out["reconnect"] = json!(true),
            Some("tool_call") => {
                let call = payload["id"].as_str().ok_or("Invalid message")?;
                let (mut result, theme) = match payload["name"].as_str() {
                    Some("set_theme") => match crate::theme::custom(&payload["arguments"]) {
                        Ok(theme) => {
                            let summary = format!(
                                "Applied. The app now shows a custom {} theme, and Profile lists it as Custom.",
                                theme["appearance"].as_str().unwrap_or_default()
                            );
                            (json!({"ok": summary}), theme)
                        }
                        Err(error) => (json!({"error": error}), Value::Null),
                    },
                    _ => (json!({"error": "This app has no such tool."}), Value::Null),
                };
                result["id"] = json!(call);
                out["replies"] = json!([frame(
                    Some(JOIN_REF),
                    None,
                    &expected,
                    "tool_result",
                    result
                )]);
                out["theme"] = theme;
            }
            _ => {}
        }
        Ok(out)
    }
}

fn topic(account: &str, id: &str) -> String {
    format!("threads:{account}:{id}")
}

/// A Phoenix V2 frame: `[join_ref, ref, topic, event, payload]`.
fn frame(
    join_ref: Option<&str>,
    reference: Option<&str>,
    topic: &str,
    event: &str,
    payload: Value,
) -> String {
    json!([join_ref, reference, topic, event, payload]).to_string()
}

/// Unpadded standard base64. Despite its `base64url.` prefix, Phoenix decodes
/// the bearer subprotocol with `Base.decode64!/2`, as its JavaScript client
/// encodes it with `btoa`.
fn base64(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let value = chunk.iter().enumerate().fold(0u32, |value, (i, byte)| {
            value | u32::from(*byte) << (16 - 8 * i)
        });
        for i in 0..=chunk.len() {
            out.push(char::from(ALPHABET[(value >> (18 - 6 * i) & 63) as usize]));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::Engine;

    const THREAD: &str = "9b2f8c4e-1d3a-4c55-9f0e-6a1b2c3d4e5f";

    fn connect(live: &mut Live) -> Value {
        let server = Url::parse("https://example.com/tuist/").unwrap();
        live.connect("socket", &server, "ana", THREAD, "token")
            .unwrap()
    }

    fn joined(live: &mut Live) {
        let reply = json!(["1", "1", format!("threads:ana:{THREAD}"), "phx_reply", {"status": "ok", "response": {}}]);
        assert_eq!(
            live.receive("socket", "ana", THREAD, &reply.to_string())
                .unwrap()["refresh"],
            true
        );
    }

    fn call(arguments: Value) -> Value {
        let message = json!(["1", null, format!("threads:ana:{THREAD}"), "tool_call",
            {"id": "call-1", "name": "set_theme", "arguments": arguments}]);
        Live::default()
            .receive("socket", "ana", THREAD, &message.to_string())
            .unwrap()
    }

    #[test]
    fn connects_with_the_bearer_as_a_subprotocol_and_offers_the_tools() {
        let server = Url::parse("https://example.com/tuist/").unwrap();
        // "?>" encodes to characters that differ between base64 and base64url.
        let socket = Live::default()
            .connect("s", &server, "ana", THREAD, "a.b?>")
            .unwrap();
        assert_eq!(
            socket["url"],
            "wss://example.com/tuist/threads/socket/websocket?vsn=2.0.0"
        );
        let protocol = socket["protocols"][1].as_str().unwrap();
        let encoded = protocol.strip_prefix("base64url.bearer.phx.").unwrap();
        let decoded = base64::engine::general_purpose::STANDARD_NO_PAD
            .decode(encoded)
            .unwrap();
        assert_eq!(decoded, b"a.b?>");
        let join: Value = serde_json::from_str(socket["join"].as_str().unwrap()).unwrap();
        assert_eq!(join[2], format!("threads:ana:{THREAD}"));
        assert_eq!(join[3], "phx_join");
        assert_eq!(join[4]["tools"][0]["name"], "set_theme");
        let loopback = Url::parse("http://localhost:8080").unwrap();
        let local = Live::default()
            .connect("s", &loopback, "ana", THREAD, "t")
            .unwrap();
        assert!(
            local["url"]
                .as_str()
                .unwrap()
                .starts_with("ws://localhost:8080/")
        );
    }

    #[test]
    fn reconnects_back_off_until_a_join_succeeds() {
        let mut live = Live::default();
        let delays: Vec<_> = (0..8).map(|_| live.wait("socket")).collect();
        assert_eq!(
            delays,
            [0, 1_000, 2_000, 4_000, 8_000, 16_000, 30_000, 30_000]
        );
        joined(&mut live);
        // A connection that joined and later dropped reopens at once.
        assert_eq!(live.wait("socket"), 0);
        assert_eq!(live.wait("socket"), 1_000);
        // Opening a socket doesn't count as joining it.
        connect(&mut live);
        assert_eq!(live.wait("socket"), 2_000);
        live.close("socket");
        assert_eq!(live.wait("socket"), 0);
        // Sockets back off independently.
        assert_eq!(live.wait("other"), 0);
    }

    #[test]
    fn an_unanswered_heartbeat_reconnects() {
        let mut live = Live::default();
        connect(&mut live);
        let tick = live.tick("socket");
        assert_eq!(tick["reconnect"], false);
        let heartbeat: Value = serde_json::from_str(tick["send"][0].as_str().unwrap()).unwrap();
        assert_eq!(
            heartbeat,
            json!([null, "heartbeat", "phoenix", "heartbeat", {}])
        );
        let reply =
            json!([null, "heartbeat", "phoenix", "phx_reply", {"status": "ok", "response": {}}]);
        live.receive("socket", "ana", THREAD, &reply.to_string())
            .unwrap();
        assert_eq!(live.tick("socket")["reconnect"], false);
        // No reply to that one: the socket is half open.
        assert_eq!(live.tick("socket"), json!({"send": [], "reconnect": true}));
        // A fresh connection starts over.
        connect(&mut live);
        assert_eq!(live.tick("socket")["reconnect"], false);
    }

    #[test]
    fn the_theme_tool_schema_names_every_token() {
        let tool = crate::theme::tool();
        let colors = &tool["parameters"]["properties"]["colors"]["properties"];
        for (token, _, _) in crate::theme::TOKENS {
            assert!(colors[token]["description"].is_string(), "{token}");
        }
    }

    #[test]
    fn set_theme_overrides_the_base_palette_and_answers_the_call() {
        let out = call(
            json!({"base": "noora", "appearance": "dark", "colors": {"button-primary-background": "#FF0066"}}),
        );
        let theme = &out["theme"];
        assert_eq!(theme["id"], "custom");
        assert_eq!(theme["appearance"], "dark");
        assert_eq!(theme["dark"]["button-primary-background"], "#ff0066");
        // Tokens left out keep the base theme's dark color, not its light one.
        assert_eq!(theme["dark"]["surface-background-primary"], "#0e0e0e");
        assert_eq!(theme["light"], theme["dark"]);
        // Cards in the conversation follow the custom theme too.
        assert_eq!(
            theme["card"]["dark"]["cssVars"]["theme"]["primary"],
            "#ff0066"
        );
        let reply: Value = serde_json::from_str(out["replies"][0].as_str().unwrap()).unwrap();
        assert_eq!(reply[0], "1");
        assert_eq!(reply[3], "tool_result");
        assert_eq!(reply[4]["id"], "call-1");
        assert!(reply[4]["ok"].as_str().unwrap().contains("dark"));
    }

    #[test]
    fn set_theme_keeps_the_appearance_a_base_imposes() {
        let out = call(json!({"base": "tokyo-night"}));
        assert_eq!(out["theme"]["appearance"], "dark");
        assert_eq!(
            out["theme"]["dark"]["surface-background-primary"],
            "#1a1b26"
        );
        assert_eq!(
            call(json!({"base": "tokyo-night", "appearance": "dark"}))["theme"]["appearance"],
            "dark"
        );
        // Light chrome over Tokyo Night's dark surfaces would be illegible.
        assert!(call(json!({"base": "tokyo-night", "appearance": "light"}))["theme"].is_null());
    }

    #[test]
    fn set_theme_refuses_invalid_colors_without_changing_the_theme() {
        for arguments in [
            json!({"appearance": "dark", "colors": {"surface-background-primary": "red"}}),
            json!({"appearance": "dark", "colors": {"not-a-token": "#000000"}}),
            json!({"appearance": "dim"}),
            json!({"colors": {}}),
            json!({"appearance": "light", "base": "unknown"}),
        ] {
            let out = call(arguments);
            assert!(out["theme"].is_null());
            let reply: Value = serde_json::from_str(out["replies"][0].as_str().unwrap()).unwrap();
            assert!(reply[4]["error"].is_string());
            assert_eq!(reply[4]["id"], "call-1");
        }
    }

    #[test]
    fn the_inbox_joins_its_own_topic_and_refreshes_at_most_every_two_seconds() {
        let server = Url::parse("https://example.com/tuist/").unwrap();
        let mut live = Live::default();
        let thread = live.connect("t", &server, "ana", THREAD, "token").unwrap();
        assert_eq!(thread["refresh_ms"], 0);
        let inbox = live.connect("i", &server, "ana", INBOX, "token").unwrap();
        assert_eq!(inbox["refresh_ms"], 2000);
        let join: Value = serde_json::from_str(inbox["join"].as_str().unwrap()).unwrap();
        // The topic the server's inbox channel pushes on.
        assert_eq!(join[2], "threads:ana:inbox");
        let snapshot = json!([null, null, "threads:ana:inbox", "snapshot", {"revision": 7}]);
        let out = live
            .receive("i", "ana", INBOX, &snapshot.to_string())
            .unwrap();
        assert_eq!(
            (&out["refresh"], &out["reconnect"]),
            (&json!(true), &json!(false))
        );
    }

    #[test]
    fn snapshots_refresh_and_another_accounts_frames_reconnect() {
        let mut live = Live::default();
        let snapshot =
            json!([null, null, format!("threads:ana:{THREAD}"), "snapshot", {"revision": 2}])
                .to_string();
        assert_eq!(
            live.receive("socket", "ana", THREAD, &snapshot).unwrap()["refresh"],
            true
        );
        // After switching to another account, the old account's socket rejoins.
        let out = live.receive("socket", "acme", THREAD, &snapshot).unwrap();
        assert_eq!(
            out,
            json!({"refresh": false, "reconnect": true, "replies": [], "theme": null})
        );
        // ...and a call on it fails at once instead of waiting out the agent's timeout.
        let stale = json!(["1", null, format!("threads:ana:{THREAD}"), "tool_call",
            {"id": "call-2", "name": "set_theme", "arguments": {"appearance": "dark"}}]);
        let out = live
            .receive("socket", "acme", THREAD, &stale.to_string())
            .unwrap();
        assert!(out["theme"].is_null());
        let reply: Value = serde_json::from_str(out["replies"][0].as_str().unwrap()).unwrap();
        assert_eq!(reply[2], format!("threads:ana:{THREAD}"));
        assert_eq!(reply[4]["id"], "call-2");
        assert!(reply[4]["error"].is_string());
        let refused = json!(["1", "1", format!("threads:ana:{THREAD}"), "phx_reply", {"status": "error", "response": {}}]);
        assert_eq!(
            live.receive("socket", "ana", THREAD, &refused.to_string())
                .unwrap()["reconnect"],
            true
        );
        assert!(live.receive("socket", "ana", THREAD, "[]").is_err());
    }
}
