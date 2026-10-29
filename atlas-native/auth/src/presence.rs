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

#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Resource {
    Tasks,
    Accounts,
    Invoices,
    People,
    TimeOff,
    Profile,
}

#[derive(Clone, Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Location {
    #[serde(skip_serializing_if = "Option::is_none")]
    resource: Option<Resource>,
    #[serde(skip_serializing_if = "Option::is_none")]
    id: Option<String>,
}

#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub(crate) enum Action {
    Open {
        session: Session,
    },
    Update {
        connection: String,
        #[serde(flatten)]
        location: Location,
    },
    Next {
        connection: String,
        after: u64,
    },
    Close {
        connection: String,
    },
}

#[derive(Deserialize, Serialize)]
struct Person {
    id: String,
    name: String,
    email: String,
    online: bool,
    here: bool,
}

#[derive(Deserialize, Serialize)]
struct Snapshot {
    self_id: String,
    people: Vec<Person>,
}

#[derive(Clone, Default)]
struct Control {
    location: Location,
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
        Action::Open { session } => {
            let mut url = validate_registration(&session.registration)?;
            if session.expires_at <= now() || session.access_token.is_empty() {
                return Err(error("sign_in_required", "Sign in to Atlas again."));
            }
            url.set_scheme("wss").map_err(|_| invalid())?;
            url.set_path("/presence/websocket");
            url.set_query(Some("vsn=2.0.0"));
            open(url.as_str(), session)
        }
        Action::Update {
            connection,
            location,
        } => {
            validate_location(&location)?;
            let connection = get(&connection)?;
            connection
                .control
                .send_modify(|control| control.location = location);
            Ok(json!({"updated":true}))
        }
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
            let mut value = latest.clone();
            value["connection"] = json!(connection);
            Ok(value)
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

fn validate_location(location: &Location) -> Result<()> {
    if let Some(id) = &location.id {
        crate::time_off::validate_id(id)?;
        if !matches!(
            location.resource,
            Some(Resource::Tasks | Resource::Accounts | Resource::Invoices)
        ) {
            return Err(invalid());
        }
    }
    Ok(())
}

fn get(id: &str) -> Result<Arc<Connection>> {
    connections()
        .lock()
        .map_err(|_| invalid())?
        .get(id)
        .cloned()
        .ok_or_else(|| error("closed", "Presence is disconnected."))
}

fn open(url: &str, session: Session) -> Result<Value> {
    let mut request = url.into_client_request().map_err(|_| invalid())?;
    let protocol = format!(
        "phoenix, base64url.bearer.phx.{}",
        URL_SAFE_NO_PAD.encode(&session.access_token)
    );
    request.headers_mut().insert(
        "Sec-WebSocket-Protocol",
        protocol.parse().map_err(|_| invalid())?,
    );
    let id = new_connection()?;
    let (control, receiver) = watch::channel(Control::default());
    let state = Arc::new(Connection {
        control,
        latest: Mutex::new(json!({"sequence":0,"people":[]})),
        changed: Condvar::new(),
    });
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|_| error("internal", "Could not start presence."))?;
    let mut registry = connections().lock().map_err(|_| invalid())?;
    if registry.len() >= 16 {
        return Err(error("internal", "Too many presence connections."));
    }
    registry.insert(id.clone(), state.clone());
    std::thread::spawn(move || runtime.block_on(run(request, session.expires_at, receiver, state)));
    Ok(json!({"connection":id}))
}

fn publish(state: &Connection, mut value: Value) {
    if let Ok(mut latest) = state.latest.lock() {
        value["sequence"] = json!(latest["sequence"].as_u64().unwrap_or(0) + 1);
        *latest = value;
        state.changed.notify_all();
    }
}

type Socket =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

pub(super) async fn connect_tls(
    request: tokio_tungstenite::tungstenite::handshake::client::Request,
    config: WebSocketConfig,
    tls: tokio_tungstenite::Connector,
) -> std::result::Result<
    (
        Socket,
        tokio_tungstenite::tungstenite::handshake::client::Response,
    ),
    tokio_tungstenite::tungstenite::Error,
