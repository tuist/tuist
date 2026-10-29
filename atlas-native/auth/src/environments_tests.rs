use super::*;
use crate::tests::{MockTransport, registration};

const ID: &str = "01922cc0-0000-7000-8000-000000000001";
const PROJECT: &str = "01922cc0-0000-7000-8000-000000000002";
const CALL: &str = "01922cc0-0000-7000-8000-000000000003";

fn session() -> Session {
    Session {
        registration: registration(),
        access_token: "test-access".into(),
        refresh_token: "test-refresh".into(),
        expires_at: now() + 3600,
        cache_id: None,
    }
}

fn action(mut value: Value) -> Action {
    value["session"] = json!(session());
    serde_json::from_value(value).unwrap()
}

#[test]
fn hosted_provider_selection_uses_the_existing_private_selection_route() {
    let network = MockTransport::new(vec![json!({"thread":{
        "id":ID,"environment_id":CALL,"environment_name":"Tuist","project_id":PROJECT
    }})]);
    let result = execute_using(
        &network,
        action(json!({
            "action":"start_provider","thread_id":ID,"provider":"tuist"
        })),
    )
    .unwrap();
    assert_eq!(result["thread"]["environment_id"], CALL);
    let requests = network.requests.borrow();
    assert_eq!(
        requests[0].0,
        format!("https://atlas.example/api/native/orbit/threads/{ID}/environment")
    );
    assert_eq!(requests[0].1["method"], "PATCH");
    assert_eq!(requests[0].1["payload"], json!({"provider":"tuist"}));
    drop(requests);
    let network = MockTransport::new(vec![]);
    for provider in ["../tuist", "https://evil.example", "", "Tuist"] {
        assert!(
            execute_using(
                &network,
                action(json!({
                    "action":"start_provider","thread_id":ID,"provider":provider
                }))
            )
            .is_err()
        );
    }
    assert!(network.requests.borrow().is_empty());
}

#[test]
fn native_bridge_decodes_environment_actions_without_networking_for_expired_sessions() {
    let mut expired = session();
    expired.expires_at = 0;
    for mut request in [
        json!({"action":"list"}),
        json!({"action":"register","id":ID,"name":"Demo Mac","enabled":true,
               "terminal":false,"display":false,"projects":[{"id":PROJECT,"name":"Example"}]}),
        json!({"action":"disable","id":ID}),
        json!({"action":"commands","id":ID}),
        json!({"action":"claim","id":ID,"command_id":CALL,"digest":"a".repeat(64)}),
        json!({"action":"thread_commands","thread_id":ID}),
        json!({"action":"cancel_command","thread_id":ID,"command_id":CALL,"digest":"a".repeat(64)}),
        json!({"action":"progress","id":ID,"command_id":CALL,"claim_token":ID,"sequence":1,"output":"building"}),
        json!({"action":"complete","id":ID,"command_id":CALL,"claim_token":ID,"success":true,"output":"done"}),
        json!({"action":"selection","thread_id":ID}),
        json!({"action":"select","thread_id":ID,"environment_id":ID,"project_id":PROJECT}),
        json!({"action":"start_provider","thread_id":ID,"provider":"tuist"}),
        json!({"action":"open","id":ID}),
    ] {
        request["operation"] = json!("environment");
        request["session"] = json!(expired);
        let response: Value =
            serde_json::from_str(&crate::bridge::execute(&request.to_string())).unwrap();
        assert_eq!(response["error"]["kind"], "sign_in_required");
        request["owner_id"] = json!(ID);
        let rejected: Value =
            serde_json::from_str(&crate::bridge::execute(&request.to_string())).unwrap();
        assert_eq!(rejected["error"]["kind"], "invalid_response");
    }
}

#[test]
fn coding_envelopes_preserve_worktree_identity_and_reject_cross_tool_arguments() {
    for (tool, args, timeout) in [
        (
            "read",
            json!({"path":"src/main.rs","offset":2,"limit":1}),
            60,
        ),
        ("write", json!({"path":"empty","content":""}), 60),
        (
            "edit",
            json!({"path":"file","edits":[{"oldText":"é","newText":"λ"}]}),
            60,
        ),
        ("bash", json!({"command":"cargo test","timeout":90}), 1800),
    ] {
        let mut args = args;
        args["project_id"] = json!(PROJECT);
        args["thread_id"] = json!(ID);
        args["title"] = json!("Fix unicode handling");
        let command = json!({"id":CALL,"tool":tool,"arguments":args,
            "execution_timeout_seconds":timeout,"digest":"a".repeat(64)});
        let accepted = sanitize_commands(json!({"commands":[command.clone()]})).unwrap();
        assert_eq!(accepted["commands"][0], command);
        let mut missing = command.clone();
        missing["arguments"]
            .as_object_mut()
            .unwrap()
            .remove("thread_id");
        assert!(sanitize_commands(json!({"commands":[missing]})).is_err());
        let mut injected = command;
        injected["arguments"]["root"] = json!("/outside");
        assert!(sanitize_commands(json!({"commands":[injected]})).is_err());
    }
    let command = json!({"id":CALL,"tool":"write","arguments":{
        "project_id":PROJECT,"thread_id":ID,"title":"Fix","path":"file","content":"ok","command":"injected"},
        "execution_timeout_seconds":60,"digest":"a".repeat(64)});
    assert!(sanitize_commands(json!({"commands":[command]})).is_err());
}

