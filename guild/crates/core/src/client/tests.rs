use super::*;
use crate::THREADS_UNAVAILABLE;
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use std::collections::VecDeque;

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
                    let path = std::env::temp_dir()
                        .join(format!("guild-store-{}-{n}", std::process::id()));
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
            _ => panic!("unexpected host action"),
        }
    }
}
fn token(exp: i64, user: u64) -> String {
    format!(
        "header.{}.sig",
        URL_SAFE_NO_PAD.encode(
            json!({"exp":exp,"sub":"account-1","user_id":user,
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
    let registration = endpoint(&server_url(server).unwrap(), "oauth2/register").to_string();
    h.responses.extend([
        (200, json!({"registration_endpoint":registration})),
        (201, json!({"client_id":"issued-client"})),
    ]);
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
    assert_eq!(h.actions.last().unwrap()["url"], registration);
    url.query_pairs()
        .find(|(k, _)| k == "state")
        .unwrap()
        .1
        .to_string()
}
#[test]
fn sign_in_requests_the_threads_scope_only_where_the_server_advertises_it() {
    let scope = |advertised: Value| {
        let (mut c, mut h) = (MobileClient::new(), Fake::default());
        let registration = "https://one.test/oauth2/register";
        h.responses.extend([
            (
                200,
                json!({"registration_endpoint":registration,"scopes_supported":advertised}),
            ),
            (201, json!({"client_id":"issued-client"})),
        ]);
        let result = call(
            &mut c,
            &mut h,
            "begin_sign_in",
            json!({"server":"https://one.test"}),
        );
        let url = Url::parse(result["data"]["url"].as_str().unwrap()).unwrap();
        url.query_pairs()
            .find(|(k, _)| k == "scope")
            .map(|(_, v)| v.to_string())
    };
    assert_eq!(scope(json!(["mcp", "threads"])), Some("threads".into()));
    // Older servers would reject an unknown scope and with it the sign-in.
    assert_eq!(scope(json!(["mcp"])), None);
    assert_eq!(scope(Value::Null), None);
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
            .contains("client_id=issued-client")
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
    // Members who aren't admins of "team" are told why, not shown an error.
    let forbidden = call(&mut c, &mut h, "threads", json!({}));
    assert!(forbidden.get("error").is_none(), "{forbidden}");
    assert_eq!(forbidden["data"]["reason"], "forbidden");
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
fn unsafe_servers_and_cross_origin_registration_fail_without_exchange() {
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
    h.responses.push_back((
        200,
        json!({"registration_endpoint":"https://evil.test/register"}),
    ));
    assert!(
        call(
            &mut c,
            &mut h,
            "begin_sign_in",
            json!({"server":"https://one.test"})
        )["error"]
            .is_string()
    );
    assert!(h.responses.is_empty());
    assert!(c.attempt.is_none());
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
        "url":format!("https://tuist.dev/tuist/guild/previews/{id}"),
        "device_url":format!("itms-services://?action=download-manifest&url=https%3A%2F%2Ftuist.dev%2F{id}"),
        "builds":[{"type":kind, "supported_platforms":[platform], "binary_id":binary_id,
            "url":format!("https://storage.test/{id}")}]})
}

#[test]
fn preview_updates_compare_the_newest_identified_build_on_tuist_dev() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://tuist.dev", 1, i64::MAX);
    // The selected profile is self-hosted; Guild's previews still come from tuist.dev.
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
    let request = h.actions.last().unwrap();
    assert_eq!(
        request["url"],
        "https://tuist.dev/api/projects/tuist/guild/previews?track=internal&supported_platforms=android&page=1&page_size=20"
    );
    assert_eq!(
        request["headers"]["Authorization"],
        format!("Bearer {}", token(i64::MAX, 1))
    );

    // Running the newest identified build, even with different hex case, is current.
    h.responses.push_back((200, page.clone()));
    let current = call(
        &mut c,
        &mut h,
        "preview_update",
        json!({"platform":"android","binary_id":"ABC123"}),
    );
    assert_eq!(current["data"], json!({"update":null}));

    // iOS installs through the preview's over-the-air manifest.
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

    // Without access to the project there is nothing to install, and nothing to report.
    h.responses.push_back((403, json!({})));
    let denied = call(
        &mut c,
        &mut h,
        "preview_update",
        json!({"platform":"android","binary_id":"def456"}),
    );
    assert!(denied.get("error").is_none(), "{denied}");
    assert_eq!(denied["data"], json!({"update":null}));
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
        json!({"url":format!("https://one.test/guild{path}")}),
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
        json!({"url":"https://two.test/guild/profile"}),
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
        json!({"url":"tuist-guild://app/profile"}),
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
        json!({"url":"https://one.test/guild/profile"}),
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
fn guild_route_catalog_roundtrips_and_rejects_ambiguous_urls() {
    use crate::navigation::{Destination, Link};
    let server = Url::parse("https://one.test/base/").unwrap();
    for (path, destination) in [
        ("/profile", Destination::Profile),
        ("/threads", Destination::Threads),
        (
            "/threads/12345678-1234-5678-9abc-123456789abc",
            Destination::Thread("12345678-1234-5678-9abc-123456789abc".into()),
        ),
    ] {
        for value in [
            path.to_owned(),
            format!("https://one.test/base/guild{path}"),
            format!("tuist-guild://app{path}?server=https%3A%2F%2Fone.test%2Fbase"),
        ] {
            let route = Link::parse(&value).unwrap().resolve(&server).unwrap();
            assert_eq!(route, destination);
            assert_eq!(route.path(), path);
        }
    }
    for value in [
        "/threads/invalid",
        "/threads/------------------------------------",
        "/threads/",
        "/profile?",
        "/profile#fragment",
        "//profile",
        "tuist-guild://oauth-callback?code=secret",
        "tuist-guild://user@app/profile",
        "tuist-guild://app:123/profile",
        "tuist-guild://app/profile?unknown=1",
        "tuist-guild://app/profile?server=https://one.test&server=https://one.test",
        "tuist-guild://app/a/../profile",
        "tuist-guild://app/%70rofile",
        "tuist-guild://app/profile#",
        "https://one.test/base/guild/../guild/profile",
        "http://one.test/guild/profile",
        "https://one.test/base/guild/profile?token=secret",
        "https://one.test/base/guild/threads/not-an-id",
    ] {
        assert!(Link::parse(value).is_err(), "{value}");
    }
    for value in [
        "https://one.test/guild/profile",
        "https://one.test/base-other/guild/profile",
        "https://one.test:8443/base/guild/profile",
        "https://two.test/base/guild/profile",
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
    // Relaunched, still offline: the store is on disk, not in memory.
    let mut c = MobileClient::new();
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
    let mut c = MobileClient::new();
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
    assert_eq!(refused["data"]["reason"], "forbidden");
    let cached = call(&mut c, &mut h, "cached_threads", json!({}));
    assert_eq!(cached["data"]["threads"][0]["title"], "Release plan");
}
