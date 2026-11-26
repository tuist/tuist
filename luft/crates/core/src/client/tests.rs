use super::*;
use crate::THREADS_UNAVAILABLE;
use crate::ai_subscriptions::{CLAUDE_TOKEN_REFUSED, UNAVAILABLE as AI_SUBSCRIPTIONS_UNAVAILABLE};
use crate::mcp_servers::{ADMINS_ONLY, CANCELLED as MCP_CANCELLED};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use std::collections::VecDeque;

mod releases;
mod resources;

#[derive(Default)]
struct Fake {
    vault: Option<String>,
    actions: Vec<Value>,
    responses: VecDeque<(u64, Value)>,
    fail_write: bool,
    /// Where local stores live; created on first use. `store_directory` isn't
    /// recorded in `actions`, so assertions about HTTP requests stay about HTTP.
    directory: Option<std::path::PathBuf>,
    offline: bool,
    /// What the core logged, kept out of `actions` like `store_directory`.
    logs: Vec<String>,
    /// Frames the presence socket receives on its next read.
    frames: Vec<String>,
}
impl Drop for Fake {
    fn drop(&mut self) {
        if let Some(directory) = &self.directory {
            let _ = std::fs::remove_dir_all(directory);
        }
    }
}
impl Host for Fake {
    fn perform(&mut self, action: Value) -> std::result::Result<Value, String> {
        match action["type"].as_str().unwrap() {
            "log" => {
                self.logs.push(action["message"].as_str().unwrap().into());
                return Ok(json!({"ok":true}));
            }
            "store_directory" => {
                let directory = self.directory.get_or_insert_with(|| {
                    static NEXT: std::sync::atomic::AtomicUsize =
                        std::sync::atomic::AtomicUsize::new(0);
                    let n = NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    let path =
                        std::env::temp_dir().join(format!("luft-store-{}-{n}", std::process::id()));
                    std::fs::create_dir_all(&path).unwrap();
                    path
                });
                return Ok(json!({"path":directory.to_str().unwrap()}));
            }
            "http" if self.offline => return Ok(json!({"error":"offline"})),
            _ => {}
        }
        self.actions.push(action.clone());
        match action["type"].as_str().unwrap() {
            "read" => Ok(json!({"value":self.vault})),
            "write" if self.fail_write => Ok(json!({"error":"sensitive host failure"})),
            "write" => {
                self.vault = Some(action["value"].as_str().unwrap().into());
                Ok(json!({"ok":true}))
            }
            "http" => {
                let (status, body) = self.responses.pop_front().expect("unexpected HTTP request");
                match status {
                    // The request went out but its response was lost.
                    0 => Ok(json!({"error":"offline"})),
                    // A host failure that isn't connectivity, such as a bad certificate.
                    1 => Ok(json!({"error":"certificate"})),
                    _ => Ok(json!({"status":status,"body":body.to_string()})),
                }
            }
            "socket_open" | "socket_send" | "socket_close" => Ok(json!({"ok":true})),
            "socket_read" => Ok(json!({"frames":std::mem::take(&mut self.frames),"closed":false})),
            _ => panic!("unexpected host action"),
        }
    }
}

#[test]
fn session_records_use_authenticated_message_routes_and_fail_closed_after_revocation_or_switch() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let thread = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    let message = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
    let id = "11111111-1111-4111-8111-111111111111";
    let mut catalog: Value = serde_json::from_str(include_str!(
        "../../../../apps/customer-management/app.json"
    ))
    .unwrap();
    catalog["title"] = json!("Accounts");
    catalog["ui_modules"][0]["source"] = json!("// installed source");
    let row = json!({"id":id,"revision":1,"name":"Northstar","email":null,"status":"active"});
    let entry = json!({"workspace":catalog,"module":"accounts.customers","reference":{"model":"accounts.customer","id":id}});
    let args = json!({"thread":thread,"message":message,"generation":c.vault.generation,"surface":"dddddddd-dddd-4ddd-8ddd-dddddddddddd"});
    h.responses.push_back((200, entry.clone()));
    h.responses.push_back((200, json!({"record":row})));
    let opened = call(&mut c, &mut h, "record_open", args.clone());
    assert!(opened.get("error").is_none(), "{opened}");
    assert_eq!(opened["data"]["view"]["record"], row);
    assert_eq!(opened["data"]["entry"], entry["reference"]);
    let http: Vec<_> = h.actions.iter().filter(|a| a["type"] == "http").collect();
    let base = format!("https://one.test/api/accounts/ana/threads/{thread}/records/{message}");
    assert_eq!(http[http.len() - 2]["url"], base);
    assert_eq!(http.last().unwrap()["url"], format!("{base}/query"));
    let body: Value = serde_json::from_str(http.last().unwrap()["body"].as_str().unwrap()).unwrap();
    assert_eq!(
        body,
        json!({"module":"accounts.customers","query":"accounts.customer.get","input":{"id":id}})
    );
    assert!(!opened.to_string().contains(&c.vault.profiles[0].access));

    let mut stale_surface = args.clone();
    stale_surface["surface"] = json!("eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee");
    let count = h.actions.len();
    assert!(call(&mut c, &mut h, "record_close", stale_surface)["error"].is_string());
    assert_eq!(h.actions.len(), count);

    // A retained request is retried under the same authenticated message, never
    // sent to the preview API or queued for a different profile.
    let mut update = args.clone();
    update["action"] = json!("accounts.customer.update");
    update["request_id"] = json!("cccccccc-cccc-4ccc-8ccc-cccccccccccc");
    update["input"] = json!({"id":id,"expected_revision":1,"values":{"status":"paused"}});
    h.responses
        .push_back((500, json!({"error":{"code":"UNAVAILABLE"}})));
    let unknown = call(&mut c, &mut h, "record_action", update);
    assert_eq!(unknown["data"]["view"]["can_retry"], true);
    let original = h.actions.last().unwrap()["body"].clone();

    // Foregrounding/remounting revalidates access and current data, but cannot
    // turn an uncertain submission into a fresh write with a different UUID.
    call(&mut c, &mut h, "record_close", args.clone());
    h.responses.push_back((200, entry.clone()));
    h.responses.push_back((200, json!({"record":row})));
    let reopened = call(&mut c, &mut h, "record_open", args.clone());
    assert_eq!(reopened["data"]["view"]["can_retry"], true);

    // A dropped response receives one byte-identical transport retry. A second
    // loss clears all rendered data, retaining only the unresolved submission.
    h.responses.extend([(0, Value::Null), (0, Value::Null)]);
    let disconnected = call(&mut c, &mut h, "record_retry", args.clone());
    assert_eq!(disconnected["data"]["view"]["connected"], false);
    assert!(disconnected["data"]["view"]["modules"].is_null());
    let attempts: Vec<_> = h.actions.iter().rev().take(2).collect();
    assert!(attempts.iter().all(|request| request["body"] == original));
    h.responses.push_back((200, entry.clone()));
    h.responses.push_back((200, json!({"record":row})));
    let reopened = call(&mut c, &mut h, "record_open", args.clone());
    assert_eq!(reopened["data"]["view"]["can_retry"], true);
    h.responses
        .push_back((403, json!({"error":{"code":"FORBIDDEN"}})));
    let denied = call(&mut c, &mut h, "record_retry", args.clone());
    assert_eq!(h.actions.last().unwrap()["body"], original);
    assert_eq!(denied["data"]["view"]["connected"], false);
    assert!(denied["data"]["view"]["record"].is_null());
    assert!(denied["data"]["view"]["modules"].is_null());

    h.responses.push_back((200, entry));
    h.responses.push_back((200, json!({"record":row})));
    call(&mut c, &mut h, "record_open", args.clone());
    call(&mut c, &mut h, "select_organization", json!({"name":"ana"}));
    // Change to another actual signed-in profile, then send the old surface's command.
    login(&mut c, &mut h, "https://two.test", 2, i64::MAX);
    let count = h.actions.len();
    assert!(call(&mut c, &mut h, "record_retry", args)["error"].is_string());
    assert_eq!(h.actions.len(), count);
    assert_eq!(
        call(&mut c, &mut h, "flush_outbox", json!({}))["data"]["sent"],
        0
    );
}

#[test]
fn decision_answers_are_online_only_retry_idempotently_and_cache_terminal_metadata() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let id = "6f1c2a8e-0b7d-4c3e-9a1f-2d4b8e0c7f53";
    let question = "12345678-1234-5678-9abc-123456789abc";
    let decision = json!({"question":"Which approach?", "options":[{"id":"a","label":"Approach A"}],
        "allow_other":true,"status":"pending","answer":null});
    let mut thread = json!({"id":id,"status":"idle","archive_status":"active","messages":[{
        "id":question,"role":"assistant","content":"Which approach?", "decision":decision,
        "ui":{"size":"medium","source":"mount(() => null)"}
    }]});
    h.responses.push_back((200, thread.clone()));
    let pending = call(&mut c, &mut h, "thread", json!({"id":id}));
    assert_eq!(pending["data"]["messages"][0]["ui"]["height"], 240);
    assert_eq!(pending["data"]["messages"][0]["decision"], decision);
    let args = json!({"id":id,"question_id":question,"option_id":"a","content":"Approach A"});
    h.responses.push_back((0, Value::Null));
    assert_eq!(
        call(&mut c, &mut h, "answer_question", args.clone())["error"],
        OFFLINE
    );
    assert_eq!(
        call(&mut c, &mut h, "flush_outbox", json!({}))["data"]["sent"],
        0
    );
    assert_eq!(
        call(&mut c, &mut h, "cached_thread", json!({"id":id}))["data"]["messages"][0]["decision"],
        decision
    );
    let first: Value =
        serde_json::from_str(h.actions.last().unwrap()["body"].as_str().unwrap()).unwrap();
    assert_eq!(first["question_id"], question);
    assert_eq!(first["option_id"], "a");
    assert_eq!(first["content"], "Approach A");
    assert_eq!(first["request_id"].as_str().unwrap().len(), 36);
    assert_eq!(
        h.actions.last().unwrap()["url"],
        format!("https://one.test/api/accounts/ana/threads/{id}/messages")
    );

    // Live refreshes between a lost answer and its retry keep the retry key.
    h.responses.push_back((200, thread.clone()));
    call(&mut c, &mut h, "thread", json!({"id":id}));

    thread["messages"][0]["decision"]["status"] = json!("answered");
    thread["messages"][0]["decision"]["answer"] = json!({"option_id":"a","text":"Approach A"});
    thread["messages"][0].as_object_mut().unwrap().remove("ui");
    h.responses.push_back((200, thread.clone()));
    let answered = call(&mut c, &mut h, "answer_question", args);
    assert!(answered.get("error").is_none(), "{answered}");
    let retry: Value =
        serde_json::from_str(h.actions.last().unwrap()["body"].as_str().unwrap()).unwrap();
    assert_eq!(retry["request_id"], first["request_id"]);
    let cached = call(&mut c, &mut h, "cached_thread", json!({"id":id}));
    assert_eq!(
        cached["data"]["messages"][0]["decision"],
        thread["messages"][0]["decision"]
    );
    assert!(cached["data"]["messages"][0].get("ui").is_none());

    thread["messages"][0]["decision"]["status"] = json!("cancelled");
    thread["messages"][0]["decision"]["answer"] = Value::Null;
    h.responses.push_back((200, thread.clone()));
    let cancelled = call(
        &mut c,
        &mut h,
        "answer_question",
        json!({"id":id,"question_id":question,"cancel":true,"content":"Dismissed"}),
    );
    assert_eq!(
        cancelled["data"]["messages"][0]["decision"]["status"],
        "cancelled"
    );
    let body: Value =
        serde_json::from_str(h.actions.last().unwrap()["body"].as_str().unwrap()).unwrap();
    assert_eq!(body["cancel"], true);
    assert!(body.get("option_id").is_none());
    assert_ne!(body["request_id"], first["request_id"]);

    let count = h.actions.len();
    for args in [
        json!({"id":id,"question_id":"../invalid","option_id":"a","content":"A"}),
        json!({"id":id,"question_id":question,"content":"A"}),
        json!({"id":id,"question_id":question,"option_id":"a","cancel":true,"content":"A"}),
    ] {
        assert!(call(&mut c, &mut h, "answer_question", args)["error"].is_string());
    }
    assert_eq!(h.actions.len(), count);
}