> {
    tokio_tungstenite::connect_async_tls_with_config(request, Some(config), true, Some(tls)).await
}

async fn run(
    request: tokio_tungstenite::tungstenite::http::Request<()>,
    expires_at: u64,
    mut control: watch::Receiver<Control>,
    state: Arc<Connection>,
) {
    let tls = match crate::transport::tls_config() {
        Ok(config) => tokio_tungstenite::Connector::Rustls(Arc::new(config)),
        Err(_) => {
            publish(
                &state,
                json!({"people":[],"error":"secure_connection_failed"}),
            );
            return;
        }
    };
    let mut backoff = 1;
    loop {
        if control.borrow().closed {
            return;
        }
        if now() >= expires_at {
            publish(
                &state,
                json!({"people":[],"error":"sign_in_required","needs_session":true}),
            );
            return;
        }
        let config = WebSocketConfig::default()
            .max_message_size(Some(1024 * 1024))
            .max_frame_size(Some(1024 * 1024));
        let connected = tokio::select! {
            value = timeout(Duration::from_secs(10), connect_tls(request.clone(), config, tls.clone())) => value,
            _ = control.changed() => continue,
        };
        let mut socket = match connected {
            Ok(Ok((socket, _response))) => socket,
            Ok(Err(ref error))
                if matches!(error, tokio_tungstenite::tungstenite::Error::Tls(_))
                    || crate::certificate_trust::tls_failure(error) =>
            {
                publish(
                    &state,
                    json!({"people":[],"error":"secure_connection_failed"}),
                );
                return;
            }
            _ => {
                publish(&state, json!({"people":[],"error":"disconnected"}));
                tokio::select! {
                    _ = tokio::time::sleep(Duration::from_secs(backoff)) => {},
                    _ = control.changed() => {},
                }
                backoff = (backoff * 2).min(30);
                continue;
            }
        };
        let mut location = control.borrow_and_update().location.clone();
        let join = json!(["1", "1", "presence:team", "phx_join", location]);
        if !send(&mut socket, join).await {
            continue;
        }
        let mut pending = Some("1".to_owned());
        let mut reference = 1_u64;
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
                    pending = Some(reference.to_string());
                    location = next.location;
                    if !send(&mut socket, json!(["1",reference.to_string(),"presence:team","location",location])).await { break; }
                }
                _ = heartbeat.tick() => {
                    if now() >= expires_at { break; }
                    if last_received.elapsed() > Duration::from_secs(30) { break; }
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
                    if frame[0] != "1" || frame[2] != "presence:team" { continue; }
                    let payload = if frame[3] == "phx_reply" {
                        if frame[4]["status"] != "ok" { break; }
                        if frame[1].as_str() != pending.as_deref() { continue; }
                        pending = None;
                        &frame[4]["response"]
                    } else if frame[3] == "snapshot" && pending.is_none() {
                        &frame[4]
                    } else if frame[3] == "phx_close" || frame[3] == "phx_error" {
                        break;
                    } else { continue; };
                    match sanitize(payload.clone()) {
                        Ok(mut value) => {
                            value["location"] = json!(location);
                            backoff = 1;
                            publish(&state, value);
                        }
                        Err(_) => break,
                    }
                }
            }
        }
        publish(&state, json!({"people":[],"error":"disconnected"}));
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
    let mut snapshot: Snapshot = serde_json::from_value(value).map_err(|_| invalid())?;
    crate::time_off::validate_id(&snapshot.self_id)?;
    for person in &mut snapshot.people {
        crate::time_off::validate_id(&person.id)?;
        person.here &= person.online && person.id != snapshot.self_id;
    }
    serde_json::to_value(snapshot).map_err(|_| invalid())
}

fn new_connection() -> Result<String> {
    let mut bytes = [0_u8; 16];
    getrandom::fill(&mut bytes).map_err(|_| error("internal", "Could not start presence."))?;
    Ok(bytes.iter().map(|byte| format!("{byte:02x}")).collect())
}

#[cfg(test)]
#[path = "presence_tests.rs"]
mod tests;
