use super::*;

const ID: &str = "11111111-1111-4111-8111-111111111111";
const CUSTOMER: &str = "22222222-2222-4222-8222-222222222222";
const REQUEST: &str = "33333333-3333-4333-8333-333333333333";

fn descriptor() -> Value {
    json!({"id":"support.conversation","title":"Support","fields":[
        {"id":"subject","label":"Subject","type":"string"},
        {"id":"status","label":"Status","type":"enum","values":["open","closed"]},
        {"id":"customer","label":"Customer","type":"reference","target":"accounts.customer"}],
        "filters":["status"],"sort":["subject"],
        "methods":[{"id":"support.create","label":"New conversation","operation":"create",
            "input":{"type":"object","additionalProperties":false,"required":["subject","customer"],
                "properties":{"subject":{"type":"string","minLength":1,"maxLength":200},"customer":{"type":["string","null"],"maxLength":36}}}},
            {"id":"support.close","label":"Close conversation","operation":"close"}]})
}

fn row() -> Value {
    json!({"id":ID,"revision":1,"subject":"Upload","status":"open","customer":CUSTOMER})
}
fn entry() -> Value {
    json!({"release":"release-1","record":row(),"collection":descriptor()})
}

fn setup() -> (MobileClient, Fake, Value) {
    let (mut client, mut host) = (MobileClient::new(), Fake::default());
    login(&mut client, &mut host, "https://one.test", 1, i64::MAX);
    let generation = call(&mut client, &mut host, "boot", json!({}))["view"]["generation"].clone();
    let args = json!({"generation":generation,"surface":"44444444-4444-4444-8444-444444444444", "thread":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","message":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"});
    (client, host, args)
}

fn body(host: &Fake) -> Value {
    serde_json::from_str(
        host.actions
            .iter()
            .rev()
            .find(|a| a["type"] == "http")
            .unwrap()["body"]
            .as_str()
            .unwrap(),
    )
    .unwrap()
}

