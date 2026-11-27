use super::*;

fn setup() -> (MobileClient, Fake, Value) {
    let (mut client, mut host) = (MobileClient::new(), Fake::default());
    login(&mut client, &mut host, "https://one.test", 1, i64::MAX);
    let generation =
        call(&mut client, &mut host, "snapshot", json!({}))["view"]["generation"].clone();
    (
        client,
        host,
        json!({"generation":generation,"surface":"44444444-4444-4444-8444-444444444444","hash":"candidate-1"}),
    )
}

fn detail() -> Value {
    json!({"hash":"candidate-1","baseline":"baseline-1","title":"Support changes","author":2,
        "reviewer":null,"active_at":null,"created_at":"2026-11-26T12:00:00.000Z",
        "state":"proposed","compatible":true,"can_approve":true,"can_activate":false,"blockers":[],
        "definition":{"source":"new JS\nexact source","schema":{"type":"string"}},
        "baseline_definition":{"source":"old JS","schema":{"type":"string"}},
        "changes":[{"path":"/source","kind":"changed","before":"old JS","after":"new JS\nexact source"}]})
}
fn list(row: Value) -> Value {
    json!({"active":"baseline-1","releases":[row]})
}
fn approved() -> Value {
    let mut value = detail();
    value["state"] = json!("approved");
    value["reviewer"] = json!(1);
    value["can_approve"] = json!(false);
    value["can_merge"] = json!(true);
    value["merge_blockers"] = json!([]);
    value
}
fn merged() -> Value {
    let mut value = approved();
    value["state"] = json!("merged");
    value["can_merge"] = json!(false);
    value["can_activate"] = json!(true);
    value
}

#[test]
fn releases_merge_requires_explicit_server_authority_and_clear_merge_blockers() {
    for state in [
        "approved",
        "merging",
        "merged",
        "merge_conflict",
        "proposed",
        "active",
        "superseded",
        "stale",
    ] {
        let (mut c, mut h, args) = setup();
        let mut value = approved();
        value["state"] = json!(state);
        let result = open(&mut c, &mut h, &args, value);
        assert!(result["data"]["error"].is_null(), "{result}");
        assert_eq!(
            result["data"]["surface"]["detail"]["actions"],
            if matches!(state, "approved" | "merging") {
                json!(["merge"])
            } else {
                json!([])
            }
        );
    }
    for (key, value) in [
        ("can_merge", json!(false)),
        ("merge_blockers", json!(["Main moved."])),
    ] {
        let (mut c, mut h, args) = setup();
        let mut candidate = approved();
        candidate[key] = value;
        let result = open(&mut c, &mut h, &args, candidate);
        assert_eq!(result["data"]["surface"]["detail"]["actions"], json!([]));
        let count = h.actions.len();
        assert!(call(&mut c, &mut h, "release_merge", args)["data"]["error"].is_string());
        assert_eq!(h.actions.len(), count);
    }
    // Older fixtures are readable, but missing fields never grant merge authority.
    for missing in ["can_merge", "merge_blockers"] {
        let (mut c, mut h, args) = setup();
        let mut value = approved();
        value.as_object_mut().unwrap().remove(missing);
        let result = open(&mut c, &mut h, &args, value);
        assert!(result["data"]["error"].is_null());
        assert_eq!(result["data"]["surface"]["detail"]["actions"], json!([]));
    }
}

#[test]
fn release_merge_uncertain_outcomes_require_fresh_review_and_never_replay() {
    for status in [200, 401, 403, 409, 500] {
        let (mut c, mut h, args) = setup();
        open(&mut c, &mut h, &args, approved());
        h.responses
            .push_back((status, json!({"hash":"candidate-1"})));
        if status == 200 {
            // Even a committed merge followed by a failed reload consumes authority.
            h.responses.push_back((500, json!({})));
        }
        let result = call(&mut c, &mut h, "release_merge", args.clone());
        assert!(result["data"]["error"].is_string());
        assert!(result["data"]["surface"]["detail"].is_null());
        let count = h.actions.len();
        call(&mut c, &mut h, "release_merge", args);
        assert_eq!(h.actions.len(), count);
    }
    let (mut c, mut h, args) = setup();
    let mut value = approved();
    value["state"] = json!("merging");
    open(&mut c, &mut h, &args, value);
    h.offline = true;
    assert!(
        call(&mut c, &mut h, "release_merge", args.clone())["data"]["surface"]["detail"].is_null()
    );
    h.offline = false;
    let count = h.actions.len();
    call(&mut c, &mut h, "release_merge", args);
    assert_eq!(h.actions.len(), count);
}