fn token(exp: i64, user: u64) -> String {
    format!(
        "header.{}.sig",
        URL_SAFE_NO_PAD.encode(
            json!({"exp":exp,"iss":"luft","sub":"account-1","user_id":user,
        "type":"account","email":"ana@example.com",
        "preferred_username":if user == 1 { "ana" } else { "ben" }})
            .to_string()
        )
    )
}
fn call(c: &mut MobileClient, h: &mut Fake, op: &str, args: Value) -> Value {
    serde_json::from_str(&c.call(&json!({"operation":op,"args":args}).to_string(), h)).unwrap()
}
fn begin(c: &mut MobileClient, h: &mut Fake, server: &str) -> String {
    h.responses
        .push_back((200, json!({"luft_oauth_client_id":LUFT_CLIENT_ID})));
    let result = call(c, h, "begin_sign_in", json!({"server":server}));
    assert!(result.get("error").is_none(), "{result}");
    let url = Url::parse(result["data"]["url"].as_str().unwrap()).unwrap();
    assert_eq!(
        url.query_pairs()
            .find(|(k, _)| k == "redirect_uri")
            .unwrap()
            .1,
        CALLBACK
    );
    assert_eq!(
        url.query_pairs()
            .find(|(k, _)| k == "code_challenge_method")
            .unwrap()
            .1,
        "S256"
    );
    // Luft signs in as its first-party client, without registering one.
    assert_eq!(
        url.query_pairs().find(|(k, _)| k == "client_id").unwrap().1,
        LUFT_CLIENT_ID
    );
    assert!(url.query_pairs().all(|(k, _)| k != "scope"));
    assert_eq!(
        h.actions.last().unwrap()["url"],
        endpoint(&server_url(server).unwrap(), ".well-known/luft.json").as_str()
    );
    url.query_pairs()
        .find(|(k, _)| k == "state")
        .unwrap()
        .1
        .to_string()
}
fn login(c: &mut MobileClient, h: &mut Fake, server: &str, user: u64, exp: i64) -> String {
    let state = begin(c, h, server);
    h.responses.push_back((
        200,
        json!({"access_token":token(exp,user),"refresh_token":format!("refresh-{user}")}),
    ));
    let result = call(
        c,
        h,
        "finish_sign_in",
        json!({"url":format!("{CALLBACK}?code=code&state={state}")}),
    );
    assert!(result.get("error").is_none(), "{result}");
    assert!(!result.to_string().contains("refresh_token"));
    result["view"]["active_profile_id"]
        .as_str()
        .unwrap()
        .to_string()
}
#[test]
fn pkce_tamper_and_cancel_are_single_use_and_preserve_selection() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    let id = login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let state = begin(&mut c, &mut h, "https://two.test");
    let forged = call(
        &mut c,
        &mut h,
        "finish_sign_in",
        json!({"url":format!("{CALLBACK}?code=code&state=forged")}),
    );
    assert!(forged["error"].is_string());
    assert_eq!(forged["view"]["active_profile_id"], id);
    assert!(
        call(
            &mut c,
            &mut h,
            "finish_sign_in",
            json!({"url":format!("{CALLBACK}?code=code&state={state}")})
        )["error"]
            .is_string()
    );
    begin(&mut c, &mut h, "https://two.test");
    let cancelled = call(&mut c, &mut h, "cancel_sign_in", json!({}));
    assert_eq!(cancelled["view"]["active_profile_id"], id);
    assert!(c.attempt.is_none());
}
#[test]
fn callbacks_require_exact_route_and_unique_parameters() {
    for suffix in ["/", "/other", ":123", "@evil.test", ""] {
        let (mut c, mut h) = (MobileClient::new(), Fake::default());
        let state = begin(&mut c, &mut h, "https://one.test");
        let url = if suffix.is_empty() {
            format!("{CALLBACK}?code=x&state={state}&state={state}")
        } else {
            format!("{CALLBACK}{suffix}?code=x&state={state}")
        };
        assert!(call(&mut c, &mut h, "finish_sign_in", json!({"url":url}))["error"].is_string());
        assert!(c.attempt.is_none());
    }
}
#[test]
fn membership_refresh_preserves_navigation_unless_selected_organization_changes() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    let id = login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let path = "/threads/12345678-1234-5678-9abc-123456789abc";
    call(&mut c, &mut h, "navigate", json!({"url":path}));
    let before = call(&mut c, &mut h, "select_tab", json!({"tab":"profile"}));
    h.responses.extend([
        (200, json!({"organizations":[{"name":"team"}]})),
        (200, json!({"organizations":[{"name":"team"}]})),
    ]);
    let refreshed = call(&mut c, &mut h, "organizations", json!({}));
    assert_eq!(
        before["view"]["navigation"],
        refreshed["view"]["navigation"]
    );
    let after = call(&mut c, &mut h, "organizations", json!({}));
    assert_eq!(refreshed["view"], after["view"]);
    assert!(after.get("error").is_none());
    let selected = call(
        &mut c,
        &mut h,
        "select_organization",
        json!({"id":id,"name":"team"}),
    );
    assert_eq!(selected["view"]["navigation"]["path"], "/threads");
    call(&mut c, &mut h, "navigate", json!({"url":path}));
    h.responses.push_back((200, json!({"organizations":[]})));
    let removed = call(&mut c, &mut h, "organizations", json!({}));
    assert_eq!(removed["view"]["navigation"]["path"], "/threads");
}
#[test]
fn multiple_origins_dedup_and_selection_are_durable() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    let one = login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let two = login(&mut c, &mut h, "https://two.test", 1, i64::MAX);
    assert_ne!(one, two);
    assert_eq!(login(&mut c, &mut h, "https://ONE.test/", 1, i64::MAX), one);
    assert_eq!(c.vault.profiles.len(), 2);
    h.fail_write = true;
    let failed = call(&mut c, &mut h, "switch_profile", json!({"id":two}));
    assert_eq!(failed["view"]["active_profile_id"], one);
    assert!(failed["error"].is_string());
    let failed = call(&mut c, &mut h, "sign_out", json!({}));
    assert_eq!(failed["view"]["active_profile_id"], one);
    h.fail_write = false;
    let result = call(&mut c, &mut h, "sign_out", json!({}));
    assert_eq!(result["view"]["active_profile_id"], two);
    let mut restored = MobileClient::new();
    let restored = call(&mut restored, &mut h, "snapshot", json!({}));
    for field in ["profiles", "active_profile_id", "generation"] {
        assert_eq!(restored["view"][field], result["view"][field]);
    }
    // Screen state is deliberately process-local, unlike saved accounts.
    assert_eq!(restored["view"]["navigation"]["path"], "/threads");
}
#[test]
fn accounts_flatten_memberships_across_profiles_through_the_active_one() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let ben = login(&mut c, &mut h, "https://one.test", 2, i64::MAX);
    login(&mut c, &mut h, "https://two.test", 1, i64::MAX);
    h.responses.extend([
        (
            200,
            json!({"organizations":[{"name":"team"},{"name":"shared"}]}),
        ),
        (200, json!({"organizations":[{"name":"shared"}]})),
        (200, json!({"organizations":[{"name":"team"}]})),
    ]);
    call(&mut c, &mut h, "organizations", json!({}));
    let selected = call(
        &mut c,
        &mut h,
        "select_organization",
        json!({"id":ben,"name":"shared"}),
    );
    assert!(selected.get("error").is_none(), "{selected}");
    let rows: Vec<_> = selected["view"]["accounts"]
        .as_array()
        .unwrap()
        .iter()
        .map(|a| {
            (
                a["name"].as_str().unwrap(),
                a["server"].as_str().unwrap(),
                a["handle"].as_str().unwrap(),
                a["selected"].as_bool().unwrap(),
            )
        })
        .collect();
    assert_eq!(
        rows,
        [
            ("ana", "https://one.test/", "ana", false),
            ("ana", "https://two.test/", "ana", false),
            ("ben", "https://one.test/", "ben", false),
            // Both one.test logins belong to "shared"; the active login owns the row.
            ("shared", "https://one.test/", "ben", true),
            ("team", "https://one.test/", "ana", false),
            ("team", "https://two.test/", "ana", false),
        ]
    );
}
#[test]
fn rotated_pair_survives_failed_write_and_retries_before_any_network() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, 1);
    h.responses.push_back((
        200,
        json!({"access_token":token(i64::MAX,1),"refresh_token":"rotated-secret"}),
    ));
    h.fail_write = true;
    assert!(call(&mut c, &mut h, "projects", json!({}))["error"].is_string());
    assert_eq!(c.vault.profiles[0].refresh, "rotated-secret");
    let http_count = h.actions.iter().filter(|a| a["type"] == "http").count();
    assert!(call(&mut c, &mut h, "snapshot", json!({}))["error"].is_string());
    assert_eq!(
        h.actions.iter().filter(|a| a["type"] == "http").count(),
        http_count
    );
    h.fail_write = false;
    h.responses.push_back((200, json!({"projects":[]})));
    let result = call(&mut c, &mut h, "projects", json!({}));
    assert!(result.get("error").is_none());
    assert!(!result.to_string().contains("rotated-secret"));
    assert!(h.vault.as_ref().unwrap().contains("rotated-secret"));
    let token_requests: Vec<_> = h
        .actions
        .iter()
        .filter(|a| a["url"] == "https://one.test/oauth2/token")
        .collect();
    assert_eq!(token_requests.len(), 2); // code exchange + exactly one refresh
    assert!(
        token_requests.last().unwrap()["body"]
            .as_str()
            .unwrap()
            .contains(&format!("client_id={LUFT_CLIENT_ID}"))
    );
}
#[test]
fn transient_refresh_keeps_pair_definitive_rejection_blocks_profile() {
    for (status, body, rejected) in [
        (503, json!({}), false),
        (400, json!({"error":"invalid_grant"}), true),
        (401, json!({}), true),
        (200, json!({"access_token":"only"}), true),
    ] {
        let (mut c, mut h) = (MobileClient::new(), Fake::default());
        let id = login(&mut c, &mut h, "https://one.test", 1, 1);
        h.responses.push_back((status, body));
        let result = call(&mut c, &mut h, "projects", json!({}));
        assert!(result["error"].is_string());
        assert_eq!(c.vault.profiles[0].rejected, rejected);
        assert_eq!(c.vault.profiles[0].refresh, "refresh-1");
        if rejected {
            assert!(
                call(
                    &mut c,
                    &mut h,
                    "select_organization",
                    json!({"id":id,"name":"ana"})
                )["error"]
                    .is_string()
            );
        }
    }
}
#[test]
fn memberships_use_each_issuer_preserve_cache_on_error_and_scope_requests() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    let one = login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let two = login(&mut c, &mut h, "https://two.test", 1, i64::MAX);
    h.responses.extend([
        (200, json!({"organizations":[{"name":"team"}]})),
        (200, json!({"organizations":[{"name":"other"}]})),
    ]);
    assert!(
        call(&mut c, &mut h, "organizations", json!({}))
            .get("error")
            .is_none()
    );
    let actions: Vec<_> = h
        .actions
        .iter()
        .filter(|a| {
            a["url"]
                .as_str()
                .is_some_and(|u| u.ends_with("/api/organizations"))
        })
        .collect();
    assert_eq!(actions[0]["url"], "https://one.test/api/organizations");
    assert_eq!(actions[1]["url"], "https://two.test/api/organizations");
    assert!(
        call(
            &mut c,
            &mut h,
            "select_organization",
            json!({"id":one,"name":"team"})
        )
        .get("error")
        .is_none()
    );
    let count = h.actions.len();
    assert!(call(&mut c, &mut h, "previews", json!({"project":"other/app"}))["error"].is_string());
    assert_eq!(h.actions.len(), count);
    h.responses.push_back((
        200,
        json!({"previews":[],"pagination_metadata":{"has_next_page":false}}),
    ));
    assert!(
        call(
            &mut c,
            &mut h,
            "previews",
            json!({"project":"team/app","track":"beta","search":"notes"})
        )
        .get("error")
        .is_none()
    );
    let url = h.actions.last().unwrap()["url"].as_str().unwrap();
    assert!(url.starts_with("https://one.test/api/projects/team/app/previews?"));
    assert!(url.contains("track=beta") && url.contains("search=notes"));
    h.responses.extend([
        (
            200,
            json!({"threads":[
                {"id":"t1","status":"idle","archive_status":"active"},
                {"id":"t2","status":"shipping","archive_status":"active"},
                {"id":"t3","status":"running","archive_status":"archived"},
                {"id":"t4","status":"interrupted","archive_status":"active"},
                {"id":"t5","status":"queued","archive_status":"active"},
                {"id":"t6","status":"something_new","archive_status":"active"}
            ],"next_cursor":"c+/="}),
        ),
        (200, json!({"threads":[],"next_cursor":"c+/="})),
        (200, json!({"error":"not a page"})),
        (404, json!({"message":"Not found."})),
        (403, json!({})),
    ]);
    let page = call(&mut c, &mut h, "threads", json!({}));
    let sections: Vec<_> = page["data"]["threads"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| (t["section"].as_str().unwrap(), t["state"].as_str()))
        .collect();
    assert_eq!(
        sections,
        [
            ("recent", Some("completed")),
            ("in_progress", Some("running")),
            ("archived", Some("running")),
            ("recent", Some("failed")),
            ("in_progress", Some("queued")),
            ("recent", None)
        ]
    );
    // Threads follow the selected organization "team".
    assert_eq!(
        h.actions.last().unwrap()["url"],
        "https://one.test/api/accounts/team/threads"
    );
    let count = h.actions.len();
    assert!(call(&mut c, &mut h, "threads", json!({"cursor":""}))["error"].is_string());
    assert_eq!(h.actions.len(), count);
    let repeated = call(&mut c, &mut h, "threads", json!({"cursor":"c+/="}));
    assert_eq!(repeated["data"]["next_cursor"], Value::Null);
    assert_eq!(
        h.actions.last().unwrap()["url"],
        "https://one.test/api/accounts/team/threads?cursor=c%2B%2F%3D"
    );
    assert!(call(&mut c, &mut h, "threads", json!({}))["error"].is_string());
    let unavailable = call(&mut c, &mut h, "threads", json!({}));
    assert!(unavailable.get("error").is_none(), "{unavailable}");
    assert_eq!(unavailable["data"]["available"], false);
    assert_eq!(unavailable["data"]["reason"], "disabled");
    // A session the server refuses, such as one from before Luft's first-party client, is asked to sign in again.
    let forbidden = call(&mut c, &mut h, "threads", json!({}));
    assert!(forbidden.get("error").is_none(), "{forbidden}");
    assert_eq!(forbidden["data"]["reason"], "sign_in_required");
    h.responses.extend([(503, json!({})), (403, json!({}))]);
    assert!(call(&mut c, &mut h, "organizations", json!({}))["error"].is_string());
    let p = c.vault.profiles.iter().find(|p| p.id == one).unwrap();
    assert_eq!(p.organizations, ["team"]);
    assert!(!p.memberships_rejected);
    assert!(
        call(
            &mut c,
            &mut h,
            "select_organization",
            json!({"id":two,"name":"other"})
        )["error"]
            .is_string()
    );
}
#[test]
fn thread_attachments_preserve_bytes_and_retry_identity_without_text_only_offline_queueing() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let id = "6f1c2a8e-0b7d-4c3e-9a1f-2d4b8e0c7f53";
    let file = json!({"name":"notes.txt", "mime_type":"text/plain", "data_base64":"SGVsbG8="});
    let args = json!({"id":id, "content":"", "attachments":[file.clone()]});
    h.offline = true;
    let offline = call(&mut c, &mut h, "send_message", args.clone());
    assert!(offline["error"].as_str().unwrap().contains("internet"));
    h.offline = false;
    assert_eq!(
        call(&mut c, &mut h, "flush_outbox", json!({}))["data"]["sent"],
        0
    );
    for _ in 0..3 {
        h.responses.push_back((503, json!({})));
    }
    call(&mut c, &mut h, "send_message", args.clone());
    call(&mut c, &mut h, "send_message", args.clone());
    let mut changed = args.clone();
    changed["attachments"][0]["data_base64"] = json!("V29ybGQ=");
    call(&mut c, &mut h, "send_message", changed);
    let posts: Vec<Value> = h
        .actions
        .iter()
        .filter(|a| {
            a["method"] == "POST" && a["url"].as_str().unwrap_or_default().ends_with("/messages")
        })
        .map(|a| serde_json::from_str(a["body"].as_str().unwrap()).unwrap())
        .collect();
    let last = &posts[posts.len() - 3..];
    assert_eq!(last[0]["attachments"], json!([file]));
    assert_eq!(last[0]["content"], "");
    assert_eq!(last[0]["request_id"], last[1]["request_id"]);
    assert_ne!(last[1]["request_id"], last[2]["request_id"]);
    let mut files = vec![file.clone(); 4];
    files[0]["data_base64"] =
        json!(base64::engine::general_purpose::STANDARD.encode(vec![42; 1_048_576]));
    let message = json!({"id":"message-1","role":"user","content":"","attachments":files});
    h.responses.push_back((
        200,
        json!({"id":id,"status":"idle","archive_status":"active","messages":[message.clone()]}),
    ));
    let sent = call(
        &mut c,
        &mut h,
        "send_message",
        json!({"id":id,"content":"","attachments":files}),
    );
    assert!(sent.get("error").is_none(), "{sent}");
    let cached = call(&mut c, &mut h, "cached_thread", json!({"id":id}));
    assert_eq!(
        cached["data"]["messages"][0]["attachments"],
        message["attachments"]
    );
    let count = h.actions.len();
    assert!(
        call(
            &mut c,
            &mut h,
            "send_message",
            json!({"id":id,"content":"x","attachments":vec![file; 5]})
        )["error"]
            .is_string()
    );
    for invalid in [
        json!({"name":"../secret", "mime_type":"text/plain", "data_base64":"YQ=="}),
        json!({"name":"empty", "mime_type":"text/plain", "data_base64":""}),
        json!({"name":"bad", "mime_type":"text/plain", "data_base64":"???"}),
        json!({"name":"large", "mime_type":"text/plain", "data_base64":base64::engine::general_purpose::STANDARD.encode(vec![42; 1_048_577])}),
    ] {
        assert!(
            call(
                &mut c,
                &mut h,
                "send_message",
                json!({"id":id,"content":"x","attachments":[invalid]})
            )["error"]
                .is_string()
        );
    }
    assert_eq!(h.actions.len(), count);
}

#[test]
fn conversations_start_on_the_server_without_a_repository_and_retry_idempotently() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let models = json!({"models":[
        {"provider":"chatgpt","id":"gpt-a","name":"A"},
        {"provider":"chatgpt","id":"gpt-b","name":"B"}
    ],"errors":[]});
    let id = "6f1c2a8e-0b7d-4c3e-9a1f-2d4b8e0c7f53";
    h.responses.extend([
        (200, models.clone()),
        (503, json!({})),
        (200, models.clone()),
        (
            200,
            json!({"id":id,"status":"queued","archive_status":"active","repository":"",
                "messages":[{"role":"user","content":"Plan the release"}]}),
        ),
    ]);
    let posts = |h: &Fake| -> Vec<Value> {
        h.actions
            .iter()
            .filter(|a| a["method"] == "POST" && a["url"].as_str().unwrap().contains("/threads"))
            .map(|a| serde_json::from_str(a["body"].as_str().unwrap()).unwrap())
            .collect()
    };
    let content = json!({"content":"Plan the release"});
    assert!(call(&mut c, &mut h, "start_thread", content.clone())["error"].is_string());
    let started = call(&mut c, &mut h, "start_thread", content.clone());
    assert!(started.get("error").is_none(), "{started}");
    assert_eq!(started["data"]["working"], true);
    assert_eq!(started["data"]["section"], "in_progress");
    let sent = posts(&h);
    assert_eq!(
        h.actions.last().unwrap()["url"],
        "https://one.test/api/accounts/ana/threads"
    );
    assert_eq!(sent.len(), 2);
    // The first model answers, no repository is chosen, and a retry of the
    // failed request reuses its key so the server cannot create two threads.
    assert_eq!(sent[1]["model"], "gpt-a");
    assert_eq!(sent[1]["provider"], "chatgpt");
    assert!(sent[1].get("repository").is_none());
    assert_eq!(sent[0]["request_id"], sent[1]["request_id"]);
    let key = sent[0]["request_id"].as_str().unwrap();
    assert_eq!(key.len(), 36);
    assert_eq!(&key[14..15], "4");
    assert!("89ab".contains(&key[19..20]));

    // A new conversation, even with the same text, gets a new key once the first succeeded.
    h.responses.extend([
        (200, models.clone()),
        (
            200,
            json!({"id":id,"status":"idle","archive_status":"active","messages":[]}),
        ),
    ]);
    call(&mut c, &mut h, "start_thread", content.clone());
    assert_ne!(posts(&h)[2]["request_id"], sent[1]["request_id"]);

    h.responses.extend([
        (
            200,
            json!({"id":id,"status":"idle","archive_status":"active","messages":[]}),
        ),
        (
            200,
            json!({"id":id,"status":"queued","archive_status":"active","messages":[]}),
        ),
    ]);
    let thread = call(&mut c, &mut h, "thread", json!({"id":id,"before":40}));
    assert_eq!(thread["data"]["working"], false);
    assert_eq!(thread["data"]["state"], "completed");
    assert_eq!(
        h.actions.last().unwrap()["url"],
        format!("https://one.test/api/accounts/ana/threads/{id}?before=40")
    );
    let replied = call(
        &mut c,
        &mut h,
        "send_message",
        json!({"id":id,"content":"And the changelog?"}),
    );
    assert_eq!(replied["data"]["working"], true);
    assert_eq!(
        h.actions.last().unwrap()["url"],
        format!("https://one.test/api/accounts/ana/threads/{id}/messages")
    );
    assert_eq!(posts(&h)[3]["content"], "And the changelog?");

    let count = h.actions.len();
    for args in [
        json!({"id":"../../projects","content":"x"}),
        json!({"id":id,"content":"  "}),
    ] {
        assert!(call(&mut c, &mut h, "send_message", args)["error"].is_string());
    }
    assert_eq!(h.actions.len(), count);

    h.responses.extend([
        (200, json!({"models":[],"errors":[{"provider":"claude"}]})),
        (404, json!({"message":"Not found."})),
    ]);
    let no_model = call(&mut c, &mut h, "start_thread", content.clone());
    assert!(no_model["error"].as_str().unwrap().contains("ChatGPT"));
    let disabled = call(&mut c, &mut h, "start_thread", content);
    assert_eq!(disabled["error"], THREADS_UNAVAILABLE);
    assert_eq!(posts(&h).len(), 4);
}

