use crate::{Result, Session, error, invalid, now, validate_registration};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::HashMap;
use std::sync::{Arc, Condvar, Mutex, OnceLock};
use std::time::Duration;
use tokio::sync::watch;
use tokio::time::{Instant, timeout};
use tokio_tungstenite::tungstenite::{
    Message, client::IntoClientRequest, protocol::WebSocketConfig,
};

#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub(crate) enum Action {
    Open { session: Session, id: String },
    OpenList { session: Session },
    Next { connection: String, after: u64 },
    Typing { connection: String, typing: bool },
    Close { connection: String },
}

#[derive(Deserialize, Serialize)]
struct Person {
    id: String,
    name: String,
    typing: bool,
}

#[derive(Deserialize, Serialize)]
struct Snapshot {
    revision: u64,
    people: Vec<Person>,
}

#[derive(Clone, Default)]
struct Control {
    typing: bool,
    closed: bool,
}

struct Connection {
    control: watch::Sender<Control>,
    latest: Mutex<Value>,
    changed: Condvar,
}

fn connections() -> &'static Mutex<HashMap<String, Arc<Connection>>> {
    static CONNECTIONS: OnceLock<Mutex<HashMap<String, Arc<Connection>>>> = OnceLock::new();
    CONNECTIONS.get_or_init(Default::default)
}

pub(crate) fn execute(action: Action) -> Result<Value> {
    match action {
        Action::Open { session, id } => {
            crate::time_off::validate_id(&id)?;
            open_session(session, format!("orbit:thread:{id}"))
        }
        Action::OpenList { session } => open_session(session, "orbit:me".into()),
        Action::Next { connection, after } => {
            let state = get(&connection)?;
            let latest = state.latest.lock().map_err(|_| invalid())?;
            let (latest, _) = state
                .changed
                .wait_timeout_while(latest, Duration::from_secs(30), |value| {
                    value["sequence"].as_u64().unwrap_or(0) <= after
                        && !state.control.borrow().closed
                })
                .map_err(|_| invalid())?;
            Ok(latest.clone())
        }
        Action::Typing { connection, typing } => {
            get(&connection)?
                .control
                .send_modify(|control| control.typing = typing);
            Ok(json!({"updated":true}))
        }
        Action::Close { connection } => {
            if let Some(state) = connections()
                .lock()
                .map_err(|_| invalid())?
                .remove(&connection)
            {
                let _latest = state.latest.lock().map_err(|_| invalid())?;
                state.control.send_modify(|control| control.closed = true);
                state.changed.notify_all();
            }
            Ok(json!({"closed":true}))
        }
    }
}

fn get(id: &str) -> Result<Arc<Connection>> {
    connections()
        .lock()
        .map_err(|_| invalid())?
        .get(id)
        .cloned()
        .ok_or_else(|| error("closed", "This thread is disconnected."))
}

fn open_session(session: Session, topic: String) -> Result<Value> {
    let mut url = validate_registration(&session.registration)?;
    if session.expires_at <= now() || session.access_token.is_empty() {
        return Err(error("sign_in_required", "Sign in to Atlas again."));
    }
    url.set_scheme("wss").map_err(|_| invalid())?;
    url.set_path("/presence/websocket");
    url.set_query(Some("vsn=2.0.0"));
    open(url.as_str(), session, topic)
}

fn open(url: &str, session: Session, topic: String) -> Result<Value> {
    let mut request = url.into_client_request().map_err(|_| invalid())?;
    let protocol = format!(
        "phoenix, base64url.bearer.phx.{}",
        URL_SAFE_NO_PAD.encode(&session.access_token)
    );
    request.headers_mut().insert(
        "Sec-WebSocket-Protocol",
        protocol.parse().map_err(|_| invalid())?,
    );
    let mut bytes = [0_u8; 16];
    getrandom::fill(&mut bytes).map_err(|_| invalid())?;
    let handle: String = bytes.iter().map(|byte| format!("{byte:02x}")).collect();
    let (control, receiver) = watch::channel(Control::default());
    let state = Arc::new(Connection {
        control,
        latest: Mutex::new(json!({"sequence":0,"revision":0,"people":[]})),
        changed: Condvar::new(),
    });
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|_| error("internal", "Could not open this thread."))?;
    let mut registry = connections().lock().map_err(|_| invalid())?;
    if registry.len() >= 16 {
        return Err(error("internal", "Too many open threads."));
    }
    registry.insert(handle.clone(), state.clone());
    std::thread::spawn(move || {
        runtime.block_on(run(request, session.expires_at, topic, receiver, state))
    });
    Ok(json!({"connection":handle}))
}

