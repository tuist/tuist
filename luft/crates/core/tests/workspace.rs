//! Public bridge contract: these operations must never invoke identity storage.
use serde_json::{Value, json};
use std::collections::VecDeque;
use tuist_app_core::{Host, MobileClient};

const TOKEN: &str = "preview-secret-do-not-display";
const ID: &str = "11111111-1111-4111-8111-111111111111";
const REQUEST: &str = "33333333-3333-4333-8333-333333333333";
const MODULE: &str = "accounts.customers";

#[derive(Default)]
struct Http {
    replies: VecDeque<Value>,
    calls: Vec<Value>,
}
impl Host for Http {
    fn perform(&mut self, action: Value) -> Result<Value, String> {
        assert_eq!(
            action["type"], "http",
            "preview touched a non-HTTP host service"
        );
        assert_eq!(
            action["headers"]["Authorization"],
            format!("Bearer {TOKEN}")
        );
        assert!(
            action["url"]
                .as_str()
                .unwrap()
                .starts_with("http://127.0.0.1:4210/")
        );
        self.calls.push(action);
        Ok(self.replies.pop_front().expect("unexpected HTTP request"))
    }
}
fn response(status: u16, body: Value) -> Value {
    json!({"status":status,"body":body.to_string()})
}
fn manifest() -> Value {
    let mut manifest: Value =
        serde_json::from_str(include_str!("../../../apps/customer-management/app.json")).unwrap();
    manifest["ui_modules"][0]["source"] = json!("// bounded native module source");
    manifest
}
fn row(status: &str, revision: u64) -> Value {
    json!({"id":ID,"revision":revision,"name":"Northstar Labs","email":"ops@northstar.example","status":status})
}
fn call(client: &mut MobileClient, host: &mut Http, op: &str, mut args: Value) -> Value {
    args["module"] = json!(MODULE);
    let result: Value =
        serde_json::from_str(&client.call(&json!({"operation":op,"args":args}).to_string(), host))
            .unwrap();
    assert!(!result.to_string().contains(TOKEN));
    result
}
fn connect() -> (MobileClient, Http) {
    let mut client = MobileClient::new();
    let mut host = Http::default();
    host.replies.push_back(response(200, manifest()));
    let result = call(
        &mut client,
        &mut host,
        "workspace_connect",
        json!({"url":"http://127.0.0.1:4210","token":TOKEN}),
    );
    assert_eq!(result["view"]["connected"], true);
    assert!(result.get("error").is_none());
    (client, host)
}
fn create_args(request: &str) -> Value {
    json!({"action":"accounts.customer.create","request_id":request,"input":{"values":{"name":"Northstar Labs","email":"ops@northstar.example","status":"lead"}}})
}

#[test]
fn workspace_lists_creates_and_updates_through_public_core() {
    let (mut client, mut host) = connect();
    host.replies
        .push_back(response(200, json!({"items":[row("active",1)]})));
    let result = call(
        &mut client,
        &mut host,
        "workspace_query",
        json!({"query":"accounts.customer.list","input":{}}),
    );
    assert_eq!(result["view"]["items"][0]["name"], "Northstar Labs");
    assert_eq!(host.calls[1]["url"], "http://127.0.0.1:4210/query");
    host.replies.push_back(response(200, row("lead", 1)));
    host.replies
        .push_back(response(200, json!({"items":[row("lead",1)]})));
    let result = call(
        &mut client,
        &mut host,
        "workspace_action",
        create_args(REQUEST),
    );
    assert!(result.get("error").is_none(), "{result}");
    assert_eq!(result["view"]["items"][0]["status"], "lead");
    host.replies.push_back(response(200, row("paused", 2)));
    host.replies
        .push_back(response(200, json!({"items":[row("paused",2)]})));
    let result = call(
        &mut client,
        &mut host,
        "workspace_action",
        json!({"action":"accounts.customer.update","request_id":REQUEST,"input":{"id":ID,"expected_revision":1,"values":{"status":"paused"}}}),
    );
    assert!(result.get("error").is_none(), "{result}");
    assert_eq!(result["view"]["items"][0]["revision"], 2);
}

