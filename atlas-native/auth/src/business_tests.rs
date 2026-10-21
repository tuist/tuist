use super::*;
use crate::tests::{MockTransport, registration};

const ID: &str = "01922cc0-0000-7000-8000-000000000001";

fn saved() -> Session {
    Session {
        registration: registration(),
        access_token: "atlas-access".into(),
        refresh_token: "atlas-refresh".into(),
        expires_at: now() + 3600,
    }
}

#[test]
fn crud_uses_fixed_resource_routes_and_filters_records() {
    for (resource, name, field) in [
        (Resource::Tasks, "tasks", "title"),
        (Resource::Accounts, "accounts", "name"),
        (Resource::Invoices, "invoices", "vendor_name"),
    ] {
        let fields = BTreeMap::from([(field.into(), Some("Example & Co".into()))]);
        let item = json!({"id":ID,"fields":{field:"Example & Co","secret":"must-not-forward"},
            "can_edit":true,"can_delete":true,"internal":"must-not-forward"});
        let cases = [
            (
                Action::Create {
                    fields: fields.clone(),
                },
                "POST",
                String::new(),
            ),
            (
                Action::Update {
                    id: ID.into(),
                    fields,
                },
                "PATCH",
                format!("/{ID}"),
            ),
            (Action::Show { id: ID.into() }, "GET", format!("/{ID}")),
        ];
        for (action, method, suffix) in cases {
            let network = MockTransport::new(vec![json!({"item":item})]);
            let output = execute_using(&network, saved(), resource, action).unwrap();
            assert_eq!(output["item"]["fields"][field], "Example & Co");
            assert!(!output.to_string().contains("must-not-forward"));
            let requests = network.requests.borrow();
            assert_eq!(
                requests[0].0,
                format!("https://atlas.example/api/native/{name}{suffix}")
            );
            assert_eq!(requests[0].1["method"], method);
            assert_eq!(requests[0].1["token"], "atlas-access");
            if method != "GET" {
                assert_eq!(requests[0].1["payload"], json!({field:"Example & Co"}));
            }
        }
        let network = MockTransport::new(vec![json!({"deleted":true})]);
        assert_eq!(
            execute_using(
                &network,
                saved(),
                resource,
                Action::Delete { id: ID.into() }
            )
            .unwrap(),
            json!({"deleted":true})
        );
        assert_eq!(network.requests.borrow()[0].1["method"], "DELETE");
    }
    let network = MockTransport::new(vec![
        json!({"item":{"id":ID,"fields":{"status":"completed"},"can_edit":true,"can_delete":true}}),
    ]);
    let output = execute_using(
        &network,
        saved(),
        Resource::Tasks,
        Action::Complete { id: ID.into() },
    )
    .unwrap();
    assert_eq!(output["item"]["fields"]["status"], "completed");
    assert_eq!(
        network.requests.borrow()[0].0,
        format!("https://atlas.example/api/native/tasks/{ID}/complete")
    );
}

#[test]
fn pagination_search_and_currency_summary_survive_the_bridge_without_rounding() {
    let summary = json!([
        {"month":"2026-09","currency":"EUR","amount":"123456789.13"},
        {"month":"2026-10","currency":"USD","amount":"7.91"}
    ]);
    let network = MockTransport::new(vec![
        json!({"items":[],"page":2,"total_pages":3,"total_count":51,
        "can_write":false,"summary":summary}),
    ]);
    let output = execute_using(
        &network,
        saved(),
        Resource::Invoices,
        Action::List {
            page: 2,
            query: "A&B + €".into(),
        },
    )
    .unwrap();
    assert_eq!(output["summary"], summary);
    assert_eq!(output["total_count"], 51);
    assert_eq!(output["can_write"], false);
    let url = url::Url::parse(&network.requests.borrow()[0].0).unwrap();
    assert_eq!(
        url.query_pairs().collect::<Vec<_>>(),
        [
            ("page".into(), "2".into()),
            ("query".into(), "A&B + €".into())
        ]
    );
}

#[test]
fn invalid_resources_paths_and_write_fields_never_send_credentials() {
    let network = MockTransport::new(vec![]);
    for action in [
        Action::Show {
            id: "../profile".into(),
        },
        Action::List {
            page: 0,
            query: String::new(),
        },
        Action::Create {
            fields: BTreeMap::from([("metadata".into(), Some("manual".into()))]),
        },
        Action::Create {
            fields: BTreeMap::from([("due_on".into(), Some("2027-02-29".into()))]),
        },
    ] {
        assert!(execute_using(&network, saved(), Resource::Tasks, action).is_err());
    }
    assert!(
        execute_using(
            &network,
            saved(),
            Resource::Invoices,
            Action::Complete { id: ID.into() }
        )
        .is_err()
    );
    assert!(
        execute_using(
            &network,
            saved(),
            Resource::Profile,
            Action::Delete { id: ID.into() }
        )
        .is_err()
    );
    let mut session = saved();
    session.registration.token_endpoint = "https://elsewhere.example/token".into();
    assert!(
        execute_using(
            &network,
            session,
            Resource::Accounts,
            Action::Show { id: ID.into() }
        )
        .is_err()
    );
    assert!(network.requests.borrow().is_empty());
    for status in [401, 403, 404, 409, 422, 429, 500] {
        let encoded =
            serde_json::to_value(response_failure(status, b"private server details")).unwrap();
        assert!(!encoded.to_string().contains("private server details"));
        assert_ne!(encoded["kind"], "rejected");
    }
}

#[test]
fn profile_is_owner_scoped_read_only_and_filters_response_fields() {
    let network = MockTransport::new(vec![
        json!({"server_version":"0.7.2","user":{"name":"Taylor","email":"taylor@example.org","token":"private"}}),
    ]);
    let output = execute_using(
        &network,
        saved(),
        Resource::Profile,
        Action::List {
            page: 1,
            query: String::new(),
        },
    )
    .unwrap();
    assert_eq!(
        output,
        json!({"server_version":"0.7.2","user":{"name":"Taylor","email":"taylor@example.org"}})
    );
    assert_eq!(
        network.requests.borrow()[0].0,
        "https://atlas.example/api/native/profile"
    );
    let mut session = saved();
    session.expires_at = 0;
    let input =
        json!({"operation":"business","resource":"tasks","action":"list","session":session});
    let output: Value = serde_json::from_str(&crate::bridge::execute(&input.to_string())).unwrap();
    assert_eq!(output["error"]["kind"], "sign_in_required");
    let mut injected = input;
    injected["url"] = json!("https://elsewhere.example");
    let output: Value =
        serde_json::from_str(&crate::bridge::execute(&injected.to_string())).unwrap();
    assert_eq!(output["error"]["kind"], "invalid_response");
}
