use super::*;
use crate::tests::registration;
use std::net::{TcpListener, TcpStream};
use std::sync::mpsc;
use tokio_tungstenite::tungstenite::{WebSocket, accept_hdr};

const SELF: &str = "01922cc0-0000-7000-8000-000000000001";
const OTHER: &str = "01922cc0-0000-7000-8000-000000000002";

fn saved() -> Session {
    Session {
        registration: registration(),
        access_token: "test-token".into(),
        refresh_token: "refresh".into(),
        expires_at: now() + 3600,
    }
}

fn response(online: bool) -> Value {
    json!({"self_id":SELF,"secret":"never-forward", "people":[
        {"id":SELF,"name":"Me","email":"me@example.org","online":true,"here":true},
        {"id":OTHER,"name":"Colleague","email":"other@example.org","online":online,"here":true,"location":"never-forward"}
    ]})
}

#[allow(clippy::result_large_err)] // The upstream handshake callback fixes the error type.
fn accept(listener: &TcpListener) -> WebSocket<TcpStream> {
    let (stream, _) = listener.accept().unwrap();
    stream
        .set_read_timeout(Some(Duration::from_secs(5)))
        .unwrap();
    accept_hdr(
        stream,
        |request: &tokio_tungstenite::tungstenite::handshake::server::Request,
         mut response: tokio_tungstenite::tungstenite::handshake::server::Response| {
            assert_eq!(request.uri(), "/presence/websocket?vsn=2.0.0");
            assert_eq!(
                request.headers()["Sec-WebSocket-Protocol"],
                "phoenix, base64url.bearer.phx.dGVzdC10b2tlbg"
            );
            response
                .headers_mut()
                .insert("Sec-WebSocket-Protocol", "phoenix".parse().unwrap());
            Ok(response)
        },
    )
    .unwrap()
}

fn receive(socket: &mut WebSocket<TcpStream>) -> Value {
    serde_json::from_str(socket.read().unwrap().to_text().unwrap()).unwrap()
}

fn reply(socket: &mut WebSocket<TcpStream>, reference: &Value, payload: Value) {
    socket
        .send(Message::Text(
            json!(["1",reference,"presence:team","phx_reply",{"status":"ok","response":payload}])
                .to_string()
                .into(),
        ))
        .unwrap();
}

fn next(id: &str, after: u64) -> Value {
    let value = crate::bridge::execute(
        &json!({"operation":"presence","action":"next","connection":id,"after":after}).to_string(),
    );
    let envelope: Value = serde_json::from_str(&value).unwrap();
    assert!(envelope["error"].is_null(), "{envelope}");
    envelope["ok"].clone()
}

#[test]
fn websocket_pushes_location_replies_reconnects_and_close_wakes_a_waiter() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let endpoint = format!(
        "ws://{}/presence/websocket?vsn=2.0.0",
        listener.local_addr().unwrap()
    );
    let (commands, events) = mpsc::channel();
    let (ready, proceed) = mpsc::channel();
    let server = std::thread::spawn(move || {
        let mut socket = accept(&listener);
        let join = receive(&mut socket);
        assert_eq!(join, json!(["1", "1", "presence:team", "phx_join", {}]));
        reply(&mut socket, &join[1], response(false));
        events.recv_timeout(Duration::from_secs(5)).unwrap();
        socket
            .send(Message::Text(
                json!(["1", null, "presence:team", "snapshot", response(true)])
                    .to_string()
                    .into(),
            ))
            .unwrap();
        let update = receive(&mut socket);
        assert_eq!(update[3], "location");
        assert_eq!(update[4], json!({"resource":"accounts","id":OTHER}));
        reply(&mut socket, &update[1], response(true));
        events.recv_timeout(Duration::from_secs(5)).unwrap();
        drop(socket);
        let mut socket = accept(&listener);
        let join = receive(&mut socket);
        assert_eq!(join[4], json!({"resource":"accounts","id":OTHER}));
        reply(&mut socket, &join[1], response(false));
        ready.send(()).unwrap();
        events.recv_timeout(Duration::from_secs(5)).unwrap();
        assert!(matches!(socket.read().unwrap(), Message::Close(_)));
    });
    let opened = open(&endpoint, saved()).unwrap();
    let id = opened["connection"].as_str().unwrap().to_owned();
    let initial = next(&id, 0);
    assert_eq!(initial["people"][0]["here"], false);
    assert_eq!(initial["people"][1]["online"], false);
    assert_eq!(initial["people"][1]["here"], false);
    assert!(!initial.to_string().contains("never-forward"));
    commands.send(()).unwrap();
    let pushed = next(&id, initial["sequence"].as_u64().unwrap());
    assert_eq!(pushed["people"][1]["online"], true);
    let update = crate::bridge::execute(&json!({"operation":"presence","action":"update","connection":id,"resource":"accounts","id":OTHER}).to_string());
    assert_eq!(
        serde_json::from_str::<Value>(&update).unwrap()["ok"],
        json!({"updated":true})
    );
    let updated = next(&id, pushed["sequence"].as_u64().unwrap());
    assert_eq!(
        updated["location"],
        json!({"resource":"accounts","id":OTHER})
    );
    commands.send(()).unwrap();
    proceed.recv_timeout(Duration::from_secs(5)).unwrap();
    let mut reconnected = next(&id, updated["sequence"].as_u64().unwrap());
    if reconnected["error"].is_string() {
        reconnected = next(&id, reconnected["sequence"].as_u64().unwrap());
    }
    assert_eq!(reconnected["people"][1]["online"], false);
    let sequence = reconnected["sequence"].as_u64().unwrap();
    let waiting_id = id.clone();
    let (done, finished) = mpsc::channel();
    let waiter = std::thread::spawn(move || {
        done.send(execute(Action::Next {
            connection: waiting_id,
            after: sequence,
        }))
        .unwrap();
    });
    // The close may race before next acquires the handle; either outcome is bounded.
    execute(Action::Close {
        connection: id.clone(),
    })
    .unwrap();
    commands.send(()).unwrap();
    match finished.recv_timeout(Duration::from_secs(2)).unwrap() {
        Ok(value) => assert_eq!(value["sequence"], sequence),
        Err(failure) => assert_eq!(failure.kind, "closed"),
    }
    waiter.join().unwrap();
    server.join().unwrap();
    assert!(get(&id).is_err());
}