#[test]
fn workspace_denies_undeclared_names_and_invalid_inputs_without_http() {
    let (mut client, mut host) = connect();
    for (op, args) in [
        (
            "workspace_query",
            json!({"query":"accounts.secret.list","input":{}}),
        ),
        (
            "workspace_action",
            json!({"action":"accounts.customer.delete","request_id":REQUEST,"input":{}}),
        ),
        (
            "workspace_action",
            json!({"action":"accounts.customer.create","request_id":REQUEST,"input":{"values":{"name":"","status":"lead"}}}),
        ),
        (
            "workspace_action",
            json!({"action":"accounts.customer.update","request_id":REQUEST,"input":{"id":ID,"expected_revision":0,"values":{"status":"active"}}}),
        ),
        (
            "workspace_action",
            json!({"action":"accounts.customer.create","request_id":"not-a-uuid","input":{"values":{"name":"Demo","status":"lead"}}}),
        ),
    ] {
        assert!(
            call(&mut client, &mut host, op, args)
                .get("error")
                .is_some()
        );
    }
    assert_eq!(host.calls.len(), 1);
}

#[test]
fn workspace_rejects_malformed_records_and_manifests() {
    for bad in [
        json!({"items":null}),
        json!({"items":[row("unknown",1)]}),
        json!({"items":[row("active",0)]}),
        json!({"items":[row("active",1),row("active",1)]}),
        json!({"items":[{"id":"not-uuid","revision":1,"name":"Bad","status":"lead"}]}),
    ] {
        let (mut client, mut host) = connect();
        host.replies.push_back(response(200, bad));
        let result = call(
            &mut client,
            &mut host,
            "workspace_query",
            json!({"query":"accounts.customer.list","input":{}}),
        );
        assert_eq!(result["error"], "Invalid workspace response");
        assert!(result["view"]["items"].is_null());
    }
    for bad in [
        json!({}),
        {
            let mut m = manifest();
            m["ui_modules"][0]["source"] = json!("");
            m
        },
        {
            let mut m = manifest();
            m["ui_modules"][0]["capabilities"]["actions"] = json!(["unknown"]);
            m
        },
    ] {
        let mut client = MobileClient::new();
        let mut host = Http::default();
        host.replies.push_back(response(200, bad));
        let result = call(
            &mut client,
            &mut host,
            "workspace_connect",
            json!({"url":"http://127.0.0.1:4210","token":TOKEN}),
        );
        assert_eq!(result["view"]["connected"], false);
        assert!(result["view"]["modules"].is_null());
    }
}

#[test]
fn workspace_safe_retries_reuse_request_and_new_submission_is_distinct() {
    let (mut client, mut host) = connect();
    host.replies.push_back(json!({"error":"offline"}));
    host.replies
        .push_back(response(500, json!({"error":{"code":"UNAVAILABLE"}})));
    let result = call(
        &mut client,
        &mut host,
        "workspace_action",
        create_args(REQUEST),
    );
    assert_eq!(result["view"]["can_retry"], true);
    assert_eq!(host.calls[1], host.calls[2]);
    host.replies.push_back(response(200, row("lead", 1)));
    host.replies
        .push_back(response(200, json!({"items":[row("lead",1)]})));
    let result = call(&mut client, &mut host, "workspace_retry", json!({}));
    assert!(result.get("error").is_none(), "{result}");
    assert_eq!(host.calls[1], host.calls[3]);
    let next = "44444444-4444-4444-8444-444444444444";
    host.replies.push_back(response(200, row("lead", 1)));
    host.replies
        .push_back(response(200, json!({"items":[row("lead",1)]})));
    call(
        &mut client,
        &mut host,
        "workspace_action",
        create_args(next),
    );
    let old: Value = serde_json::from_str(host.calls[1]["body"].as_str().unwrap()).unwrap();
    let new: Value = serde_json::from_str(host.calls[5]["body"].as_str().unwrap()).unwrap();
    assert_ne!(old["request_id"], new["request_id"]);
}

