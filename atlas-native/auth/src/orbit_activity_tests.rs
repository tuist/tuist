use super::*;
use crate::tests::{MockTransport, registration};

const ID: &str = "01922cc0-0000-7000-8000-000000000001";
const SECOND_ID: &str = "01922cc0-0000-7000-8000-000000000002";
const THIRD_ID: &str = "01922cc0-0000-7000-8000-000000000003";

fn session() -> Session {
    Session {
        registration: registration(),
        access_token: "atlas-access".into(),
        refresh_token: "atlas-refresh".into(),
        expires_at: now() + 3600,
    }
}

fn register() -> Action {
    Action::Register {
        registration_id: ID.into(),
        token: "ab".repeat(32),
        environment: Environment::Production,
    }
}

fn unregister() -> Action {
    Action::Unregister {
        registration_id: ID.into(),
    }
}

fn status() -> Value {
    json!({
        "available": true,
        "content": {
            "active_count": 1,
            "conversations": [{
                "id": ID,
                "status": "running",
                "started_at": 1_790_000_000,
                "completed_steps": 2
            }],
            "updated_at": 1_790_000_060
        }
    })
}

#[test]
fn status_uses_only_fixed_bearer_get_and_filters_every_response_level() {
    let mut expected = status();
    expected["content"]["conversations"][0]["title"] = json!("Cash flow forecast");
    let mut response = expected.clone();
    response["owner_id"] = json!(SECOND_ID);
    response["token"] = json!("private-device-token");
    response["content"]["title"] = json!("Private conversation title");
    response["content"]["url"] = json!("https://private.example");
    response["content"]["conversations"][0]["messages"] = json!(["secret message"]);
    response["content"]["conversations"][0]["tool_output"] = json!("secret result");
    let network = MockTransport::new(vec![response]);
    assert_eq!(
        execute_using(&network, session(), Action::Status {}).unwrap(),
        expected
    );
    assert_eq!(
        *network.requests.borrow(),
        vec![(
            "https://atlas.example/api/me/orbit-live-activity".into(),
            json!({"method":"GET","token":"atlas-access","payload":null})
        )]
    );
}

#[test]
fn register_uses_exact_bearer_put_payload_and_filters_confirmation() {
    for (environment, name, token) in [
        (Environment::Sandbox, "sandbox", "AB".repeat(16)),
        (Environment::Production, "production", "ab".repeat(256)),
    ] {
        let network = MockTransport::new(vec![json!({
            "registered":true,"registration_id":ID,"token":"private-token","topic":"private-topic"
        })]);
        assert_eq!(
            execute_using(
                &network,
                session(),
                Action::Register {
                    registration_id: ID.into(),
                    token: token.clone(),
                    environment,
                }
            )
            .unwrap(),
            json!({"registered":true})
        );
        assert_eq!(
            *network.requests.borrow(),
            vec![(
                format!("https://atlas.example/api/me/orbit-live-activity/{ID}"),
                json!({"method":"PUT","token":"atlas-access","payload":{"token":token,"environment":name}})
            )]
        );
    }
}

#[test]
fn unregister_uses_fixed_bearer_delete_without_payload_or_provider_token() {
    let network = MockTransport::new(vec![json!({"deleted":true,"token":"private-token"})]);
    assert_eq!(
        execute_using(&network, session(), unregister()).unwrap(),
        json!({"deleted":true})
    );
    assert_eq!(
        *network.requests.borrow(),
        vec![(
            format!("https://atlas.example/api/me/orbit-live-activity/{ID}"),
            json!({"method":"DELETE","token":"atlas-access","payload":null})
        )]
    );
}

#[test]
fn all_allowlisted_work_states_are_preserved() {
    for (state, title) in [
        ("queued", "Cash flow forecast".to_owned()),
        ("running", "Berlin team holiday plan".to_owned()),
        ("compacting", "😀".repeat(80)),
        ("using_tools", "e\u{301}".repeat(40)),
    ] {
        let mut response = status();
        response["content"]["conversations"][0]["status"] = json!(state);
        response["content"]["conversations"][0]["title"] = json!(title);
        let network = MockTransport::new(vec![response.clone()]);
        assert_eq!(
            execute_using(&network, session(), Action::Status {}).unwrap(),
            response
        );
    }
}

#[test]
fn empty_unavailable_and_three_entry_aggregate_snapshots_are_supported() {
    let mut empty = status();
    empty["available"] = json!(false);
    empty["content"] = json!({"active_count":0,"conversations":[],"updated_at":0});
    let mut full = status();
    let mut second = full["content"]["conversations"][0].clone();
    second["id"] = json!(SECOND_ID);
    let mut third = second.clone();
    third["id"] = json!(THIRD_ID);
    full["content"]["conversations"]
        .as_array_mut()
        .unwrap()
        .extend([second, third]);
    full["content"]["active_count"] = json!(7);
    for response in [empty, full, status()] {
        let network = MockTransport::new(vec![response.clone()]);
        assert_eq!(
            execute_using(&network, session(), Action::Status {}).unwrap(),
            response
        );
    }
    let mut nullable = status();
    nullable["content"]["conversations"][0]["title"] = Value::Null;
    let network = MockTransport::new(vec![nullable]);
    assert_eq!(
        execute_using(&network, session(), Action::Status {}).unwrap(),
        status()
    );
}

