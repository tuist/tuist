use super::*;
use crate::tests::{MockTransport, registration};

fn session() -> Session {
    Session {
        registration: registration(),
        access_token: "atlas-access".into(),
        refresh_token: "atlas-refresh".into(),
        expires_at: now() + 3600,
    }
}

fn pending() -> Pending {
    Pending {
        provider: Provider::Google,
        server: "https://atlas.example/".into(),
        client_id: registration().client_id,
        state: "a".repeat(43),
        created_at: now(),
    }
}

fn callback() -> String {
    format!(
        "{CALLBACK}?state={}&provider=google&status=connected",
        "a".repeat(43)
    )
}

#[test]
fn prepare_is_bearer_scoped_to_each_provider_and_never_returns_provider_credentials() {
    for provider in [Provider::Github, Provider::Slack, Provider::Google] {
        let browser = format!(
            "https://atlas.example/connections/{}/authorize?native=signed-ticket",
            provider.name()
        );
        let network = MockTransport::new(vec![json!({
            "authorization_url": browser, "access_token": "must-not-return"
        })]);
        let value = execute_using(&network, session(), Action::Begin { provider }).unwrap();
        assert_eq!(value["authorization_url"], browser);
        assert_eq!(value["pending"]["provider"], provider.name());
        assert_eq!(value["pending"]["state"].as_str().unwrap().len(), 43);
        assert!(!value.to_string().contains("must-not-return"));
        let requests = network.requests.borrow();
        assert_eq!(
            requests[0].0,
            format!(
                "https://atlas.example/api/me/connections/{}/authorize",
                provider.name()
            )
        );
        assert_eq!(requests[0].1["method"], "POST");
        assert_eq!(requests[0].1["token"], "atlas-access");
        assert_eq!(requests[0].1["payload"]["state"], value["pending"]["state"]);
    }
}

#[test]
fn authorization_urls_cannot_change_origin_provider_or_callback() {
    for url in [
        "https://evil.example/connections/google/authorize?native=ticket",
        "https://atlas.example/connections/slack/authorize?native=ticket",
        "https://atlas.example/connections/google/authorize?native=ticket&redirect_uri=https://evil.example",
        "https://atlas.example/connections/google/authorize?native=one&native=two",
        "https://user@atlas.example/connections/google/authorize?native=ticket",
        "http://atlas.example/connections/google/authorize?native=ticket",
    ] {
        let network = MockTransport::new(vec![json!({"authorization_url": url})]);
        assert!(
            execute_using(
                &network,
                session(),
                Action::Begin {
                    provider: Provider::Google
                }
            )
            .is_err()
        );
    }
}

#[test]
fn connection_return_is_separate_from_login_and_bound_to_state_provider_expiry_and_session() {
    assert_eq!(
        complete(&session(), pending(), &callback()).unwrap()["status"],
        "connected"
    );
    assert_eq!(
        complete(
            &session(),
            pending(),
            &callback().replace("status=connected", "status=error")
        )
        .unwrap()["status"],
        "error"
    );
    let invalid = [
        callback().replace("connections-callback", "oauth-callback"),
        callback().replace("connections-callback", "connections-callback/"),
        callback().replace("provider=google", "provider=github"),
        callback().replace(&"a".repeat(43), &"b".repeat(43)),
        format!("{}&state={}", callback(), "a".repeat(43)),
        format!("{}&access_token=secret", callback()),
        callback().replace("status=connected", "status=unexpected"),
        callback().replace("?state=", "#state="),
    ];
    for value in invalid {
        let failure = complete(&session(), pending(), &value).unwrap_err();
        assert_eq!(failure.kind, "invalid_callback");
        assert!(!failure.message.contains(&value));
    }
    for (created_at, server, client_id) in [
        (
            now() - 601,
            "https://atlas.example/",
            registration().client_id,
        ),
        (
            now() + 60,
            "https://atlas.example/",
            registration().client_id,
        ),
        (now(), "https://another.example/", registration().client_id),
        (now(), "https://atlas.example/", "another-client".into()),
    ] {
        let value = Pending {
            created_at,
            server: server.into(),
            client_id,
            ..pending()
        };
        assert!(complete(&session(), value, &callback()).is_err());
    }
    let mut boundary = pending();
    boundary.created_at = now() - 599;
    assert!(complete(&session(), boundary, &callback()).is_ok());
}

#[test]
fn metadata_is_filtered_and_disconnect_targets_only_the_selected_provider() {
    let network = MockTransport::new(vec![json!({"connections":[{
        "provider":"slack", "name":"Slack", "configured":true, "account_name":"Demo teammate",
        "scopes":["search:read"], "status":"connected", "access_token":"must-not-return"
    }]})]);
    let response = execute_using(&network, session(), Action::List).unwrap();
    assert_eq!(response["connections"][0]["account_name"], "Demo teammate");
    assert!(!response.to_string().contains("must-not-return"));
    for provider in [Provider::Github, Provider::Slack, Provider::Google] {
        let network = MockTransport::new(vec![json!({"disconnected":true})]);
        assert_eq!(
            execute_using(&network, session(), Action::Disconnect { provider }).unwrap(),
            json!({"disconnected":true})
        );
        let requests = network.requests.borrow();
        assert_eq!(
            requests[0].0,
            format!(
                "https://atlas.example/api/me/connections/{}",
                provider.name()
            )
        );
        assert_eq!(requests[0].1["method"], "DELETE");
        assert_eq!(requests[0].1["token"], "atlas-access");
    }
}

#[test]
fn expired_sessions_and_unknown_providers_never_send_credentials() {
    let network = MockTransport::new(vec![]);
    let mut expired = session();
    expired.expires_at = now();
    assert!(execute_using(&network, expired, Action::List).is_err());
    assert!(network.requests.borrow().is_empty());
    let value = crate::bridge::execute(&json!({
        "operation":"connections", "session":session(), "action":"begin", "provider":"arbitrary/path"
    }).to_string());
    assert!(
        serde_json::from_str::<Value>(&value)
            .unwrap()
            .get("error")
            .is_some()
    );
}