#[test]
fn workspace_disconnect_clears_source_data_credentials_and_blocks_calls() {
    for explicit in [true, false] {
        let (mut client, mut host) = connect();
        host.replies
            .push_back(response(200, json!({"items":[row("active",1)]})));
        call(
            &mut client,
            &mut host,
            "workspace_query",
            json!({"query":"accounts.customer.list","input":{}}),
        );
        let result = if explicit {
            call(&mut client, &mut host, "workspace_disconnect", json!({}))
        } else {
            host.replies
                .extend([json!({"error":"offline"}), json!({"error":"offline"})]);
            call(
                &mut client,
                &mut host,
                "workspace_action",
                create_args(REQUEST),
            )
        };
        assert_eq!(result["view"]["connected"], false);
        assert!(result["view"]["modules"].is_null());
        assert!(result["view"]["items"].is_null());
        let count = host.calls.len();
        let result = call(
            &mut client,
            &mut host,
            "workspace_action",
            create_args(REQUEST),
        );
        assert!(result.get("error").is_some());
        assert_eq!(host.calls.len(), count);
    }
}

#[test]
fn workspace_never_discloses_credentials_even_in_escaped_server_strings() {
    let (mut client, mut host) = connect();
    let mut bad = row("active", 1);
    bad["name"] = json!(TOKEN);
    let text = json!({"items":[bad]})
        .to_string()
        .replace("preview-secret", "\\u0070review-secret");
    host.replies.push_back(json!({"status":200,"body":text}));
    assert_eq!(
        call(
            &mut client,
            &mut host,
            "workspace_query",
            json!({"query":"accounts.customer.list","input":{}})
        )["error"],
        "Invalid workspace response"
    );
    host.replies.push_back(response(
        422,
        json!({"error":{"code":"VALIDATION_FAILED","message":format!("unsafe {TOKEN}")}}),
    ));
    assert!(
        call(
            &mut client,
            &mut host,
            "workspace_action",
            create_args(REQUEST)
        )
        .get("error")
        .is_some()
    );
    let snapshot = call(&mut client, &mut host, "workspace_snapshot", json!({}));
    assert!(!snapshot.to_string().contains("Bearer"));
}

#[test]
fn workspace_rejects_nonlocal_insecure_or_credentialed_origins_before_http() {
    let mut client = MobileClient::new();
    let mut host = Http::default();
    for url in [
        "http://192.168.1.1:4210",
        "http://example.com",
        "file:///tmp/workspace",
        "https://user:password@example.com",
        "http://localhost:4210/?token=bad",
        "http://localhost:4210/api",
    ] {
        let result = call(
            &mut client,
            &mut host,
            "workspace_connect",
            json!({"url":url,"token":TOKEN}),
        );
        assert_eq!(result["view"]["connected"], false);
        assert!(result.get("error").is_some());
    }
    assert!(host.calls.is_empty());
}

#[test]
fn workspace_accepts_additive_versions_defaults_and_null_optional_fields() {
    // Deliberately authored separately from workspace.json: this checks the
    // server contract rather than making both sides agree on one fixture.
    let published = json!({"format":1,"organization":"demo","title":"Versioned test",
        "models":{"accounts.customer":{"version":3,"fields":{
            "name":{"type":"string","required":true},
            "email":{"type":"string"},
            "status":{"type":"enum","values":["lead","active"],"required":true,"default":"lead"},
            "code":{"type":"string","nullable":false,"default":"external"},
            "notes":{"type":"string"}}}},
        "queries":{"accounts.customer.list":{"model":"accounts.customer","operation":"list"}},
        "actions":{"accounts.customer.create":{"model":"accounts.customer","operation":"create"}},
        "ui_modules":[{"id":MODULE,"title":"Customers","group":"Accounts","model":"accounts.customer",
            "source":"// test","capabilities":{"queries":["accounts.customer.list"],"actions":["accounts.customer.create"]}}]});
    let mut client = MobileClient::new();
    let mut host = Http::default();
    host.replies.push_back(response(200, published));
    let result = call(
        &mut client,
        &mut host,
        "workspace_connect",
        json!({"url":"http://127.0.0.1:4210","token":TOKEN}),
    );
    assert!(result.get("error").is_none(), "{result}");
    let saved = json!({"id":ID,"revision":1,"name":"Defaulted customer","email":null,"status":"lead","code":"external","notes":null});
    host.replies.push_back(response(200, saved.clone()));
    host.replies
        .push_back(response(200, json!({"items":[saved]})));
    let result = call(
        &mut client,
        &mut host,
        "workspace_action",
        json!({"action":"accounts.customer.create","request_id":REQUEST,"input":{"values":{"name":"Defaulted customer"}}}),
    );
    assert!(result.get("error").is_none(), "{result}");
    assert_eq!(result["view"]["items"][0]["status"], "lead");
    assert!(result["view"]["items"][0]["notes"].is_null());
    host.replies.push_back(response(
        200,
        json!({"items":[{"id":ID,"revision":1,"name":"Invalid null","email":null,"status":"lead","code":null,"notes":null}]}),
    ));
    assert!(
        call(
            &mut client,
            &mut host,
            "workspace_query",
            json!({"query":"accounts.customer.list","input":{}})
        )
        .get("error")
        .is_some()
    );
    // A default is allowed on *input*, but required response fields must exist.
    host.replies.push_back(response(
        200,
        json!({"items":[{"id":ID,"revision":1,"name":"Missing saved status"}]}),
    ));
    assert!(
        call(
            &mut client,
            &mut host,
            "workspace_query",
            json!({"query":"accounts.customer.list","input":{}})
        )
        .get("error")
        .is_some()
    );
}

