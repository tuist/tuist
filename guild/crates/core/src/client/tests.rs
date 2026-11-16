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
}
impl Host for Fake {
    fn perform(&mut self, action: Value) -> std::result::Result<Value, String> {
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
                Ok(json!({"status":status,"body":body.to_string()}))
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
        "type":"account","email":"ana@example.com","preferred_username":"ana"})
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
fn unchanged_memberships_do_not_reset_native_navigation() {
    let (mut c, mut h) = (MobileClient::new(), Fake::default());
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX);
    h.responses.extend([
        (200, json!({"organizations":[{"name":"team"}]})),
        (200, json!({"organizations":[{"name":"team"}]})),
    ]);
    let before = call(&mut c, &mut h, "organizations", json!({}));
    let after = call(&mut c, &mut h, "organizations", json!({}));
    assert_eq!(before["view"], after["view"]);
    assert!(after.get("error").is_none());
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
    assert_eq!(
        call(&mut restored, &mut h, "snapshot", json!({}))["view"],
        result["view"]
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
    // Threads stay on the personal account while the organization "team" is selected.
    assert_eq!(
        h.actions.last().unwrap()["url"],
        "https://one.test/api/accounts/ana/threads"
    );
    let count = h.actions.len();
    assert!(call(&mut c, &mut h, "threads", json!({"cursor":""}))["error"].is_string());
    assert_eq!(h.actions.len(), count);
    let repeated = call(&mut c, &mut h, "threads", json!({"cursor":"c+/="}));
    assert_eq!(repeated["data"]["next_cursor"], Value::Null);
    assert_eq!(
        h.actions.last().unwrap()["url"],
        "https://one.test/api/accounts/ana/threads?cursor=c%2B%2F%3D"
    );
    assert!(call(&mut c, &mut h, "threads", json!({}))["error"].is_string());
    let unavailable = call(&mut c, &mut h, "threads", json!({}));
    assert!(unavailable.get("error").is_none(), "{unavailable}");
    assert_eq!(unavailable["data"]["available"], false);
    assert!(call(&mut c, &mut h, "threads", json!({}))["error"].is_string());
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
