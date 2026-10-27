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

fn request() -> Value {
    json!({"id":"01922cc0-0000-7000-8000-000000000001", "starts_on":"2027-06-07", "ends_on":"2027-06-11", "status":"pending", "working_days":5, "user_id":"must-not-forward", "access_token":"must-not-forward"})
}

#[test]
fn actions_use_fixed_owner_scoped_routes_and_filter_responses() {
    let id = "01922cc0-0000-7000-8000-000000000001";
    let page = json!({"items":[request()],"page":1,"total_pages":1,"total_count":1});
    let holidays = json!({"items":[],"page":1,"total_pages":0,"total_count":0});
    let cases = [
        (
            Action::List {
                requests_page: 2,
                holidays_page: 1,
            },
            "GET",
            "?requests_page=2&holidays_page=1".to_string(),
            Value::Null,
            json!({"requests":page,"public_holidays":holidays}),
        ),
        (
            Action::Create {
                starts_on: "2027-06-07".into(),
                ends_on: "2027-06-11".into(),
            },
            "POST",
            "".into(),
            json!({"starts_on":"2027-06-07","ends_on":"2027-06-11"}),
            json!({"request":request()}),
        ),
        (
            Action::Update {
                id: id.into(),
                starts_on: "2027-06-07".into(),
                ends_on: "2027-06-11".into(),
            },
            "PATCH",
            format!("/{id}"),
            json!({"starts_on":"2027-06-07","ends_on":"2027-06-11"}),
            json!({"request":request()}),
        ),
        (
            Action::Cancel { id: id.into() },
            "DELETE",
            format!("/{id}"),
            Value::Null,
            json!({"request":request()}),
        ),
    ];
    for (action, method, suffix, payload, response) in cases {
        let network = MockTransport::new(vec![response]);
        let value = execute_using(&network, saved(), action).unwrap();
        assert!(!value.to_string().contains("must-not-forward"));
        let requests = network.requests.borrow();
        assert_eq!(requests.len(), 1);
        assert_eq!(
            requests[0].0,
            format!("https://atlas.example/api/me/time-off{suffix}")
        );
        assert_eq!(requests[0].1["method"], method);
        assert_eq!(requests[0].1["token"], "atlas-access");
        assert_eq!(requests[0].1["payload"], payload);
    }
}

#[test]
fn invalid_dates_and_path_injection_never_send_requests() {
    let network = MockTransport::new(vec![]);
    for (first, last) in [
        ("2027-02-29", "2027-03-01"),
        ("2027-06-11", "2027-06-07"),
        ("2027-01-01T00:00:00Z", "2027-01-02"),
        ("2101-01-01", "2101-01-01"),
        ("ééééé", "2027-01-02"),
    ] {
        assert!(
            execute_using(
                &network,
                saved(),
                Action::Create {
                    starts_on: first.into(),
                    ends_on: last.into()
                }
            )
            .is_err()
        );
    }
    for id in [
        "../llm-providers",
        "https://evil.example",
        "id?owner=other",
        "",
    ] {
        assert!(execute_using(&network, saved(), Action::Cancel { id: id.into() }).is_err());
    }
    assert!(network.requests.borrow().is_empty());
    assert!(valid_date("2028-02-29"));
    assert!(!valid_date("2100-02-29"));
}

#[test]
fn rejected_sessions_and_origins_never_send_credentials() {
    for field in ["server", "endpoint", "expired", "empty"] {
        let network = MockTransport::new(vec![]);
        let mut session = saved();
        match field {
            "server" => session.registration.server = "http://atlas.example".into(),
            "endpoint" => session.registration.token_endpoint = "https://evil.example/token".into(),
            "expired" => session.expires_at = 0,
            _ => session.access_token.clear(),
        }
        assert!(
            execute_using(
                &network,
                session,
                Action::List {
                    requests_page: 1,
                    holidays_page: 1
                }
            )
            .is_err()
        );
        assert!(network.requests.borrow().is_empty());
    }
}

#[test]
fn bridge_decodes_all_employee_actions_and_rejects_owner_or_status_overrides() {
    let mut session = saved();
    session.expires_at = 0;
    let id = "01922cc0-0000-7000-8000-000000000001";
    for mut input in [
        json!({"action":"list","requests_page":1,"holidays_page":2}),
        json!({"action":"create","starts_on":"2027-06-07","ends_on":"2027-06-11"}),
        json!({"action":"update","id":id,"starts_on":"2027-06-07","ends_on":"2027-06-11"}),
        json!({"action":"cancel","id":id}),
    ] {
        input["operation"] = json!("time_off");
        input["session"] = serde_json::to_value(&session).unwrap();
        let result: Value =
            serde_json::from_str(&crate::bridge::execute(&input.to_string())).unwrap();
        assert_eq!(result["error"]["kind"], "sign_in_required");
        for field in ["user_id", "status", "url"] {
            input[field] = json!("must-not-echo");
            let output = crate::bridge::execute(&input.to_string());
            assert!(!output.contains("must-not-echo"));
            let result: Value = serde_json::from_str(&output).unwrap();
            assert_eq!(result["error"]["kind"], "invalid_response");
            input.as_object_mut().unwrap().remove(field);
        }
    }
}

#[test]
fn errors_are_fixed_and_never_echo_server_bodies() {
    for status in [401, 404, 422, 429, 500] {
        let value =
            serde_json::to_string(&response_failure(status, b"secret-provider-body")).unwrap();
        assert!(!value.contains("secret-provider-body"));
    }
}
