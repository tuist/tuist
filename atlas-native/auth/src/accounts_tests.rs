use super::*;
use crate::tests::{MockTransport, registration};

fn saved() -> Session {
    Session {
        registration: registration(),
        access_token: "atlas-access".into(),
        refresh_token: "atlas-refresh".into(),
        expires_at: now() + 3600,
    }
}

fn metadata() -> Value {
    json!({"provider":"claude", "credential_configured": true, "login_available": true,
        "expires_at":null,"updated_at":null,"access_token":"must-not-return"})
}

fn login() -> Value {
    json!({"login_id":"owner-scoped", "user_code":"EXAMPLE-CODE", "interval":5,
        "expires_at":"2026-10-15T16:00:00Z", "verification_url":"https://auth.openai.com/codex/device",
        "access_token":"must-not-return", "device_auth_id":"must-not-return"})
}

#[test]
fn every_action_uses_the_selected_origin_method_bearer_and_owner_scoped_route() {
    let cases = [
        (
            Action::List,
            "GET",
            "",
            Value::Null,
            json!({"providers":[metadata()]}),
        ),
        (
            Action::ConnectClaude {
                token: "subscription-token".into(),
            },
            "PUT",
            "/claude",
            json!({"token":"subscription-token"}),
            metadata(),
        ),
        (
            Action::StartChatgpt,
            "POST",
            "/chatgpt/login",
            json!({}),
            login(),
        ),
        (
            Action::PollChatgpt {
                login_id: "login".into(),
            },
            "POST",
            "/chatgpt/login/poll",
            json!({"login_id":"login"}),
            json!({"status":"pending"}),
        ),
        (
            Action::CancelChatgpt {
                login_id: "login".into(),
            },
            "DELETE",
            "/chatgpt/login",
            json!({"login_id":"login"}),
            json!({"status":"cancelled"}),
        ),
        (
            Action::Disconnect {
                provider: Provider::Claude,
            },
            "DELETE",
            "/claude",
            Value::Null,
            metadata(),
        ),
        (
            Action::Disconnect {
                provider: Provider::Chatgpt,
            },
            "DELETE",
            "/chatgpt",
            Value::Null,
            json!({"provider":"chatgpt","credential_configured":false,"login_available":true,
                "updated_at":null,"expires_at":null}),
        ),
    ];
    for (action, method, suffix, payload, response) in cases {
        let network = MockTransport::new(vec![response]);
        let result = execute_using(&network, saved(), action).unwrap();
        assert!(!result.to_string().contains("must-not-return"));
        let requests = network.requests.borrow();
        assert_eq!(requests.len(), 1);
        assert_eq!(
            requests[0].0,
            format!("https://atlas.example/api/me/llm-providers{suffix}")
        );
        assert_eq!(requests[0].1["method"], method);
        assert_eq!(requests[0].1["token"], "atlas-access");
        assert_eq!(requests[0].1["payload"], payload);
    }
}

#[test]
fn invalid_or_expired_sessions_never_send_credentials() {
    for field in ["server", "endpoint", "expired", "empty"] {
        let network = MockTransport::new(vec![]);
        let mut session = saved();
        match field {
            "server" => session.registration.server = "http://atlas.example".into(),
            "endpoint" => session.registration.token_endpoint = "https://evil.example/token".into(),
            "expired" => session.expires_at = 0,
            _ => session.access_token.clear(),
        }
        assert!(execute_using(&network, session, Action::List).is_err());
        assert!(network.requests.borrow().is_empty());
    }
}

#[test]
fn device_signin_links_and_polling_intervals_are_validated_before_display() {
    for url in [
        "http://auth.openai.com/device",
        "https://evil.example/device",
        "https://secret@auth.openai.com/device",
        "https://auth.openai.com:8443/device",
    ] {
        let mut response = login();
        response["verification_url"] = json!(url);
        assert!(
            execute_using(
                &MockTransport::new(vec![response]),
                saved(),
                Action::StartChatgpt
            )
            .is_err()
        );
    }
    for interval in [0, 901] {
        let mut response = login();
        response["interval"] = json!(interval);
        assert!(
            execute_using(
                &MockTransport::new(vec![response]),
                saved(),
                Action::StartChatgpt
            )
            .is_err()
        );
    }
}

#[test]
fn api_failures_are_sanitized_and_do_not_reject_the_oauth_refresh_credential() {
    for (status, code, expected) in [
        (401, "anything", "sign_in_required"),
        (422, "invalid_claude_token", "invalid_token"),
        (503, "chatgpt_not_configured", "unavailable"),
        (409, "login_in_progress", "login_in_progress"),
        (429, "anything", "rate_limited"),
        (410, "anything", "login_expired"),
        (502, "private-response", "server"),
    ] {
        let bytes = json!({"error":code,"detail":"secret-token"}).to_string();
        let failure = response_failure(status, bytes.as_bytes());
        assert_eq!(failure.kind, expected);
        assert_ne!(failure.kind, "rejected");
        assert!(!failure.message.contains("secret-token"));
        assert!(!failure.message.contains("private-response"));
    }
}

#[test]
fn bridge_accepts_only_known_actions_and_never_echoes_submitted_credentials() {
    let mut session = saved();
    session.access_token.clear();
    let input = json!({"operation":"ai_accounts","session":session,"action":"connect_claude","token":"must-not-echo"});
    let result = crate::bridge::execute(&input.to_string());
    assert!(result.contains("sign_in_required"));
    assert!(!result.contains("must-not-echo"));
    for action in [
        json!({"action":"disconnect","provider":"other"}),
        json!({"action":"arbitrary_url","url":"https://evil.example"}),
    ] {
        assert!(serde_json::from_value::<Action>(action).is_err());
    }
}
