use super::*;
use serde_json::{Value, json};
use std::cell::RefCell;
use std::collections::VecDeque;

pub(super) struct MockTransport {
    responses: RefCell<VecDeque<Value>>,
    pub(super) requests: RefCell<Vec<(String, Value)>>,
}

impl MockTransport {
    pub(super) fn new(responses: Vec<Value>) -> Self {
        Self {
            responses: RefCell::new(responses.into()),
            requests: RefCell::new(Vec::new()),
        }
    }
}

impl Transport for MockTransport {
    fn request<T: serde::de::DeserializeOwned>(&self, url: &Url, body: Body<'_>) -> Result<T> {
        let value = match body {
            Body::Get => Value::Null,
            Body::Json(value) => value,
            Body::Api {
                method,
                token,
                payload,
                ..
            } => json!({"method": method.as_str(), "token": token, "payload": payload}),
            Body::Form(pairs) => Value::Object(
                pairs
                    .into_iter()
                    .map(|(key, value)| (key.to_string(), json!(value)))
                    .collect(),
            ),
        };
        self.requests.borrow_mut().push((url.to_string(), value));
        let response = self
            .responses
            .borrow_mut()
            .pop_front()
            .expect("unexpected network request");
        serde_json::from_value(response).map_err(|_| invalid())
    }
}

fn discovery() -> Value {
    json!({
        "issuer": "https://atlas.example",
        "authorization_endpoint": "https://atlas.example/oauth2/authorize",
        "token_endpoint": "https://atlas.example/oauth2/token",
        "registration_endpoint": "https://atlas.example/oauth2/register",
        "code_challenge_methods_supported": ["S256"]
    })
}

#[test]
fn discovers_registers_exchanges_and_rotates_public_client_credentials() {
    let network = MockTransport::new(vec![
        discovery(),
        json!({"client_id": "native-client", "token_endpoint_auth_method": "none"}),
        json!({"access_token": "access", "refresh_token": "refresh", "token_type": "bearer", "expires_in": 3600}),
        json!({"access_token": "rotated-access", "refresh_token": "rotated-refresh", "token_type": "bearer", "expires_in": 3600}),
    ]);
    let login = begin_using(&network, "https://atlas.example", None).unwrap();
    let verifier = login.pending.verifier.clone();
    let callback = format!(
        "{REDIRECT_URI}?state={}&code=code%2B%26",
        login.pending.state
    );
    let mut session = complete_using(&network, login.pending, &callback).unwrap();
    session.expires_at = 0;
    let session = restore_using(&network, session).unwrap();
    assert_eq!(session.access_token, "rotated-access");
    assert_eq!(session.refresh_token, "rotated-refresh");
    assert_eq!(session.registration.server, "https://atlas.example/");
    let requests = network.requests.borrow();
    assert_eq!(
        requests[0].0,
        "https://atlas.example/.well-known/oauth-authorization-server"
    );
    assert_eq!(requests[1].0, "https://atlas.example/oauth2/register");
    assert_eq!(requests[1].1["token_endpoint_auth_method"], "none");
    assert_eq!(requests[1].1["redirect_uris"], json!([REDIRECT_URI]));
    assert_eq!(requests[2].0, "https://atlas.example/oauth2/token");
    assert_eq!(requests[2].1["code"], "code+&");
    assert_eq!(requests[2].1["code_verifier"], verifier);
    assert_eq!(requests[2].1["client_id"], "native-client");
    assert_eq!(requests[3].1["grant_type"], "refresh_token");
    assert_eq!(requests[3].1["client_id"], "native-client");
    assert_eq!(requests[3].1["refresh_token"], "refresh");
    assert!(network.responses.borrow().is_empty());
}

#[test]
fn untrusted_discovery_never_registers_or_sends_tokens() {
    for key in [
        "issuer",
        "authorization_endpoint",
        "token_endpoint",
        "registration_endpoint",
    ] {
        let mut value = discovery();
        value[key] = json!("https://evil.example/oauth");
        let network = MockTransport::new(vec![value]);
        assert!(begin_using(&network, "https://atlas.example", None).is_err());
        assert_eq!(network.requests.borrow().len(), 1);
    }
    let mut value = discovery();
    value["code_challenge_methods_supported"] = json!(["plain"]);
    assert!(
        begin_using(
            &MockTransport::new(vec![value]),
            "https://atlas.example",
            None
        )
        .is_err()
    );
}