#[test]
fn count_and_timestamp_upper_bounds_are_supported_without_truncation() {
    let mut response = status();
    response["content"]["active_count"] = json!(MAX_COUNT);
    response["content"]["updated_at"] = json!(MAX_TIMESTAMP);
    response["content"]["conversations"][0]["completed_steps"] = json!(MAX_COUNT);
    response["content"]["conversations"][0]["started_at"] = json!(MAX_TIMESTAMP);
    let network = MockTransport::new(vec![response.clone()]);
    assert_eq!(
        execute_using(&network, session(), Action::Status {}).unwrap(),
        response
    );
}

#[test]
fn invalid_scalar_types_and_bounds_fail_closed_without_echoing_response_data() {
    for (pointer, value) in [
        ("/available", json!("true")),
        ("/content/active_count", json!(-1)),
        ("/content/active_count", json!(0)),
        ("/content/active_count", json!(1.5)),
        ("/content/active_count", json!(MAX_COUNT as u64 + 1)),
        ("/content/active_count", json!(u64::MAX)),
        ("/content/updated_at", json!(-1)),
        ("/content/updated_at", json!(MAX_TIMESTAMP + 1)),
        ("/content/updated_at", json!(1_790_000_060.5)),
        ("/content/updated_at", json!("1790000060")),
        ("/content/conversations/0/started_at", json!(-1)),
        ("/content/conversations/0/started_at", json!(1_790_000_061)),
        ("/content/conversations/0/started_at", json!(u64::MAX)),
        ("/content/conversations/0/completed_steps", json!(-1)),
        ("/content/conversations/0/completed_steps", json!(0.5)),
        (
            "/content/conversations/0/completed_steps",
            json!(MAX_COUNT as u64 + 1),
        ),
        ("/content/conversations/0/id", json!("../private-token")),
        (
            "/content/conversations/0/id",
            json!("01922CC0-0000-7000-8000-000000000001"),
        ),
        ("/content/conversations/0/status", json!("idle")),
        ("/content/conversations/0/status", json!("private-token")),
        ("/content/conversations/0/status", Value::Null),
        ("/content/conversations/0/title", json!("😀".repeat(81))),
        (
            "/content/conversations/0/title",
            json!("e\u{301}".repeat(41)),
        ),
        (
            "/content/conversations/0/title",
            json!("private-token".repeat(80)),
        ),
        ("/content/conversations/0/title", json!(80)),
        ("/content/conversations/0/title", json!(true)),
        ("/content/conversations/0/title", json!(["private-token"])),
        (
            "/content/conversations/0/title",
            json!({"body":"private-token"}),
        ),
    ] {
        let mut response = status();
        response["content"]["conversations"][0]["title"] = json!("");
        *response.pointer_mut(pointer).unwrap() = value;
        let network = MockTransport::new(vec![response]);
        let failure = execute_using(&network, session(), Action::Status {}).unwrap_err();
        assert_eq!(failure.kind, "invalid_response", "{pointer}");
        assert!(
            !serde_json::to_string(&failure)
                .unwrap()
                .contains("private-token")
        );
    }
}

#[test]
fn too_many_duplicate_and_incomplete_conversations_fail_closed() {
    let mut too_many = status();
    too_many["content"]["active_count"] = json!(4);
    too_many["content"]["conversations"] =
        json!(vec![status()["content"]["conversations"][0].clone(); 4]);
    let mut duplicate = status();
    duplicate["content"]["active_count"] = json!(2);
    duplicate["content"]["conversations"] =
        json!(vec![status()["content"]["conversations"][0].clone(); 2]);
    let mut incomplete = status();
    incomplete["content"]["conversations"][0]
        .as_object_mut()
        .unwrap()
        .remove("completed_steps");
    for response in [
        too_many,
        duplicate,
        incomplete,
        json!({"available":true}),
        json!({"available":false,"content":null}),
        json!({"available":true,"content":{"active_count":0,"conversations":[]}}),
        json!({"available":true,"content":{"active_count":0,"conversations":null,"updated_at":0}}),
    ] {
        let network = MockTransport::new(vec![response]);
        assert!(execute_using(&network, session(), Action::Status {}).is_err());
    }
}

#[test]
fn malformed_registration_ids_and_tokens_never_reach_network() {
    let network = MockTransport::new(vec![]);
    for id in [
        "",
        "../settings",
        "https://evil.example",
        "id?owner=other",
        "01922CC0-0000-7000-8000-000000000001",
        "01922cc0-0000-7000-8000-00000000000g",
        "01922cc0000070008000000000000001",
        "01922cc0-0000-7000-8000-000000000001/extra",
    ] {
        for action in [
            Action::Unregister {
                registration_id: id.into(),
            },
            Action::Register {
                registration_id: id.into(),
                token: "ab".repeat(32),
                environment: Environment::Production,
            },
        ] {
            assert!(execute_using(&network, session(), action).is_err());
        }
    }
    for token in [
        String::new(),
        "ab".repeat(15),
        "a".repeat(31),
        "a".repeat(33),
        "ab".repeat(257),
        "gg".repeat(32),
        "\u{e9}".repeat(32),
        format!("{}\n", "a".repeat(31)),
        format!("{} ", "a".repeat(31)),
        format!("{}\0", "a".repeat(31)),
    ] {
        assert!(
            execute_using(
                &network,
                session(),
                Action::Register {
                    registration_id: ID.into(),
                    token,
                    environment: Environment::Production,
                }
            )
            .is_err()
        );
    }
    assert!(network.requests.borrow().is_empty());
}

