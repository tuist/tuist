use super::*;
use crate::tests::{MockTransport, registration};

const ID: &str = "01922cc0-0000-7000-8000-000000000001";

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
        installation_id: ID.into(),
        platform: Platform::Ios,
        token: "ab".repeat(32),
        environment: Environment::Production,
    }
}

#[test]
fn registration_uses_fixed_bearer_route_and_filters_response() {
    let network = MockTransport::new(vec![
        json!({"registered":true,"registration_id":ID,"token":"must-not-forward"}),
    ]);
    assert_eq!(
        execute_using(&network, session(), register()).unwrap(),
        json!({"registered":true,"registration_id":ID})
    );
    let requests = network.requests.borrow();
    assert_eq!(
        requests[0].0,
        format!("https://atlas.example/api/me/push-devices/{ID}")
    );
    assert_eq!(requests[0].1["method"], "PUT");
    assert_eq!(requests[0].1["token"], "atlas-access");
    assert_eq!(requests[0].1["payload"]["platform"], "ios");
}

#[test]
fn unregister_is_owner_scoped_and_contains_no_provider_token() {
    let network = MockTransport::new(vec![json!({"deleted":true})]);
    assert_eq!(
        execute_using(
            &network,
            session(),
            Action::Unregister {
                installation_id: ID.into()
            }
        )
        .unwrap(),
        json!({"deleted":true})
    );
    let requests = network.requests.borrow();
    assert_eq!(requests[0].1["method"], "DELETE");
    assert_eq!(requests[0].1["payload"], Value::Null);
}

#[test]
fn android_uses_production_fcm_tokens_and_validates_before_networking() {
    let network = MockTransport::new(vec![json!({"registered":true,"registration_id":ID})]);
    execute_using(
        &network,
        session(),
        Action::Register {
            installation_id: ID.into(),
            platform: Platform::Android,
            token: "firebase:token_value-123".into(),
            environment: Environment::Production,
        },
    )
    .unwrap();
    assert_eq!(
        network.requests.borrow()[0].1["payload"]["platform"],
        "android"
    );
    let none = MockTransport::new(vec![]);
    for (token, environment) in [
        ("firebase:token_value-123", Environment::Sandbox),
        ("token with spaces", Environment::Production),
    ] {
        assert!(
            execute_using(
                &none,
                session(),
                Action::Register {
                    installation_id: ID.into(),
                    platform: Platform::Android,
                    token: token.into(),
                    environment,
                }
            )
            .is_err()
        );
    }
    assert!(none.requests.borrow().is_empty());
}

#[test]
fn malformed_identifiers_tokens_and_sessions_never_reach_network() {
    let network = MockTransport::new(vec![]);
    for id in [
        "../settings",
        "https://evil.example",
        "",
        "id?user=other",
        "01922CC0-0000-7000-8000-000000000001",
    ] {
        assert!(
            execute_using(
                &network,
                session(),
                Action::Unregister {
                    installation_id: id.into()
                }
            )
            .is_err()
        );
    }
    for token in ["", "not-hex", "\u{e9}", "ab\ncd"] {
        assert!(
            execute_using(
                &network,
                session(),
                Action::Register {
                    installation_id: ID.into(),
                    platform: Platform::Ios,
                    token: token.into(),
                    environment: Environment::Production,
                }
            )
            .is_err()
        );
    }
    let mut expired = session();
    expired.expires_at = 0;
    assert!(execute_using(&network, expired, register()).is_err());
    let mut wrong_origin = session();
    wrong_origin.registration.token_endpoint = "https://evil.example/token".into();
    assert!(execute_using(&network, wrong_origin, register()).is_err());
    assert!(network.requests.borrow().is_empty());
}

#[test]
fn invalid_registration_responses_fail_closed() {
    for response in [
        json!({"registered":true}),
        json!({"registered":false,"registration_id":ID}),
        json!({"registered":true,"registration_id":"secret-invalid-id"}),
        json!({"registered":true,"registration_id":"01922CC0-0000-7000-8000-000000000001"}),
    ] {
        let network = MockTransport::new(vec![response]);
        assert!(execute_using(&network, session(), register()).is_err());
    }
}

#[test]
fn command_rejects_owner_selectors_and_errors_never_echo_bodies() {
    let action = json!({"action":"unregister","installation_id":ID,"user_id":ID});
    assert!(serde_json::from_value::<Action>(action).is_err());
    assert_eq!(response_failure(400, b"").kind, "invalid_request");
    assert_eq!(response_failure(403, b"").kind, "unsupported_client");
    assert_eq!(response_failure(503, b"").kind, "unavailable");
    for status in [400, 401, 403, 404, 409, 422, 429, 500, 503] {
        let failure = response_failure(status, b"secret-device-token");
        assert!(
            !serde_json::to_string(&failure)
                .unwrap()
                .contains("secret-device-token")
        );
        assert_ne!(failure.kind, "rejected");
    }
}