#[test]
fn workspace_readiness_is_live_only_and_not_replayed_from_cached_history() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let id = "6f1c2a8e-0b7d-4c3e-9a1f-2d4b8e0c7f53";
    h.responses.push_back((
        200,
        json!({"id":id,"status":"running","archive_status":"active",
            "workspace_ready_id":"threads:run:3","messages":[]}),
    ));
    let live = call(&mut c, &mut h, "thread", json!({"id":id}));
    assert_eq!(live["data"]["workspace_ready_id"], "threads:run:3");
    let cached = call(&mut c, &mut h, "cached_thread", json!({"id":id}));
    assert!(cached["data"]["workspace_ready_id"].is_null());
    h.offline = true;
    let offline = call(&mut c, &mut h, "thread", json!({"id":id}));
    assert_eq!(offline["data"]["freshness"]["state"], "cached");
    assert!(offline["data"]["workspace_ready_id"].is_null());
    h.offline = false;
    for status in ["idle", "failed"] {
        h.responses.push_back((
            200,
            json!({"id":id,"status":status,"archive_status":"active",
                "workspace_ready_id":"threads:run:3","messages":[]}),
        ));
        let ended = call(&mut c, &mut h, "thread", json!({"id":id}));
        assert!(ended["data"]["workspace_ready_id"].is_null());
    }
}
#[test]
fn complete_project_enumeration_detects_repeated_pages_and_filters_account() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    h.responses.extend([
        (200,json!({"projects":[{"full_name":"ana/first"},{"full_name":"other/hidden"}],"pagination_metadata":{"has_next_page":true}})),
        (200,json!({"projects":[{"full_name":"ana/second"}],"pagination_metadata":{"has_next_page":false}}))]);
    let result = call(&mut c, &mut h, "projects", json!({}));
    assert_eq!(result["data"]["projects"].as_array().unwrap().len(), 2);
    assert!(
        h.actions.last().unwrap()["url"]
            .as_str()
            .unwrap()
            .contains("page=2")
    );
    let page = (
        200,
        json!({"projects":[{"full_name":"ana/first"}],"pagination_metadata":{"has_next_page":true}}),
    );
    h.responses.extend([page.clone(), page]);
    assert_eq!(
        call(&mut c, &mut h, "projects", json!({}))["error"],
        "Project pagination did not advance"
    );
}
#[test]
fn filters_reject_ignored_semantics_and_tracks_keep_full_counts() {
    assert!(
        validate_filters(
            &json!({"previews":[{"track":"BETA","release_notes":"Full NOTES here"}]}),
            &json!({"track":"beta","search":"notes"})
        )
        .is_ok()
    );
    assert!(
        validate_filters(
            &json!({"previews":[{"track":null}]}),
            &json!({"track":"beta"})
        )
        .is_err()
    );
    assert!(
        validate_filters(
            &json!({"previews":[{"display_name":"different"}]}),
            &json!({"search":"notes"})
        )
        .is_err()
    );
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let summary = json!({"total_count":100,"tracks":[{"name":"beta","count":60}]});
    h.responses.push_back((200, summary.clone()));
    assert_eq!(
        call(&mut c, &mut h, "tracks", json!({"project":"ana/app"}))["data"],
        summary
    );
    assert_eq!(
        h.actions.last().unwrap()["url"],
        "https://one.test/api/projects/ana/app/previews/tracks"
    );
}
#[test]
fn unsafe_servers_fail_without_a_request() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    assert!(
        call(
            &mut c,
            &mut h,
            "begin_sign_in",
            json!({"server":"http://evil.test"})
        )["error"]
            .is_string()
    );
    assert!(h.actions.iter().all(|a| a["type"] != "http"));
    assert!(c.attempt.is_none());
}
#[test]
fn servers_without_luft_client_refuse_sign_in_before_the_browser() {
    // A 404 (no discovery), discovery without the client, or another client ID.
    for response in [
        (404, Value::Null),
        (200, json!({"network_trusted_cache_access":false})),
        (200, json!({"luft_oauth_client_id":"another-client"})),
    ] {
        let (mut c, mut h) = (MobileClient::new(), Fake::default());
        h.responses.push_back(response);
        let result = call(
            &mut c,
            &mut h,
            "begin_sign_in",
            json!({"server":"https://old.test"}),
        );
        assert_eq!(result["error"], UNSUPPORTED_SERVER, "{result}");
        assert!(c.attempt.is_none());
    }
}
#[test]
fn detail_and_delete_paths_are_project_scoped() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    for op in ["preview", "delete_preview"] {
        h.responses.push_back((200, json!({"id":"opaque"})));
        assert!(
            call(
                &mut c,
                &mut h,
                op,
                json!({"project":"ana/app","id":"opaque"})
            )
            .get("error")
            .is_none()
        );
        let action = h.actions.last().unwrap();
        assert_eq!(
            action["url"],
            "https://one.test/api/projects/ana/app/previews/opaque"
        );
        assert_eq!(
            action["method"],
            if op == "preview" { "GET" } else { "DELETE" }
        );
    }
    h.responses.push_back((204, Value::Null));
    assert!(
        call(&mut c, &mut h, "delete_account", json!({}))
            .get("error")
            .is_none()
    );
    assert_eq!(
        h.actions
            .iter()
            .rev()
            .find(|a| a["type"] == "http")
            .unwrap()["url"],
        "https://one.test/api/accounts/ana"
    );
    assert!(c.vault.profiles.is_empty());
}

fn preview(id: &str, kind: &str, platform: &str, binary_id: Value) -> Value {
    json!({"id":id, "version":"0.1.0", "git_commit_sha":format!("{id}0123456789"),
        "url":format!("https://tuist.dev/tuist/luft/previews/{id}"),
        "device_url":format!("itms-services://?action=download-manifest&url=https%3A%2F%2Ftuist.dev%2F{id}"),
        "builds":[{"type":kind, "supported_platforms":[platform], "binary_id":binary_id,
            "url":format!("https://storage.test/{id}")}]})
}

#[test]
fn preview_updates_compare_the_newest_identified_build_through_luft() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://luft.work", 1, i64::MAX);
    // The selected profile is self-hosted; updates still use the hosted Luft API.
    login(&mut c, &mut h, "https://one.test", 2, i64::MAX);
    let page = json!({"previews":[
        // Newest first: an unidentifiable build and another platform's build are skipped.
        preview("unidentified", "apk", "android", Value::Null),
        preview("ios", "ipa", "ios", json!("ios-id")),
        preview("newer", "apk", "android", json!("abc123")),
        preview("running", "apk", "android", json!("def456")),
    ]});
    h.responses.push_back((200, page.clone()));
    let result = call(
        &mut c,
        &mut h,
        "preview_update",
        json!({"platform":"android","binary_id":"def456"}),
    );
    assert!(result.get("error").is_none(), "{result}");
    let update = &result["data"]["update"];
    assert_eq!(update["id"], "newer");
    assert_eq!(update["commit"], "newer01");
    assert_eq!(update["install_url"], "https://storage.test/newer");
    assert_eq!(
        result["data"]["suggest"], true,
        "a newer build is suggested"
    );
    let request = h.actions.last().unwrap();
    assert_eq!(
        request["url"],
        "https://luft.work/api/projects/tuist/luft/previews?track=internal&supported_platforms=android&page=1&page_size=20"
    );
    assert_eq!(
        request["headers"]["Authorization"],
        format!("Bearer {}", token(i64::MAX, 1))
    );

    // Later checks, such as returning to the foreground, still report the build
    // without suggesting it again.
    h.responses.push_back((200, page.clone()));
    let again = call(
        &mut c,
        &mut h,
        "preview_update",
        json!({"platform":"android","binary_id":"def456"}),
    );
    assert_eq!(again["data"]["update"]["id"], "newer");
    assert_eq!(again["data"]["suggest"], false);

    // Running the newest identified build, even with different hex case, is current.
    h.responses.push_back((200, page.clone()));
    let current = call(
        &mut c,
        &mut h,
        "preview_update",
        json!({"platform":"android","binary_id":"ABC123"}),
    );
    assert_eq!(current["data"], json!({"update":null,"suggest":false}));

    // iOS installs through the preview's over-the-air manifest. Another build
    // than the one last suggested is suggested again.
    h.responses.push_back((200, page));
    let ios = call(
        &mut c,
        &mut h,
        "preview_update",
        json!({"platform":"ios","binary_id":"other"}),
    );
    assert_eq!(
        ios["data"]["update"]["install_url"],
        "itms-services://?action=download-manifest&url=https%3A%2F%2Ftuist.dev%2Fios"
    );
    assert_eq!(ios["data"]["suggest"], true);

    // Without access to the project there is nothing to install, and nothing to report.
    h.responses.push_back((403, json!({})));
    let denied = call(
        &mut c,
        &mut h,
        "preview_update",
        json!({"platform":"android","binary_id":"def456"}),
    );
    assert!(denied.get("error").is_none(), "{denied}");
    assert_eq!(denied["data"], json!({"update":null,"suggest":false}));
}

#[test]
fn preview_updates_need_a_tuist_dev_profile() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let requests = h.actions.len();
    let result = call(
        &mut c,
        &mut h,
        "preview_update",
        json!({"platform":"macos","binary_id":"id"}),
    );
    assert_eq!(result["data"], json!({"update":null}));
    assert_eq!(
        h.actions.len(),
        requests,
        "no request leaves for another server"
    );
    assert!(
        call(
            &mut c,
            &mut h,
            "preview_update",
            json!({"platform":"linux","binary_id":"id"})
        )["error"]
            .is_string()
    );
}

#[test]
fn proactive_refresh_for_discovery_never_uses_the_active_issuer_for_another_profile() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    let soon = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64
        + 29;
    login(&mut c, &mut h, "https://one.test", 1, soon);
    login(&mut c, &mut h, "https://two.test", 2, soon);
    let start = h.actions.len();
    h.responses.extend([
        (
            200,
            json!({"access_token":token(i64::MAX,1),"refresh_token":"new-one"}),
        ),
        (200, json!({"organizations":[]})),
        (
            200,
            json!({"access_token":token(i64::MAX,2),"refresh_token":"new-two"}),
        ),
        (200, json!({"organizations":[]})),
    ]);
    assert!(
        call(&mut c, &mut h, "organizations", json!({}))
            .get("error")
            .is_none()
    );
    let requests: Vec<_> = h.actions[start..]
        .iter()
        .filter(|a| a["type"] == "http")
        .collect();
    assert_eq!(requests[0]["url"], "https://one.test/oauth2/token");
    assert!(
        requests[0]["body"]
            .as_str()
            .unwrap()
            .contains("refresh_token=refresh-1")
    );
    assert_eq!(requests[2]["url"], "https://two.test/oauth2/token");
    assert!(
        requests[2]["body"]
            .as_str()
            .unwrap()
            .contains("refresh_token=refresh-2")
    );
}

#[test]
fn selection_write_failure_preserves_organization_and_generation() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    let id = login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    h.responses
        .push_back((200, json!({"organizations":[{"name":"team"}]})));
    let before = call(&mut c, &mut h, "organizations", json!({}));
    h.fail_write = true;
    let after = call(
        &mut c,
        &mut h,
        "select_organization",
        json!({"id":id,"name":"team"}),
    );
    assert_eq!(before["view"], after["view"]);
    assert!(after["error"].is_string());
}

#[test]
fn credential_fields_and_echoed_values_are_not_returned_to_frontends() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let access = c.vault.profiles[0].access.clone();
    h.responses.push_back((
        200,
        json!({"id":"opaque","access_token":access,
        "nested":{"refresh_token":"refresh-1","echo":"Bearer refresh-1"}}),
    ));
    let result = call(
        &mut c,
        &mut h,
        "preview",
        json!({"project":"ana/app","id":"opaque"}),
    );
    assert!(!result.to_string().contains("refresh-1"));
    assert!(!result.to_string().contains(&access));
    assert!(result["data"].get("access_token").is_none());
    assert!(result["data"]["nested"].get("refresh_token").is_none());
}

#[test]
fn profiles_that_used_the_tuist_app_session_are_dropped_on_load() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    let own = login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let mut vault: Value = serde_json::from_str(h.vault.as_ref().unwrap()).unwrap();
    let mut legacy = vault["profiles"][0].clone();
    legacy["id"] = json!("legacy");
    legacy["server"] = json!("https://tuist.dev/");
    legacy["access"] = json!("");
    legacy["refresh"] = json!("");
    legacy["shared"] = json!("https://tuist.dev");
    vault["profiles"].as_array_mut().unwrap().push(legacy);
    let mut direct = vault["profiles"][0].clone();
    direct["id"] = json!("direct-tuist");
    direct["server"] = json!("https://tuist.dev/");
    direct["access"] = json!(format!(
        "e30.{}.signature",
        URL_SAFE_NO_PAD.encode(json!({"sub":"2","type":"account","exp":i64::MAX}).to_string())
    ));
    vault["profiles"].as_array_mut().unwrap().push(direct);
    vault["active_profile_id"] = json!("legacy");
    vault["unlinked"] = json!([["https://tuist.dev", "account-2"]]);
    h.vault = Some(vault.to_string());
    h.actions.clear();

    let mut c = MobileClient::new();
    let view = call(&mut c, &mut h, "snapshot", json!({}))["view"].clone();

    assert_eq!(view["profiles"].as_array().unwrap().len(), 1);
    assert_eq!(view["active_profile_id"], own);
    let stored: Value = serde_json::from_str(h.vault.as_ref().unwrap()).unwrap();
    assert_eq!(stored["profiles"].as_array().unwrap().len(), 1);
    assert_eq!(stored["active_profile_id"], own);
    assert!(stored.get("unlinked").is_none());
    let types: Vec<_> = h.actions.iter().map(|a| a["type"].clone()).collect();
    assert_eq!(types, [json!("read"), json!("write")]);

    // A corrupt vault fails closed instead of panicking in the migration.
    h.vault = Some("[]".into());
    let mut c = MobileClient::new();
    assert!(call(&mut c, &mut h, "snapshot", json!({}))["error"].is_string());
}

#[test]
fn url_navigation_survives_login_preserves_tab_stacks_and_resets_between_profiles() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    let path = "/threads/12345678-1234-5678-9abc-123456789abc";
    call(
        &mut c,
        &mut h,
        "navigate",
        json!({"url":format!("https://one.test/luft{path}")}),
    );
    let first = login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let nav = call(&mut c, &mut h, "snapshot", json!({}))["view"]["navigation"].clone();
    assert_eq!(nav["path"], path);
    assert_eq!(nav["tab"], "threads");
    assert_eq!(nav["thread_id"], "12345678-1234-5678-9abc-123456789abc");
    call(&mut c, &mut h, "select_tab", json!({"tab":"profile"}));
    assert_eq!(
        call(&mut c, &mut h, "select_tab", json!({"tab":"threads"}))["view"]["navigation"]["path"],
        path
    );
    let invalid = call(
        &mut c,
        &mut h,
        "navigate",
        json!({"url":"https://two.test/luft/profile"}),
    );
    assert!(invalid["error"].is_string());
    assert_eq!(invalid["view"]["navigation"]["path"], path);
    assert_eq!(
        call(&mut c, &mut h, "navigation_back", json!({}))["view"]["navigation"]["path"],
        "/threads"
    );
    call(&mut c, &mut h, "navigate", json!({"url":path}));
    login(&mut c, &mut h, "https://two.test", 2, i64::MAX);
    assert_eq!(
        call(&mut c, &mut h, "snapshot", json!({}))["view"]["navigation"]["path"],
        "/threads"
    );
    assert_eq!(
        call(&mut c, &mut h, "switch_profile", json!({"id":first}))["view"]["navigation"]["path"],
        "/threads"
    );
}

#[test]
fn pending_navigation_revalidates_server_and_is_consumed_after_sign_in() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    call(
        &mut c,
        &mut h,
        "navigate",
        json!({"url":"luft://app/profile"}),
    );
    let state = begin(&mut c, &mut h, "https://other.test");
    h.responses.push_back((
        200,
        json!({"access_token":token(i64::MAX,1),"refresh_token":"refresh-1"}),
    ));
    let result = call(
        &mut c,
        &mut h,
        "finish_sign_in",
        json!({"url":format!("{CALLBACK}?code=code&state={state}")}),
    );
    assert!(result["error"].is_string());
    assert!(result["view"]["active_profile_id"].is_string());
    assert_eq!(result["view"]["navigation"]["path"], "/threads");
    assert!(
        call(&mut c, &mut h, "snapshot", json!({}))
            .get("error")
            .is_none()
    );
}

#[test]
fn pending_link_survives_reauthentication_of_the_same_profile() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    let id = login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    h.responses.push_back((401, json!({})));
    assert!(call(&mut c, &mut h, "organizations", json!({}))["error"].is_string());
    let queued = call(
        &mut c,
        &mut h,
        "navigate",
        json!({"url":"https://one.test/luft/profile"}),
    );
    assert!(queued.get("error").is_none());
    assert_eq!(queued["view"]["navigation"]["path"], "/threads");
    assert_eq!(login(&mut c, &mut h, "https://one.test", 1, i64::MAX), id);
    let resumed = call(&mut c, &mut h, "snapshot", json!({}));
    assert_eq!(resumed["view"]["navigation"]["path"], "/profile");
}

