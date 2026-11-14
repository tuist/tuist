use super::*;
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use std::collections::{BTreeMap, VecDeque};
use std::sync::{Arc, Mutex};

#[derive(Default)]
struct Fake {
    vault: Option<String>,
    actions: Vec<Value>,
    responses: VecDeque<(u64, Value)>,
    fail_write: bool,
    /// The Tuist app's Keychain items, by storage key.
    shared: Arc<Mutex<BTreeMap<String, Value>>>,
    fail_shared_write: bool,
    /// A Tuist app without the shared lock rotating the pair while a refresh is in flight.
    rotate_during_refresh: Option<Value>,
}
impl Host for Fake {
    fn perform(&mut self, action: Value) -> std::result::Result<Value, String> {
        self.actions.push(action.clone());
        let mut shared = self.shared.lock().unwrap();
        let server = action["server"].as_str().unwrap_or_default();
        match action["type"].as_str().unwrap() {
            "read" => Ok(json!({"value":self.vault})),
            "write" if self.fail_write => Ok(json!({"error":"sensitive host failure"})),
            "write" => {
                self.vault = Some(action["value"].as_str().unwrap().into());
                Ok(json!({"ok":true}))
            }
            "shared_list" => Ok(json!({"servers":shared.keys().collect::<Vec<_>>()})),
            "shared_read" => Ok(json!({"value":shared.get(server)})),
            "shared_write" if self.fail_shared_write => Ok(json!({"error":"keychain failure"})),
            "shared_write" => {
                let item = shared
                    .get_mut(server)
                    .expect("only existing items are updated");
                item["access_token"] = action["access_token"].clone();
                item["refresh_token"] = action["refresh_token"].clone();
                Ok(json!({"ok":true}))
            }
            "http" => {
                if action["body"]
                    .as_str()
                    .is_some_and(|b| b.contains("grant_type=refresh_token"))
                    && let Some(rotated) = self.rotate_during_refresh.take()
                {
                    shared.insert("https://tuist.dev".into(), rotated);
                }
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

#[cfg(target_os = "macos")]
mod tuist_app_session {
    use super::*;
    use std::time::Duration;
    use tuist_credentials::RefreshLock;

    const KEY: &str = "https://tuist.dev";

    fn setup(name: &str) -> (MobileClient, Fake) {
        let state = std::env::temp_dir().join(format!("tuist-code-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&state);
        let mut c = MobileClient::new();
        c.state = Some(state);
        (c, Fake::default())
    }
    fn refresh_token(n: u64) -> String {
        format!(
            "header.{}.sig",
            URL_SAFE_NO_PAD.encode(json!({"exp":i64::MAX,"type":"account","jti":n}).to_string())
        )
    }
    fn session(access: String, refresh: &str) -> Value {
        json!({"access_token":access,"refresh_token":refresh,"oauth_client_id":"app-client","rejected":false})
    }
    fn token_requests(h: &Fake) -> Vec<&Value> {
        h.actions
            .iter()
            .filter(|a| a["url"] == "https://tuist.dev/oauth2/token")
            .collect()
    }

    #[test]
    fn the_session_is_listed_refreshed_under_its_lock_and_never_stored() {
        let (mut c, mut h) = setup("refresh");
        let spent = refresh_token(1);
        h.shared
            .lock()
            .unwrap()
            .insert(KEY.into(), session(token(1, 1), &spent));
        let view = call(&mut c, &mut h, "snapshot", json!({}))["view"].clone();
        assert_eq!(view["profiles"][0]["shared"], true);
        assert_eq!(view["profiles"][0]["server"], "https://tuist.dev/");
        assert_eq!(view["active_profile_id"], view["profiles"][0]["id"]);

        let rotated = refresh_token(2);
        h.responses.extend([
            (
                200,
                json!({"access_token":token(i64::MAX,1),"refresh_token":rotated}),
            ),
            (200, json!({"projects":[]})),
        ]);
        let result = call(&mut c, &mut h, "projects", json!({}));
        assert!(result.get("error").is_none(), "{result}");
        let body = token_requests(&h)[0]["body"].as_str().unwrap().to_string();
        assert!(
            body.contains(&format!("refresh_token={spent}"))
                && body.contains("client_id=app-client")
        );
        assert_eq!(h.shared.lock().unwrap()[KEY]["refresh_token"], rotated);
        // The lock the Tuist app takes for https://tuist.dev.
        let lock = c
            .state
            .as_ref()
            .unwrap()
            .join("cached_value_store/credential-refresh-d79fb54a63e03cb2.lock");
        assert!(lock.exists());
        let vault = h.vault.clone().unwrap();
        assert!(
            !vault.contains(&spent) && !vault.contains(&rotated) && !vault.contains("app-client")
        );

        let mut restarted = MobileClient::new();
        restarted.state = c.state.clone();
        assert_eq!(
            call(&mut restarted, &mut h, "snapshot", json!({}))["view"],
            view
        );
    }

    #[test]
    fn a_rotation_by_the_lock_holder_is_used_without_another_refresh() {
        let (mut c, mut h) = setup("waiting");
        h.shared
            .lock()
            .unwrap()
            .insert(KEY.into(), session(token(1, 1), &refresh_token(1)));
        call(&mut c, &mut h, "snapshot", json!({}));
        let held = RefreshLock::acquire(&RefreshLock::path_for_key(c.state.as_ref().unwrap(), KEY))
            .unwrap();
        let shared = h.shared.clone();
        let peer = std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(300));
            shared
                .lock()
                .unwrap()
                .insert(KEY.into(), session(token(i64::MAX, 1), &refresh_token(2)));
            drop(held);
        });
        h.responses.push_back((200, json!({"projects":[]})));
        let result = call(&mut c, &mut h, "projects", json!({}));
        peer.join().unwrap();
        assert!(result.get("error").is_none(), "{result}");
        assert!(token_requests(&h).is_empty());
        let projects = h
            .actions
            .iter()
            .find(|a| {
                a["url"]
                    .as_str()
                    .is_some_and(|u| u.contains("api/projects"))
            })
            .unwrap();
        assert_eq!(
            projects["headers"]["Authorization"],
            format!("Bearer {}", token(i64::MAX, 1))
        );
    }

    #[test]
    fn a_rejected_refresh_rejects_only_here_unless_an_unlocked_peer_rotated() {
        for peer_rotates in [false, true] {
            let (mut c, mut h) = setup(&format!("rejected-{peer_rotates}"));
            h.shared
                .lock()
                .unwrap()
                .insert(KEY.into(), session(token(1, 1), &refresh_token(1)));
            call(&mut c, &mut h, "snapshot", json!({}));
            let peer = session(token(i64::MAX, 1), &refresh_token(2));
            if peer_rotates {
                h.rotate_during_refresh = Some(peer.clone());
                h.responses
                    .push_back((400, json!({"error":"invalid_grant"})));
                h.responses.push_back((200, json!({"projects":[]})));
            } else {
                h.responses
                    .push_back((400, json!({"error":"invalid_grant"})));
            }
            let result = call(&mut c, &mut h, "projects", json!({}));
            assert_eq!(result.get("error").is_none(), peer_rotates, "{result}");
            assert_eq!(c.vault.profiles[0].rejected, !peer_rotates);
            assert!(!h.actions.iter().any(|a| a["type"] == "shared_write"));
            let stored = h.shared.lock().unwrap()[KEY].clone();
            assert_eq!(stored["rejected"], false);
            if peer_rotates {
                assert_eq!(stored, peer);
            }
        }
    }

    #[test]
    fn signing_out_unlinks_the_session_and_leaves_the_tuist_app_signed_in() {
        let (mut c, mut h) = setup("sign-out");
        let app = session(token(i64::MAX, 1), &refresh_token(1));
        h.shared.lock().unwrap().insert(KEY.into(), app.clone());
        call(&mut c, &mut h, "snapshot", json!({}));
        let result = call(&mut c, &mut h, "sign_out", json!({}));
        assert_eq!(result["view"]["profiles"], json!([]));
        assert_eq!(
            call(&mut c, &mut h, "snapshot", json!({}))["view"]["profiles"],
            json!([])
        );
        assert_eq!(h.shared.lock().unwrap()[KEY], app);
        assert!(!h.actions.iter().any(|a| a["type"] == "shared_write"));

        // A different user signing in to the Tuist app is offered again.
        h.shared
            .lock()
            .unwrap()
            .insert(KEY.into(), session(token(i64::MAX, 2), &refresh_token(3)));
        let view = call(&mut c, &mut h, "snapshot", json!({}))["view"].clone();
        assert_eq!(view["profiles"].as_array().unwrap().len(), 1);
        assert_eq!(view["profiles"][0]["shared"], true);
    }

    #[test]
    fn a_failed_keychain_update_is_retried_before_any_other_request() {
        let (mut c, mut h) = setup("retry");
        h.shared
            .lock()
            .unwrap()
            .insert(KEY.into(), session(token(1, 1), &refresh_token(1)));
        call(&mut c, &mut h, "snapshot", json!({}));
        let rotated = refresh_token(2);
        h.responses.push_back((
            200,
            json!({"access_token":token(i64::MAX,1),"refresh_token":rotated}),
        ));
        h.fail_shared_write = true;
        assert!(call(&mut c, &mut h, "projects", json!({}))["error"].is_string());
        h.fail_shared_write = false;
        h.responses.push_back((200, json!({"projects":[]})));
        let result = call(&mut c, &mut h, "projects", json!({}));
        assert!(result.get("error").is_none(), "{result}");
        assert_eq!(h.shared.lock().unwrap()[KEY]["refresh_token"], rotated);
        assert_eq!(token_requests(&h).len(), 1);
        let write = h
            .actions
            .iter()
            .rposition(|a| a["type"] == "shared_write")
            .unwrap();
        let get = h.actions.iter().rposition(|a| a["type"] == "http").unwrap();
        assert!(write < get);
    }
}