#[test]
fn github_checkout_metadata_round_trips_without_becoming_a_path_or_permission() {
    let configuration = json!({"name":"Demo Mac","enabled":true,"terminal":false,"display":false,
        "projects":[{"id":PROJECT,"name":"Code","coding":true,"repository":"acme/code"}]});
    let mut environment = configuration.clone();
    environment["id"] = json!(ID);
    environment["online"] = json!(false);
    let network = MockTransport::new(vec![
        json!({"environment":environment}),
        json!({"owner_id":ID,"environments":[environment]}),
    ]);
    let mut register = configuration.clone();
    register["action"] = json!("register");
    register["id"] = json!(ID);
    execute_using(&network, action(register)).unwrap();
    let list = execute_using(&network, action(json!({"action":"list"}))).unwrap();
    assert_eq!(
        list["environments"][0]["projects"][0]["repository"],
        "acme/code"
    );
    assert_eq!(network.requests.borrow()[0].1["payload"], configuration);
    for project in [
        json!({"id":PROJECT,"name":"Code","repository":"acme/code"}),
        json!({"id":PROJECT,"name":"Code","coding":true,"repository":"/Users/me/code"}),
        json!({"id":PROJECT,"name":"Code","coding":true,"repository":"https://github.com/acme/code"}),
    ] {
        let mut invalid = configuration.clone();
        invalid["projects"] = json!([project]);
        let config: Configuration = serde_json::from_value(invalid).unwrap();
        assert!(validate_configuration(&config).is_err());
    }
}

#[test]
fn environment_lifecycle_uses_fixed_routes_and_projects_only_validated_results() {
    let configuration = json!({
        "name":"Demo Mac", "enabled":true, "terminal":true, "display":false,
        "projects":[{"id":PROJECT,"name":"Example"}]
    });
    let mut environment = configuration.clone();
    environment["id"] = json!(ID);
    environment["online"] = json!(false);
    environment["owner_secret"] = json!("must-not-forward");
    let command = json!({
        "id":CALL,"tool":"environment_terminal","arguments":{"project_id":PROJECT,"command":"pwd"},
        "execution_timeout_seconds":1800,
        "digest":"a".repeat(64),"claim_token":ID,"secret":"must-not-forward"
    });
    let network = MockTransport::new(vec![
        json!({"environment":environment}),
        json!({"command":command}),
        json!({"received":true,"secret":"must-not-forward"}),
        json!({"disabled":true}),
    ]);
    let mut register = configuration.clone();
    register["action"] = json!("register");
    register["id"] = json!(ID);
    assert_eq!(
        execute_using(&network, action(register)).unwrap(),
        json!({"registered":true})
    );
    let claimed = execute_using(
        &network,
        action(json!({
            "action":"claim","id":ID,"command_id":CALL,"digest":"a".repeat(64)
        })),
    )
    .unwrap();
    assert_eq!(claimed["command"]["arguments"]["command"], "pwd");
    assert!(claimed["command"].get("secret").is_none());
    assert_eq!(execute_using(&network, action(json!({
        "action":"complete","id":ID,"command_id":CALL,"claim_token":ID,"success":true,"output":"/demo"
    }))).unwrap(), json!({"completed":true}));
    assert_eq!(
        execute_using(&network, action(json!({"action":"disable","id":ID}))).unwrap(),
        json!({"disabled":true})
    );
    let requests = network.requests.borrow();
    for (index, (suffix, method)) in [
        ("".into(), "PUT"),
        (format!("/commands/{CALL}/claim"), "POST"),
        (format!("/commands/{CALL}/result"), "POST"),
        ("".into(), "DELETE"),
    ]
    .into_iter()
    .enumerate()
    {
        assert_eq!(
            requests[index].0,
            format!("https://atlas.example/api/me/environments/{ID}{suffix}")
        );
        assert_eq!(requests[index].1["method"], method);
        assert_eq!(requests[index].1["token"], "test-access");
    }
    assert_eq!(requests[0].1["payload"], configuration);
    assert_eq!(requests[1].1["payload"], json!({"digest":"a".repeat(64)}));
    assert_eq!(
        requests[2].1["payload"],
        json!({"claim_token":ID,"success":true,"output":"/demo"})
    );
}