#[test]
fn workspace_string_limit_is_4000_bytes_not_characters() {
    for (name, valid) in [
        ("x".repeat(4000), true),
        ("x".repeat(4001), false),
        ("é".repeat(2000), true),
        ("é".repeat(2001), false),
    ] {
        let (mut client, mut host) = connect();
        let mut args = create_args(REQUEST);
        args["input"]["values"]["name"] = json!(name);
        if valid {
            let mut saved = row("lead", 1);
            saved["name"] = args["input"]["values"]["name"].clone();
            host.replies.push_back(response(200, saved.clone()));
            host.replies
                .push_back(response(200, json!({"items":[saved]})));
        }
        let result = call(&mut client, &mut host, "workspace_action", args);
        assert_eq!(result.get("error").is_none(), valid, "{result}");
        assert_eq!(host.calls.len(), if valid { 3 } else { 1 });
    }
}

#[test]
fn workspace_unauthorized_is_closed_even_when_the_body_is_malformed() {
    let (mut client, mut host) = connect();
    host.replies
        .push_back(json!({"status":401,"body":"not-json"}));
    let result = call(
        &mut client,
        &mut host,
        "workspace_query",
        json!({"query":"accounts.customer.list","input":{}}),
    );
    assert_eq!(result["view"]["connected"], false);
    assert!(result["view"]["modules"].is_null());
}

fn support_manifest() -> Value {
    let mut catalog = manifest();
    let support: Value =
        serde_json::from_str(include_str!("../../../apps/support/app.json")).unwrap();
    for kind in ["models", "queries", "actions"] {
        catalog[kind]
            .as_object_mut()
            .unwrap()
            .extend(support[kind].as_object().unwrap().clone());
    }
    let mut module = support["ui_modules"][0].clone();
    module["source"] = json!("// independent support source");
    // Deliberately put the foreign getter first: writes must refresh the inbox.
    module["capabilities"]["queries"] = json!([
        "accounts.customer.get",
        "support.conversation.list",
        "support.conversation.get"
    ]);
    catalog["ui_modules"] = json!([module]);
    catalog
}

fn support_connect(catalog: Value) -> (MobileClient, Http, Value) {
    let mut client = MobileClient::new();
    let mut host = Http::default();
    host.replies.push_back(response(200, catalog));
    let result = call(
        &mut client,
        &mut host,
        "workspace_connect",
        json!({"url":"http://127.0.0.1:4210","token":TOKEN}),
    );
    (client, host, result)
}

fn support_call(client: &mut MobileClient, host: &mut Http, op: &str, mut args: Value) -> Value {
    args["module"] = json!("support.inbox");
    let result: Value =
        serde_json::from_str(&client.call(&json!({"operation":op,"args":args}).to_string(), host))
            .unwrap();
    assert!(!result.to_string().contains(TOKEN));
    result
}