fn open(c: &mut MobileClient, h: &mut Fake, args: &Value, value: Value) -> Value {
    h.responses.push_back((200, value));
    call(c, h, "release_open", args.clone())
}

#[test]
fn releases_review_exact_definition_and_separate_actions_reload_both_resources() {
    let (mut c, mut h, args) = setup();
    h.responses.push_back((200, list(detail())));
    let rows = call(&mut c, &mut h, "releases", args.clone());
    assert_eq!(
        rows["data"]["surface"]["list"]["releases"][0]["hash"],
        "candidate-1"
    );
    let request = h.actions.last().unwrap();
    assert_eq!(request["url"], "https://one.test/api/accounts/ana/releases");
    assert!(
        request["headers"]["Authorization"]
            .as_str()
            .unwrap()
            .starts_with("Bearer ")
    );
    let result = open(&mut c, &mut h, &args, detail());
    let view = &result["data"]["surface"]["detail"];
    assert_eq!(view["actions"], json!(["approve"]));
    assert_eq!(view["changes"], detail()["changes"]);
    assert_eq!(
        serde_json::from_str::<Value>(view["definition_text"].as_str().unwrap()).unwrap(),
        detail()["definition"]
    );
    for (op, value) in [
        ("release_approve", approved()),
        ("release_merge", merged()),
        ("release_activate", {
            let mut v = merged();
            v["state"] = json!("active");
            v["active_at"] = json!("2026-11-26T12:00:01Z");
            v["can_activate"] = json!(false);
            v
        }),
    ] {
        h.responses.extend([
            (200, json!({"hash":"candidate-1"})),
            (200, list(value.clone())),
            (200, value.clone()),
        ]);
        let start = h.actions.len();
        let result = call(&mut c, &mut h, op, args.clone());
        assert!(result["data"]["error"].is_null(), "{result}");
        assert_eq!(result["data"]["surface"]["detail"]["state"], value["state"]);
        let requests: Vec<_> = h.actions[start..]
            .iter()
            .filter(|a| a["type"] == "http")
            .collect();
        assert_eq!(requests.len(), 3);
        assert_eq!(requests[0]["method"], "POST");
        assert_eq!(requests[0]["body"], "{}");
        assert_eq!(
            requests[0]["url"],
            format!(
                "https://one.test/api/accounts/ana/releases/candidate-1/{}",
                op.strip_prefix("release_").unwrap()
            )
        );
        assert_eq!(
            requests[1]["url"],
            "https://one.test/api/accounts/ana/releases"
        );
        assert_eq!(
            requests[2]["url"],
            "https://one.test/api/accounts/ana/releases/candidate-1"
        );
    }
}

#[test]
fn releases_never_offer_self_approval_or_ineligible_activation() {
    for (key, value) in [
        ("author", json!(1)),
        ("can_approve", json!(false)),
        ("state", json!("stale")),
    ] {
        let (mut c, mut h, args) = setup();
        let mut v = detail();
        v[key] = value;
        assert_eq!(
            open(&mut c, &mut h, &args, v)["data"]["surface"]["detail"]["actions"],
            json!([])
        );
        let count = h.actions.len();
        assert!(call(&mut c, &mut h, "release_approve", args)["data"]["error"].is_string());
        assert_eq!(h.actions.len(), count);
    }
    for (key, value) in [
        ("can_activate", json!(false)),
        ("compatible", json!(false)),
        ("state", json!("approved")),
        ("state", json!("merging")),
        ("state", json!("merge_conflict")),
        ("state", json!("stale")),
        ("state", json!("superseded")),
        ("active_at", json!("2026-11-26T12:00:00Z")),
        ("blockers", json!(["The active baseline changed."])),
    ] {
        let (mut c, mut h, args) = setup();
        let mut v = merged();
        v[key] = value;
        assert_eq!(
            open(&mut c, &mut h, &args, v)["data"]["surface"]["detail"]["actions"],
            json!([])
        );
        let count = h.actions.len();
        call(&mut c, &mut h, "release_activate", args);
        assert_eq!(h.actions.len(), count);
    }
}