#[test]
fn invalid_selectors_permissions_and_mutation_acknowledgements_fail_closed() {
    let mut valid = json!({
        "action":"register","id":ID,"session":session(),"name":"Demo Mac","enabled":true,
        "terminal":false,"display":false,"projects":[{"id":PROJECT,"name":"Example"}]
    });
    let parsed: Action = serde_json::from_value(valid.clone()).unwrap();
    let network = MockTransport::new(vec![json!({"environment":null})]);
    assert!(execute_using(&network, parsed).is_err());
    valid["owner_id"] = json!(ID);
    assert!(serde_json::from_value::<Action>(valid).is_err());
    let network = MockTransport::new(vec![]);
    for value in [
        json!({"action":"commands","id":"../../other-owner"}),
        json!({"action":"select","thread_id":ID,"environment_id":ID,"project_id":null}),
        json!({"action":"complete","id":ID,"command_id":CALL,"claim_token":ID,"success":true,"output":"x".repeat(65537)}),
    ] {
        assert!(execute_using(&network, action(value)).is_err());
    }
    assert!(network.requests.borrow().is_empty());
    let network = MockTransport::new(vec![json!({"command":{
        "id":CALL,"tool":"environment_terminal","arguments":{"project_id":PROJECT,"command":"pwd"},
        "digest":"a".repeat(64),"claim_token":ID
    }})]);
    assert!(
        execute_using(
            &network,
            action(json!({
                "action":"claim","id":ID,"command_id":CALL,"digest":"a".repeat(64)
            }))
        )
        .is_err()
    );
    let network = MockTransport::new(vec![json!({"disabled":false})]);
    assert!(execute_using(&network, action(json!({"action":"disable","id":ID}))).is_err());
}

#[test]
fn device_progress_and_owner_cancellation_use_separate_authorities_and_fixed_routes() {
    let job = json!({
        "id":CALL,"message_id":CALL,"environment_id":ID,"environment_name":"Build Mac",
        "project_id":PROJECT,"project_name":"Application","digest":"b".repeat(64),
        "command":"xcodebuild -scheme Example build","status":"queued","output":"",
        "success":null,"cancel_requested":false,"progress_sequence":0,"execution_timeout_seconds":1800,
        "claim_token":"must-not-forward"
    });
    let network = MockTransport::new(vec![
        json!({"commands":[job]}),
        json!({"received":true,"cancel_requested":true,"private":"must-not-forward"}),
        json!({"received":true}),
    ]);
    let activity = execute_using(
        &network,
        action(json!({"action":"thread_commands","thread_id":ID})),
    )
    .unwrap();
    assert!(activity["commands"][0].get("claim_token").is_none());
    assert_eq!(
        activity["commands"][0]["command"],
        "xcodebuild -scheme Example build"
    );
    let progress = execute_using(&network, action(json!({
        "action":"progress","id":ID,"command_id":CALL,"claim_token":PROJECT,"sequence":17,"output":"Compile 42"
    }))).unwrap();
    assert_eq!(progress, json!({"received":true,"cancel_requested":true}));
    execute_using(
        &network,
        action(json!({
            "action":"cancel_command","thread_id":ID,"command_id":CALL,"digest":"b".repeat(64)
        })),
    )
    .unwrap();
    let requests = network.requests.borrow();
    assert_eq!(
        requests[0].0,
        format!("https://atlas.example/api/native/orbit/threads/{ID}/environment-commands")
    );
    assert_eq!(requests[0].1["method"], "GET");
    assert_eq!(
        requests[1].0,
        format!("https://atlas.example/api/me/environments/{ID}/commands/{CALL}/progress")
    );
    assert_eq!(
        requests[1].1["payload"],
        json!({"claim_token":PROJECT,"sequence":17,"output":"Compile 42"})
    );
    assert_eq!(
        requests[2].0,
        format!(
            "https://atlas.example/api/native/orbit/threads/{ID}/environment-commands/{CALL}/cancel"
        )
    );
    assert_eq!(requests[2].1["payload"], json!({"digest":"b".repeat(64)}));
}

#[test]
fn terminal_requires_the_fixed_execution_limit_but_no_per_command_approval() {
    let command = json!({
        "id":CALL,"tool":"environment_terminal","arguments":{"project_id":PROJECT,"command":"pwd"},
        "digest":"a".repeat(64)
    });
    for additions in [
        json!({}),
        json!({"execution_timeout_seconds":1799}),
        json!({"execution_timeout_seconds":1801}),
    ] {
        let mut invalid_command = command.clone();
        invalid_command
            .as_object_mut()
            .unwrap()
            .extend(additions.as_object().unwrap().clone());
        assert!(sanitize_commands(json!({"commands":[invalid_command]})).is_err());
    }
    let mut valid = command.clone();
    valid["execution_timeout_seconds"] = json!(1800);
    assert!(sanitize_commands(json!({"commands":[valid]})).is_ok());
    let mut legacy_claim =
        json!({"action":"claim","id":ID,"command_id":CALL,"digest":"a".repeat(64),"approved":true});
    legacy_claim["session"] = json!(session());
    assert!(serde_json::from_value::<Action>(legacy_claim).is_err());
    let network = MockTransport::new(vec![]);
    for value in [
        json!({"action":"progress","id":ID,"command_id":CALL,"claim_token":ID,"sequence":0,"output":""}),
        json!({"action":"progress","id":ID,"command_id":CALL,"claim_token":ID,"sequence":1,"output":"x".repeat(49153)}),
        json!({"action":"cancel_command","thread_id":"../other","command_id":CALL,"digest":"a".repeat(64)}),
    ] {
        assert!(execute_using(&network, action(value)).is_err());
    }
    assert!(network.requests.borrow().is_empty());
}