#[test]
fn conditional_navigation_does_not_override_newer_navigation_or_sessions() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let before = call(&mut c, &mut h, "snapshot", json!({}));
    let args = json!({"url":"/profile", "if_generation":before["view"]["generation"],
        "if_revision":before["view"]["navigation"]["revision"]});
    let applied = call(&mut c, &mut h, "navigate", args.clone());
    assert_eq!(applied["view"]["navigation"]["path"], "/profile");
    call(&mut c, &mut h, "navigate", json!({"url":"/threads"}));
    let stale = call(&mut c, &mut h, "navigate", args);
    assert_eq!(stale["view"]["navigation"]["path"], "/threads");
    login(&mut c, &mut h, "https://two.test", 2, i64::MAX);
    let current = call(&mut c, &mut h, "snapshot", json!({}));
    let stale_session = call(
        &mut c,
        &mut h,
        "navigate",
        json!({"url":"/profile",
        "if_generation":before["view"]["generation"],
        "if_revision":current["view"]["navigation"]["revision"]}),
    );
    assert_eq!(stale_session["view"]["navigation"]["path"], "/threads");
}

#[test]
fn new_thread_route_opens_start_conversation_until_any_other_navigation() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    // Signed out, a shortcut's request waits for sign-in like any link.
    let queued = call(
        &mut c,
        &mut h,
        "navigate",
        json!({"url":"/threads/new/dictation"}),
    );
    assert!(queued["view"]["navigation"]["compose"].is_null());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let nav = &call(&mut c, &mut h, "snapshot", json!({}))["view"]["navigation"];
    assert_eq!(nav["compose"], "dictation");
    assert_eq!(nav["path"], "/threads/new/dictation");
    assert_eq!(nav["tab"], "threads");
    assert!(nav["thread_id"].is_null());

    let thread = "12345678-1234-5678-9abc-123456789abc";
    call(
        &mut c,
        &mut h,
        "navigate",
        json!({"url":format!("/threads/{thread}")}),
    );
    let opened = call(&mut c, &mut h, "navigate", json!({"url":"/threads/new"}));
    let nav = &opened["view"]["navigation"];
    assert_eq!(nav["compose"], "text");
    assert!(
        nav["thread_id"].is_null(),
        "starting pops the open conversation"
    );

    for (operation, args) in [
        ("select_tab", json!({"tab":"profile"})),
        ("navigation_back", json!({})),
        ("navigate", json!({"url":format!("/threads/{thread}")})),
    ] {
        call(&mut c, &mut h, "navigate", json!({"url":"/threads/new"}));
        let nav = &call(&mut c, &mut h, operation, args)["view"]["navigation"];
        assert!(nav["compose"].is_null(), "{operation}");
        assert_ne!(nav["path"], "/threads/new", "{operation}");
    }
}

#[test]
fn luft_route_catalog_roundtrips_and_rejects_ambiguous_urls() {
    use crate::navigation::{Destination, Link};
    let server = Url::parse("https://one.test/base/").unwrap();
    for (path, destination) in [
        ("/profile", Destination::Profile),
        ("/threads", Destination::THREADS),
        ("/threads/new", Destination::NewThread { dictate: false }),
        (
            "/threads/12345678-1234-5678-9abc-123456789abc",
            Destination::Conversation("threads", "12345678-1234-5678-9abc-123456789abc".into()),
        ),
        ("/lounges", Destination::List("lounges")),
        (
            "/lounges/12345678-1234-5678-9abc-123456789abc",
            Destination::Conversation("lounges", "12345678-1234-5678-9abc-123456789abc".into()),
        ),
        (
            "/dms/12345678-1234-5678-9abc-123456789abc",
            Destination::Conversation("dms", "12345678-1234-5678-9abc-123456789abc".into()),
        ),
        (
            "/threads/12345678-1234-5678-9abc-123456789abc/snooze",
            Destination::Snooze("12345678-1234-5678-9abc-123456789abc".into()),
        ),
    ] {
        for value in [
            path.to_owned(),
            format!("https://one.test/base/luft{path}"),
            format!("luft://app{path}?server=https%3A%2F%2Fone.test%2Fbase"),
        ] {
            let route = Link::parse(&value).unwrap().resolve(&server).unwrap();
            assert_eq!(route, destination);
            assert_eq!(route.path(), path);
        }
    }
    assert_eq!(
        Link::parse("/threads/new/dictation")
            .unwrap()
            .resolve(&server)
            .unwrap(),
        Destination::NewThread { dictate: true }
    );
    for value in [
        "luft://app/threads/new/dictation",
        "luft://app/threads/new/dictation?server=https%3A%2F%2Fone.test%2Fbase",
        "https://one.test/base/luft/threads/new/dictation",
        "/threads/invalid",
        "/threads/new/",
        "/threads/new?dictate",
        "/threads/new/voice",
        "/threads/------------------------------------",
        "/threads/",
        "/lounges/not-an-id",
        "/threads/new/snooze",
        "/threads/snooze",
        "/lounges/12345678-1234-5678-9abc-123456789abc/snooze",
        "/threads/12345678-1234-5678-9abc-123456789abc/snooze/",
        "/channels",
        "/profile?",
        "/profile#fragment",
        "//profile",
        "luft://oauth-callback?code=secret",
        "luft://user@app/profile",
        "luft://app:123/profile",
        "luft://app/profile?unknown=1",
        "luft://app/profile?server=https://one.test&server=https://one.test",
        "luft://app/a/../profile",
        "luft://app/%70rofile",
        "luft://app/profile#",
        "https://one.test/base/luft/../luft/profile",
        "http://one.test/luft/profile",
        "https://one.test/base/luft/profile?token=secret",
        "https://one.test/base/luft/threads/not-an-id",
    ] {
        assert!(Link::parse(value).is_err(), "{value}");
    }
    for value in [
        "https://one.test/luft/profile",
        "https://one.test/base-other/luft/profile",
        "https://one.test:8443/base/luft/profile",
        "https://two.test/base/luft/profile",
    ] {
        assert!(
            Link::parse(value).unwrap().resolve(&server).is_err(),
            "{value}"
        );
    }
}
#[test]
fn offline_reads_come_from_the_store_and_queued_threads_replay_once_online() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let seen = "6f1c2a8e-0b7d-4c3e-9a1f-2d4b8e0c7f53";
    h.responses.push_back((
        200,
        json!({"threads":[{"id":seen,"title":"Release plan","status":"idle","archive_status":"active"}],"next_cursor":null}),
    ));
    let live = call(&mut c, &mut h, "threads", json!({}));
    assert_eq!(live["data"]["freshness"]["state"], "live");

    // On a plane: the inbox still renders, and new threads queue.
    h.offline = true;
    let cached = call(&mut c, &mut h, "threads", json!({}));
    assert!(cached.get("error").is_none(), "{cached}");
    assert_eq!(cached["data"]["freshness"]["state"], "cached");
    assert_eq!(cached["data"]["threads"][0]["id"], seen);
    let queued = call(
        &mut c,
        &mut h,
        "start_thread",
        json!({"content":"Idea one"}),
    );
    assert_eq!(queued["data"]["freshness"]["state"], "queued");
    let local_id = queued["data"]["id"].as_str().unwrap().to_string();
    let reopened = call(&mut c, &mut h, "thread", json!({"id":local_id}));
    assert_eq!(reopened["data"]["messages"][0]["content"], "Idea one");
    // Earlier pages are never stored: offline they fail rather than repeat the latest page.
    let earlier = call(&mut c, &mut h, "thread", json!({"id":seen,"before":10}));
    assert!(earlier.get("error").is_some(), "{earlier}");
    // Relaunched, still offline: the store is on disk, not in memory. Replacing
    // the client closes its database, which Windows needs before sign-out
    // can delete the file.
    c = MobileClient::new();
    let inbox = call(&mut c, &mut h, "cached_threads", json!({}));
    assert_eq!(inbox["data"]["threads"][0]["pending"], true);
    assert_eq!(inbox["data"]["threads"][1]["id"], seen);
    assert_eq!(inbox["data"]["freshness"]["state"], "cached");
    // A conversation never opened on this device says so instead of looking empty.
    let unseen = call(
        &mut c,
        &mut h,
        "cached_thread",
        json!({"id":"7f1c2a8e-0b7d-4c3e-9a1f-2d4b8e0c7f53"}),
    );
    assert_eq!(unseen["data"]["freshness"]["state"], "never_loaded");

    // Back online: the queued thread is sent with the key it was queued with.
    h.offline = false;
    h.responses.extend([
        (200, json!({"models":[{"provider":"chatgpt","id":"gpt-a"}],"errors":[]})),
        (
            200,
            json!({"id":"8f1c2a8e-0b7d-4c3e-9a1f-2d4b8e0c7f53","status":"queued","archive_status":"active",
                "messages":[{"role":"user","content":"Idea one"}]}),
        ),
    ]);
    let flushed = call(&mut c, &mut h, "flush_outbox", json!({}));
    assert_eq!(flushed["data"]["sent"], 1, "{flushed}");
    let body: Value =
        serde_json::from_str(h.actions.last().unwrap()["body"].as_str().unwrap()).unwrap();
    assert_eq!(body["request_id"], local_id);
    // The sent thread stays in the inbox under the server's id.
    let after = call(&mut c, &mut h, "cached_threads", json!({}));
    let ids: Vec<_> = after["data"]["threads"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["id"].clone())
        .collect();
    assert_eq!(
        ids,
        [json!("8f1c2a8e-0b7d-4c3e-9a1f-2d4b8e0c7f53"), json!(seen)]
    );

    // Signing out removes the profile's database.
    call(&mut c, &mut h, "sign_out", json!({}));
    let left: Vec<_> = std::fs::read_dir(h.directory.as_ref().unwrap())
        .unwrap()
        .collect();
    assert!(left.is_empty(), "{left:?}");
}
#[test]
fn boot_migrates_each_store_once_and_keeps_queued_writes() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let first = call(&mut c, &mut h, "boot", json!({}));
    let names: Vec<_> = store::MIGRATIONS.iter().map(|(name, _)| *name).collect();
    assert_eq!(
        first["data"]["stores"][0]["migrated"],
        json!(names),
        "{first}"
    );
    assert!(
        h.logs
            .iter()
            .any(|l| l.ends_with("migrated create_local_store"))
    );
    assert_eq!(h.logs.last().unwrap(), "boot: ready");

    h.offline = true;
    call(
        &mut c,
        &mut h,
        "start_thread",
        json!({"content":"Idea one"}),
    );

    // Relaunched: nothing left to migrate, and the queued write is still there.
    let mut c = MobileClient::new();
    let again = call(&mut c, &mut h, "boot", json!({}));
    assert_eq!(again["data"]["stores"][0]["migrated"], json!([]), "{again}");
    let inbox = call(&mut c, &mut h, "cached_threads", json!({}));
    assert_eq!(inbox["data"]["threads"][0]["title"], "Idea one");

    // A database written by a newer build is refused, not misread.
    let profile = again["view"]["active_profile_id"]
        .as_str()
        .unwrap()
        .to_string();
    let directory = h.directory.clone().unwrap();
    let path = directory.join(format!("{profile}.sqlite3"));
    rusqlite::Connection::open(&path)
        .unwrap()
        .pragma_update(None, "user_version", store::MIGRATIONS.len() as i64 + 1)
        .unwrap();
    let mut c = MobileClient::new();
    let newer = call(&mut c, &mut h, "boot", json!({}));
    assert_eq!(newer["data"]["stores"], json!([]), "{newer}");
    assert!(
        h.logs
            .iter()
            .any(|l| l.ends_with("newer version of the app"))
    );
}

fn sent_body(h: &Fake) -> Value {
    serde_json::from_str(h.actions.last().unwrap()["body"].as_str().unwrap()).unwrap()
}
const SERVER_ID: &str = "8f1c2a8e-0b7d-4c3e-9a1f-2d4b8e0c7f53";
fn server_thread(messages: Value) -> Value {
    json!({"id":SERVER_ID,"status":"queued","archive_status":"active","messages":messages})
}

#[test]
fn follow_ups_belong_to_the_latest_completed_answer_including_cached_reads() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let mut thread = server_thread(json!([
        {"role":"assistant","suggestions":["Old suggestion"]},
        {"role":"user","content":"What next?"},
        {"role":"assistant","content":"Done","suggestions":[
            "", 42, "  Explain the tradeoff  ", "é".repeat(120), "x".repeat(121), "Add a regression test", "Fourth"
        ], "suggestion_icons": {"Explain the tradeoff":"explain", "Add a regression test":"unknown", "Fourth":"test"}}
    ]));
    thread["status"] = json!("idle");
    h.responses.push_back((200, thread.clone()));
    let result = call(&mut c, &mut h, "thread", json!({"id":SERVER_ID}));
    let expected = json!([
        "Explain the tradeoff",
        "é".repeat(120),
        "Add a regression test"
    ]);
    assert_eq!(result["data"]["suggestions"], expected, "{result}");
    assert_eq!(
        result["data"]["suggestion_icons"],
        json!({"Explain the tradeoff":"explain"})
    );
    let cached = call(&mut c, &mut h, "cached_thread", json!({"id":SERVER_ID}));
    assert_eq!(cached["data"]["suggestions"], expected, "{cached}");
    assert_eq!(
        cached["data"]["suggestion_icons"],
        json!({"Explain the tradeoff":"explain"})
    );

    for status in [
        "queued",
        "running",
        "failed",
        "interrupted",
        "outcome_unknown",
    ] {
        let mut working = thread.clone();
        working["status"] = json!(status);
        h.responses.push_back((200, working));
        let result = call(&mut c, &mut h, "thread", json!({"id":SERVER_ID}));
        assert_eq!(
            result["data"]["suggestions"],
            json!([]),
            "{status}: {result}"
        );
        assert_eq!(result["data"]["suggestion_icons"], json!({}));
    }
    let mut archived = thread.clone();
    archived["archive_status"] = json!("archived");
    h.responses.push_back((200, archived));
    let result = call(&mut c, &mut h, "thread", json!({"id":SERVER_ID}));
    assert_eq!(result["data"]["suggestions"], json!([]));

    // A newer answer without suggestions must not revive an older turn's.
    thread["messages"]
        .as_array_mut()
        .unwrap()
        .push(json!({"role":"assistant","content":"No follow-up"}));
    h.responses.push_back((200, thread.clone()));
    let result = call(&mut c, &mut h, "thread", json!({"id":SERVER_ID}));
    assert_eq!(result["data"]["suggestions"], json!([]));

    thread["messages"].as_array_mut().unwrap().pop();
    h.responses.push_back((200, thread));
    call(&mut c, &mut h, "thread", json!({"id":SERVER_ID}));
    h.offline = true;
    let queued = call(
        &mut c,
        &mut h,
        "send_message",
        json!({"id":SERVER_ID,"content":"My next question"}),
    );
    assert_eq!(queued["data"]["suggestions"], json!([]), "{queued}");
    assert_eq!(queued["data"]["suggestion_icons"], json!({}));
    let cached = call(&mut c, &mut h, "cached_thread", json!({"id":SERVER_ID}));
    assert_eq!(cached["data"]["suggestions"], json!([]), "{cached}");
}