fn publish(state: &Connection, mut value: Value) {
    if let Ok(mut latest) = state.latest.lock() {
        value["sequence"] = json!(latest["sequence"].as_u64().unwrap_or(0) + 1);
        *latest = value;
        state.changed.notify_all();
    }
}

async fn run(
    request: tokio_tungstenite::tungstenite::http::Request<()>,
    expires_at: u64,
    topic: String,
    mut control: watch::Receiver<Control>,
    state: Arc<Connection>,
) {
    let mut backoff = 1;
    loop {
        if control.borrow().closed {
            return;
        }
        if now() >= expires_at {
            publish(
                &state,
                json!({"revision":0,"people":[],"error":"sign_in_required","needs_session":true}),
            );
            return;
        }
        let config = WebSocketConfig::default()
            .max_message_size(Some(1024 * 1024))
            .max_frame_size(Some(1024 * 1024));
        let connected = tokio::select! {
            value = timeout(Duration::from_secs(10), tokio_tungstenite::connect_async_with_config(request.clone(), Some(config), true)) => value,
            _ = control.changed() => continue,
        };
        if let Ok(Ok((mut socket, _))) = connected
            && send(&mut socket, json!(["1", "1", topic, "phx_join", {}])).await
        {
            let mut reference = 1_u64;
            let mut joined = false;
            let mut heartbeat = tokio::time::interval(Duration::from_secs(10));
            heartbeat.tick().await;
            let mut last_received = Instant::now();
            loop {
                tokio::select! {
                    _ = control.changed() => {
                        let next = control.borrow_and_update().clone();
                        if next.closed {
                            let _ = timeout(Duration::from_secs(2), socket.close(None)).await;
                            return;
                        }
                        reference += 1;
                        if !send(&mut socket, json!(["1",reference.to_string(),topic,"typing",{"typing":next.typing}])).await { break; }
                    }
                    _ = heartbeat.tick() => {
                        if now() >= expires_at || last_received.elapsed() > Duration::from_secs(30) { break; }
                        reference += 1;
                        if !send(&mut socket, json!([null,reference.to_string(),"phoenix","heartbeat",{}])).await { break; }
                    }
                    message = socket.next() => {
                        let Some(Ok(message)) = message else { break; };
                        last_received = Instant::now();
                        let Message::Text(text) = message else {
                            if matches!(message, Message::Close(_)) { break; }
                            continue;
                        };
                        let Ok(frame) = serde_json::from_str::<Value>(&text) else { break; };
                        if frame[2] == "phoenix" { continue; }
                        if frame[0] != "1" || frame[2] != topic { continue; }
                        let payload = if frame[3] == "phx_reply" && frame[1] == "1" {
                            if frame[4]["status"] != "ok" {
                                publish(&state, json!({"revision":0,"people":[],"error":"unavailable"}));
                                return;
                            }
                            joined = true;
                            &frame[4]["response"]
                        } else if frame[3] == "snapshot" && joined {
                            &frame[4]
                        } else if frame[3] == "phx_close" || frame[3] == "phx_error" { break; }
                        else { continue; };
                        match sanitize(payload.clone()) {
                            Ok(value) => { backoff = 1; publish(&state, value); }
                            Err(_) => break,
                        }
                    }
                }
            }
        }
        publish(
            &state,
            json!({"revision":0,"people":[],"error":"disconnected"}),
        );
        tokio::select! {
            _ = tokio::time::sleep(Duration::from_secs(backoff)) => {},
            _ = control.changed() => {},
        }
        backoff = (backoff * 2).min(30);
    }
}

async fn send<S>(socket: &mut tokio_tungstenite::WebSocketStream<S>, value: Value) -> bool
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin,
{
    matches!(
        timeout(
            Duration::from_secs(5),
            socket.send(Message::Text(value.to_string().into()))
        )
        .await,
        Ok(Ok(()))
    )
}

fn sanitize(value: Value) -> Result<Value> {
    let snapshot: Snapshot = serde_json::from_value(value).map_err(|_| invalid())?;
    if snapshot.people.len() > 100 {
        return Err(invalid());
    }
    for person in &snapshot.people {
        crate::time_off::validate_id(&person.id)?;
        if person.name.len() > 500 {
            return Err(invalid());
        }
    }
    serde_json::to_value(snapshot).map_err(|_| invalid())
}

#[cfg(test)]
#[path = "orbit_live_tests.rs"]
mod tests;