#[test]
fn releases_fail_closed_on_bad_data_failed_reads_and_uncertain_writes() {
    let mut bad_values = Vec::new();
    for (key, value) in [
        ("hash", json!("other")),
        ("definition", json!([])),
        ("created_at", json!("not a date")),
        ("can_approve", json!("true")),
        ("can_merge", json!("true")),
        ("merge_blockers", json!([false])),
        ("merge_blockers", json!(null)),
        ("changes", json!([])),
        ("baseline_definition", json!(false)),
    ] {
        let mut v = detail();
        v[key] = value;
        bad_values.push(v);
    }
    for (key, value) in [
        ("before", json!("forged")),
        ("after", json!("forged")),
        ("path", json!("/bad~pointer")),
        ("kind", json!("guessed")),
    ] {
        let mut v = detail();
        v["changes"][0][key] = value;
        bad_values.push(v);
    }
    for bad in bad_values {
        let (mut c, mut h, args) = setup();
        open(&mut c, &mut h, &args, detail());
        let result = open(&mut c, &mut h, &args, bad);
        assert!(result["data"]["error"].is_string(), "{result}");
        assert!(result["data"]["surface"]["detail"].is_null());
        let count = h.actions.len();
        call(&mut c, &mut h, "release_approve", args);
        assert_eq!(h.actions.len(), count);
    }
    for status in [401, 403, 404, 409, 500] {
        let (mut c, mut h, args) = setup();
        open(&mut c, &mut h, &args, detail());
        h.responses
            .push_back((status, json!({"error":"private server text"})));
        let result = call(&mut c, &mut h, "release_approve", args.clone());
        assert!(result["data"]["surface"]["detail"].is_null());
        assert!(!result.to_string().contains("private server text"));
        let count = h.actions.len();
        call(&mut c, &mut h, "release_approve", args);
        assert_eq!(h.actions.len(), count);
    }
    let (mut c, mut h, args) = setup();
    open(&mut c, &mut h, &args, detail());
    h.offline = true;
    assert!(
        call(&mut c, &mut h, "release_approve", args.clone())["data"]["surface"]["detail"]
            .is_null()
    );
    h.offline = false;
    let count = h.actions.len();
    call(&mut c, &mut h, "release_approve", args);
    assert_eq!(count, h.actions.len());
}

#[test]
fn releases_bind_actions_to_exact_hash_surface_generation_and_background() {
    for key in ["hash", "surface", "generation"] {
        let (mut c, mut h, args) = setup();
        open(&mut c, &mut h, &args, detail());
        let mut wrong = args.clone();
        wrong[key] = if key == "generation" {
            json!(999)
        } else if key == "hash" {
            json!("other")
        } else {
            json!("55555555-5555-4555-8555-555555555555")
        };
        let count = h.actions.len();
        let result = call(&mut c, &mut h, "release_approve", wrong);
        assert!(result["data"]["surface"]["detail"].is_null());
        call(&mut c, &mut h, "release_approve", args);
        assert_eq!(count, h.actions.len());
    }
    for op in [
        "presence_disconnect",
        "release_close",
        "select_organization",
    ] {
        let (mut c, mut h, args) = setup();
        open(&mut c, &mut h, &args, detail());
        let input = if op == "select_organization" {
            login(&mut c, &mut h, "https://two.test", 2, i64::MAX);
            json!({"id":c.vault.active_profile_id,"name":null})
        } else {
            args.clone()
        };
        call(&mut c, &mut h, op, input);
        let count = h.actions.len();
        call(&mut c, &mut h, "release_approve", args);
        assert_eq!(count, h.actions.len());
    }
}

