//! Presence: who in an organization has Luft open right now. The core
//! keeps one Phoenix channel joined on `presence:<organization handle>` over a
//! WebSocket the platform opens for it (`Socket`), and the server tracks the
//! person as online while it stays joined. Phoenix's wire protocol, the join,
//! heartbeats, reconnection and the presence state all live here, so every
//! frontend shows the same thing.
use std::collections::{BTreeMap, BTreeSet};

use serde_json::{Value, json};
use url::Url;

use crate::client::Result;

/// A WebSocket the platform owns. The core calls it only from `Presence`,
/// one connection at a time, and never blocks on it: `read` returns what has
/// arrived since the last call.
pub trait Socket {
    /// Opens a connection to `url` offering `protocols`, replacing any open
    /// one. The protocols carry the bearer credential: never log them.
    fn open(&mut self, url: &Url, protocols: &[String]) -> Result<()>;
    fn send(&mut self, text: &str) -> Result<()>;
    /// The text frames received since the last read, and whether the
    /// connection has closed.
    fn read(&mut self) -> Result<(Vec<String>, bool)>;
    fn close(&mut self);
}

/// Phoenix closes sockets that send nothing for 60 s.
const HEARTBEAT: i64 = 25;
/// How long to wait before reconnecting after a dropped connection, and after
/// the server refused the join (flags off, not a member).
const RECONNECT: i64 = 5;
const REFUSED_RETRY: i64 = 60;

#[derive(Default)]
pub struct Presence {
    /// The server and organization handle of the current connection.
    target: Option<(String, String)>,
    connected: bool,
    joined: bool,
    refused: bool,
    join_ref: String,
    next_ref: u64,
    last_sent: i64,
    retry_at: i64,
    /// User ID → handle and the connection refs keeping them online.
    online: BTreeMap<String, (String, BTreeSet<String>)>,
}

impl Presence {
    pub fn new() -> Self {
        Self::default()
    }

    /// Keeps the person joined to `handle`'s presence on `server` and applies
    /// what arrived. Call it every few seconds while the app is in front;
    /// `token` is asked for only when a connection opens. Returns
    /// `{available, reason, connected, online:[{id,handle}]}`, the person
    /// included in `online`.
    pub fn poll(
        &mut self,
        server: &Url,
        handle: &str,
        token: &mut dyn FnMut() -> Result<String>,
        socket: &mut dyn Socket,
        now: i64,
    ) -> Result<Value> {
        let target = (server.to_string(), handle.to_string());
        if self.target.as_ref() != Some(&target) {
            self.disconnect(socket);
            // Another organization's refusal says nothing about this one.
            self.refused = false;
            self.retry_at = 0;
            self.target = Some(target);
        }
        if !self.connected && now >= self.retry_at {
            let mut url = server
                .join("threads/socket/websocket")
                .map_err(|_| "Invalid server")?;
            url.set_query(Some("vsn=2.0.0"));
            let scheme = if url.scheme() == "http" { "ws" } else { "wss" };
            url.set_scheme(scheme).map_err(|_| "Invalid server")?;
            let protocols = vec![
                "phoenix".to_string(),
                format!("base64url.bearer.phx.{}", base64url(token()?.as_bytes())),
            ];
            self.join_ref = self.reference();
            socket.open(&url, &protocols)?;
            self.connected = true;
            self.last_sent = now;
            let join = json!([self.join_ref, self.join_ref, self.topic(), "phx_join", {}]);
            if socket.send(&join.to_string()).is_err() {
                self.drop_connection(socket, now, RECONNECT);
            }
        }
        if self.connected {
            match socket.read() {
                Ok((frames, closed)) => {
                    for frame in frames {
                        self.receive(&frame, socket, now);
                    }
                    if closed && self.connected {
                        self.drop_connection(socket, now, RECONNECT);
                    }
                }
                Err(_) => self.drop_connection(socket, now, RECONNECT),
            }
        }
        if self.connected && now - self.last_sent >= HEARTBEAT {
            let heartbeat = json!([null, self.reference(), "phoenix", "heartbeat", {}]);
            if socket.send(&heartbeat.to_string()).is_ok() {
                self.last_sent = now;
            } else {
                self.drop_connection(socket, now, RECONNECT);
            }
        }
        let online: Vec<Value> = self
            .online
            .iter()
            .map(|(id, (handle, _))| json!({"id": id.parse::<u64>().ok(), "handle": handle}))
            .collect();
        Ok(json!({
            "available": !self.refused,
            "reason": if self.refused { json!("disabled") } else { Value::Null },
            "connected": self.joined,
            "online": online,
        }))
    }

