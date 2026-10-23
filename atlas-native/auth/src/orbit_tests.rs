use super::*;
use crate::tests::{MockTransport, registration};
use serde_json::Value;

fn execute_using(network: &impl Transport, session: Session, action: Action) -> Result<Value> {
    match &action {
        Action::List { .. } => {
            serde_json::to_value(request_using::<Overview>(network, session, action)?)
        }
        Action::Private | Action::Create { .. } => {
            serde_json::to_value(request_using::<Created>(network, session, action)?)
        }
        Action::Messages { .. } => {
            serde_json::to_value(request_using::<History>(network, session, action)?)
        }
        Action::Send { .. } => {
            serde_json::to_value(request_using::<Sent>(network, session, action)?)
        }
    }
    .map_err(|_| invalid())
}

fn saved() -> Session {
    Session {
        registration: registration(),
        access_token: "atlas-access".into(),
        refresh_token: "atlas-refresh".into(),
        expires_at: now() + 3600,
    }
}

const ID: &str = "01922cc0-0000-7000-8000-000000000001";

fn thread() -> Value {
    json!({"id":ID,"title":"Investigate latency","kind":"shared","status":"active","summary":"Comparing plans","origin":"manual","owner_id":ID,"participants":[{"id":ID,"name":"A colleague","email":"must-not-forward"}],"updated_at":"2027-06-07T10:00:00Z","credentials":"must-not-forward"})
}

fn message() -> Value {
    json!({"id":ID,"kind":"human","body":"Please investigate","author_id":ID,"author_name":"A colleague","inserted_at":"2027-06-07T10:00:00Z","provider_token":"must-not-forward"})
}

#[test]
fn fixed_routes_use_selected_instance_and_filter_payloads() {
    let cases = [
        (
            Action::List { page: 2 },
            "GET",
            "?page=2".to_owned(),
            Value::Null,
            json!({"assistant":{"name":"Pip","configured":true,"token":"must-not-forward"},"threads":{"items":[thread()],"page":2,"total_pages":2,"total_count":26}}),
        ),
        (
            Action::Private,
            "POST",
            "/private".into(),
            json!({}),
            json!({"thread":thread()}),
        ),
        (
            Action::Create {
                title: "Investigate latency".into(),
                participant_ids: vec![ID.into()],
            },
            "POST",
            "".into(),
            json!({"title":"Investigate latency","participant_ids":[ID]}),
            json!({"thread":thread()}),
        ),
        (
            Action::Messages {
                id: ID.into(),
                page: 1,
            },
            "GET",
            format!("/{ID}/messages?page=1"),
            Value::Null,
            json!({"thread":thread(),"messages":{"items":[message()],"page":1,"total_pages":1,"total_count":1}}),
        ),
        (
            Action::Send {
                id: ID.into(),
                body: "Please investigate".into(),
                client_id: ID.into(),
                address_agent: true,
            },
            "POST",
            format!("/{ID}/messages"),
            json!({"body":"Please investigate","client_id":ID,"address_agent":true}),
            json!({"message":message()}),
        ),
    ];
    for (action, method, suffix, payload, response) in cases {
        let network = MockTransport::new(vec![response]);
        let value = execute_using(&network, saved(), action).unwrap();
        assert!(!value.to_string().contains("must-not-forward"));
        let requests = network.requests.borrow();
        assert_eq!(
            requests[0].0,
            format!("https://atlas.example/api/native/orbit/threads{suffix}")
        );
        assert_eq!(requests[0].1["method"], method);
        assert_eq!(requests[0].1["payload"], payload);
        assert_eq!(requests[0].1["token"], "atlas-access");
    }
}

#[test]
fn invalid_paths_pages_and_messages_never_leave_device() {
    let network = MockTransport::new(vec![]);
    for action in [
        Action::Messages {
            id: "../admin".into(),
            page: 1,
        },
        Action::Messages {
            id: ID.into(),
            page: 0,
        },
        Action::List { page: 0 },
        Action::Create {
            title: " ".into(),
            participant_ids: vec![],
        },
        Action::Create {
            title: "Title".into(),
            participant_ids: vec!["https://evil.example".into()],
        },
        Action::Send {
            id: ID.into(),
            body: " ".into(),
            client_id: ID.into(),
            address_agent: false,
        },
        Action::Send {
            id: ID.into(),
            body: "x".repeat(16001),
            client_id: ID.into(),
            address_agent: false,
        },
        Action::Send {
            id: ID.into(),
            body: "Hello".into(),
            client_id: "bad".into(),
            address_agent: false,
        },
    ] {
        assert!(execute_using(&network, saved(), action).is_err());
    }
    assert!(network.requests.borrow().is_empty());
}

#[test]
fn expired_session_and_cross_origin_registration_never_send_credentials() {
    let network = MockTransport::new(vec![]);
    for field in ["expired", "empty", "origin"] {
        let mut session = saved();
        match field {
            "expired" => session.expires_at = 0,
            "empty" => session.access_token.clear(),
            _ => session.registration.token_endpoint = "https://evil.example/token".into(),
        }
        assert!(execute_using(&network, session, Action::Private).is_err());
    }
    assert!(network.requests.borrow().is_empty());
}

#[test]
fn errors_do_not_echo_provider_or_thread_bodies() {
    for status in [401, 403, 404, 409, 422, 429, 500, 501] {
        assert!(
            !serde_json::to_string(&response_failure(status, b"confidential-body"))
                .unwrap()
                .contains("confidential-body")
        );
    }
}