#[test]
fn releases_validate_json_pointer_escapes_additions_removals_and_first_release() {
    let (mut c, mut h, args) = setup();
    let mut v = detail();
    v["baseline_definition"] = json!({"a/b":{"~key":null},"remove":true});
    v["definition"] = json!({"a/b":{"~key":"value"},"add":null});
    v["changes"] = json!([
        {"path":"/a~1b/~0key","kind":"changed","before":null,"after":"value"},
        {"path":"/remove","kind":"removed","before":true,"after":null},
        {"path":"/add","kind":"added","before":null,"after":null}]);
    assert!(open(&mut c, &mut h, &args, v)["data"]["error"].is_null());
    let mut v = detail();
    v["baseline"] = Value::Null;
    v["baseline_definition"] = Value::Null;
    v["changes"] = json!([{"path":"","kind":"added","before":null,"after":v["definition"]}]);
    assert!(open(&mut c, &mut h, &args, v)["data"]["error"].is_null());
}

#[test]
fn releases_failed_reload_after_committed_action_cannot_reuse_old_authority() {
    for failed_detail in [false, true] {
        let (mut c, mut h, args) = setup();
        open(&mut c, &mut h, &args, detail());
        h.responses.push_back((200, json!({"hash":"candidate-1"})));
        if failed_detail {
            h.responses.push_back((200, list(approved())));
        }
        h.responses.push_back((500, json!({})));
        let result = call(&mut c, &mut h, "release_approve", args.clone());
        assert!(result["data"]["error"].is_string());
        assert!(result["data"]["surface"]["detail"].is_null());
        let count = h.actions.len();
        call(&mut c, &mut h, "release_approve", args);
        assert_eq!(h.actions.len(), count);
    }
    for op in ["release_open", "releases"] {
        let (mut c, mut h, args) = setup();
        open(&mut c, &mut h, &args, detail());
        h.responses.push_back((403, json!({})));
        assert!(call(&mut c, &mut h, op, args.clone())["data"]["surface"]["detail"].is_null());
        let count = h.actions.len();
        call(&mut c, &mut h, "release_approve", args);
        assert_eq!(h.actions.len(), count);
    }
}

#[test]
fn releases_account_selection_scopes_transport_and_stale_close_does_not_clear_new_surface() {
    let (mut c, mut h, mut args) = setup();
    h.responses
        .push_back((200, json!({"organizations":[{"name":"team"}]})));
    call(&mut c, &mut h, "organizations", json!({}));
    args["generation"] = call(&mut c, &mut h, "snapshot", json!({}))["view"]["generation"].clone();
    open(&mut c, &mut h, &args, detail());
    let profile = c.vault.active_profile_id.clone().unwrap();
    let selected = call(
        &mut c,
        &mut h,
        "select_organization",
        json!({"id":profile,"name":"team"}),
    );
    assert!(selected.get("error").is_none(), "{selected}");
    let count = h.actions.len();
    call(&mut c, &mut h, "release_approve", args.clone());
    assert_eq!(h.actions.len(), count);
    args["generation"] = selected["view"]["generation"].clone();
    open(&mut c, &mut h, &args, detail());
    assert_eq!(
        h.actions.last().unwrap()["url"],
        "https://one.test/api/accounts/team/releases/candidate-1"
    );
    let mut stale = args.clone();
    stale["surface"] = json!("55555555-5555-4555-8555-555555555555");
    call(&mut c, &mut h, "release_close", stale);
    h.responses.extend([
        (200, json!({"hash":"candidate-1"})),
        (200, list(approved())),
        (200, approved()),
    ]);
    assert!(call(&mut c, &mut h, "release_approve", args)["data"]["error"].is_null());
}