    /// Leaves presence, so the person shows offline, until the next `poll`.
    pub fn disconnect(&mut self, socket: &mut dyn Socket) {
        if self.connected {
            socket.close();
        }
        self.connected = false;
        self.joined = false;
        self.online.clear();
        // Coming back to the front retries a dropped connection at once, but
        // a refused join still waits out its delay.
        if !self.refused {
            self.retry_at = 0;
        }
    }

    /// The online user IDs, while joined. `None` means unknown: keep what the
    /// server answered over HTTP.
    pub fn online_ids(&self, handle: &str) -> Option<BTreeSet<u64>> {
        (self.joined && self.target.as_ref().is_some_and(|(_, h)| h == handle)).then(|| {
            self.online
                .keys()
                .filter_map(|id| id.parse().ok())
                .collect()
        })
    }

    fn topic(&self) -> String {
        format!(
            "presence:{}",
            self.target.as_ref().map(|(_, h)| h.as_str()).unwrap_or("")
        )
    }

    fn reference(&mut self) -> String {
        self.next_ref += 1;
        self.next_ref.to_string()
    }

    fn drop_connection(&mut self, socket: &mut dyn Socket, now: i64, wait: i64) {
        socket.close();
        self.connected = false;
        self.joined = false;
        self.online.clear();
        self.retry_at = now + wait;
    }

    fn receive(&mut self, frame: &str, socket: &mut dyn Socket, now: i64) {
        let Ok(Value::Array(parts)) = serde_json::from_str::<Value>(frame) else {
            return;
        };
        let [join_ref, reference, topic, event, payload] = parts.as_slice() else {
            return;
        };
        if topic.as_str() != Some(self.topic().as_str()) {
            return;
        }
        // Replies and pushes from an earlier join on this socket are stale.
        if !join_ref.is_null() && join_ref.as_str() != Some(self.join_ref.as_str()) {
            return;
        }
        match event.as_str() {
            Some("phx_reply") if reference.as_str() == Some(self.join_ref.as_str()) => {
                if payload["status"] == "ok" {
                    self.joined = true;
                    self.refused = false;
                } else {
                    self.drop_connection(socket, now, REFUSED_RETRY);
                    self.refused = true;
                }
            }
            Some("presence_state") => {
                self.online.clear();
                self.join(payload);
            }
            Some("presence_diff") => {
                self.join(&payload["joins"]);
                if let Some(leaves) = payload["leaves"].as_object() {
                    for (id, entry) in leaves {
                        if let Some((_, refs)) = self.online.get_mut(id) {
                            for meta in entry["metas"].as_array().into_iter().flatten() {
                                if let Some(r) = meta["phx_ref"].as_str() {
                                    refs.remove(r);
                                }
                            }
                            if refs.is_empty() {
                                self.online.remove(id);
                            }
                        }
                    }
                }
            }
            Some("phx_close" | "phx_error") => self.drop_connection(socket, now, RECONNECT),
            _ => {}
        }
    }

    /// Adds every connection in a presence state or diff's `joins`.
    fn join(&mut self, entries: &Value) {
        let Some(entries) = entries.as_object() else {
            return;
        };
        for (id, entry) in entries {
            for meta in entry["metas"].as_array().into_iter().flatten() {
                let handle = meta["handle"].as_str().unwrap_or_default().to_string();
                let slot = self.online.entry(id.clone()).or_default();
                if !handle.is_empty() {
                    slot.0 = handle;
                }
                if let Some(r) = meta["phx_ref"].as_str() {
                    slot.1.insert(r.to_string());
                }
            }
        }
    }
}