#[test]
fn support_reads_customer_without_replacing_inbox_and_refreshes_its_own_model_after_writes() {
    let (mut client, mut host, connected) = support_connect(support_manifest());
    assert!(connected.get("error").is_none(), "{connected}");
    let conversation = json!({"id":REQUEST,"revision":4,"subject":"Build cache setup","status":"open","customer":ID});
    host.replies
        .push_back(response(200, json!({"items":[conversation]})));
    let listed = support_call(
        &mut client,
        &mut host,
        "workspace_query",
        json!({"query":"support.conversation.list","input":{}}),
    );
    assert!(listed.get("error").is_none(), "{listed}");
    host.replies
        .push_back(response(200, json!({"record":row("active",2)})));
    let detail = support_call(
        &mut client,
        &mut host,
        "workspace_query",
        json!({"query":"accounts.customer.get","input":{"id":ID}}),
    );
    assert!(detail.get("error").is_none(), "{detail}");
    assert_eq!(detail["data"]["record"]["name"], "Northstar Labs");
    assert_eq!(detail["view"]["items"], listed["view"]["items"]);
    let saved = json!({"id":REQUEST,"revision":5,"subject":"Build cache setup","status":"closed","customer":ID});
    host.replies.push_back(response(200, saved.clone()));
    host.replies
        .push_back(response(200, json!({"items":[saved]})));
    let changed = support_call(
        &mut client,
        &mut host,
        "workspace_action",
        json!({"action":"support.conversation.update","request_id":ID,"input":{"id":REQUEST,"expected_revision":4,"values":{"status":"closed"}}}),
    );
    assert!(changed.get("error").is_none(), "{changed}");
    assert_eq!(changed["view"]["items"][0]["status"], "closed");
    let refresh: Value =
        serde_json::from_str(host.calls.last().unwrap()["body"].as_str().unwrap()).unwrap();
    assert_eq!(refresh["query"], "support.conversation.list");
    let denied = support_call(&mut client, &mut host, "workspace_action", create_args(ID));
    assert_eq!(denied["error"], "Workspace capability denied");
    assert_eq!(host.calls.len(), 5);
}

#[test]
fn customer_get_requires_explicit_capability_and_validates_record_identity() {
    let mut catalog = support_manifest();
    catalog["ui_modules"][0]["capabilities"]["queries"] = json!(["support.conversation.list"]);
    let (mut client, mut host, _) = support_connect(catalog);
    let denied = support_call(
        &mut client,
        &mut host,
        "workspace_query",
        json!({"query":"accounts.customer.get","input":{"id":ID}}),
    );
    assert_eq!(denied["error"], "Workspace capability denied");
    assert_eq!(host.calls.len(), 1);
    for bad_id in [REQUEST, "not-a-uuid"] {
        let (mut client, mut host, _) = support_connect(support_manifest());
        let mut wrong = row("active", 1);
        wrong["id"] = json!(bad_id);
        host.replies
            .push_back(response(200, json!({"record":wrong})));
        let result = support_call(
            &mut client,
            &mut host,
            "workspace_query",
            json!({"query":"accounts.customer.get","input":{"id":ID}}),
        );
        assert!(result.get("error").is_some(), "{result}");
        assert!(result["data"].is_null());
    }
    let mut catalog = support_manifest();
    catalog["ui_modules"][0]["capabilities"]["actions"] = json!(["accounts.customer.update"]);
    let (_, _, rejected) = support_connect(catalog);
    assert_eq!(rejected["view"]["connected"], false);
}

#[test]
fn reference_inputs_and_rows_are_uuid_typed() {
    let (mut client, mut host, _) = support_connect(support_manifest());
    let invalid = support_call(
        &mut client,
        &mut host,
        "workspace_action",
        json!({"action":"support.conversation.update","request_id":ID,"input":{"id":REQUEST,"expected_revision":1,"values":{"customer":"Northstar"}}}),
    );
    assert!(invalid.get("error").is_some());
    assert_eq!(host.calls.len(), 1);
    host.replies.push_back(response(200, json!({"items":[{"id":REQUEST,"revision":1,"subject":"Invalid reference","status":"open","customer":"Northstar"}]})));
    let invalid = support_call(
        &mut client,
        &mut host,
        "workspace_query",
        json!({"query":"support.conversation.list","input":{}}),
    );
    assert!(invalid.get("error").is_some());
    assert!(invalid["view"]["items"].is_null());
}

