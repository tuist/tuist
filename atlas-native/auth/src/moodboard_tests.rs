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

fn capture(id: &str) -> Action {
    Action::Capture {
        request_id: id.into(),
        attributes: Attributes {
            title: "A reference".into(),
            url: "".into(),
            content: "Keep the asymmetry".into(),
            description: "My note".into(),
            tags: vec!["design".into()],
        },
    }
}

#[test]
fn fixed_routes_preserve_replay_identity_and_strip_response_extras() {
    let id = "01922cc0-0000-7000-8000-000000000001";
    let network = MockTransport::new(vec![
        json!({"saved":true,"resource_id":id,"token":"not-forwarded"}),
    ]);
    assert_eq!(
        execute_using(&network, saved(), capture(id)).unwrap(),
        json!({"saved":true,"resource_id":id})
    );
    let requests = network.requests.borrow();
    assert_eq!(
        requests[0].0,
        format!("https://atlas.example/api/native/moodboard/captures/{id}")
    );
    assert_eq!(requests[0].1["method"], "PUT");
    assert_eq!(requests[0].1["token"], "atlas-access");
    assert_eq!(requests[0].1["payload"]["content"], "Keep the asymmetry");

    let fields =
        json!({"title":"A page","description":"A summary","tags":["design"],"generated":true});
    let network = MockTransport::new(vec![
        json!({"suggestions":fields,"provider_token":"not-forwarded"}),
    ]);
    assert_eq!(
        execute_using(
            &network,
            saved(),
            Action::Suggest {
                url: "https://example.com/page".into(),
                content: "Quoted text".into()
            }
        )
        .unwrap(),
        json!({"suggestions":fields})
    );
    let requests = network.requests.borrow();
    assert_eq!(
        requests[0].0,
        "https://atlas.example/api/native/moodboard/suggestions"
    );
    assert_eq!(requests[0].1["method"], "POST");
    assert_eq!(
        requests[0].1["payload"],
        json!({"url":"https://example.com/page","content":"Quoted text"})
    );
}

#[test]
fn invalid_content_paths_and_sessions_never_send_credentials() {
    let network = MockTransport::new(vec![]);
    for url in [
        "http://example.com",
        "https://user:secret@example.com/",
        "file:///private/test",
        "https://example.com:444/path",
    ] {
        assert!(
            execute_using(
                &network,
                saved(),
                Action::Suggest {
                    url: url.into(),
                    content: "".into()
                }
            )
            .is_err()
        );
    }
    assert!(execute_using(&network, saved(), capture("../profile")).is_err());
    assert!(
        execute_using(
            &network,
            saved(),
            Action::Suggest {
                url: "".into(),
                content: "x".repeat(20_001)
            }
        )
        .is_err()
    );
    let mut expired = saved();
    expired.expires_at = 0;
    assert!(
        execute_using(
            &network,
            expired,
            capture("01922cc0-0000-7000-8000-000000000001")
        )
        .is_err()
    );
    assert!(network.requests.borrow().is_empty());
    for status in [401, 403, 404, 409, 422, 429, 500] {
        let error = response_failure(status, b"secret provider response");
        assert!(!error.message.contains("secret"));
        assert_ne!(error.kind, "rejected");
    }
}

#[test]
fn malformed_or_unbounded_suggestions_are_not_forwarded() {
    for fields in [
        json!({"title":"x".repeat(201),"description":"","tags":[],"generated":true}),
        json!({"title":"Page","description":{},"tags":[],"generated":true}),
        json!({"title":"Page","description":"","tags":["x".repeat(41)],"generated":true}),
    ] {
        let network = MockTransport::new(vec![json!({"suggestions":fields})]);
        assert!(
            execute_using(
                &network,
                saved(),
                Action::Suggest {
                    url: "".into(),
                    content: "A thought".into()
                }
            )
            .is_err()
        );
    }
    assert!(
        serde_json::from_value::<Action>(
            json!({"action":"suggest","url":"","content":"A thought","owner_id":"other"})
        )
        .is_err()
    );
}
