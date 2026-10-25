use super::*;
use crate::tests::{MockTransport, registration};
use serde_json::Value;

fn execute_using(network: &impl Transport, session: Session, action: Action) -> Result<Value> {
    match &action {
        Action::List { .. } => {
            serde_json::to_value(request_using::<Overview>(network, session, action)?)
        }
        Action::Private | Action::CreatePrivate { .. } | Action::Create { .. } => {
            serde_json::to_value(request_using::<Created>(network, session, action)?)
        }
        Action::Messages { .. } => {
            serde_json::to_value(request_using::<History>(network, session, action)?)
        }
        Action::People { .. } => {
            serde_json::to_value(request_using::<People>(network, session, action)?)
        }
        Action::Send { .. } => {
            serde_json::to_value(request_using::<Sent>(network, session, action)?)
        }
        Action::UploadAttachment { .. } => {
            serde_json::to_value(request_using::<Attached>(network, session, action)?)
        }
        Action::DownloadAttachment { .. } => {
            serde_json::to_value(request_using::<Downloaded>(network, session, action)?)
        }
        Action::DeleteAttachment { .. } => return request_using(network, session, action),
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
            Action::List {
                page: 2,
                kind: None,
            },
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
            Action::List {
                page: 1,
                kind: Some("private".into()),
            },
            "GET",
            "?page=1&kind=private".into(),
            Value::Null,
            json!({"assistant":{"name":"Pip","configured":true,"can_create_private":true},"threads":{"items":[],"page":1,"total_pages":1,"total_count":0}}),
        ),
        (
            Action::CreatePrivate {
                request_id: ID.into(),
            },
            "POST",
            "".into(),
            json!({"kind":"private","request_id":ID}),
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
            Action::People {
                id: ID.into(),
                query: "Ali & Bob".into(),
            },
            "GET",
            format!("/{ID}/people?query=Ali+%26+Bob"),
            Value::Null,
            json!({"people":[{"id":ID,"name":"Alice Smith","email":"must-not-forward"}]}),
        ),
        (
            Action::Send {
                id: ID.into(),
                body: "@Alice Smith please investigate".into(),
                client_id: ID.into(),
                address_agent: false,
                attachment_ids: vec![],
                mention_ids: vec![ID.into()],
            },
            "POST",
            format!("/{ID}/messages"),
            json!({"body":"@Alice Smith please investigate","client_id":ID,"address_agent":false,"attachment_ids":[],"mention_ids":[ID]}),
            json!({"message":message()}),
        ),
        (
            Action::Send {
                id: ID.into(),
                body: "Please investigate".into(),
                client_id: ID.into(),
                address_agent: true,
                attachment_ids: vec![],
                mention_ids: vec![],
            },
            "POST",
            format!("/{ID}/messages"),
            json!({"body":"Please investigate","client_id":ID,"address_agent":true,"attachment_ids":[]}),
            json!({"message":message()}),
        ),
    ];
    for (action, method, suffix, payload, response) in cases {
        let network = MockTransport::new(vec![response]);
        let value = execute_using(&network, saved(), action).unwrap();
        assert!(!value.to_string().contains("must-not-forward"));
        if value.get("assistant").is_some() {
            assert_eq!(
                value["assistant"]["can_create_private"],
                suffix.contains("kind=private")
            );
        }
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
        Action::List {
            page: 0,
            kind: None,
        },
        Action::List {
            page: 1,
            kind: Some("../admin".into()),
        },
        Action::CreatePrivate {
            request_id: "not-a-uuid".into(),
        },
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
            attachment_ids: vec![],
            mention_ids: vec![],
        },
        Action::Send {
            id: ID.into(),
            body: "x".repeat(16001),
            client_id: ID.into(),
            address_agent: false,
            attachment_ids: vec![],
            mention_ids: vec![],
        },
        Action::Send {
            id: ID.into(),
            body: "Hello".into(),
            client_id: "bad".into(),
            address_agent: false,
            attachment_ids: vec![],
            mention_ids: vec![],
        },
    ] {
        assert!(execute_using(&network, saved(), action).is_err());
    }
    for query in ["x".repeat(101), "line\nbreak".into()] {
        assert!(
            execute_using(
                &network,
                saved(),
                Action::People {
                    id: ID.into(),
                    query
                }
            )
            .is_err()
        );
    }
    assert!(
        execute_using(
            &network,
            saved(),
            Action::People {
                id: "../admin".into(),
                query: "".into()
            }
        )
        .is_err()
    );
    for mention_ids in [
        vec!["../user".into()],
        vec![ID.into(); 11],
        vec![ID.into(); 2],
    ] {
        assert!(
            execute_using(
                &network,
                saved(),
                Action::Send {
                    id: ID.into(),
                    body: "Hello".into(),
                    client_id: ID.into(),
                    address_agent: false,
                    attachment_ids: vec![],
                    mention_ids,
                }
            )
            .is_err()
        );
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

#[test]
fn attachment_routes_are_fixed_authenticated_and_filter_download_metadata() {
    let metadata = json!({"id":ID,"filename":"report.txt","content_type":"text/plain","byte_size":5,"url":"must-not-forward"});
    let network = MockTransport::new(vec![
        json!({"attachment":metadata}),
        json!({"attachment":{
            "id":ID,"filename":"report.txt","content_type":"text/plain","byte_size":5,"data":"aGVsbG8=","url":"must-not-forward"
        }}),
        json!({"deleted":true}),
    ]);
    for action in [
        Action::UploadAttachment {
            id: ID.into(),
            client_id: ID.into(),
            filename: "report.txt".into(),
            content_type: "text/plain".into(),
            data: "aGVsbG8=".into(),
        },
        Action::DownloadAttachment {
            id: ID.into(),
            attachment_id: ID.into(),
        },
        Action::DeleteAttachment {
            id: ID.into(),
            attachment_id: ID.into(),
        },
    ] {
        assert!(
            !execute_using(&network, saved(), action)
                .unwrap()
                .to_string()
                .contains("must-not-forward")
        );
    }
    let requests = network.requests.borrow();
    assert_eq!(
        requests[0].0,
        format!("https://atlas.example/api/native/orbit/threads/{ID}/attachments")
    );
    assert_eq!(requests[0].1["payload"]["client_id"], ID);
    assert_eq!(
        requests[1].0,
        format!("https://atlas.example/api/native/orbit/threads/{ID}/attachments/{ID}")
    );
    assert_eq!(requests[1].1["attachment"], true);
    assert_eq!(requests[1].1["token"], "atlas-access");
    assert_eq!(requests[2].1["method"], "DELETE");
    // Older servers omit the array and remain readable.
    assert!(
        serde_json::from_value::<Message>(message())
            .unwrap()
            .attachments
            .is_empty()
    );
}

#[test]
fn attachment_validation_rejects_paths_names_sizes_types_and_base64_before_network() {
    for name in [
        "../secret",
        "a/b",
        "a\\b",
        "a\n.txt",
        "\u{202e}txt.exe",
        "",
        "..",
    ] {
        assert!(validate_file(name, "text/plain", 5).is_err());
    }
    for size in [0, MAX_ATTACHMENT_BYTES + 1] {
        assert!(validate_file("report.txt", "text/plain", size).is_err());
    }
    assert!(validate_file("report.txt", "text/plain\r\nX:y", 5).is_err());
    assert!(decode_attachment("aGVsbG8=\n").is_err());
    let largest = STANDARD.encode(vec![1; MAX_ATTACHMENT_BYTES]);
    assert_eq!(
        decode_attachment(&largest).unwrap().len(),
        MAX_ATTACHMENT_BYTES
    );
    assert!(decode_attachment(&STANDARD.encode(vec![1; MAX_ATTACHMENT_BYTES + 1])).is_err());
    assert!(validate_attachment_ids(&vec![ID.into(); 5]).is_err());
    assert!(validate_attachment_ids(&[ID.into(), ID.into()]).is_err());
    let network = MockTransport::new(vec![]);
    for action in [
        Action::DownloadAttachment {
            id: ID.into(),
            attachment_id: "../secret".into(),
        },
        Action::UploadAttachment {
            id: ID.into(),
            client_id: ID.into(),
            filename: "../file".into(),
            content_type: "text/plain".into(),
            data: "aGVsbG8=".into(),
        },
    ] {
        assert!(execute_using(&network, saved(), action).is_err());
    }
    assert!(network.requests.borrow().is_empty());
}

#[test]
fn parent_links_are_optional_validated_uuid_metadata_not_inferred_hierarchy() {
    assert!(
        serde_json::from_value::<Message>(message())
            .unwrap()
            .parent_message_id
            .is_none()
    );
    for parent in [json!(ID), json!(null), json!("../other-thread"), json!(42)] {
        let mut value = message();
        value["parent_message_id"] = parent.clone();
        let parsed: Message = serde_json::from_value(value).unwrap();
        assert_eq!(
            parsed.parent_message_id.as_deref(),
            if parent == ID { Some(ID) } else { None }
        );
        assert_eq!(parsed.body, "Please investigate");
    }
    let legacy: Message = serde_json::from_value(message()).unwrap();
    assert!(legacy.notice_kind.is_none());
    assert!(legacy.mentioned_user_ids.is_empty());
    for notice in [
        json!("handoff"),
        json!(null),
        json!(42),
        json!({"kind":"handoff"}),
        json!("unknown"),
    ] {
        let mut value = message();
        value["notice_kind"] = notice.clone();
        value["mentioned_user_ids"] = json!([ID, 42, "../user", ID, null]);
        let parsed: Message = serde_json::from_value(value).unwrap();
        assert_eq!(
            parsed.notice_kind.as_deref(),
            if notice == "handoff" {
                Some("handoff")
            } else {
                None
            }
        );
        assert_eq!(parsed.mentioned_user_ids, vec![ID]);
    }
    for ids in [json!(null), json!(42), json!("not-an-array")] {
        let mut value = message();
        value["mentioned_user_ids"] = ids;
        assert!(
            serde_json::from_value::<Message>(value)
                .unwrap()
                .mentioned_user_ids
                .is_empty()
        );
    }
    let mut choices = vec![
        json!({"id":"../invalid","name":"No"}),
        json!({"id":ID,"name":42}),
    ];
    choices.extend((1..=25).map(|index| json!({"id":format!("01922cc0-0000-7000-8000-{index:012}"),"name":"A colleague","email":"must-not-forward"})));
    let people: People = serde_json::from_value(json!({"people":choices})).unwrap();
    assert_eq!(people.people.len(), 20);
    assert!(
        !serde_json::to_string(&people)
            .unwrap()
            .contains("must-not-forward")
    );
}
