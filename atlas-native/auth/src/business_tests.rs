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
            filters: BTreeMap::from([("status".into(), "needs_review".into())]),
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
            ("query".into(), "A&B + €".into()),
            ("status".into(), "needs_review".into())
        ]
    );
}

#[test]
fn list_filters_are_top_level_encoded_queries_and_reminder_groups_survive() {
    let fields = json!({"title":"Boundary task", "reminder_group":"overdue", "secret":"private"});
    let network = MockTransport::new(vec![
        json!({"items":[{"id":ID,"fields":fields,"can_edit":true,"can_delete":true}],
            "page":2,"total_pages":2,"total_count":26,"can_write":true}),
        json!({"items":[],"page":1,"total_pages":1,"total_count":0,"can_write":true}),
    ]);
    let action: Action = serde_json::from_value(
        json!({"action":"list","page":2,"query":"A&B + €?status=completed#",
        "filters":{"status":"open","assignee_id":ID,"reminder":"overdue","group_by":"reminder"}}),
    )
    .unwrap();
    let output = execute_using(&network, saved(), Resource::Tasks, action).unwrap();
    assert_eq!(output["items"][0]["fields"]["reminder_group"], "overdue");
    assert!(output["items"][0]["fields"].get("secret").is_none());
    assert_eq!(output["total_count"], 26);
    let url = url::Url::parse(&network.requests.borrow()[0].0).unwrap();
    assert_eq!(url.path(), "/api/native/tasks");
    assert!(url.fragment().is_none());
    assert_eq!(
        url.query_pairs().collect::<Vec<_>>(),
        [
            ("page".into(), "2".into()),
            ("query".into(), "A&B + €?status=completed#".into()),
            ("assignee_id".into(), ID.into()),
            ("group_by".into(), "reminder".into()),
            ("reminder".into(), "overdue".into()),
            ("status".into(), "open".into()),
        ]
    );

    let legacy: Action = serde_json::from_value(json!({"action":"list"})).unwrap();
    execute_using(&network, saved(), Resource::Tasks, legacy).unwrap();
    assert_eq!(
        network.requests.borrow()[1].0,
        "https://atlas.example/api/native/tasks?page=1&query="
    );
}

#[test]
fn resource_filter_allowlists_validate_before_networking() {
    for (resource, key, values) in [
        (Resource::Tasks, "status", vec!["", "open", "completed"]),
        (Resource::Tasks, "assignee_id", vec!["", ID]),
        (
            Resource::Tasks,
            "reminder",
            vec!["", "overdue", "upcoming", "none"],
        ),
        (Resource::Tasks, "group_by", vec!["", "reminder"]),
        (
            Resource::Accounts,
            "segment",
            vec!["", "customer", "lead", "prospect"],
        ),
        (
            Resource::Accounts,
            "status",
            vec!["", "active", "churned", "paused", "trial"],
        ),
        (
            Resource::Accounts,
            "deal_stage",
            vec![
                "",
                "discovery",
                "poc",
                "legal_review",
                "security_review",
                "negotiation",
                "closed_won",
                "closed_lost",
            ],
        ),
        (
            Resource::Invoices,
            "status",
            vec!["", "extracted", "needs_review", "failed"],
        ),
    ] {
        for value in values {
            let network = MockTransport::new(vec![
                json!({"items":[],"page":1,"total_pages":1,"total_count":0,"can_write":false}),
            ]);
            execute_using(
                &network,
                saved(),
                resource,
                Action::List {
                    page: 1,
                    query: String::new(),
                    filters: BTreeMap::from([(key.into(), value.into())]),
                },
            )
            .unwrap();
            let url = url::Url::parse(&network.requests.borrow()[0].0).unwrap();
            assert_eq!(
                url.query_pairs().find(|(name, _)| name == key).unwrap().1,
                value
            );
        }
    }

    let network = MockTransport::new(vec![]);
    for (resource, key, value) in [
        (Resource::Tasks, "status", "active"),
        (Resource::Tasks, "assignee_id", "../profile"),
        (Resource::Tasks, "reminder", "completed"),
        (Resource::Tasks, "group_by", "due_on"),
        (Resource::Tasks, "segment", ""),
        (Resource::Accounts, "status", "open"),
        (Resource::Accounts, "segment", "other"),
        (Resource::Accounts, "deal_stage", "other"),
        (Resource::Accounts, "assignee_id", ""),
        (Resource::Accounts, "group_by", "reminder"),
        (Resource::Invoices, "status", "paid"),
        (Resource::Invoices, "reminder", ""),
        (Resource::Profile, "status", ""),
    ] {
        assert!(
            execute_using(
                &network,
                saved(),
                resource,
                Action::List {
                    page: 1,
                    query: String::new(),
                    filters: BTreeMap::from([(key.into(), value.into())]),
                }
            )
            .is_err()
        );
    }
    for resource in [
        Resource::Tasks,
        Resource::Accounts,
        Resource::Invoices,
        Resource::Profile,
    ] {
        for key in [
            "unknown",
            "page",
            "query",
            "page_size",
            "filters[status]",
            "url",
        ] {
            assert!(
                execute_using(
                    &network,
                    saved(),
                    resource,
                    Action::List {
                        page: 1,
                        query: String::new(),
                        filters: BTreeMap::from([(key.into(), String::new())]),
                    }
                )
                .is_err()
            );
        }
    }
    for filters in [
        json!({"status":null}),
        json!({"status":[]}),
        json!([]),
        json!("open"),
    ] {
        assert!(
            serde_json::from_value::<Action>(json!({"action":"list","filters":filters})).is_err()
        );
    }
    assert!(network.requests.borrow().is_empty());
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
            filters: BTreeMap::new(),
        },
        Action::Create {
            fields: BTreeMap::from([("metadata".into(), Some("manual".into()))]),
        },
        Action::Create {
            fields: BTreeMap::from([("reminder_group".into(), Some("overdue".into()))]),
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
            filters: BTreeMap::new(),
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
