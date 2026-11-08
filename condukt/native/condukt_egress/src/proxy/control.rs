//! Bidirectional NDJSON control channel between the sidecar and the
//! BEAM-side `ControlBridge`.
//!
//! Outbound traffic (sidecar -> BEAM): events that fire over a request's
//! lifecycle (`request_opened`, `request_allowed`, `request_denied`,
//! `request_closed`) and `decision_request` frames the sidecar emits
//! when a connection's host isn't in the static deny/allow lists and
//! the BEAM-side policy has a decider configured.
//!
//! Inbound traffic (BEAM -> sidecar): `decision` frames keyed by the
//! `id` field of the decision_request the BEAM was answering.
//!
//! Each TCP peer that connects to the sidecar's `--control-listen`
//! port gets a single bidirectional NDJSON stream over the lifetime
//! of that connection. The sidecar accepts at most one peer at a
//! time; new peers replace the old one (the BEAM typically opens a
//! single long-lived control bridge per session).

use crate::proxy::event::{DecisionAction, Event, Inbound, Outbound};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpListener;
use tokio::sync::{Mutex, mpsc, oneshot};

const BUFFER_CAP: usize = 1024;

pub struct ControlChannel {
    out_tx: mpsc::Sender<Outbound>,
    pending: Arc<Mutex<HashMap<String, oneshot::Sender<Decision>>>>,
}

#[derive(Debug, Clone)]
pub struct Decision {
    pub action: DecisionAction,
    pub reason: Option<String>,
}

impl ControlChannel {
    pub async fn start(bind: &str) -> std::io::Result<Self> {
        let listener = TcpListener::bind(bind).await?;
        let (out_tx, out_rx) = mpsc::channel::<Outbound>(BUFFER_CAP);
        let pending: Arc<Mutex<HashMap<String, oneshot::Sender<Decision>>>> =
            Arc::new(Mutex::new(HashMap::new()));

        let out_rx = Arc::new(Mutex::new(out_rx));
        let pending_for_loop = Arc::clone(&pending);
        tokio::spawn(accept_loop(listener, out_rx, pending_for_loop));

        Ok(ControlChannel { out_tx, pending })
    }

    /// Emit an event for delivery. Non-blocking; if the buffer is full
    /// or no peer is connected, the event is dropped with a stderr
    /// warning.
    pub fn emit(&self, event: Event) {
        if let Err(err) = self.out_tx.try_send(Outbound::Event(Box::new(event))) {
            eprintln!("condukt-egress control: dropped event ({err})");
        }
    }

    /// Register a pending decision and emit the matching
    /// `decision_request`. Returns a future that resolves when the
    /// BEAM responds or when `timeout` elapses.
    pub async fn request_decision(
        &self,
        id: String,
        session_id: Option<String>,
        host: String,
        port: u16,
        scheme: String,
        timeout: Duration,
    ) -> Option<Decision> {
        let (tx, rx) = oneshot::channel::<Decision>();
        {
            let mut map = self.pending.lock().await;
            map.insert(id.clone(), tx);
        }

        let frame = Outbound::DecisionRequest {
            id: id.clone(),
            session_id,
            host,
            port,
            scheme,
        };

        if self.out_tx.try_send(frame).is_err() {
            let mut map = self.pending.lock().await;
            map.remove(&id);
            return None;
        }

        match tokio::time::timeout(timeout, rx).await {
            Ok(Ok(decision)) => Some(decision),
            _ => {
                let mut map = self.pending.lock().await;
                map.remove(&id);
                None
            }
        }
    }
}

async fn accept_loop(
    listener: TcpListener,
    out_rx: Arc<Mutex<mpsc::Receiver<Outbound>>>,
    pending: Arc<Mutex<HashMap<String, oneshot::Sender<Decision>>>>,
) {
    loop {
        let (stream, peer) = match listener.accept().await {
            Ok(pair) => pair,
            Err(err) => {
                eprintln!("condukt-egress control: accept failed: {err}");
                tokio::time::sleep(Duration::from_secs(1)).await;
                continue;
            }
        };

        eprintln!("condukt-egress control: peer connected from {peer}");
        let (reader, writer) = stream.into_split();

        let pending_for_reader = Arc::clone(&pending);
        let read_task = tokio::spawn(read_loop(reader, pending_for_reader));

        {
            let mut rx = out_rx.lock().await;
            write_loop(writer, &mut rx).await;
        }

        let _ = read_task.await;
        eprintln!("condukt-egress control: peer disconnected");
    }
}