#[test]
fn contextual_references_fetch_current_records_and_fail_closed() {
    let (mut client, mut host, _) = support_connect(support_manifest());
    let reference = json!({"model":"support.conversation","id":REQUEST});
    for revision in [4, 7] {
        let record = json!({"id":REQUEST,"revision":revision,"subject":"Current subject","status":"closed","customer":ID});
        host.replies
            .push_back(response(200, json!({"record":record})));
        let opened = support_call(&mut client, &mut host, "workspace_open", reference.clone());
        assert!(opened.get("error").is_none(), "{opened}");
        assert_eq!(opened["data"]["record"], record);
        assert_eq!(opened["view"]["record"], record);
        assert!(opened["view"]["items"].is_null());
        let body: Value =
            serde_json::from_str(host.calls.last().unwrap()["body"].as_str().unwrap()).unwrap();
        assert_eq!(
            body,
            json!({"query":"support.conversation.get","input":{"id":REQUEST}})
        );
    }
    let count = host.calls.len();
    for invalid in [
        json!({"model":"accounts.customer","id":ID}),
        json!({"model":"support.conversation","id":"not-a-uuid"}),
    ] {
        let result = support_call(&mut client, &mut host, "workspace_open", invalid);
        assert!(result.get("error").is_some());
    }
    assert_eq!(host.calls.len(), count);
    host.replies
        .push_back(response(404, json!({"error":{"code":"NOT_FOUND"}})));
    let absent = support_call(&mut client, &mut host, "workspace_open", reference.clone());
    assert!(absent["view"]["record"].is_null());
    assert!(absent["data"].is_null());
    assert!(absent.get("error").is_some());

    let mut catalog = support_manifest();
    catalog["ui_modules"][0]["capabilities"]["queries"] = json!(["support.conversation.list"]);
    let (mut client, mut host, _) = support_connect(catalog);
    let denied = support_call(&mut client, &mut host, "workspace_open", reference);
    assert_eq!(denied["error"], "Workspace record entry is not declared");
    assert_eq!(host.calls.len(), 1);
}

#[test]
fn committed_write_remains_successful_when_refresh_fails() {
    let (mut client, mut host) = connect();
    let saved = row("lead", 1);
    host.replies.push_back(response(200, saved.clone()));
    host.replies
        .push_back(response(500, json!({"error":{"code":"UNAVAILABLE"}})));
    let created = call(
        &mut client,
        &mut host,
        "workspace_action",
        create_args(REQUEST),
    );
    assert!(created.get("error").is_none(), "{created}");
    assert_eq!(created["data"], saved);
    assert_eq!(created["view"]["can_retry"], false);
    assert!(
        created["view"]["warning"]
            .as_str()
            .unwrap()
            .starts_with("Saved,")
    );
    let count = host.calls.len();
    let retry = call(&mut client, &mut host, "workspace_retry", json!({}));
    assert_eq!(retry["error"], "Nothing to retry");
    assert_eq!(host.calls.len(), count);
    host.replies
        .push_back(response(200, json!({"items":[saved]})));
    let refreshed = call(
        &mut client,
        &mut host,
        "workspace_query",
        json!({"query":"accounts.customer.list","input":{}}),
    );
    assert!(refreshed["view"]["warning"].is_null());
    assert_eq!(refreshed["view"]["items"][0]["revision"], 1);
}

#[test]
fn pending_submission_cannot_be_replaced_and_failed_reads_preserve_retry() {
    let (mut client, mut host) = connect();
    host.replies
        .push_back(response(500, json!({"error":{"code":"UNAVAILABLE"}})));
    let result = call(
        &mut client,
        &mut host,
        "workspace_action",
        create_args(REQUEST),
    );
    assert_eq!(result["view"]["can_retry"], true);
    let count = host.calls.len();
    let blocked = call(&mut client, &mut host, "workspace_action", create_args(ID));
    assert!(blocked.get("error").is_some());
    assert_eq!(host.calls.len(), count);
    host.replies
        .push_back(response(404, json!({"error":{"code":"NOT_FOUND"}})));
    let read = call(
        &mut client,
        &mut host,
        "workspace_query",
        json!({"query":"accounts.customer.list","input":{}}),
    );
    assert_eq!(read["view"]["can_retry"], true);
    host.replies.push_back(response(200, row("lead", 1)));
    host.replies
        .push_back(response(200, json!({"items":[row("lead",1)]})));
    let retry = call(&mut client, &mut host, "workspace_retry", json!({}));
    assert!(retry.get("error").is_none());
    assert_eq!(host.calls[1], host.calls[3]);
}