#[test]
fn location_free_fallback_keeps_the_roster_connected_and_allows_navigation() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let endpoint = format!(
        "ws://{}/presence/websocket?vsn=2.0.0",
        listener.local_addr().unwrap()
    );
    let (commands, events) = mpsc::channel();
    let server = std::thread::spawn(move || {
        let mut socket = accept(&listener);
        let join = receive(&mut socket);
        reply(&mut socket, &join[1], response(false));
        let restricted = receive(&mut socket);
        assert_eq!(restricted[4], json!({"resource":"invoices"}));
        // The server keeps authenticated availability but withholds location hints.
        let mut fallback = response(true);
        fallback["people"][1]["here"] = json!(false);
        reply(&mut socket, &restricted[1], fallback);
        let allowed = receive(&mut socket);
        assert_eq!(allowed[4], json!({"resource":"tasks"}));
        reply(&mut socket, &allowed[1], response(true));
        events.recv_timeout(Duration::from_secs(5)).unwrap();
        assert!(matches!(socket.read().unwrap(), Message::Close(_)));
    });
    let opened = open(&endpoint, saved()).unwrap();
    let id = opened["connection"].as_str().unwrap().to_owned();
    let initial = next(&id, 0);
    execute(Action::Update {
        connection: id.clone(),
        location: serde_json::from_value(json!({"resource":"invoices"})).unwrap(),
    })
    .unwrap();
    let fallback = next(&id, initial["sequence"].as_u64().unwrap());
    assert!(fallback["error"].is_null());
    assert_eq!(fallback["location"], json!({"resource":"invoices"}));
    assert_eq!(fallback["people"][0]["online"], true);
    assert_eq!(fallback["people"][1]["online"], true);
    assert_eq!(fallback["people"][1]["here"], false);
    execute(Action::Update {
        connection: id.clone(),
        location: serde_json::from_value(json!({"resource":"tasks"})).unwrap(),
    })
    .unwrap();
    let allowed = next(&id, fallback["sequence"].as_u64().unwrap());
    assert_eq!(allowed["location"], json!({"resource":"tasks"}));
    assert_eq!(allowed["people"][1]["here"], true);
    execute(Action::Close { connection: id }).unwrap();
    commands.send(()).unwrap();
    server.join().unwrap();
}

#[test]
fn rejects_unsafe_locations_and_expired_credentials_without_networking() {
    for value in [
        json!({"resource":"people","id":OTHER}),
        json!({"id":OTHER}),
        json!({"resource":"accounts","id":"../../admin"}),
    ] {
        let location = serde_json::from_value(value).unwrap();
        assert!(validate_location(&location).is_err());
    }
    assert!(serde_json::from_value::<Location>(json!({"path":"/admin"})).is_err());
    let mut session = saved();
    session.expires_at = 0;
    assert_eq!(
        execute(Action::Open { session }).unwrap_err().kind,
        "sign_in_required"
    );
}