#[test]
fn releases_preserve_readable_blockers_allow_incompatible_review_and_validate_dates() {
    let (mut c, mut h, args) = setup();
    let mut value = detail();
    value["compatible"] = json!(false);
    value["blockers"] = json!(["The runtime must be upgraded before activation."]);
    value["created_at"] = json!("2026-11-26T13:00:00+01:00");
    let result = open(&mut c, &mut h, &args, value);
    assert_eq!(
        result["data"]["surface"]["detail"]["actions"],
        json!(["approve"])
    );
    assert_eq!(
        result["data"]["surface"]["detail"]["blockers"],
        json!(["The runtime must be upgraded before activation."])
    );
    for date in [
        "2026-02-30T12:00:00Z",
        "2026-11-26T25:00:00Z",
        "2026-11-26T12:00:00.Z",
        "2026-11-26T12:00:00",
    ] {
        let mut value = detail();
        value["created_at"] = json!(date);
        assert!(open(&mut c, &mut h, &args, value)["data"]["error"].is_string());
    }
    let mut value = detail();
    value["definition"]["access_token"] = json!("must not be silently removed");
    let result = open(&mut c, &mut h, &args, value);
    assert!(result["data"]["surface"]["detail"].is_null());
    assert!(result["data"]["error"].is_string());
}

/// Desktop uses this transport directly: no mobile vault, host, or profile.
#[derive(Default)]
struct DesktopReleaseTransport {
    responses: std::collections::VecDeque<Result<(u64, Value)>>,
    requests: Vec<(String, String)>,
}
impl Transport for DesktopReleaseTransport {
    fn send(&mut self, method: &str, url: Url, _: Option<Value>) -> Result<(u64, Value)> {
        self.requests.push((method.into(), url.to_string()));
        self.responses
            .pop_front()
            .expect("unexpected desktop request")
    }
}

#[test]
fn desktop_release_reviews_share_validation_and_never_replay_uncertain_mutations() {
    let server = Url::parse("https://desktop.test").unwrap();
    let mut reviews = ReleaseReviews::default();
    let mut http = DesktopReleaseTransport::default();
    let args = json!({"hash":"candidate-1"});
    http.responses.push_back(Ok((200, detail())));
    let opened = reviews
        .call(
            &server,
            "team",
            "user:1",
            1,
            "desktop",
            "release_open",
            &args,
            &mut http,
            |_| true,
        )
        .unwrap();
    assert_eq!(opened["surface"]["detail"]["actions"], json!(["approve"]));
    assert_eq!(
        opened["surface"]["detail"]["review_changes"][0]["after"],
        json!("\"new JS\\nexact source\"")
    );
    http.responses.push_back(Err("Response lost after commit"));
    let uncertain = reviews
        .call(
            &server,
            "team",
            "user:1",
            1,
            "desktop",
            "release_approve",
            &args,
            &mut http,
            |_| true,
        )
        .unwrap();
    assert!(uncertain["surface"]["detail"].is_null());
    let requests = http.requests.len();
    let replay = reviews
        .call(
            &server,
            "team",
            "user:1",
            1,
            "desktop",
            "release_approve",
            &args,
            &mut http,
            |_| true,
        )
        .unwrap();
    assert!(replay["error"].is_string());
    assert_eq!(http.requests.len(), requests);
    assert_eq!(
        http.requests[1],
        (
            "POST".into(),
            "https://desktop.test/api/accounts/team/releases/candidate-1/approve".into()
        )
    );
}

#[test]
fn desktop_release_authority_is_bound_to_server_account_identity_and_surface() {
    let args = json!({"hash":"candidate-1"});
    for (server, account, identity, generation, surface) in [
        ("https://other.test", "team", "user:1", 1, "desktop"),
        ("https://desktop.test", "other", "user:1", 1, "desktop"),
        ("https://desktop.test", "team", "user:2", 1, "desktop"),
        ("https://desktop.test", "team", "user:1", 2, "desktop"),
        ("https://desktop.test", "team", "user:1", 1, "other"),
    ] {
        let mut reviews = ReleaseReviews::default();
        let mut http = DesktopReleaseTransport::default();
        http.responses.push_back(Ok((200, merged())));
        reviews
            .call(
                &Url::parse("https://desktop.test").unwrap(),
                "team",
                "user:1",
                1,
                "desktop",
                "release_open",
                &args,
                &mut http,
                |_| true,
            )
            .unwrap();
        let refused = reviews
            .call(
                &Url::parse(server).unwrap(),
                account,
                identity,
                generation,
                surface,
                "release_activate",
                &args,
                &mut http,
                |_| true,
            )
            .unwrap();
        assert!(refused["error"].is_string());
        assert!(refused["surface"]["detail"].is_null());
        assert_eq!(http.requests.len(), 1);
    }
}