async fn write_loop(
    mut writer: tokio::net::tcp::OwnedWriteHalf,
    rx: &mut mpsc::Receiver<Outbound>,
) {
    while let Some(frame) = rx.recv().await {
        let mut line = match serde_json::to_string(&frame) {
            Ok(json) => json,
            Err(err) => {
                eprintln!("condukt-egress control: serialize failed: {err}");
                continue;
            }
        };
        line.push('\n');

        if let Err(err) = writer.write_all(line.as_bytes()).await {
            eprintln!("condukt-egress control: write failed: {err}");
            return;
        }
    }
}

async fn read_loop(
    reader: tokio::net::tcp::OwnedReadHalf,
    pending: Arc<Mutex<HashMap<String, oneshot::Sender<Decision>>>>,
) {
    let mut buf = BufReader::new(reader).lines();
    loop {
        match buf.next_line().await {
            Ok(Some(line)) if line.trim().is_empty() => continue,
            Ok(Some(line)) => handle_line(&line, &pending).await,
            Ok(None) => return,
            Err(err) => {
                eprintln!("condukt-egress control: read failed: {err}");
                return;
            }
        }
    }
}

async fn handle_line(line: &str, pending: &Mutex<HashMap<String, oneshot::Sender<Decision>>>) {
    let parsed: Inbound = match serde_json::from_str(line) {
        Ok(p) => p,
        Err(err) => {
            eprintln!("condukt-egress control: bad inbound frame: {err}");
            return;
        }
    };

    match parsed {
        Inbound::Decision { id, action, reason } => {
            let mut map = pending.lock().await;
            if let Some(tx) = map.remove(&id) {
                let _ = tx.send(Decision { action, reason });
            } else {
                eprintln!("condukt-egress control: decision for unknown id {id}");
            }
        }
        Inbound::Unknown => {
            eprintln!("condukt-egress control: ignoring unknown frame type");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn pending() -> Mutex<HashMap<String, oneshot::Sender<Decision>>> {
        Mutex::new(HashMap::new())
    }

    #[tokio::test]
    async fn handle_line_resolves_the_matching_pending_decision() {
        let map = pending();
        let (tx, rx) = oneshot::channel::<Decision>();
        map.lock().await.insert("d1".to_string(), tx);

        handle_line(
            r#"{"type":"decision","id":"d1","action":"deny","reason":"nope"}"#,
            &map,
        )
        .await;

        let decision = rx.await.expect("pending decision should be resolved");
        assert_eq!(decision.action, DecisionAction::Deny);
        assert_eq!(decision.reason.as_deref(), Some("nope"));
        assert!(
            map.lock().await.is_empty(),
            "resolved id must be removed from the pending map"
        );
    }

    #[tokio::test]
    async fn handle_line_tolerates_unknown_id_bad_json_and_unknown_type() {
        let map = pending();

        // None of these should panic or leave state behind.
        handle_line(r#"{"type":"decision","id":"ghost","action":"allow"}"#, &map).await;
        handle_line("definitely not json", &map).await;
        handle_line(r#"{"type":"from_the_future"}"#, &map).await;

        assert!(map.lock().await.is_empty());
    }

    #[tokio::test]
    async fn request_decision_returns_none_when_no_peer_answers() {
        let channel = ControlChannel::start("127.0.0.1:0").await.unwrap();

        let result = channel
            .request_decision(
                "d9".into(),
                Some("s1".into()),
                "evil.com".into(),
                443,
                "https".into(),
                Duration::from_millis(50),
            )
            .await;

        assert!(result.is_none(), "no peer connected, so it must time out");
        assert!(
            channel.pending.lock().await.is_empty(),
            "a timed-out request must not leak its pending entry"
        );
    }
}