#[test]
fn replies_to_a_thread_started_offline_follow_it_to_the_server_id() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    h.offline = true;
    let started = call(
        &mut c,
        &mut h,
        "start_thread",
        json!({"content":"Idea one"}),
    );
    let local = started["data"]["id"].as_str().unwrap().to_string();
    call(
        &mut c,
        &mut h,
        "send_message",
        json!({"id":local,"content":"More detail"}),
    );

    // Online but not flushed: the server doesn't have the thread yet, so a
    // reply queues behind it instead of posting to the local id.
    h.offline = false;
    let behind = call(
        &mut c,
        &mut h,
        "send_message",
        json!({"id":local,"content":"And this"}),
    );
    assert_eq!(behind["data"]["freshness"]["state"], "queued", "{behind}");
    let contents: Vec<_> = behind["data"]["messages"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| m["content"].clone())
        .collect();
    assert_eq!(
        contents,
        [json!("Idea one"), json!("More detail"), json!("And this")]
    );

    h.responses.extend([
        (200, json!({"models":[{"provider":"chatgpt","id":"gpt-a"}],"errors":[]})),
        (200, server_thread(json!([{"role":"user","content":"Idea one"}]))),
        (200, server_thread(json!([{"role":"user","content":"Idea one"},{"role":"user","content":"More detail"}]))),
        (200, server_thread(json!([{"role":"user","content":"Idea one"},{"role":"user","content":"More detail"},{"role":"user","content":"And this"}]))),
    ]);
    let flushed = call(&mut c, &mut h, "flush_outbox", json!({}));
    assert_eq!(flushed["data"]["sent"], 3, "{flushed}");
    let posts: Vec<_> = h
        .actions
        .iter()
        .filter(|a| a["method"] == "POST" && a["type"] == "http")
        .map(|a| a["url"].as_str().unwrap().to_string())
        .collect();
    let tail = &posts[posts.len() - 3..];
    assert!(tail[0].ends_with("/threads"), "{tail:?}");
    assert!(
        tail[1].ends_with(&format!("/threads/{SERVER_ID}/messages")),
        "{tail:?}"
    );
    assert!(
        tail[2].ends_with(&format!("/threads/{SERVER_ID}/messages")),
        "{tail:?}"
    );
    assert_eq!(sent_body(&h)["content"], "And this");

    // A view still open on the local id reads the server's thread.
    let reopened = call(&mut c, &mut h, "cached_thread", json!({"id":local}));
    assert_eq!(reopened["data"]["id"], SERVER_ID);
    assert_eq!(reopened["data"]["messages"].as_array().unwrap().len(), 3);
    assert_eq!(reopened["data"]["freshness"]["state"], "cached");
    h.responses.push_back((200, server_thread(json!([]))));
    call(&mut c, &mut h, "thread", json!({"id":local}));
    assert!(
        h.actions.last().unwrap()["url"]
            .as_str()
            .unwrap()
            .ends_with(SERVER_ID)
    );
}
#[test]
fn a_write_whose_response_was_lost_replays_under_the_key_it_was_sent_with() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    h.responses.extend([
        (
            200,
            json!({"models":[{"provider":"chatgpt","id":"gpt-a"}],"errors":[]}),
        ),
        (0, Value::Null),
    ]);
    let queued = call(
        &mut c,
        &mut h,
        "start_thread",
        json!({"content":"Idea one"}),
    );
    assert_eq!(queued["data"]["freshness"]["state"], "queued", "{queued}");
    let first = sent_body(&h)["request_id"].clone();
    assert_eq!(queued["data"]["id"], first);

    h.responses.extend([
        (
            200,
            json!({"models":[{"provider":"chatgpt","id":"gpt-a"}],"errors":[]}),
        ),
        (
            200,
            server_thread(json!([{"role":"user","content":"Idea one"}])),
        ),
    ]);
    assert_eq!(
        call(&mut c, &mut h, "flush_outbox", json!({}))["data"]["sent"],
        1
    );
    assert_eq!(sent_body(&h)["request_id"], first);

    // Writing the same text again afterwards is a new message, not a replay.
    h.responses.push_back((200, server_thread(json!([]))));
    call(
        &mut c,
        &mut h,
        "send_message",
        json!({"id":SERVER_ID,"content":"Idea one"}),
    );
    assert_ne!(sent_body(&h)["request_id"], first);
}
#[test]
fn flushing_stops_at_errors_that_may_clear_and_fails_only_refused_writes() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    h.offline = true;
    for content in ["First", "Second"] {
        call(
            &mut c,
            &mut h,
            "send_message",
            json!({"id":SERVER_ID,"content":content}),
        );
    }
    h.offline = false;
    // A server error, then a busy thread: nothing is sent, nothing is lost,
    // and the second write isn't tried ahead of the first.
    for status in [503, 409] {
        h.responses.push_back((status, Value::Null));
        assert_eq!(
            call(&mut c, &mut h, "flush_outbox", json!({}))["data"]["sent"],
            0
        );
        assert!(h.responses.is_empty());
    }
    h.responses.extend([
        (200, server_thread(json!([]))),
        (200, server_thread(json!([]))),
    ]);
    assert_eq!(
        call(&mut c, &mut h, "flush_outbox", json!({}))["data"]["sent"],
        2
    );
    assert_eq!(sent_body(&h)["content"], "Second");

    // A write the server refuses is kept and shown as failed, not retried.
    h.offline = true;
    call(
        &mut c,
        &mut h,
        "send_message",
        json!({"id":SERVER_ID,"content":"Third"}),
    );
    h.offline = false;
    h.responses.push_back((400, Value::Null));
    assert_eq!(
        call(&mut c, &mut h, "flush_outbox", json!({}))["data"]["sent"],
        0
    );
    let view = call(&mut c, &mut h, "cached_thread", json!({"id":SERVER_ID}));
    let last = view["data"]["messages"]
        .as_array()
        .unwrap()
        .last()
        .unwrap()
        .clone();
    assert_eq!(
        (last["content"].clone(), last["failed"].clone()),
        (json!("Third"), json!(true))
    );
    assert_eq!(
        call(&mut c, &mut h, "flush_outbox", json!({}))["data"]["sent"],
        0
    );
}
#[test]
fn the_store_never_masks_what_the_server_said() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    let profile = login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let page = json!({"threads":[{"id":SERVER_ID,"title":"Release plan","status":"idle","archive_status":"active"}],"next_cursor":null});
    h.responses.push_back((200, page.clone()));
    call(&mut c, &mut h, "threads", json!({}));

    // A host failure that isn't connectivity is an error, not a cached inbox.
    h.responses.push_back((1, Value::Null));
    let failed = call(&mut c, &mut h, "threads", json!({}));
    assert!(failed["error"].is_string(), "{failed}");
    h.responses.extend([
        (
            200,
            json!({"models":[{"provider":"chatgpt","id":"gpt-a"}],"errors":[]}),
        ),
        (1, Value::Null),
    ]);
    assert!(call(&mut c, &mut h, "start_thread", json!({"content":"Idea"}))["error"].is_string());

    // Older messages come from the server, not the cached latest page.
    h.responses.push_back((
        200,
        server_thread(json!([{"role":"user","content":"Latest"}])),
    ));
    call(&mut c, &mut h, "thread", json!({"id":SERVER_ID}));
    h.responses.push_back((
        200,
        server_thread(json!([{"role":"user","content":"Older"}])),
    ));
    let older = call(&mut c, &mut h, "thread", json!({"id":SERVER_ID,"before":5}));
    assert_eq!(older["data"]["messages"][0]["content"], "Older");
    let cached = call(&mut c, &mut h, "cached_thread", json!({"id":SERVER_ID}));
    assert_eq!(cached["data"]["messages"][0]["content"], "Latest");

    // A database from a newer build can't be used, but live answers still arrive.
    let path = h
        .directory
        .clone()
        .unwrap()
        .join(format!("{profile}.sqlite3"));
    c = MobileClient::new();
    rusqlite::Connection::open(&path)
        .unwrap()
        .pragma_update(None, "user_version", store::MIGRATIONS.len() as i64 + 1)
        .unwrap();
    h.responses.push_back((200, page));
    let live = call(&mut c, &mut h, "threads", json!({}));
    assert_eq!(
        live["data"]["threads"][0]["title"], "Release plan",
        "{live}"
    );
    assert_eq!(live["data"]["freshness"]["state"], "live");
    // Sign-out still removes it.
    assert!(
        call(&mut c, &mut h, "sign_out", json!({}))
            .get("error")
            .is_none()
    );
    assert!(!path.exists());
}
#[test]
fn an_inbox_the_server_refuses_keeps_what_was_stored() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    h.responses.push_back((
        200,
        json!({"threads":[{"id":SERVER_ID,"title":"Release plan","status":"idle","archive_status":"active"}],"next_cursor":null}),
    ));
    call(&mut c, &mut h, "threads", json!({}));
    h.responses.push_back((403, Value::Null));
    let refused = call(&mut c, &mut h, "threads", json!({}));
    assert_eq!(refused["data"]["available"], false, "{refused}");
    assert_eq!(refused["data"]["reason"], "sign_in_required");
    let cached = call(&mut c, &mut h, "cached_threads", json!({}));
    assert_eq!(cached["data"]["threads"][0]["title"], "Release plan");
}

#[test]
fn lounge_operations_use_the_luft_api_and_keep_direct_conversations_private() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    let profile = login(&mut c, &mut h, "https://luft.work", 1, i64::MAX);
    h.responses
        .push_back((200, json!({"organizations":[{"name":"team"}]})));
    call(&mut c, &mut h, "organizations", json!({}));
    call(
        &mut c,
        &mut h,
        "select_organization",
        json!({"id":profile,"name":"team"}),
    );

    let lounge =
        json!({"id":SERVER_ID,"kind":"lounge","name":"releases","members":[],"messages":[]});
    let direct =
        json!({"id":SERVER_ID,"kind":"direct","members":[{"id":2,"handle":"ana"}],"messages":[]});
    for (operation, args, response, method, suffix) in [
        (
            "lounges",
            json!({}),
            json!({"lounges":[lounge.clone()],"directs":[direct.clone()]}),
            "GET",
            String::new(),
        ),
        (
            "create_lounge",
            json!({"name":"releases","user_ids":[2]}),
            lounge.clone(),
            "POST",
            String::new(),
        ),
        (
            "lounge",
            json!({"id":SERVER_ID,"before":7}),
            lounge.clone(),
            "GET",
            format!("/{SERVER_ID}?before=7"),
        ),
        (
            "send_lounge_message",
            json!({"id":SERVER_ID,"content":"Hello"}),
            lounge.clone(),
            "POST",
            format!("/{SERVER_ID}/messages"),
        ),
        (
            "read_lounge",
            json!({"id":SERVER_ID,"position":7}),
            json!({"ok":true}),
            "POST",
            format!("/{SERVER_ID}/read"),
        ),
        (
            "invite_lounge",
            json!({"id":SERVER_ID,"user_ids":[2]}),
            lounge.clone(),
            "POST",
            format!("/{SERVER_ID}/members"),
        ),
        (
            "lounge_people",
            json!({}),
            json!({"people":[{"id":2,"handle":"ana"}]}),
            "GET",
            "/people".into(),
        ),
        (
            "start_direct",
            json!({"user_ids":[2]}),
            direct.clone(),
            "POST",
            "/directs".into(),
        ),
        // Reading, sending and marking read use the same operations for a DM,
        // without changing its server kind or exposing it as a public lounge.
        (
            "lounge",
            json!({"id":SERVER_ID}),
            direct.clone(),
            "GET",
            format!("/{SERVER_ID}"),
        ),
        (
            "send_lounge_message",
            json!({"id":SERVER_ID,"content":"Private"}),
            direct.clone(),
            "POST",
            format!("/{SERVER_ID}/messages"),
        ),
        (
            "read_lounge",
            json!({"id":SERVER_ID,"position":8}),
            json!({"ok":true}),
            "POST",
            format!("/{SERVER_ID}/read"),
        ),
    ] {
        let expected_kind = response.get("kind").cloned();
        h.responses.push_back((200, response));
        let result = call(&mut c, &mut h, operation, args);
        assert!(result.get("error").is_none(), "{operation}: {result}");
        if let Some(kind) = expected_kind {
            assert_eq!(result["data"]["kind"], kind, "{operation}");
        }
        let request = h
            .actions
            .iter()
            .rev()
            .find(|action| action["type"] == "http")
            .unwrap();
        assert_eq!(request["method"], method, "{operation}");
        assert_eq!(
            request["url"],
            format!("https://luft.work/api/accounts/team/lounges{suffix}"),
            "{operation}"
        );
        match operation {
            "lounges" => {
                assert_eq!(result["data"]["lounges"][0]["kind"], "lounge");
                assert_eq!(result["data"]["lounges"][0]["title"], "#releases");
                assert_eq!(result["data"]["directs"][0]["kind"], "direct");
                assert_eq!(result["data"]["directs"][0]["title"], "ana");
            }
            "create_lounge" => assert_eq!(sent_body(&h)["name"], "releases"),
            "start_direct" => {
                assert_eq!(sent_body(&h)["user_ids"], json!([2]));
                assert!(sent_body(&h).get("kind").is_none());
                assert_eq!(result["data"]["kind"], "direct");
            }
            _ => {}
        }
    }
    assert!(h.responses.is_empty());
}

#[test]
fn each_conversation_tab_keeps_its_own_stack_and_back_stays_in_it() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let lounge = "aaaaaaaa-1234-5678-9abc-123456789abc";
    let thread = "bbbbbbbb-1234-5678-9abc-123456789abc";
    call(
        &mut c,
        &mut h,
        "navigate",
        json!({"url":format!("/threads/{thread}")}),
    );
    let nav = call(
        &mut c,
        &mut h,
        "navigate",
        json!({"url":format!("/lounges/{lounge}")}),
    )["view"]["navigation"]
        .clone();
    assert_eq!(
        (nav["tab"].as_str(), nav["lounge_id"].as_str()),
        (Some("lounges"), Some(lounge))
    );
    assert_eq!(nav["thread_id"], thread);

    let dms =
        call(&mut c, &mut h, "select_tab", json!({"tab":"dms"}))["view"]["navigation"].clone();
    assert_eq!(dms["path"], "/dms");
    let back = call(&mut c, &mut h, "select_tab", json!({"tab":"lounges"}));
    assert_eq!(
        back["view"]["navigation"]["path"],
        format!("/lounges/{lounge}")
    );

    // Back leaves the lounge for the lounges list; the thread stays open in its tab.
    let nav = call(&mut c, &mut h, "navigation_back", json!({}))["view"]["navigation"].clone();
    assert_eq!(
        (nav["path"].as_str(), nav["lounge_id"].is_null()),
        (Some("/lounges"), true)
    );
    let threads = call(&mut c, &mut h, "select_tab", json!({"tab":"threads"}));
    assert_eq!(
        threads["view"]["navigation"]["path"],
        format!("/threads/{thread}")
    );
    assert!(call(&mut c, &mut h, "select_tab", json!({"tab":"channels"}))["error"].is_string());
}

#[test]
fn presence_joins_the_selected_organization_and_marks_lounges_people_online() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    let id = login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    // A personal account has no presence and opens nothing.
    let personal = call(&mut c, &mut h, "presence", json!({}));
    assert_eq!(personal["data"]["reason"], "personal");
    assert!(h.actions.iter().all(|a| a["type"] != "socket_open"));

    h.responses
        .push_back((200, json!({"organizations":[{"name":"team"}]})));
    call(&mut c, &mut h, "organizations", json!({}));
    call(
        &mut c,
        &mut h,
        "select_organization",
        json!({"id":id,"name":"team"}),
    );
    call(&mut c, &mut h, "presence", json!({}));
    let open = h
        .actions
        .iter()
        .find(|a| a["type"] == "socket_open")
        .unwrap()
        .clone();
    assert_eq!(
        open["url"],
        "wss://one.test/threads/socket/websocket?vsn=2.0.0"
    );
    assert!(
        open["protocols"][1]
            .as_str()
            .unwrap()
            .starts_with("base64url.bearer.phx.")
    );
    // Credentials go to the host action only, never into a response.
    h.frames = vec![
        r#"["1","1","presence:team","phx_reply",{"status":"ok","response":{}}]"#.into(),
        r#"["1",null,"presence:team","presence_state",{"2":{"metas":[{"handle":"ben","phx_ref":"x"}]}}]"#.into(),
    ];
    let joined = call(&mut c, &mut h, "presence", json!({}));
    assert_eq!(joined["data"]["online"], json!([{"id":2,"handle":"ben"}]));
    assert!(!joined.to_string().contains("base64url.bearer"));

    h.responses.push_back((200, json!({"people":[{"id":2,"handle":"ben","online":false},{"id":3,"handle":"cai","online":true}]})));
    let people = call(&mut c, &mut h, "lounge_people", json!({}));
    assert_eq!(people["data"]["people"][0]["online"], true);
    assert_eq!(people["data"]["people"][1]["online"], false);

    let before = h.actions.len();
    call(&mut c, &mut h, "sign_out", json!({}));
    assert!(
        h.actions[before..]
            .iter()
            .any(|a| a["type"] == "socket_close")
    );
}

#[test]
fn cards_get_the_height_of_their_size_class_and_unshowable_ones_fall_back_to_text() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let card = |size: Value, source: &str| json!({"role":"assistant","content":"Fallback","ui":{"size":size,"source":source}});
    h.responses.push_back((
        200,
        server_thread(json!([
            card(json!("compact"), "mount()"),
            card(json!("tall"), "mount()"),
            card(json!("huge"), "mount()"),
            card(json!(null), "mount()"),
            card(json!("medium"), ""),
            card(json!("medium"), &"x".repeat(256 * 1024 + 1)),
        ])),
    ));
    let shown = |thread: &Value| -> Vec<Value> {
        thread["data"]["messages"]
            .as_array()
            .unwrap()
            .iter()
            .map(|m| m.get("ui").map_or(Value::Null, |ui| ui["height"].clone()))
            .collect()
    };
    let expected = vec![
        json!(120),
        json!(400),
        Value::Null,
        Value::Null,
        Value::Null,
        Value::Null,
    ];
    let thread = call(&mut c, &mut h, "thread", json!({"id":SERVER_ID}));
    assert_eq!(shown(&thread), expected, "{thread}");
    assert!(
        thread["data"]["messages"]
            .as_array()
            .unwrap()
            .iter()
            .all(|m| m["content"] == "Fallback")
    );
    // Offline, the stored conversation keeps the same frames.
    let cached = call(&mut c, &mut h, "cached_thread", json!({"id":SERVER_ID}));
    assert_eq!(shown(&cached), expected, "{cached}");
}