#[test]
fn native_message_resource_and_related_record_use_independent_authenticated_routes() {
    let (mut c, mut h, args) = setup();
    h.responses.push_back((200, entry()));
    let result = call(&mut c, &mut h, "native_record_open", args.clone());
    assert_eq!(result["data"]["surface"]["record"], row());
    assert_eq!(
        result["data"]["surface"]["fields"][2]["target"],
        "accounts.customer"
    );
    assert!(!result.to_string().contains("source"));
    let request = h.actions.last().unwrap();
    assert_eq!(
        request["url"],
        "https://one.test/api/accounts/ana/threads/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/resources/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    );
    assert!(
        request["headers"]["Authorization"]
            .as_str()
            .unwrap()
            .starts_with("Bearer ")
    );
    let related = json!({"generation":args["generation"],"surface":args["surface"],"collection":"accounts.customer","record":CUSTOMER});
    h.responses.push_back((200,json!({"release":"release-1","collection":{"id":"accounts.customer","title":"Customers","fields":[{"id":"name","label":"Name","type":"string"}],"methods":[]},"record":{"id":CUSTOMER,"revision":1,"name":"Harbor"}})));
    let result = call(&mut c, &mut h, "collection_open", related);
    assert_eq!(result["data"]["surface"]["record"]["name"], "Harbor");
    assert_eq!(
        h.actions.last().unwrap()["url"],
        format!(
            "https://one.test/api/accounts/ana/collections/accounts.customer/records/{CUSTOMER}"
        )
    );
}

#[test]
fn collections_query_validate_paginate_and_preserve_server_order() {
    let (mut c, mut h, mut args) = setup();
    args["collection"] = json!("support.conversation");
    let catalog = json!({"release":"release-1","collections":[descriptor()]});
    h.responses.push_back((200, catalog.clone()));
    assert_eq!(
        call(&mut c, &mut h, "collections", args.clone())["data"],
        catalog
    );
    h.responses.extend([
        (200, catalog),
        (200, json!({"items":[row()],"has_more":true})),
    ]);
    let result = call(&mut c, &mut h, "collection_open", args.clone());
    assert_eq!(result["data"]["surface"]["items"][0]["id"], ID);
    assert_eq!(
        result["data"]["surface"]["filter_fields"][0]["id"],
        "status"
    );
    assert_eq!(
        result["data"]["surface"]["filter_fields"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    assert_eq!(result["data"]["surface"]["sort_fields"][0]["id"], "subject");
    assert_eq!(body(&h), json!({"offset":0,"limit":20}));
    let mut query = args.clone();
    query["input"] = json!({"search":"upload","filters":{"status":"open"},"sort":"subject","direction":"desc","limit":1});
    h.responses
        .push_back((200, json!({"items":[row()],"has_more":true})));
    call(&mut c, &mut h, "collection_query", query.clone());
    assert_eq!(body(&h)["filters"], json!({"status":"open"}));
    query["input"] = json!({"next":true});
    let mut second = row();
    second["id"] = json!(CUSTOMER);
    h.responses
        .push_back((200, json!({"items":[second],"has_more":false})));
    let next = call(&mut c, &mut h, "collection_query", query.clone());
    assert_eq!(body(&h)["offset"], 1);
    assert_eq!(body(&h)["search"], "upload");
    assert_eq!(
        next["data"]["surface"]["items"].as_array().unwrap().len(),
        2
    );
    for input in [
        json!({"limit":51}),
        json!({"filters":{"status":"invalid"}}),
        json!({"sort":"secret"}),
        json!({"search":"x".repeat(201)}),
        json!({"next":true,"offset":0}),
    ] {
        query["input"] = input;
        let count = h.actions.len();
        let result = call(&mut c, &mut h, "collection_query", query.clone());
        assert!(result["data"]["error"].is_string(), "{result}");
        assert_eq!(count, h.actions.len());
    }
    call(&mut c, &mut h, "collection_close", args.clone());
    h.responses.extend([
        (
            200,
            json!({"release":"release-1","collections":[descriptor()]}),
        ),
        (200, json!({"items":[row()],"has_more":false})),
    ]);
    let reopened = call(&mut c, &mut h, "collection_open", args);
    assert_eq!(
        reopened["data"]["surface"]["items"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        body(&h),
        json!({"search":"upload","filters":{"status":"open"},"sort":"subject","direction":"desc","limit":1,"offset":0})
    );
}

#[test]
fn ambiguous_native_method_keeps_exact_identity_across_failed_reopens_and_revocation_clears_it() {
    let (mut c, mut h, args) = setup();
    h.responses.push_back((200, entry()));
    call(&mut c, &mut h, "native_record_open", args.clone());
    let mut action = args.clone();
    action["action"] = json!("support.close");
    action["request_id"] = json!(REQUEST);
    action["input"] = json!({"id":ID,"expected_revision":1,"values":{}});
    h.responses.push_back((0, Value::Null));
    let result = call(&mut c, &mut h, "native_record_action", action.clone());
    assert_eq!(result["data"]["surface"]["connected"], false);
    let sent = body(&h);
    assert_eq!(
        sent,
        json!({"request_id":REQUEST,"input":{"id":ID,"expected_revision":1}})
    );
    // Opening again may itself be offline, without forgetting the submission.
    h.responses.push_back((0, Value::Null));
    call(&mut c, &mut h, "native_record_open", args.clone());
    h.responses.push_back((200, entry()));
    assert_eq!(
        call(&mut c, &mut h, "native_record_open", args.clone())["data"]["surface"]["can_retry"],
        true
    );
    let count = h.actions.len();
    action["request_id"] = json!(CUSTOMER);
    assert!(call(&mut c, &mut h, "native_record_action", action)["data"]["error"].is_string());
    assert_eq!(count, h.actions.len());
    h.responses
        .push_back((500, json!({"error":{"code":"UNAVAILABLE"}})));
    assert_eq!(
        call(&mut c, &mut h, "native_record_retry", args.clone())["data"]["surface"]["can_retry"],
        true
    );
    assert_eq!(body(&h), sent);
    let mut saved = row();
    saved["revision"] = json!(2);
    saved["status"] = json!("closed");
    h.responses.push_back((200, saved.clone()));
    let result = call(&mut c, &mut h, "native_record_retry", args.clone());
    assert_eq!(body(&h), sent);
    assert_eq!(result["data"]["surface"]["can_retry"], false);
    assert_eq!(result["data"]["surface"]["record"], saved);
    let mut refresh = args.clone();
    refresh["id"] = json!(ID);
    h.responses
        .push_back((403, json!({"error":{"code":"FORBIDDEN"}})));
    let result = call(&mut c, &mut h, "native_record_refresh", refresh);
    assert_eq!(result["data"]["surface"], json!({"connected":false}));
    let count = h.actions.len();
    call(&mut c, &mut h, "native_record_retry", args);
    assert_eq!(count, h.actions.len());
}

#[test]
fn native_form_schema_and_historical_reads_are_validated_by_the_core() {
    let (mut c, mut h, args) = setup();
    h.responses.push_back((200, entry()));
    let opened = call(&mut c, &mut h, "native_record_open", args.clone());
    assert_eq!(
        opened["data"]["surface"]["actions"][0]["fields"]
            .as_array()
            .unwrap()
            .len(),
        2
    );
    let mut action = args.clone();
    action["action"] = json!("support.create");
    action["request_id"] = json!(REQUEST);
    action["input"] = json!({"values":{"subject":"","customer":""}});
    let count = h.actions.len();
    assert!(
        call(&mut c, &mut h, "native_record_action", action.clone())["data"]["error"].is_string()
    );
    assert_eq!(count, h.actions.len());
    action["input"] = json!({"values":{"subject":"Help","customer":""}});
    let mut saved = row();
    saved["customer"] = Value::Null;
    saved["subject"] = json!("Help");
    h.responses.push_back((200, saved));
    assert_eq!(
        call(&mut c, &mut h, "native_record_action", action.clone())["data"]["surface"]["can_retry"],
        false
    );
    assert_eq!(
        body(&h),
        json!({"request_id":REQUEST,"input":{"subject":"Help","customer":null}})
    );
    let mut historical = args.clone();
    historical["collection"] = json!("support.conversation");
    historical["record"] = json!(ID);
    historical["version"] = json!(1);
    h.responses.push_back((200, entry()));
    let history = call(&mut c, &mut h, "collection_open", historical.clone());
    assert_eq!(history["data"]["surface"]["actions"], json!([]));
    assert!(
        h.actions.last().unwrap()["url"]
            .as_str()
            .unwrap()
            .ends_with("?version=1")
    );
    historical["action"] = action["action"].clone();
    historical["request_id"] = action["request_id"].clone();
    historical["input"] = action["input"].clone();
    let count = h.actions.len();
    assert!(call(&mut c, &mut h, "collection_action", historical)["data"]["error"].is_string());
    assert_eq!(count, h.actions.len());
}

#[test]
fn native_resources_reject_generation_and_surface_switches_without_network_or_stale_data() {
    let (mut c, mut h, args) = setup();
    h.responses.push_back((200, entry()));
    call(&mut c, &mut h, "native_record_open", args.clone());
    let mut stale = args.clone();
    stale["surface"] = json!(CUSTOMER);
    let count = h.actions.len();
    let result = call(&mut c, &mut h, "native_record_retry", stale);
    assert!(result["error"].is_string());
    assert!(result["data"].is_null());
    assert_eq!(count, h.actions.len());
    login(&mut c, &mut h, "https://two.test", 2, i64::MAX);
    let count = h.actions.len();
    let result = call(&mut c, &mut h, "native_record_retry", args);
    assert!(result["error"].is_string());
    assert!(result["data"].is_null());
    assert_eq!(count, h.actions.len());
}

#[test]
fn native_pending_identity_survives_same_account_reauthentication_but_not_revocation() {
    let (mut c, mut h, mut args) = setup();
    h.responses.push_back((200, entry()));
    call(&mut c, &mut h, "native_record_open", args.clone());
    let mut action = args.clone();
    action["action"] = json!("support.close");
    action["request_id"] = json!(REQUEST);
    action["input"] = json!({"id":ID,"expected_revision":1,"values":{}});
    h.responses
        .push_back((500, json!({"error":{"code":"UNAVAILABLE"}})));
    call(&mut c, &mut h, "native_record_action", action.clone());
    let original = body(&h);
    login(&mut c, &mut h, "https://one.test", 1, i64::MAX - 1);
    let generation = call(&mut c, &mut h, "boot", json!({}))["view"]["generation"].clone();
    assert_ne!(args["generation"], generation);
    args["generation"] = generation;
    h.responses.push_back((200, entry()));
    assert_eq!(
        call(&mut c, &mut h, "native_record_open", args.clone())["data"]["surface"]["can_retry"],
        true
    );
    h.responses
        .push_back((403, json!({"error":{"code":"FORBIDDEN"}})));
    assert_eq!(
        call(&mut c, &mut h, "native_record_retry", args.clone())["data"]["surface"],
        json!({"connected":false})
    );
    assert_eq!(body(&h), original);
    h.responses.push_back((200, entry()));
    assert_eq!(
        call(&mut c, &mut h, "native_record_open", args)["data"]["surface"]["can_retry"],
        false
    );
}

#[test]
fn native_response_validation_drops_undeclared_projection_and_malformed_schema() {
    let (mut c, mut h, args) = setup();
    let mut extra = entry();
    extra["record"]["private_note"] = json!("Not in projection");
    let mut missing = entry();
    missing["record"].as_object_mut().unwrap().remove("subject");
    let mut schema = entry();
    schema["collection"]["methods"][0]["input"]["properties"]["subject"] = json!(false);
    for entry in [extra, missing, schema] {
        h.responses.push_back((200, entry));
        let result = call(&mut c, &mut h, "native_record_open", args.clone());
        assert_eq!(result["data"]["surface"], json!({"connected":false}));
        assert!(result["data"]["error"].is_string());
        assert!(!result.to_string().contains("Not in projection"));
    }
}

#[test]
fn native_token_rotation_preserves_generation_and_authorizes_the_business_request() {
    let (mut c, mut h, mut args) = setup();
    login(&mut c, &mut h, "https://one.test", 1, 1);
    args["generation"] = call(&mut c, &mut h, "boot", json!({}))["view"]["generation"].clone();
    h.responses.push_back((
        200,
        json!({"access_token":token(i64::MAX,1),"refresh_token":"rotated"}),
    ));
    h.responses.push_back((200, entry()));
    let result = call(&mut c, &mut h, "native_record_open", args.clone());
    assert_eq!(result["view"]["generation"], args["generation"]);
    assert_eq!(result["data"]["surface"]["record"], row());
    let requests: Vec<_> = h.actions.iter().filter(|a| a["type"] == "http").collect();
    assert!(
        requests[requests.len() - 2]["url"]
            .as_str()
            .unwrap()
            .ends_with("/oauth2/token")
    );
    assert_eq!(
        requests.last().unwrap()["headers"]["Authorization"],
        format!("Bearer {}", token(i64::MAX, 1))
    );
}