/// Sets `online` on every person (an object with `id` and `handle`) in a
/// lounges response from the live presence state.
pub(crate) fn mark_online(value: &mut Value, online: &BTreeSet<u64>) {
    match value {
        Value::Object(map) => {
            if let (Some(id), true) = (
                map.get("id").and_then(Value::as_u64),
                map.contains_key("handle"),
            ) {
                map.insert("online".into(), json!(online.contains(&id)));
            }
            for value in map.values_mut() {
                mark_online(value, online);
            }
        }
        Value::Array(values) => values.iter_mut().for_each(|v| mark_online(v, online)),
        _ => {}
    }
}

fn base64url(bytes: &[u8]) -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let n = chunk
            .iter()
            .enumerate()
            .fold(0u32, |n, (i, b)| n | u32::from(*b) << (16 - 8 * i));
        for i in 0..=chunk.len() {
            out.push(ALPHABET[(n >> (18 - 6 * i) & 63) as usize] as char);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Default)]
    struct FakeSocket {
        opened: Vec<(String, Vec<String>)>,
        sent: Vec<Value>,
        inbox: Vec<String>,
        closed: bool,
        closes: usize,
    }

    impl Socket for FakeSocket {
        fn open(&mut self, url: &Url, protocols: &[String]) -> Result<()> {
            self.opened.push((url.to_string(), protocols.to_vec()));
            self.closed = false;
            Ok(())
        }
        fn send(&mut self, text: &str) -> Result<()> {
            self.sent.push(serde_json::from_str(text).unwrap());
            Ok(())
        }
        fn read(&mut self) -> Result<(Vec<String>, bool)> {
            Ok((std::mem::take(&mut self.inbox), self.closed))
        }
        fn close(&mut self) {
            self.closes += 1;
        }
    }

    fn server() -> Url {
        Url::parse("https://tuist.dev/base/").unwrap()
    }

    fn token() -> impl FnMut() -> Result<String> {
        || Ok("secret".to_string())
    }

    fn ids(value: &Value) -> Vec<u64> {
        value["online"]
            .as_array()
            .unwrap()
            .iter()
            .map(|p| p["id"].as_u64().unwrap())
            .collect()
    }

    #[test]
    fn joins_with_the_bearer_subprotocol_and_tracks_state_and_diffs() {
        let (mut presence, mut socket) = (Presence::new(), FakeSocket::default());
        presence
            .poll(&server(), "tuist", &mut token(), &mut socket, 100)
            .unwrap();
        let (url, protocols) = &socket.opened[0];
        assert_eq!(
            url,
            "wss://tuist.dev/base/threads/socket/websocket?vsn=2.0.0"
        );
        // base64url("secret") without padding.
        assert_eq!(protocols, &["phoenix", "base64url.bearer.phx.c2VjcmV0"]);
        assert_eq!(
            socket.sent[0],
            json!(["1", "1", "presence:tuist", "phx_join", {}])
        );

        socket.inbox = vec![
            r#"["1","1","presence:tuist","phx_reply",{"status":"ok","response":{}}]"#.into(),
            r#"["1",null,"presence:tuist","presence_state",{"7":{"metas":[{"handle":"ana","phx_ref":"a"}]}}]"#.into(),
            r#"["1",null,"presence:tuist","presence_diff",{"joins":{"9":{"metas":[{"handle":"ben","phx_ref":"b1"},{"handle":"ben","phx_ref":"b2"}]}},"leaves":{}}]"#.into(),
            // Another organization's topic never counts.
            r#"["1",null,"presence:other","presence_diff",{"joins":{"11":{"metas":[{"handle":"eve","phx_ref":"e"}]}},"leaves":{}}]"#.into(),
        ];
        let state = presence
            .poll(&server(), "tuist", &mut token(), &mut socket, 101)
            .unwrap();
        assert_eq!(state["connected"], true);
        assert_eq!(ids(&state), vec![7, 9]);
        assert_eq!(presence.online_ids("tuist"), Some(BTreeSet::from([7, 9])));
        assert_eq!(presence.online_ids("other"), None);

        // Ben stays online until his last connection leaves.
        socket.inbox = vec![r#"["1",null,"presence:tuist","presence_diff",{"joins":{},"leaves":{"9":{"metas":[{"phx_ref":"b1"}]}}}]"#.into()];
        assert_eq!(
            ids(&presence
                .poll(&server(), "tuist", &mut token(), &mut socket, 102)
                .unwrap()),
            vec![7, 9]
        );
        socket.inbox = vec![r#"["1",null,"presence:tuist","presence_diff",{"joins":{},"leaves":{"9":{"metas":[{"phx_ref":"b2"}]}}}]"#.into()];
        assert_eq!(
            ids(&presence
                .poll(&server(), "tuist", &mut token(), &mut socket, 103)
                .unwrap()),
            vec![7]
        );
        assert_eq!(socket.opened.len(), 1);
    }

    #[test]
    fn heartbeats_reconnects_after_a_drop_and_follows_the_organization() {
        let (mut presence, mut socket) = (Presence::new(), FakeSocket::default());
        presence
            .poll(&server(), "tuist", &mut token(), &mut socket, 0)
            .unwrap();
        presence
            .poll(&server(), "tuist", &mut token(), &mut socket, HEARTBEAT)
            .unwrap();
        assert_eq!(socket.sent.last().unwrap()[3], "heartbeat");

        socket.closed = true;
        presence
            .poll(&server(), "tuist", &mut token(), &mut socket, 30)
            .unwrap();
        assert_eq!(socket.opened.len(), 1, "waits before reconnecting");
        presence
            .poll(
                &server(),
                "tuist",
                &mut token(),
                &mut socket,
                30 + RECONNECT,
            )
            .unwrap();
        assert_eq!(socket.opened.len(), 2);

        // A different organization closes the old connection and joins the new topic.
        presence
            .poll(&server(), "acme", &mut token(), &mut socket, 40)
            .unwrap();
        assert_eq!(socket.opened.len(), 3);
        assert_eq!(socket.sent.last().unwrap()[2], "presence:acme");
        assert!(socket.closes >= 2);
    }

    #[test]
    fn a_refused_join_reports_unavailable_and_waits_before_trying_again() {
        let (mut presence, mut socket) = (Presence::new(), FakeSocket::default());
        presence
            .poll(&server(), "tuist", &mut token(), &mut socket, 0)
            .unwrap();
        socket.inbox = vec![r#"["1","1","presence:tuist","phx_reply",{"status":"error","response":{"reason":"not_found"}}]"#.into()];
        let state = presence
            .poll(&server(), "tuist", &mut token(), &mut socket, 1)
            .unwrap();
        assert_eq!(
            (state["available"].as_bool(), state["reason"].as_str()),
            (Some(false), Some("disabled"))
        );
        // Leaving and coming back (the app going to the background) neither
        // skips the wait nor claims presence is available again.
        presence.disconnect(&mut socket);
        let state = presence
            .poll(&server(), "tuist", &mut token(), &mut socket, 30)
            .unwrap();
        assert_eq!(socket.opened.len(), 1);
        assert_eq!(state["available"], false);
        let state = presence
            .poll(
                &server(),
                "tuist",
                &mut token(),
                &mut socket,
                1 + REFUSED_RETRY,
            )
            .unwrap();
        assert_eq!(socket.opened.len(), 2);
        assert_eq!(
            state["available"], false,
            "unknown until the server answers"
        );
        socket.inbox =
            vec![r#"["2","2","presence:tuist","phx_reply",{"status":"ok","response":{}}]"#.into()];
        let state = presence
            .poll(
                &server(),
                "tuist",
                &mut token(),
                &mut socket,
                2 + REFUSED_RETRY,
            )
            .unwrap();
        assert_eq!(state["available"], true);
    }

    #[test]
    fn marks_people_online_anywhere_in_a_lounges_response() {
        let mut value = json!({"members":[{"id":7,"handle":"ana","online":false}],
            "messages":[{"id":"m","author":{"id":9,"handle":"ben","online":true}}]});
        mark_online(&mut value, &BTreeSet::from([7]));
        assert_eq!(value["members"][0]["online"], true);
        assert_eq!(value["messages"][0]["author"]["online"], false);
        assert!(value["messages"][0].get("online").is_none());
    }

    #[test]
    fn base64url_matches_the_rfc_vectors() {
        for (input, output) in [
            ("", ""),
            ("f", "Zg"),
            ("fo", "Zm8"),
            ("foo", "Zm9v"),
            ("foob", "Zm9vYg"),
            ("\u{ff}\u{fe}", "w7_Dvg"),
        ] {
            assert_eq!(base64url(input.as_bytes()), output);
        }
    }
}