#[test]
fn tool_results_unwrap_text_without_replacing_raw_evidence() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let payload = json!({"test_cases":[
        {"name":"shard_with_remote_test_products()", "module_name":"TuistServerAcceptanceTests",
         "suite_name":"ShardAcceptanceTests", "is_flaky":true, "state":"muted", "id":"keep-in-raw"},
        {"name":"test_run_tests_with_specified_arch()", "is_flaky":false}
    ]});
    let raw = json!({"content":[{"type":"text","text":payload.to_string()}]}).to_string();
    let mixed = json!({"content":[{"type":"text","text":"keep me"},
        {"type":"image","data":"image-evidence","mimeType":"image/png"}]})
    .to_string();
    let long = "🛠".repeat(1201);
    let messages = json!([
        {"role":"tool","content":raw},
        {"role":"tool","content":"{truncated"},
        {"role":"tool","content":mixed},
        {"role":"tool","content":long},
        {"role":"assistant","content":raw},
        {"role":"tool","content":json!({"content":[{"type":"text","text":"First"},{"type":"text","text":"Second"}]}).to_string()}
    ]);
    h.responses.push_back((200, server_thread(messages)));
    let thread = call(&mut c, &mut h, "thread", json!({"id":SERVER_ID}));
    let shown = &thread["data"]["messages"];
    assert_eq!(shown[0]["content"], raw);
    assert_eq!(
        serde_json::from_str::<Value>(shown[0]["toolResult"]["text"].as_str().unwrap()).unwrap(),
        payload
    );
    assert_eq!(
        serde_json::from_str::<Value>(shown[0]["toolResult"]["raw"].as_str().unwrap()).unwrap(),
        serde_json::from_str::<Value>(&raw).unwrap()
    );
    assert_eq!(
        shown[0]["toolResult"]["testCases"][0],
        json!({
            "name":"shard_with_remote_test_products()", "module":"TuistServerAcceptanceTests",
            "suite":"ShardAcceptanceTests", "flaky":true, "state":"muted"
        })
    );
    assert_eq!(shown[0]["toolResult"]["testCases"][1]["flaky"], false);
    assert_eq!(shown[1]["toolResult"]["text"], "{truncated");
    assert_eq!(shown[1]["toolResult"]["raw"], "{truncated");
    assert!(
        shown[2]["toolResult"]["text"]
            .as_str()
            .unwrap()
            .contains("image-evidence")
    );
    assert_eq!(shown[3]["toolResult"]["preview"], "🛠".repeat(1200));
    assert_eq!(shown[3]["toolResult"]["text"], long);
    assert_eq!(shown[4].get("toolResult"), None);
    assert_eq!(shown[5]["toolResult"]["text"], "First\n\nSecond");
}

#[test]
fn a_bash_calls_struo_build_shows_its_share_of_planned_targets_while_it_runs() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let build = |state: &str, planned: u64, done: u64| {
        json!({"command":"build","state":state,"target":"//app","planned":planned,"done":done,
               "cached":1,"failed":0,"running":[],"tests":{"passed":0,"failed":0,"skipped":0}})
    };
    let messages = json!([
        {"role":"user","content":"Build it"},
        {"role":"tool","content":"Building //app with Struo · 3 of 4 targets (1 cached)","toolName":"Bash",
         "toolStatus":"running","build":build("running", 4, 3)},
        {"role":"tool","content":"Building","toolName":"Bash","toolStatus":"running","build":build("running", 0, 2)},
        {"role":"tool","content":"done","toolName":"Bash","toolStatus":"complete","build":build("succeeded", 4, 4)},
        {"role":"tool","content":"Building","toolName":"Bash","toolStatus":"running",
         "build":{"command":"deploy","state":"running"}},
        {"role":"tool","content":"Testing","toolName":"Bash","toolStatus":"running",
         "build":{"command":"test","state":"running","planned":2,"done":3,"cached":0,"failed":0,
                  "tests":{"passed":5,"failed":1,"skipped":0}}},
    ]);
    h.responses
        .push_back((200, server_thread(messages.clone())));
    let thread = call(&mut c, &mut h, "thread", json!({"id":SERVER_ID}));
    let shown = &thread["data"]["messages"];
    assert_eq!(shown[1]["build"]["fraction"], json!(0.75), "{thread}");
    assert_eq!(shown[1]["build"]["active"], true);
    // No plan yet: the share is unknown, not zero.
    assert_eq!(shown[2]["build"]["fraction"], Value::Null);
    // A finished call's build stays as evidence but no longer animates.
    assert_eq!(shown[3]["build"]["active"], false);
    assert_eq!(shown[3]["build"]["fraction"], json!(1.0));
    // A build this core can't show falls back to the message's content.
    assert_eq!(shown[4].get("build"), None);
    // Edges draw what the core decided: no tests until a case ran, counts
    // within the plan, and a failing case marks the build failing.
    assert_eq!(shown[1]["build"]["tests"], Value::Null);
    assert_eq!(shown[1]["build"]["failing"], false);
    assert_eq!(shown[5]["build"]["done"], 2);
    assert_eq!(shown[5]["build"]["fraction"], json!(1.0));
    assert_eq!(shown[5]["build"]["failing"], true);
    assert_eq!(
        shown[5]["build"]["tests"],
        json!({"passed":5,"failed":1,"skipped":0})
    );

    let mut ended = server_thread(messages);
    ended["status"] = json!("interrupted");
    h.responses.push_back((200, ended));
    let thread = call(&mut c, &mut h, "thread", json!({"id":SERVER_ID}));
    assert_eq!(thread["data"]["messages"][1]["build"]["active"], false);
}

#[test]
fn only_the_answering_runs_plan_is_active_and_says_what_the_thread_does_now() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let plan =
        |steps: Value| json!({"role":"system","content":"- [ ] Plan","progress":{"steps":steps}});
    let step = |title: &str, status: &str| json!({"title":title,"status":status});
    let messages = json!([
        {"role":"user","content":"First"},
        plan(json!([step("Read", "completed"), step("Answer", "in_progress")])),
        {"role":"assistant","content":"Done"},
        {"role":"user","content":"Second"},
        plan(json!([step("Read", "done")])),
        plan(json!([step("Find the bug", "completed"), step("Fix it", "in_progress"), step("Test it", "pending")])),
        {"role":"tool","content":"Working…","toolName":"Bash","toolStatus":"running"},
    ]);
    h.responses
        .push_back((200, server_thread(messages.clone())));
    let thread = call(&mut c, &mut h, "thread", json!({"id":SERVER_ID}));
    let data = &thread["data"];
    assert_eq!(
        data["activity"],
        json!({"title":"Fix it","step":2,"total":3}),
        "{thread}"
    );
    let progress: Vec<Value> = data["messages"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| m.get("progress").cloned().unwrap_or(Value::Null))
        .collect();
    assert_eq!(progress[1]["active"], false);
    assert_eq!(
        (&progress[1]["completed"], &progress[1]["total"]),
        (&json!(1), &json!(2))
    );
    // A plan with a step this core can't show falls back to its content.
    assert_eq!(progress[4], Value::Null);
    assert_eq!(data["messages"][4]["content"], "- [ ] Plan");
    assert_eq!(progress[5]["active"], true);
    let cached = call(&mut c, &mut h, "cached_thread", json!({"id":SERVER_ID}));
    assert_eq!(cached["data"]["activity"], data["activity"], "{cached}");

    // Once the run ends, its plan is no longer active, even with a step left.
    let mut ended = server_thread(messages);
    ended["status"] = json!("idle");
    h.responses.push_back((200, ended));
    let thread = call(&mut c, &mut h, "thread", json!({"id":SERVER_ID}));
    assert_eq!(thread["data"]["activity"], Value::Null, "{thread}");
    assert_eq!(thread["data"]["messages"][5]["progress"]["active"], false);

    // A new message's run has no plan yet, so the previous one isn't current.
    let asked = json!([{"role":"user","content":"First"}, plan(json!([step("Read", "in_progress")])), {"role":"user","content":"Third"}]);
    h.responses.push_back((200, server_thread(asked)));
    let thread = call(&mut c, &mut h, "thread", json!({"id":SERVER_ID}));
    assert_eq!(thread["data"]["activity"], Value::Null, "{thread}");
    assert_eq!(thread["data"]["messages"][1]["progress"]["active"], false);
}

#[test]
fn live_activities_register_for_the_active_profile_and_report_retired_ids() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let id = "11111111-1111-4111-8111-111111111111";
    let token = "ab".repeat(32);
    let last = |h: &Fake| {
        h.actions
            .iter()
            .rev()
            .find(|a| a["type"] == "http")
            .unwrap()
            .clone()
    };
    let register = json!({"id":id,"token":token,"environment":"sandbox"});

    h.responses.push_back((204, Value::Null));
    let registered = call(&mut c, &mut h, "live_activity_register", register.clone());
    assert_eq!(registered["data"], json!({"registered":true}));
    let request = last(&h);
    assert_eq!(request["method"], "PUT");
    assert_eq!(
        request["url"],
        format!("https://one.test/api/me/thread-live-activities/{id}")
    );
    assert_eq!(
        serde_json::from_str::<Value>(request["body"].as_str().unwrap()).unwrap(),
        json!({"token":token,"environment":"sandbox"})
    );

    h.responses.push_back((410, json!({"message":"retired"})));
    let retired = call(&mut c, &mut h, "live_activity_register", register.clone());
    assert_eq!(
        retired["data"],
        json!({"registered":false,"reason":"retired"})
    );

    // Servers from before Live Activities answer 404: nothing to show, no error.
    h.responses.push_back((404, Value::Null));
    let old = call(&mut c, &mut h, "live_activity_register", register);
    assert_eq!(
        old["data"],
        json!({"registered":false,"reason":"unavailable"})
    );

    let before = h.actions.len();
    let invalid = call(
        &mut c,
        &mut h,
        "live_activity_register",
        json!({"id":id,"token":"not-hex","environment":"sandbox"}),
    );
    assert!(invalid["error"].is_string());
    assert_eq!(h.actions.len(), before);

    h.responses.push_back((204, Value::Null));
    let gone = call(&mut c, &mut h, "live_activity_unregister", json!({"id":id}));
    assert_eq!(gone["data"], json!({"unregistered":true}));
    assert_eq!(last(&h)["method"], "DELETE");

    // The push-to-start token goes with the active profile's ID, which the
    // server echoes in the attributes of the activities it starts.
    let profile = c.vault.active_profile_id.clone().unwrap();
    h.responses.push_back((204, Value::Null));
    let starter = call(
        &mut c,
        &mut h,
        "live_activity_starter_register",
        json!({"token":token,"environment":"production"}),
    );
    assert_eq!(starter["data"], json!({"registered":true}));
    let request = last(&h);
    assert_eq!(request["method"], "PUT");
    assert_eq!(
        request["url"],
        "https://one.test/api/me/thread-live-activity-starter"
    );
    assert_eq!(
        serde_json::from_str::<Value>(request["body"].as_str().unwrap()).unwrap(),
        json!({"token":token,"environment":"production","profile_id":profile})
    );

    h.responses.push_back((404, Value::Null));
    let old = call(
        &mut c,
        &mut h,
        "live_activity_starter_register",
        json!({"token":token,"environment":"production"}),
    );
    assert_eq!(
        old["data"],
        json!({"registered":false,"reason":"unavailable"})
    );

    h.responses.push_back((204, Value::Null));
    let forgotten = call(
        &mut c,
        &mut h,
        "live_activity_starter_unregister",
        json!({}),
    );
    assert_eq!(forgotten["data"], json!({"unregistered":true}));
    assert_eq!(last(&h)["method"], "DELETE");

    // Moving to a profile on another server forgets the token on the old one.
    login(&mut c, &mut h, "https://two.test", 2, i64::MAX);
    h.responses.push_back((204, Value::Null));
    let moved = call(
        &mut c,
        &mut h,
        "live_activity_starter_unregister",
        json!({"profile_id":profile}),
    );
    assert_eq!(moved["data"], json!({"unregistered":true}));
    assert_eq!(
        last(&h)["url"],
        "https://one.test/api/me/thread-live-activity-starter"
    );

    let before = h.actions.len();
    let unknown = call(
        &mut c,
        &mut h,
        "live_activity_starter_unregister",
        json!({"profile_id":"gone"}),
    );
    assert!(unknown["error"].is_string());
    assert_eq!(h.actions.len(), before);
}

#[test]
fn push_registration_keeps_one_installation_per_profile_and_rotates_when_retired() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let [first, second, third] = [
        "11111111-1111-4111-8111-111111111111",
        "22222222-2222-4222-8222-222222222222",
        "33333333-3333-4333-8333-333333333333",
    ];
    let device = |id: &str| json!({"installation_id":id,"platform":"ios","token":"ab".repeat(32),"environment":"production","name":"iPhone 17 Pro"});
    let last_url = |h: &Fake| {
        let request = h
            .actions
            .iter()
            .rev()
            .find(|a| a["type"] == "http")
            .unwrap();
        (request["method"].clone(), request["url"].clone())
    };

    // Off until the person turns them on: nothing reaches the server.
    let before = h.actions.len();
    let off = call(&mut c, &mut h, "push_register", device(first));
    assert_eq!(off["data"], json!({"registered":false,"reason":"disabled"}));
    assert_eq!(h.actions.len(), before);
    let on = call(&mut c, &mut h, "push_enable", json!({"enabled":true}));
    assert_eq!(on["view"]["profiles"][0]["push_enabled"], true);

    h.responses
        .push_back((200, json!({"registration_id":"r1"})));
    let registered = call(&mut c, &mut h, "push_register", device(first));
    assert_eq!(
        registered["data"],
        json!({"registered":true,"registration_id":"r1"})
    );
    assert_eq!(
        last_url(&h),
        (
            json!("PUT"),
            json!(format!("https://one.test/api/me/push-devices/{first}"))
        )
    );
    let body = &h
        .actions
        .iter()
        .rev()
        .find(|a| a["type"] == "http")
        .unwrap()["body"];
    assert_eq!(
        serde_json::from_str::<Value>(body.as_str().unwrap()).unwrap(),
        json!({"platform":"ios","token":"ab".repeat(32),"environment":"production","name":"iPhone 17 Pro"})
    );

    // The profile keeps its installation, whatever ID the edge proposes.
    h.responses
        .push_back((200, json!({"registration_id":"r1"})));
    call(&mut c, &mut h, "push_register", device(second));
    assert!(last_url(&h).1.as_str().unwrap().ends_with(first));

    // A retired installation moves to the edge's fresh ID.
    h.responses.extend([
        (410, json!({"reason":"retired"})),
        (200, json!({"registration_id":"r2"})),
    ]);
    let rotated = call(&mut c, &mut h, "push_register", device(second));
    assert_eq!(rotated["data"]["registration_id"], "r2");
    assert!(last_url(&h).1.as_str().unwrap().ends_with(second));
    // Saved without a new generation, so screens keep their state.
    assert_eq!(
        rotated["view"]["generation"],
        registered["view"]["generation"]
    );

    // Turning them off must reach the server; until it does they stay on.
    h.responses.push_back((500, Value::Null));
    let failed = call(&mut c, &mut h, "push_enable", json!({"enabled":false}));
    assert!(failed["error"].is_string());
    assert_eq!(failed["view"]["profiles"][0]["push_enabled"], true);
    h.responses.push_back((204, Value::Null));
    let off = call(&mut c, &mut h, "push_enable", json!({"enabled":false}));
    assert_eq!(off["view"]["profiles"][0]["push_enabled"], false);
    assert_eq!(
        last_url(&h),
        (
            json!("DELETE"),
            json!(format!("https://one.test/api/me/push-devices/{second}"))
        )
    );

    // Back on, the device registers as a new installation.
    call(&mut c, &mut h, "push_enable", json!({"enabled":true}));
    h.responses
        .push_back((200, json!({"registration_id":"r3"})));
    call(&mut c, &mut h, "push_register", device(first));
    assert!(last_url(&h).1.as_str().unwrap().ends_with(first));

    // Removed from the device list: the switch turns off, and nothing is sent
    // until the person turns it back on.
    h.responses.push_back((410, json!({"reason":"removed"})));
    let removed = call(&mut c, &mut h, "push_register", device(third));
    assert_eq!(
        removed["data"],
        json!({"registered":false,"reason":"removed"})
    );
    assert_eq!(removed["view"]["profiles"][0]["push_enabled"], false);
    let before = h.actions.len();
    let again = call(&mut c, &mut h, "push_register", device(third));
    assert_eq!(again["data"]["reason"], "disabled");
    assert_eq!(h.actions.len(), before);

    assert!(call(&mut c, &mut h, "push_register", device("not-a-uuid"))["error"].is_string());
}

#[test]
fn sign_out_unregisters_the_profiles_push_installation() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let id = "11111111-1111-4111-8111-111111111111";
    call(&mut c, &mut h, "push_enable", json!({"enabled":true}));
    h.responses
        .push_back((200, json!({"registration_id":"r1"})));
    call(
        &mut c,
        &mut h,
        "push_register",
        json!({"installation_id":id,"platform":"macos","token":"ab".repeat(32),"environment":"sandbox"}),
    );
    // Unreachable: sign-out still goes ahead.
    h.responses.push_back((0, Value::Null));
    let signed_out = call(&mut c, &mut h, "sign_out", json!({}));
    assert!(signed_out.get("error").is_none(), "{signed_out}");
    // The edge invalidates its device token, since the server still sends to it.
    assert_eq!(signed_out["data"]["push_unregister_failed"], true);
    let request = h
        .actions
        .iter()
        .rev()
        .find(|a| a["type"] == "http")
        .unwrap();
    assert_eq!(request["method"], "DELETE");
    assert_eq!(
        request["url"],
        format!("https://one.test/api/me/push-devices/{id}")
    );
}