#[test]
fn switching_servers_does_not_reuse_another_servers_client() {
    let mut old = registration();
    old.server = "https://old.example/".into();
    let network = MockTransport::new(vec![
        discovery(),
        json!({"client_id": "new-client", "token_endpoint_auth_method": "none"}),
    ]);
    let login = begin_using(&network, "https://atlas.example", Some(old)).unwrap();
    assert_eq!(login.registration.client_id, "new-client");
    assert_eq!(network.requests.borrow().len(), 2);
}

#[test]
fn only_definitive_oauth_failures_reject_credentials_and_never_echo_bodies() {
    for oauth_error in ["invalid_grant", "invalid_client", "unauthorized_client"] {
        let body =
            json!({"error": oauth_error, "error_description": "secret-do-not-echo"}).to_string();
        let failure = transport::response_failure(400, body.as_bytes());
        assert_eq!(failure.kind, "rejected");
        assert!(!failure.message.contains("secret-do-not-echo"));
        assert_eq!(
            transport::response_failure(503, body.as_bytes()).kind,
            "server"
        );
    }
    for (status, body) in [
        (400, "proxy unavailable"),
        (401, "not-json"),
        (429, r#"{"error":"invalid_grant"}"#),
        (500, "upstream unavailable"),
        (302, "redirect"),
        (400, r#"{"error":"invalid_request"}"#),
    ] {
        assert_eq!(
            transport::response_failure(status, body.as_bytes()).kind,
            "server"
        );
    }
}

#[test]
fn invalid_callbacks_and_fresh_sessions_do_not_use_the_network() {
    let network = MockTransport::new(vec![]);
    let login = begin_using(&network, "https://atlas.example", Some(registration())).unwrap();
    assert!(
        complete_using(
            &network,
            login.pending,
            "dev.tuist.atlas://oauth-callback?state=wrong&code=secret"
        )
        .is_err()
    );
    let session = Session {
        registration: registration(),
        access_token: "access".into(),
        refresh_token: "refresh".into(),
        expires_at: now() + 3600,
    };
    assert!(restore_using(&network, session).is_ok());
    assert!(network.requests.borrow().is_empty());
}

pub(super) fn registration() -> Registration {
    Registration {
        server: "https://atlas.example/".into(),
        authorization_endpoint: "https://atlas.example/oauth2/authorize".into(),
        token_endpoint: "https://atlas.example/oauth2/token".into(),
        client_id: "native-client".into(),
    }
}

#[test]
fn rejects_unsafe_server_addresses_and_cross_origin_endpoints() {
    for address in [
        "http://atlas.example",
        "https://user:pass@atlas.example",
        "https://atlas.example/path",
        "https://atlas.example?query=1",
        "https://atlas.example#fragment",
    ] {
        assert!(server_url(address).is_err());
    }
    let server = server_url(" https://atlas.example ").unwrap();
    assert_eq!(server.as_str(), "https://atlas.example/");
    for address in [
        "https://evil.example/token",
        "http://atlas.example/token",
        "https://atlas.example:444/token",
        "https://user@atlas.example/token",
    ] {
        assert!(endpoint(&server, address).is_err());
    }
}

#[test]
fn reused_registration_builds_unique_pkce_logins_without_network() {
    let first = begin("https://atlas.example", Some(registration()), None).unwrap();
    let second = begin("https://atlas.example", Some(registration()), None).unwrap();
    assert_ne!(first.pending.state, second.pending.state);
    assert_ne!(first.pending.verifier, second.pending.verifier);
    assert_eq!(first.pending.verifier.len(), 43);
    let url = Url::parse(&first.authorization_url).unwrap();
    let query: std::collections::HashMap<_, _> = url.query_pairs().collect();
    assert_eq!(query["redirect_uri"], REDIRECT_URI);
    assert_eq!(query["code_challenge_method"], "S256");
    assert_eq!(
        query["code_challenge"],
        URL_SAFE_NO_PAD.encode(Sha256::digest(first.pending.verifier.as_bytes()))
    );
}

#[test]
fn callback_checks_origin_state_duplicates_expiry_and_denial() {
    let login = begin("https://atlas.example", Some(registration()), None).unwrap();
    let mut pending = login.pending;
    let callback = format!("{REDIRECT_URI}?state={}&code=a%2Bb%26c", pending.state);
    assert_eq!(callback_code(&pending, &callback).unwrap(), "a+b&c");
    for callback in [
        callback.replace("oauth-callback", "other"),
        callback.replace("dev.tuist.atlas:", "evil:"),
        callback.replace(&pending.state, "wrong"),
        format!("{callback}&code=second"),
        format!("{callback}&state={}", pending.state),
        format!("{callback}#fragment"),
        format!("{callback}&error=access_denied"),
    ] {
        assert!(callback_code(&pending, &callback).is_err());
    }
    pending.created_at = now() - 601;
    assert!(callback_code(&pending, &callback).is_err());
}

#[test]
fn callback_failures_identify_the_check_without_exposing_login_parameters() {
    let login = begin("https://atlas.example", Some(registration()), None).unwrap();
    let callback = format!(
        "{REDIRECT_URI}?state={}&code=secret-code",
        login.pending.state
    );
    let pending = json!(login.pending);
    for (callback, expired, message) in [
        (
            callback.replace("oauth-callback", "unexpected-host"),
            false,
            "The sign-in callback used an unexpected destination. Start a new sign-in and try again.",
        ),
        (
            callback.replace("oauth-callback?", "oauth-callback/?"),
            false,
            "The sign-in callback used an unexpected path. Start a new sign-in and try again.",
        ),
        (
            format!("{callback}#secret-fragment"),
            false,
            "The sign-in callback included an unexpected fragment. Start a new sign-in and try again.",
        ),
        (
            callback,
            true,
            "Sign-in expired after ten minutes. Start a new sign-in and try again.",
        ),
    ] {
        let mut request = json!({
            "operation": "complete",
            "pending": pending,
            "callback": callback
        });
        if expired {
            request["pending"]["created_at"] = json!(0);
        }
        let response: Value = serde_json::from_str(&bridge::execute(&request.to_string())).unwrap();
        assert_eq!(
            response,
            json!({"error": {"kind": "invalid_callback", "message": message}})
        );
    }
}

#[test]
fn google_login_uses_the_same_authorization_endpoint_and_pkce_flow() {
    let request = json!({
        "operation": "begin",
        "server": "https://atlas.example",
        "registration": registration(),
        "provider": "google"
    });
    let response: Value = serde_json::from_str(&bridge::execute(&request.to_string())).unwrap();
    let login = &response["ok"];
    let url = Url::parse(login["authorization_url"].as_str().unwrap()).unwrap();
    assert_eq!(url.origin().ascii_serialization(), "https://atlas.example");
    assert_eq!(url.path(), "/oauth2/authorize");
    let query: std::collections::HashMap<_, _> = url.query_pairs().collect();
    assert_eq!(query["provider"], "google");
    assert_eq!(query["client_id"], "native-client");
    assert_eq!(query["redirect_uri"], REDIRECT_URI);
    assert_eq!(query["state"], login["pending"]["state"].as_str().unwrap());
    assert_eq!(query["code_challenge_method"], "S256");
    assert_eq!(
        query["code_challenge"],
        URL_SAFE_NO_PAD.encode(Sha256::digest(
            login["pending"]["verifier"].as_str().unwrap().as_bytes()
        ))
    );
}

#[test]
fn the_bridge_preserves_default_login_and_rejects_unknown_providers() {
    let mut request = json!({
        "operation": "begin",
        "server": "https://atlas.example",
        "registration": registration()
    });
    let response: Value = serde_json::from_str(&bridge::execute(&request.to_string())).unwrap();
    let url = Url::parse(response["ok"]["authorization_url"].as_str().unwrap()).unwrap();
    assert!(!url.query_pairs().any(|(key, _)| key == "provider"));

    request["provider"] = json!("https://untrusted.example");
    let response: Value = serde_json::from_str(&bridge::execute(&request.to_string())).unwrap();
    assert_eq!(response["error"]["kind"], "invalid_response");
}

#[test]
fn rotation_keeps_issuing_client_and_refresh_token_when_omitted() {
    let tokens = Tokens {
        access_token: "new-access".into(),
        refresh_token: None,
        token_type: "Bearer".into(),
        expires_in: 3600,
    };
    let session = session(registration(), tokens, Some("old-refresh".into())).unwrap();
    assert_eq!(session.registration.client_id, "native-client");
    assert_eq!(session.refresh_token, "old-refresh");
    let restored = restore(session).unwrap();
    assert_eq!(restored.access_token, "new-access");
}

#[test]
fn invalid_commands_return_sanitized_errors_and_owned_strings() {
    use std::ffi::{CStr, CString};
    for input in [
        "not-json",
        r#"{"operation":"unknown","secret":"do-not-echo"}"#,
    ] {
        let output = bridge::execute(input);
        assert!(output.contains("invalid_response"));
        assert!(!output.contains("do-not-echo"));
    }
    let input = CString::new("{}").unwrap();
    unsafe {
        let output = bridge::atlas_auth_execute(input.as_ptr());
        assert!(CStr::from_ptr(output).to_str().unwrap().contains("error"));
        bridge::atlas_auth_free(output);
        bridge::atlas_auth_free(std::ptr::null_mut());
    }
}
