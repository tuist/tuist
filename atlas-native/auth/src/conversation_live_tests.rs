use super::*;
use crate::tests::registration;
use std::net::TcpListener;
use std::sync::mpsc;
use tokio_tungstenite::tungstenite::accept_hdr;

const ID: &str = "01922cc0-0000-7000-8000-000000000001";

fn saved() -> Session {
    Session {
        registration: registration(),
        access_token: "test-token".into(),
        refresh_token: "refresh".into(),
        expires_at: now() + 3600,
    }
}

#[test]
#[allow(clippy::result_large_err)]
fn live_conversation_joins_fixed_topic_pushes_typing_and_filters_snapshots() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let endpoint = format!(
        "ws://{}/presence/websocket?vsn=2.0.0",
        listener.local_addr().unwrap()
    );
    let (commands, events) = mpsc::channel();
    let server = std::thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        let mut socket = accept_hdr(stream, |request: &tokio_tungstenite::tungstenite::handshake::server::Request, mut response: tokio_tungstenite::tungstenite::handshake::server::Response| {
            assert_eq!(request.uri(), "/presence/websocket?vsn=2.0.0");
            assert_eq!(request.headers()["Sec-WebSocket-Protocol"], "phoenix, base64url.bearer.phx.dGVzdC10b2tlbg");
            response.headers_mut().insert("Sec-WebSocket-Protocol", "phoenix".parse().unwrap());
            Ok(response)
        }).unwrap();
        let join: Value = serde_json::from_str(socket.read().unwrap().to_text().unwrap()).unwrap();
        assert_eq!(
            join,
            json!(["1", "1", format!("conversation:{ID}"), "phx_join", {}])
        );
        let snapshot = json!({"revision":1,"people":[{"id":ID,"name":"Colleague","typing":false,"draft":"must-not-forward"}],"token":"must-not-forward"});
        socket.send(Message::Text(json!(["1","1",format!("conversation:{ID}"),"phx_reply",{"status":"ok","response":snapshot}]).to_string().into())).unwrap();
        let typing: Value =
            serde_json::from_str(socket.read().unwrap().to_text().unwrap()).unwrap();
        assert_eq!(typing[3], "typing");
        assert_eq!(typing[4], json!({"typing":true}));
        socket.send(Message::Text(json!(["1",null,format!("conversation:{ID}"),"snapshot",{"revision":2,"people":[]}]).to_string().into())).unwrap();
        events.recv_timeout(Duration::from_secs(5)).unwrap();
        assert!(matches!(socket.read().unwrap(), Message::Close(_)));
    });
    let opened = open(&endpoint, saved(), format!("conversation:{ID}")).unwrap();
    let connection = opened["connection"].as_str().unwrap().to_owned();
    let initial = execute(Action::Next {
        connection: connection.clone(),
        after: 0,
    })
    .unwrap();
    assert_eq!(initial["revision"], 1);
    assert!(!initial.to_string().contains("must-not-forward"));
    execute(Action::Typing {
        connection: connection.clone(),
        typing: true,
    })
    .unwrap();
    let pushed = execute(Action::Next {
        connection: connection.clone(),
        after: initial["sequence"].as_u64().unwrap(),
    })
    .unwrap();
    assert_eq!(pushed["revision"], 2);
    execute(Action::Close {
        connection: connection.clone(),
    })
    .unwrap();
    commands.send(()).unwrap();
    server.join().unwrap();
    assert!(get(&connection).is_err());
}

#[test]
#[allow(clippy::result_large_err)]
fn inbox_channel_pushes_invalidations_without_exposing_private_thread_data() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let endpoint = format!(
        "ws://{}/presence/websocket?vsn=2.0.0",
        listener.local_addr().unwrap()
    );
    let (commands, events) = mpsc::channel();
    let server = std::thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        let mut socket=accept_hdr(stream,|_request: &tokio_tungstenite::tungstenite::handshake::server::Request,mut response: tokio_tungstenite::tungstenite::handshake::server::Response| {
            response.headers_mut().insert("Sec-WebSocket-Protocol","phoenix".parse().unwrap());
            Ok(response)
        }).unwrap();
        let join: Value = serde_json::from_str(socket.read().unwrap().to_text().unwrap()).unwrap();
        assert_eq!(join[2], "conversations:me");
        socket.send(Message::Text(json!(["1","1","conversations:me","phx_reply",{"status":"ok","response":{"revision":10,"people":[]}}]).to_string().into())).unwrap();
        events.recv_timeout(Duration::from_secs(5)).unwrap();
        socket.send(Message::Text(json!(["1",null,"conversations:me","snapshot",{"revision":11,"people":[],"private_ids":["must-not-forward"]}]).to_string().into())).unwrap();
        events.recv_timeout(Duration::from_secs(5)).unwrap();
        assert!(matches!(socket.read().unwrap(), Message::Close(_)));
    });
    let opened = open(&endpoint, saved(), "conversations:me".into()).unwrap();
    let connection = opened["connection"].as_str().unwrap().to_owned();
    let first = execute(Action::Next {
        connection: connection.clone(),
        after: 0,
    })
    .unwrap();
    assert_eq!(first["revision"], 10);
    commands.send(()).unwrap();
    let second = execute(Action::Next {
        connection: connection.clone(),
        after: first["sequence"].as_u64().unwrap(),
    })
    .unwrap();
    assert_eq!(second["revision"], 11);
    assert!(!second.to_string().contains("must-not-forward"));
    execute(Action::Close { connection }).unwrap();
    commands.send(()).unwrap();
    server.join().unwrap();
}

#[test]
fn invalid_topics_and_credentials_are_rejected_before_opening() {
    assert!(
        execute(Action::Open {
            session: saved(),
            id: "../admin".into()
        })
        .is_err()
    );
    let mut session = saved();
    session.expires_at = 0;
    assert!(
        execute(Action::Open {
            session,
            id: ID.into()
        })
        .is_err()
    );
    assert!(
        sanitize(json!({"revision":1,"people":[{"id":"bad","name":"A","typing":false}]})).is_err()
    );
}