#[test]
fn notifications_open_their_thread_in_the_account_they_belong_to() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    let thread = "12345678-1234-5678-9abc-123456789abc";
    let url = |server: &str| format!("{server}/luft/threads/{thread}");

    // Signed out, the link waits for sign-in like any other.
    call(
        &mut c,
        &mut h,
        "open_notification",
        json!({"url":url("https://one.test"),"account":"ana"}),
    );
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    assert_eq!(
        call(&mut c, &mut h, "snapshot", json!({}))["view"]["navigation"]["path"],
        format!("/threads/{thread}")
    );
    call(&mut c, &mut h, "navigation_back", json!({}));

    h.responses
        .push_back((200, json!({"organizations":[{"name":"team"}]})));
    call(&mut c, &mut h, "organizations", json!({}));
    let opened = call(
        &mut c,
        &mut h,
        "open_notification",
        json!({"url":url("https://one.test"),"account":"team"}),
    );
    assert!(opened.get("error").is_none(), "{opened}");
    assert_eq!(
        opened["view"]["navigation"]["path"],
        format!("/threads/{thread}")
    );
    assert_eq!(c.vault.profiles[0].organization.as_deref(), Some("team"));

    // Another server's, or an account no profile has: nothing changes.
    for (server, account) in [
        ("https://two.test", "ana"),
        ("https://one.test", "strangers"),
    ] {
        call(&mut c, &mut h, "navigation_back", json!({}));
        let refused = call(
            &mut c,
            &mut h,
            "open_notification",
            json!({"url":url(server),"account":account}),
        );
        assert!(refused["error"].is_string());
        assert_eq!(refused["view"]["navigation"]["path"], "/threads");
        assert_eq!(c.vault.profiles[0].organization.as_deref(), Some("team"));
    }

    // Back to the personal account.
    let personal = call(
        &mut c,
        &mut h,
        "open_notification",
        json!({"url":url("https://one.test"),"account":"ana"}),
    );
    assert_eq!(
        personal["view"]["navigation"]["path"],
        format!("/threads/{thread}")
    );
    assert_eq!(c.vault.profiles[0].organization, None);
}

#[test]
fn notifications_open_in_the_owners_profile_when_several_share_the_account() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    let ana = login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let ben = login(&mut c, &mut h, "https://one.test", 2, i64::MAX);
    h.responses.extend([
        (200, json!({"organizations":[{"name":"team"}]})),
        (200, json!({"organizations":[{"name":"team"}]})),
    ]);
    call(&mut c, &mut h, "organizations", json!({}));
    let url = "https://one.test/luft/threads/12345678-1234-5678-9abc-123456789abc";

    // Ben is active and in `team`, but the thread is Ana's.
    let opened = call(
        &mut c,
        &mut h,
        "open_notification",
        json!({"url":url,"account":"team","user":"ana"}),
    );
    assert!(opened.get("error").is_none(), "{opened}");
    assert_eq!(opened["view"]["active_profile_id"], ana);

    // Nobody signed in as the owner: nothing changes.
    let refused = call(
        &mut c,
        &mut h,
        "open_notification",
        json!({"url":url,"account":"team","user":"cleo"}),
    );
    assert!(refused["error"].is_string());
    assert_eq!(refused["view"]["active_profile_id"], ana);
    assert_ne!(ana, ben);
}

#[test]
fn threads_start_on_a_runner_only_online_and_runners_register_with_their_secret() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let runner = "9a1c2a8e-0b7d-4c3e-9a1f-2d4b8e0c7f53";

    h.responses.push_back((
        201,
        json!({"id":runner,"name":"macbook","platform":"macos","online":false,"token":"tgr_secret"}),
    ));
    let registered = call(
        &mut c,
        &mut h,
        "register_runner",
        json!({"name":"macbook","platform":"macos"}),
    );
    assert_eq!(registered["data"]["token"], "tgr_secret", "{registered}");
    assert_eq!(registered["data"]["server"], "https://one.test");
    assert_eq!(
        h.actions.last().unwrap()["url"],
        "https://one.test/api/me/thread-runners"
    );
    let refused = call(
        &mut c,
        &mut h,
        "register_runner",
        json!({"name":"x","platform":"beos"}),
    );
    assert!(refused.get("error").is_some());

    h.responses.extend([
        (
            200,
            json!({"models":[{"provider":"chatgpt","id":"gpt-a"}],"errors":[]}),
        ),
        (
            200,
            server_thread(json!([{"role":"user","content":"Look around"}])),
        ),
    ]);
    let started = call(
        &mut c,
        &mut h,
        "start_thread",
        json!({"content":"Look around","runner_id":runner}),
    );
    assert!(started.get("error").is_none(), "{started}");
    let body = sent_body(&h);
    assert_eq!(body["runner_id"], runner);
    let on_runner = body["request_id"].clone();

    // The same text on Tuist's sandbox is another thread, under another key.
    h.responses.extend([
        (
            200,
            json!({"models":[{"provider":"chatgpt","id":"gpt-a"}],"errors":[]}),
        ),
        (
            200,
            server_thread(json!([{"role":"user","content":"Look around"}])),
        ),
    ]);
    call(
        &mut c,
        &mut h,
        "start_thread",
        json!({"content":"Look around"}),
    );
    assert!(sent_body(&h).get("runner_id").is_none());
    assert_ne!(sent_body(&h)["request_id"], on_runner);

    // A runner the server hasn't heard from is refused, with its own message.
    h.responses.extend([
        (
            200,
            json!({"models":[{"provider":"chatgpt","id":"gpt-a"}],"errors":[]}),
        ),
        (
            409,
            json!({"reason":"runner_offline","message":"The runner is offline."}),
        ),
    ]);
    let refused = call(
        &mut c,
        &mut h,
        "start_thread",
        json!({"content":"Look again","runner_id":runner}),
    );
    assert_eq!(
        refused["error"],
        "That runner is offline. Open Luft on that machine and check its runner is connected"
    );

    // Offline, a thread on a runner fails instead of queueing without its runner.
    h.offline = true;
    let offline = call(
        &mut c,
        &mut h,
        "start_thread",
        json!({"content":"Later","runner_id":runner}),
    );
    assert_eq!(
        offline["error"],
        "Connect to the internet to start a thread on a runner"
    );
    let inbox = call(&mut c, &mut h, "cached_threads", json!({}));
    assert!(
        inbox["data"]["threads"]
            .as_array()
            .unwrap()
            .iter()
            .all(|t| t["pending"] != true),
        "{inbox}"
    );
}

#[test]
fn snooze_options_follow_the_local_clock() {
    use crate::threads::snooze_options;
    let until = |options: &Value, id: &str| {
        options["options"]
            .as_array()
            .unwrap()
            .iter()
            .find(|o| o["id"] == id)
            .map(|o| o["until"].clone())
    };
    // Wednesday 2026-11-18 08:30 UTC is 09:30 in Berlin (UTC+1).
    let wednesday = 1794990600;
    let options = snooze_options(wednesday, 3600, true);
    assert_eq!(until(&options, "until_needed"), Some(Value::Null));
    assert_eq!(
        until(&options, "in_2_hours"),
        Some(json!("2026-11-18T10:30:00Z"))
    );
    // 18:00 and 09:00 Berlin time, in UTC.
    assert_eq!(
        until(&options, "this_evening"),
        Some(json!("2026-11-18T17:00:00Z"))
    );
    assert_eq!(
        until(&options, "tomorrow"),
        Some(json!("2026-11-19T08:00:00Z"))
    );
    assert_eq!(
        until(&options, "next_week"),
        Some(json!("2026-11-23T08:00:00Z"))
    );
    // A finished thread has nothing to wait for.
    assert_eq!(
        until(&snooze_options(wednesday, 3600, false), "until_needed"),
        None
    );
    // At 17:30 Berlin, the evening is here already.
    assert_eq!(
        until(
            &snooze_options(wednesday + 8 * 3600, 3600, false),
            "this_evening"
        ),
        None
    );
    // 23:30 UTC on Wednesday is already Thursday in Tokyo (UTC+9).
    let tokyo = snooze_options(wednesday + 15 * 3600, 9 * 3600, false);
    assert_eq!(
        until(&tokyo, "tomorrow"),
        Some(json!("2026-11-20T00:00:00Z"))
    );
    // On a Sunday, next week starts the Monday after tomorrow.
    let sunday = wednesday + 4 * 86_400;
    assert_eq!(
        until(&snooze_options(sunday, 3600, false), "next_week"),
        Some(json!("2026-11-30T08:00:00Z"))
    );
}

#[test]
fn snoozed_threads_leave_their_section_until_the_snooze_ends() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let id = "6f1c2a8e-0b7d-4c3e-9a1f-2d4b8e0c7f53";
    let later = "2099-01-01T09:00:00Z";
    h.responses.extend([
        (
            200,
            json!({"threads":[
                {"id":"a","status":"running","archive_status":"active","snoozed_until_needed":true},
                {"id":"b","status":"idle","archive_status":"active","snoozed_until":later},
                {"id":"c","status":"idle","archive_status":"active","snoozed_until":"2020-01-01T09:00:00Z"},
                {"id":"d","status":"idle","archive_status":"active","snoozed_until_needed":true}
            ],"next_cursor":null}),
        ),
        (
            200,
            json!({"id":id,"status":"running","archive_status":"active","snoozed_until":later,"messages":[]}),
        ),
        (409, json!({})),
    ]);
    let page = call(&mut c, &mut h, "threads", json!({}));
    let shown: Vec<_> = page["data"]["threads"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| (t["section"].as_str().unwrap(), t["snooze"].clone()))
        .collect();
    assert_eq!(
        shown,
        [
            ("snoozed", json!({"until":null,"until_needed":true})),
            ("snoozed", json!({"until":later,"until_needed":false})),
            ("recent", Value::Null),
            ("recent", Value::Null),
        ]
    );

    let snoozed = call(
        &mut c,
        &mut h,
        "snooze_thread",
        json!({"id":id,"snooze":later}),
    );
    assert_eq!(snoozed["data"]["section"], "snoozed", "{snoozed}");
    assert_eq!(snoozed["data"]["working"], true);
    let request = h.actions.last().unwrap();
    assert_eq!(request["method"], "PATCH");
    assert_eq!(
        request["url"],
        format!("https://one.test/api/accounts/ana/threads/{id}")
    );
    assert_eq!(sent_body(&h), json!({"snooze":{"until":later}}));

    let finished = call(
        &mut c,
        &mut h,
        "snooze_thread",
        json!({"id":id,"snooze":"until_needed"}),
    );
    assert!(
        finished["error"]
            .as_str()
            .unwrap()
            .contains("nothing to wait for")
    );
    let count = h.actions.len();
    for snooze in [
        json!("2020-01-01T09:00:00Z"),
        json!("tomorrow"),
        json!(true),
    ] {
        assert!(
            call(
                &mut c,
                &mut h,
                "snooze_thread",
                json!({"id":id,"snooze":snooze})
            )["error"]
                .is_string()
        );
    }
    assert_eq!(h.actions.len(), count);

    // The stored conversation keeps the snooze offline.
    h.offline = true;
    let cached = call(&mut c, &mut h, "thread", json!({"id":id}));
    assert_eq!(cached["data"]["section"], "snoozed", "{cached}");
}

#[test]
fn reauthorization_requires_explicit_online_consent_and_never_sends_a_message() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    h.responses.push_back((
        200,
        json!({"id":SERVER_ID,"status":"idle","messages":[],
        "reauthorization_required":true,"can_reauthorize":true}),
    ));
    let thread = call(&mut c, &mut h, "thread", json!({"id":SERVER_ID}));
    assert_eq!(thread["data"]["can_reauthorize"], true);
    let count = h.actions.len();
    let denied = call(
        &mut c,
        &mut h,
        "reauthorize_thread",
        json!({"id":SERVER_ID}),
    );
    assert!(denied["error"].is_string());
    assert_eq!(h.actions.len(), count);
    h.offline = true;
    assert!(
        call(
            &mut c,
            &mut h,
            "send_message",
            json!({"id":SERVER_ID,"content":"draft"})
        )["error"]
            .is_string()
    );
    let consent = json!({"id":SERVER_ID,"consent":true});
    assert!(call(&mut c, &mut h, "reauthorize_thread", consent.clone())["error"].is_string());
    assert_eq!(
        call(&mut c, &mut h, "cached_thread", json!({"id":SERVER_ID}))["data"]["reauthorization_required"],
        true
    );
    h.offline = false;
    h.responses.push_back((403, json!({})));
    assert!(call(&mut c, &mut h, "reauthorize_thread", consent.clone())["error"].is_string());
    h.responses.push_back((
        200,
        json!({"id":SERVER_ID,"status":"idle","messages":[],
        "reauthorization_required":false,"can_reauthorize":true}),
    ));
    let authorized = call(&mut c, &mut h, "reauthorize_thread", consent);
    assert_eq!(authorized["data"]["reauthorization_required"], false);
    assert_eq!(authorized["data"]["can_reauthorize"], false);
    let request = h.actions.last().unwrap();
    assert_eq!(request["method"], "POST");
    assert_eq!(
        request["url"],
        format!("https://one.test/api/accounts/ana/threads/{SERVER_ID}/reauthorize")
    );
    assert_eq!(sent_body(&h), json!({}));
    assert_eq!(
        call(&mut c, &mut h, "flush_outbox", json!({}))["data"]["sent"],
        0
    );
    h.offline = true;
    assert_eq!(
        call(&mut c, &mut h, "cached_thread", json!({"id":SERVER_ID}))["data"]["reauthorization_required"],
        false
    );
}

#[test]
fn archiving_and_restoring_a_thread_moves_it_in_the_stored_inbox() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    h.responses.extend([
        (
            200,
            json!({"threads":[{"id":SERVER_ID,"status":"running","archive_status":"active"}],"next_cursor":null}),
        ),
        (
            200,
            json!({"id":SERVER_ID,"status":"idle","archive_status":"archived","messages":[]}),
        ),
    ]);
    call(&mut c, &mut h, "threads", json!({}));

    let archived = call(&mut c, &mut h, "archive_thread", json!({"id":SERVER_ID}));
    assert_eq!(archived["data"]["section"], "archived", "{archived}");
    let request = h.actions.last().unwrap();
    assert_eq!(request["method"], "PATCH");
    assert_eq!(
        request["url"],
        format!("https://one.test/api/accounts/ana/threads/{SERVER_ID}")
    );
    assert_eq!(sent_body(&h), json!({"status":"archived"}));

    let inbox = call(&mut c, &mut h, "cached_threads", json!({}));
    assert_eq!(
        inbox["data"]["threads"][0]["section"], "archived",
        "{inbox}"
    );

    h.responses.push_back((
        200,
        json!({"id":SERVER_ID,"status":"idle","archive_status":"active","messages":[]}),
    ));
    let restored = call(
        &mut c,
        &mut h,
        "archive_thread",
        json!({"id":SERVER_ID,"archived":false}),
    );
    assert_eq!(restored["data"]["section"], "recent", "{restored}");
    assert_eq!(sent_body(&h), json!({"status":"active"}));
    let inbox = call(&mut c, &mut h, "cached_threads", json!({}));
    assert_eq!(inbox["data"]["threads"][0]["section"], "recent", "{inbox}");

    let count = h.actions.len();
    let invalid = call(
        &mut c,
        &mut h,
        "archive_thread",
        json!({"id":SERVER_ID,"archived":"no"}),
    );
    assert!(invalid["error"].is_string());
    assert_eq!(h.actions.len(), count);
}

#[test]
fn palette_searches_the_stored_inbox_and_the_lounges_of_the_selected_account() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    let id = login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    h.responses
        .push_back((200, json!({"organizations":[{"name":"team"}]})));
    call(&mut c, &mut h, "organizations", json!({}));
    call(
        &mut c,
        &mut h,
        "select_organization",
        json!({"id":id,"name":"team"}),
    );
    h.responses.push_back((
        200,
        json!({"threads":[{"id":SERVER_ID,"title":"Release plan","status":"idle","archive_status":"active"}],"next_cursor":null}),
    ));
    call(&mut c, &mut h, "threads", json!({}));
    let lounge = "11111111-1111-1111-1111-111111111111";
    h.responses.push_back((
        200,
        json!({"lounges":[{"id":lounge,"kind":"lounge","name":"releases","members":[],"unread":0}],"directs":[]}),
    ));
    call(&mut c, &mut h, "lounges", json!({}));

    // Offline and without requests: the palette reads only what is stored.
    h.offline = true;
    let before = h.actions.len();
    let found = call(&mut c, &mut h, "palette", json!({"query":"release"}));
    assert_eq!(h.actions.len(), before);
    let urls: Vec<&str> = found["data"]["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| i["url"].as_str().unwrap())
        .collect();
    assert_eq!(
        urls,
        [
            format!("/threads/{SERVER_ID}"),
            format!("/lounges/{lounge}")
        ]
    );
    // Navigating to a result opens it like any link.
    call(&mut c, &mut h, "navigate", json!({"url":urls[1]}));
    let view = call(&mut c, &mut h, "snapshot", json!({}));
    assert_eq!(view["view"]["navigation"]["lounge_id"], lounge);

    // Another account's lounges are not offered.
    call(
        &mut c,
        &mut h,
        "select_organization",
        json!({"id":id,"name":null}),
    );
    let personal = call(&mut c, &mut h, "palette", json!({"query":"#rel"}));
    assert_eq!(personal["data"]["items"], json!([]));
}
#[test]
fn a_refreshed_first_page_keeps_the_pages_loaded_after_it() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let thread =
        |id: &str, status: &str| json!({"id":id,"status":status,"archive_status":"active"});
    let ids = |page: &Value| -> Vec<String> {
        page["data"]["threads"]
            .as_array()
            .unwrap()
            .iter()
            .map(|t| t["id"].as_str().unwrap().to_string())
            .collect()
    };
    h.responses.extend([
        (
            200,
            json!({"threads":[thread("a","idle"), thread("b","idle")],"next_cursor":"after-b"}),
        ),
        (
            200,
            json!({"threads":[thread("c","idle"), thread("d","idle")],"next_cursor":"after-d"}),
        ),
        // `d` started working, so it moved to the top and pushed `b` off the first page.
        (
            200,
            json!({"threads":[thread("d","running"), thread("a","idle")],"next_cursor":"after-a"}),
        ),
    ]);
    call(&mut c, &mut h, "threads", json!({}));
    call(&mut c, &mut h, "threads", json!({"cursor":"after-b"}));
    let refreshed = call(&mut c, &mut h, "threads", json!({}));
    assert_eq!(ids(&refreshed), ["d", "a", "b", "c"]);
    assert_eq!(refreshed["data"]["threads"][0]["section"], "in_progress");
    // Paging continues after the last thread loaded, not after the new first page.
    assert_eq!(refreshed["data"]["next_cursor"], "after-d");
    assert_eq!(
        call(&mut c, &mut h, "cached_threads", json!({}))["data"]["next_cursor"],
        "after-d"
    );

    // A first page that is the whole inbox replaces it: `b` and `c` are gone.
    h.responses.push_back((
        200,
        json!({"threads":[thread("d","idle"), thread("a","idle")],"next_cursor":null}),
    ));
    let whole = call(&mut c, &mut h, "threads", json!({}));
    assert_eq!(ids(&whole), ["d", "a"]);
    assert_eq!(whole["data"]["next_cursor"], Value::Null);
}