#[test]
fn expired_empty_and_invalid_origin_sessions_never_reach_network_or_refresh() {
    let network = MockTransport::new(vec![]);
    let mut expired = session();
    expired.expires_at = now();
    let mut empty_token = session();
    empty_token.access_token.clear();
    let mut wrong_origin = session();
    wrong_origin.registration.token_endpoint = "https://evil.example/token".into();
    let mut wrong_authorization = session();
    wrong_authorization.registration.authorization_endpoint =
        "https://evil.example/authorize".into();
    let mut invalid_server = session();
    invalid_server.registration.server = "http://atlas.example".into();
    let mut empty_client = session();
    empty_client.registration.client_id.clear();
    for invalid_session in [
        expired,
        empty_token,
        wrong_origin,
        wrong_authorization,
        invalid_server,
        empty_client,
    ] {
        for action in [Action::Status {}, register(), unregister()] {
            assert!(execute_using(&network, invalid_session.clone(), action).is_err());
        }
    }
    assert!(network.requests.borrow().is_empty());
}

#[test]
fn mutation_confirmations_require_exact_true_booleans() {
    for response in [
        json!({}),
        json!({"registered":false}),
        json!({"registered":1}),
    ] {
        let network = MockTransport::new(vec![response]);
        assert!(execute_using(&network, session(), register()).is_err());
    }
    for response in [
        json!({}),
        json!({"deleted":false}),
        json!({"deleted":"true"}),
    ] {
        let network = MockTransport::new(vec![response]);
        assert!(execute_using(&network, session(), unregister()).is_err());
    }
}

#[test]
fn bridge_dispatches_all_actions_and_rejects_selectors_without_echoing_secrets() {
    let mut expired = session();
    expired.expires_at = 0;
    for action in [
        json!({"action":"status"}),
        json!({"action":"register","registration_id":ID,"token":"ab".repeat(32),"environment":"sandbox"}),
        json!({"action":"unregister","registration_id":ID}),
    ] {
        let mut command = action;
        command["operation"] = json!("orbit_activity");
        command["session"] = json!(expired);
        let output: Value =
            serde_json::from_str(&crate::bridge::execute(&command.to_string())).unwrap();
        assert_eq!(output["error"]["kind"], "sign_in_required");
        for key in [
            "owner_id", "user_id", "url", "endpoint", "topic", "platform",
        ] {
            let mut selected = command.clone();
            selected[key] = json!("private-selector-secret");
            let output = crate::bridge::execute(&selected.to_string());
            let failure: Value = serde_json::from_str(&output).unwrap();
            assert_eq!(failure["error"]["kind"], "invalid_response", "{key}");
            assert!(!output.contains("private-selector-secret"));
        }
    }
    for action in [
        json!({"action":"register","registration_id":ID,"token":"private-token","environment":"development"}),
        json!({"action":"register","registration_id":ID,"token":"private-token"}),
        json!({"action":"register","token":"private-token","environment":"production"}),
        json!({"action":"unregister"}),
        json!({"action":"unknown"}),
    ] {
        assert!(serde_json::from_value::<Action>(action).is_err());
    }
}

struct FailureTransport(u16);

impl Transport for FailureTransport {
    fn request<T: serde::de::DeserializeOwned>(
        &self,
        _url: &url::Url,
        body: Body<'_>,
    ) -> Result<T> {
        let Body::Api { failure, .. } = body else {
            panic!("expected authenticated API transport");
        };
        Err(failure(
            self.0,
            br#"{"error":"invalid_grant","token":"private-token"}"#,
        ))
    }
}

#[test]
fn optional_route_failures_are_fixed_and_never_reject_credentials() {
    for (status, kind) in [
        (400, "invalid_request"),
        (401, "sign_in_required"),
        (403, "unsupported_client"),
        (404, "unavailable"),
        (409, "conflict"),
        (422, "invalid_request"),
        (429, "rate_limited"),
        (500, "server"),
        (501, "unavailable"),
        (503, "unavailable"),
    ] {
        for action in [Action::Status {}, register(), unregister()] {
            let failure = execute_using(&FailureTransport(status), session(), action).unwrap_err();
            assert_eq!(failure.kind, kind);
            assert_ne!(failure.kind, "rejected");
            if matches!(status, 403 | 404 | 501 | 503) {
                assert_ne!(failure.kind, "sign_in_required");
            }
            let output = serde_json::to_string(&failure).unwrap();
            assert!(!output.contains("private-token"));
            assert!(!output.contains("invalid_grant"));
        }
    }
}