#[test]
fn ai_subscriptions_connect_claude_and_sign_in_to_chatgpt() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let list = |claude: bool| {
        json!({"subscriptions":[
            {"provider":"claude","connected":claude,"updated_at":null,"login_available":true,"runs_threads":false},
            {"provider":"chatgpt","connected":false,"updated_at":null,"login_available":true,"runs_threads":true}]})
    };

    h.responses.push_back((200, list(false)));
    let listed = call(&mut c, &mut h, "ai_subscriptions", json!({}));
    assert_eq!(listed["data"], list(false));
    assert_eq!(
        h.actions.last().unwrap()["url"],
        "https://one.test/api/me/ai-subscriptions"
    );

    // An API key instead of the setup token: the server refuses it, and the person hears why.
    h.responses
        .push_back((422, json!({"message":"Provide the subscription token"})));
    let refused = call(
        &mut c,
        &mut h,
        "connect_claude",
        json!({"token":"sk-ant-api03"}),
    );
    assert_eq!(refused["error"], CLAUDE_TOKEN_REFUSED);

    h.responses.push_back((200, list(true)));
    let connected = call(
        &mut c,
        &mut h,
        "connect_claude",
        json!({"token":"  sk-ant-oat01-x \n"}),
    );
    assert_eq!(connected["data"], list(true));
    let request = h.actions.last().unwrap();
    assert_eq!(request["method"], "PUT");
    assert_eq!(
        request["url"],
        "https://one.test/api/me/ai-subscriptions/claude"
    );
    // Pasted tokens keep no surrounding whitespace.
    assert_eq!(sent_body(&h), json!({"token":"sk-ant-oat01-x"}));
    // The token never reaches a view or the vault.
    assert!(!connected.to_string().contains("sk-ant-oat01-x"));
    assert!(!h.vault.as_ref().unwrap().contains("sk-ant-oat01-x"));

    h.responses.push_back((
        200,
        json!({"login_id":"l&1","user_code":"ABCD-EFGH","verification_url":"https://auth.openai.com/codex/device","interval":5,"expires_at":"2026-11-25T23:00:00Z"}),
    ));
    let started = call(&mut c, &mut h, "start_chatgpt_login", json!({}));
    assert_eq!(started["data"]["user_code"], "ABCD-EFGH");

    h.responses.push_back((200, json!({"status":"pending"})));
    let pending = call(
        &mut c,
        &mut h,
        "poll_chatgpt_login",
        json!({"login_id":"l&1"}),
    );
    assert_eq!(pending["data"]["status"], "pending");
    assert_eq!(sent_body(&h), json!({"login_id":"l&1"}));

    h.responses.push_back((410, json!({"message":"expired"})));
    let expired = call(
        &mut c,
        &mut h,
        "poll_chatgpt_login",
        json!({"login_id":"l&1"}),
    );
    assert_eq!(expired["data"]["status"], "failed");

    // Cancelling a sign-in the server already forgot is done.
    h.responses
        .push_back((404, json!({"message":"Not found."})));
    let cancelled = call(
        &mut c,
        &mut h,
        "cancel_chatgpt_login",
        json!({"login_id":"l&1"}),
    );
    assert!(cancelled.get("error").is_none(), "{cancelled}");
    let request = h.actions.last().unwrap();
    assert_eq!(request["method"], "DELETE");
    assert_eq!(
        request["url"],
        "https://one.test/api/me/ai-subscriptions/chatgpt/login?login_id=l%261"
    );

    h.responses.push_back((200, list(false)));
    call(
        &mut c,
        &mut h,
        "disconnect_ai_subscription",
        json!({"provider":"claude"}),
    );
    assert_eq!(
        h.actions.last().unwrap()["url"],
        "https://one.test/api/me/ai-subscriptions/claude"
    );
    let requests = h.actions.len();
    let unknown = call(
        &mut c,
        &mut h,
        "disconnect_ai_subscription",
        json!({"provider":"../x"}),
    );
    assert!(unknown["error"].is_string());
    assert_eq!(h.actions.len(), requests);

    // A server or account without the feature.
    h.responses
        .push_back((404, json!({"message":"Not found."})));
    let unavailable = call(&mut c, &mut h, "ai_subscriptions", json!({}));
    assert_eq!(unavailable["error"], AI_SUBSCRIPTIONS_UNAVAILABLE);
}

#[test]
fn mcp_servers_are_listed_changed_and_signed_in_to_per_list() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let id = "0192f0a0-0000-7000-8000-000000000001";

    h.responses.push_back((200, json!({"servers":[]})));
    let listed = call(&mut c, &mut h, "mcp_servers", json!({}));
    assert_eq!(listed["data"], json!({"servers":[]}));
    assert_eq!(
        h.actions.last().unwrap()["url"],
        "https://one.test/api/me/mcp-servers"
    );

    h.responses.push_back((
        422,
        json!({"code":"invalid_url","message":"Enter the server's HTTPS URL."}),
    ));
    let refused = call(
        &mut c,
        &mut h,
        "add_mcp_server",
        json!({"url":"http://x","account_handle":"team"}),
    );
    assert_eq!(refused["error"], "Enter the server's HTTPS URL.");
    assert_eq!(
        h.actions.last().unwrap()["url"],
        "https://one.test/api/accounts/team/mcp-servers"
    );

    h.responses.push_back((403, json!({"code":"forbidden"})));
    let members = call(
        &mut c,
        &mut h,
        "remove_mcp_server",
        json!({"id":id,"account_handle":"team"}),
    );
    assert_eq!(members["error"], ADMINS_ONLY);

    // Handles and IDs never reach the URL unchecked.
    let requests = h.actions.len();
    for args in [json!({"account_handle":"../x"}), json!({"id":"../x"})] {
        let op = if args.get("id").is_some() {
            "remove_mcp_server"
        } else {
            "mcp_servers"
        };
        assert!(call(&mut c, &mut h, op, args)["error"].is_string());
    }
    assert_eq!(h.actions.len(), requests);

    // Nothing started: a callback completes nothing.
    let stray = call(
        &mut c,
        &mut h,
        "complete_mcp_server",
        json!({"url":"luft://mcp-callback?state=s&code=c"}),
    );
    assert!(stray["error"].is_string());
    assert_eq!(h.actions.len(), requests);

    h.responses
        .push_back((200, json!({"url":"https://auth.example/authorize?state=s"})));
    let started = call(
        &mut c,
        &mut h,
        "authorize_mcp_server",
        json!({"id":id,"account_handle":"team"}),
    );
    assert_eq!(
        started["data"],
        json!({"url":"https://auth.example/authorize?state=s","callback_scheme":"luft"})
    );
    assert_eq!(
        h.actions.last().unwrap()["url"],
        format!("https://one.test/api/accounts/team/mcp-servers/{id}/authorize")
    );

    // The core remembers the list: the callback goes to the organization's.
    h.responses
        .push_back((200, json!({"server":{"id":id,"connected":true}})));
    let completed = call(
        &mut c,
        &mut h,
        "complete_mcp_server",
        json!({"url":"luft://mcp-callback?state=s&code=c%26d&iss=https%3A%2F%2Fauth.example"}),
    );
    assert_eq!(completed["data"]["server"]["connected"], true);
    assert_eq!(
        h.actions.last().unwrap()["url"],
        "https://one.test/api/accounts/team/mcp-servers/complete"
    );
    assert_eq!(
        sent_body(&h),
        json!({"state":"s","code":"c&d","iss":"https://auth.example"})
    );

    // Used once.
    let requests = h.actions.len();
    let again = call(
        &mut c,
        &mut h,
        "complete_mcp_server",
        json!({"url":"luft://mcp-callback?state=s&code=c"}),
    );
    assert!(again["error"].is_string());

    // A refused sign-in says so without asking the server.
    h.responses
        .push_back((200, json!({"url":"https://auth.example/authorize"})));
    call(&mut c, &mut h, "authorize_mcp_server", json!({"id":id}));
    let denied = call(
        &mut c,
        &mut h,
        "complete_mcp_server",
        json!({"url":"luft://mcp-callback?state=s&error=access_denied"}),
    );
    assert_eq!(denied["error"], MCP_CANCELLED);
    assert_eq!(h.actions.len(), requests + 1);
}

#[test]
fn an_mcp_sign_in_survives_another_profiles_mcp_operations() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    let one = login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let two = login(&mut c, &mut h, "https://two.test", 2, i64::MAX);
    let id = "0192f0a0-0000-7000-8000-000000000001";

    call(&mut c, &mut h, "switch_profile", json!({"id":one}));
    h.responses
        .push_back((200, json!({"url":"https://auth.example/authorize?state=s"})));
    call(&mut c, &mut h, "authorize_mcp_server", json!({"id":id}));

    // The other profile can't complete it, and listing its servers keeps it.
    call(&mut c, &mut h, "switch_profile", json!({"id":two}));
    let elsewhere = call(
        &mut c,
        &mut h,
        "complete_mcp_server",
        json!({"url":"luft://mcp-callback?state=s&code=c"}),
    );
    assert!(elsewhere["error"].is_string());
    h.responses.push_back((200, json!({"servers":[]})));
    call(&mut c, &mut h, "mcp_servers", json!({}));

    call(&mut c, &mut h, "switch_profile", json!({"id":one}));
    h.responses
        .push_back((200, json!({"server":{"id":id,"connected":true}})));
    let completed = call(
        &mut c,
        &mut h,
        "complete_mcp_server",
        json!({"url":"luft://mcp-callback?state=s&code=c"}),
    );
    assert_eq!(
        completed["data"]["server"]["connected"], true,
        "{completed}"
    );
    assert_eq!(
        h.actions.last().unwrap()["url"],
        "https://one.test/api/me/mcp-servers/complete"
    );
}

#[test]
fn live_diffs_merge_into_the_store_and_queued_replies_stay_unsent_until_the_server_has_them() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    let message = |id: &str, position: u64, role: &str, content: &str| json!({"id":id,"position":position,"role":role,"content":content});
    let mut loaded = server_thread(json!([
        message("m1", 1, "assistant", "first"),
        message("m2", 2, "assistant", "second"),
    ]));
    loaded["revision"] = json!(2);
    loaded["has_more"] = json!(true);
    loaded["next_before"] = json!(1);
    h.responses.push_back((200, loaded.clone()));
    call(&mut c, &mut h, "thread", json!({"id":SERVER_ID}));

    // The socket resumes from the stored revision.
    let plan = call(
        &mut c,
        &mut h,
        "live_connect",
        json!({"id":SERVER_ID,"socket":"s"}),
    );
    let join: Value = serde_json::from_str(plan["data"]["join"].as_str().unwrap()).unwrap();
    assert_eq!(join[4]["sync"], true);
    assert_eq!(join[4]["since"], 2);

    h.offline = true;
    let queued = call(
        &mut c,
        &mut h,
        "send_message",
        json!({"id":SERVER_ID,"content":"Ship it"}),
    );
    let unsent = queued["data"]["messages"]
        .as_array()
        .unwrap()
        .last()
        .unwrap()
        .clone();
    assert_eq!(unsent["send_state"], "offline", "{queued}");
    h.offline = false;

    let receive = |c: &mut MobileClient, h: &mut Fake, event: &str, payload: Value| {
        let frame = json!(["1", "1", format!("threads:ana:{SERVER_ID}"), event, payload]);
        let out = call(
            c,
            h,
            "live_receive",
            json!({"socket":"s","id":SERVER_ID,"message":frame.to_string()}),
        );
        assert!(out.get("error").is_none(), "{out}");
        out["data"].clone()
    };
    let joined = receive(
        &mut c,
        &mut h,
        "phx_reply",
        json!({"status":"ok","response":{}}),
    );
    assert_eq!(joined["changed"], false, "{joined}");

    // An edit to a stored message, the queued reply as the server stored it,
    // and an edit to a message before the stored page.
    let mut reply = message("m3", 4, "user", "Ship it");
    reply["request_id"] = unsent["id"].clone();
    let diff = json!({"reset":false,"cursor":4,"thread":{
        "id":SERVER_ID,"status":"running","archive_status":"active","revision":4,
        "messages":[message("m0", 0, "assistant", "older"), message("m1", 1, "assistant", "edited"), reply]
    }});
    let out = receive(&mut c, &mut h, "diff", diff.clone());
    assert_eq!(out["changed"], true, "{out}");
    assert!(out.get("diff").is_none());

    let cached = call(&mut c, &mut h, "cached_thread", json!({"id":SERVER_ID}))["data"].clone();
    let contents: Vec<_> = cached["messages"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| m["content"].clone())
        .collect();
    assert_eq!(
        contents,
        [json!("edited"), json!("second"), json!("Ship it")],
        "{cached}"
    );
    assert!(cached["messages"][2].get("send_state").is_none());
    assert_eq!(cached["freshness"]["state"], "live");
    assert_eq!(cached["working"], true);
    assert_eq!(cached["has_more"], true);
    assert_eq!(cached["next_before"], 1);

    // A repeated diff and a slower load of an older revision change nothing.
    assert_eq!(receive(&mut c, &mut h, "diff", diff)["changed"], false);
    h.responses.push_back((200, loaded));
    let load = call(&mut c, &mut h, "thread", json!({"id":SERVER_ID}));
    assert_eq!(load["data"]["messages"][0]["content"], "edited", "{load}");

    let plan = call(
        &mut c,
        &mut h,
        "live_connect",
        json!({"id":SERVER_ID,"socket":"s"}),
    );
    let join: Value = serde_json::from_str(plan["data"]["join"].as_str().unwrap()).unwrap();
    assert_eq!(join[4]["since"], 4);

    // A delta the store can't apply (the conversation was dropped since the
    // join) reconnects, and the next join asks for the latest page.
    let directory = h.directory.clone().unwrap();
    let file = std::fs::read_dir(&directory)
        .unwrap()
        .map(|e| e.unwrap().path())
        .find(|p| p.extension().is_some_and(|e| e == "sqlite3"))
        .unwrap();
    rusqlite::Connection::open(file)
        .unwrap()
        .execute("DELETE FROM conversations WHERE id = ?1", [SERVER_ID])
        .unwrap();
    let out = receive(
        &mut c,
        &mut h,
        "diff",
        json!({"reset":false,"cursor":5,"thread":{"id":SERVER_ID,"messages":[]}}),
    );
    assert_eq!(
        (out["changed"].clone(), out["reconnect"].clone()),
        (json!(false), json!(true))
    );
    let plan = call(
        &mut c,
        &mut h,
        "live_connect",
        json!({"id":SERVER_ID,"socket":"s"}),
    );
    let join: Value = serde_json::from_str(plan["data"]["join"].as_str().unwrap()).unwrap();
    assert_eq!(join[4]["since"], Value::Null);
}

#[test]
fn live_refreshes_reach_the_edge_while_refresh_tokens_stay_scrubbed() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    call(
        &mut c,
        &mut h,
        "live_connect",
        json!({"id":"inbox","socket":"i"}),
    );
    let frame = json!([null, null, "threads:ana:inbox", "snapshot", {"revision": 7}]);
    let out = call(
        &mut c,
        &mut h,
        "live_receive",
        json!({"socket":"i","id":"inbox","message":frame.to_string()}),
    );
    assert_eq!(out["data"]["refresh"], true, "{out}");
    let profile = &out["view"]["profiles"][0];
    assert!(profile.is_object(), "{out}");
    assert!(profile.get("refresh").is_none() && profile.get("access").is_none());
    assert!(!out.to_string().contains("refresh-1"));
}
