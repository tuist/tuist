use super::*;
use crate::tests::registration;
use serde::de::DeserializeOwned;

const FIRST: &str = "01922cc0-0000-7000-8000-000000000001";
const SECOND: &str = "01922cc0-0000-7000-8000-000000000002";

fn saved() -> Session {
    Session {
        registration: registration(),
        access_token: "atlas-access".into(),
        refresh_token: "atlas-refresh".into(),
        expires_at: crate::now() + 3600,
    }
}

fn thread(id: &str, kind: &str) -> Thread {
    serde_json::from_value(json!({"id":id,"title":"A purpose","kind":kind,"status":"active","summary":"","origin":"manual","owner_id":FIRST,"participants":[],"updated_at":"2027-06-07T10:00:00Z"})).unwrap()
}

fn opened() -> (String, Arc<Model>) {
    let opened = execute(Action::Open { session: saved() }).unwrap();
    let id = opened["connection"].as_str().unwrap().to_owned();
    let model = get(&id).unwrap();
    {
        let mut state = model.state.lock().unwrap();
        state.snapshot.threads = vec![thread(FIRST, "private"), thread(SECOND, "shared")];
    }
    (id, model)
}

#[test]
fn agent_activity_is_updated_even_when_history_revision_is_unchanged() {
    let mut snapshot = Snapshot {
        selected: Some(thread(FIRST, "private")),
        ..Default::default()
    };
    for status in ["queued", "running", "compacting", "idle"] {
        apply_agent_status(
            &mut snapshot,
            &json!({"revision": 42, "agent_status": status}),
        );
        assert_eq!(
            serde_json::to_value(&snapshot.selected).unwrap()["agent_status"],
            status
        );
    }
    apply_agent_status(&mut snapshot, &json!({"revision": 42}));
    assert!(snapshot.selected.as_ref().unwrap().agent_status.is_none());
    snapshot.selected = None;
    apply_agent_status(&mut snapshot, &json!({"agent_status": "running"}));
    assert!(snapshot.selected.is_none());
}

#[test]
fn card_events_require_a_current_server_supplied_action_and_live_selection() {
    let (connection, model) = opened();
    let message: Message = serde_json::from_value(json!({
        "id":"evidence", "kind":"tool", "body":"", "author_name":"Assistant", "inserted_at":"2026-10-22T12:00:00Z", "tool_status":"succeeded",
        "component":{"type":"result_table","version":1,"data":{"title":"Accounts","columns":["Name"],"rows":[["Northstar"]]},"actions":[{"id":"show_evidence","label":"View source"}],"fallback":"Northstar"}
    })).unwrap();
    {
        let mut state = model.state.lock().unwrap();
        state.active = true;
        state.snapshot.selected = Some(thread(FIRST, "private"));
        state.snapshot.messages = vec![message];
    }
    let event = |id: &str, message_id: &str, event: &str| Action::CardEvent {
        connection: connection.clone(),
        id: id.into(),
        message_id: message_id.into(),
        event: event.into(),
    };
    assert_eq!(
        execute(event(FIRST, "evidence", "show_evidence")).unwrap()["effect"],
        "show_evidence"
    );
    assert!(execute(event(SECOND, "evidence", "show_evidence")).is_err());
    assert!(execute(event(FIRST, "missing", "show_evidence")).is_err());
    assert!(execute(event(FIRST, "evidence", "execute_tool")).is_err());
    model.state.lock().unwrap().active = false;
    assert!(execute(event(FIRST, "evidence", "show_evidence")).is_err());
    {
        let mut state = model.state.lock().unwrap();
        state.active = true;
        state.snapshot.needs_session = true;
    }
    assert!(execute(event(FIRST, "evidence", "show_evidence")).is_err());
    {
        let mut state = model.state.lock().unwrap();
        state.snapshot.needs_session = false;
        state.snapshot.messages[0].tool_status = Some("running".into());
    }
    assert!(execute(event(FIRST, "evidence", "show_evidence")).is_err());
    {
        let mut state = model.state.lock().unwrap();
        state.snapshot.messages[0].tool_status = Some("succeeded".into());
        state.snapshot.messages[0].component = None;
    }
    assert!(execute(event(FIRST, "evidence", "show_evidence")).is_err());
    {
        let mut state = model.state.lock().unwrap();
        state.snapshot.messages.clear();
    }
    assert!(execute(event(FIRST, "evidence", "show_evidence")).is_err());
    execute(Action::Close {
        connection: connection.clone(),
    })
    .unwrap();
    assert!(execute(event(FIRST, "evidence", "show_evidence")).is_err());
}

#[test]
fn shared_state_preserves_drafts_and_retry_identity_per_thread() {
    let (id, model) = opened();
    {
        let mut state = model.state.lock().unwrap();
        state.snapshot.selected = Some(thread(FIRST, "private"));
    }
    draft(&model, FIRST.into(), "Hello".into()).unwrap();
    let first_key = model.state.lock().unwrap().drafts[FIRST].client_id.clone();
    crate::time_off::validate_id(&first_key).unwrap();
    draft(&model, FIRST.into(), "Hello".into()).unwrap();
    assert_eq!(
        model.state.lock().unwrap().drafts[FIRST].client_id,
        first_key
    );
    draft(&model, FIRST.into(), "A new thought".into()).unwrap();
    assert_ne!(
        model.state.lock().unwrap().drafts[FIRST].client_id,
        first_key
    );
    {
        let mut state = model.state.lock().unwrap();
        state.snapshot.selected = Some(thread(SECOND, "shared"));
    }
    draft(&model, SECOND.into(), "Other thread".into()).unwrap();
    {
        let mut state = model.state.lock().unwrap();
        state.snapshot.selected = Some(thread(FIRST, "private"));
        publish(&model, &mut state);
    }
    assert_eq!(snapshot(&model).unwrap()["draft"], "A new thought");
    execute(Action::Close { connection: id }).unwrap();
    assert!(model.state.lock().unwrap().drafts.is_empty());
}

#[test]
fn late_draft_leave_and_send_cannot_target_a_different_thread() {
    let (id, model) = opened();
    {
        let mut state = model.state.lock().unwrap();
        state.snapshot.selection_id = Some(SECOND.into());
        state.snapshot.selected = Some(thread(SECOND, "shared"));
    }
    draft(&model, FIRST.into(), "Typed before navigation".into()).unwrap();
    assert_eq!(snapshot(&model).unwrap()["draft"], "");
    assert_eq!(
        model.state.lock().unwrap().drafts[FIRST].body,
        "Typed before navigation"
    );
    perform(&model, Command::Leave { id: FIRST.into() }).unwrap();
    send(&model, FIRST.into(), "Typed before navigation".into(), true).unwrap();
    assert_eq!(snapshot(&model).unwrap()["selected"]["id"], SECOND);
    assert!(!model.state.lock().unwrap().snapshot.saving);
    execute(Action::Close { connection: id }).unwrap();
}

#[test]
fn captured_send_body_keeps_retry_key_without_overwriting_newer_drafts() {
    let (id, model) = opened();
    draft(&model, FIRST.into(), "At tap time".into()).unwrap();
    let mut state = model.state.lock().unwrap();
    let key = prepare_send(&mut state, FIRST, "At tap time").unwrap();
    let original_key = state.drafts[FIRST].client_id.clone();
    assert_eq!(key, original_key);
    state.drafts.insert(
        FIRST.into(),
        Draft {
            body: "New thought".into(),
            client_id: random_uuid().unwrap(),
            attachments: vec![],
            mentions: vec![],
        },
    );
    assert_eq!(prepare_send(&mut state, FIRST, "At tap time").unwrap(), key);
    assert_eq!(state.drafts[FIRST].body, "New thought");
    assert_ne!(prepare_send(&mut state, FIRST, "New thought").unwrap(), key);
    let mentions = [Person {
        id: SECOND.into(),
        name: "Alice Smith".into(),
    }];
    let mentioned_key =
        prepare_send_draft(&mut state, FIRST, "@Alice Smith ", &[], &mentions).unwrap();
    assert_eq!(
        prepare_send_draft(&mut state, FIRST, "@Alice Smith ", &[], &mentions).unwrap(),
        mentioned_key
    );
    let different_invitee = [Person {
        id: UNSEEN.into(),
        name: "Alice Smith".into(),
    }];
    assert_ne!(
        prepare_send_draft(&mut state, FIRST, "@Alice Smith ", &[], &different_invitee).unwrap(),
        mentioned_key
    );
    assert_eq!(state.drafts[FIRST].body, "New thought");
    drop(state);
    execute(Action::Close { connection: id }).unwrap();
}

#[test]
fn duplicate_submission_reuses_key_but_retyping_the_same_text_is_a_new_message() {
    let (id, model) = opened();
    draft(&model, FIRST.into(), "Hello".into()).unwrap();
    let first = {
        let mut state = model.state.lock().unwrap();
        let key = prepare_send(&mut state, FIRST, "Hello").unwrap();
        state.drafts.remove(FIRST);
        assert_eq!(prepare_send(&mut state, FIRST, "Hello").unwrap(), key);
        key
    };
    draft(&model, FIRST.into(), "Hello".into()).unwrap();
    assert_ne!(
        prepare_send(&mut model.state.lock().unwrap(), FIRST, "Hello").unwrap(),
        first
    );
    execute(Action::Close { connection: id }).unwrap();
}

#[test]
fn reconciliation_deduplicates_and_keeps_private_thread_first() {
    let mut items = vec![];
    merge_thread(&mut items, thread(SECOND, "shared"));
    merge_thread(&mut items, thread(FIRST, "private"));
    let mut updated = thread(SECOND, "shared");
    updated.title = "Updated".into();
    merge_thread(&mut items, updated);
    assert_eq!(items.len(), 2);
    assert_eq!(items[0].id, FIRST);
    assert_eq!(items[1].title, "Updated");
}

#[test]
fn leave_clears_history_and_presence_but_retains_drafts_and_increments_fence() {
    let (id, model) = opened();
    {
        let mut state = model.state.lock().unwrap();
        state.snapshot.selection_id = Some(FIRST.into());
        state.snapshot.selected = Some(thread(FIRST, "shared"));
        state.snapshot.people.push(Viewer {
            id: SECOND.into(),
            name: "Colleague".into(),
            typing: true,
        });
    }
    draft(&model, FIRST.into(), "Keep this".into()).unwrap();
    let generation = model.state.lock().unwrap().generation;
    select(&model, None, Some(FIRST.into())).unwrap();
    let state = model.state.lock().unwrap();
    assert!(state.snapshot.selected.is_none());
    assert!(state.snapshot.messages.is_empty());
    assert!(state.snapshot.people.is_empty());
    assert_eq!(state.drafts[FIRST].body, "Keep this");
    assert!(state.generation > generation);
    drop(state);
    execute(Action::Close { connection: id }).unwrap();
}

#[test]
fn closing_wakes_waiters_and_removes_handle() {
    let (id, model) = opened();
    let waiting = id.clone();
    let (done, finished) = std::sync::mpsc::channel();
    let worker = std::thread::spawn(move || {
        done.send(execute(Action::Next {
            connection: waiting,
            after: 0,
        }))
        .unwrap();
    });
    execute(Action::Close {
        connection: id.clone(),
    })
    .unwrap();
    let _ = finished.recv_timeout(Duration::from_secs(2)).unwrap();
    worker.join().unwrap();
    assert!(get(&id).is_err());
    assert!(model.state.lock().unwrap().closed);
}

fn history_page(page: u32, messages: Vec<Value>) -> History {
    serde_json::from_value(json!({"thread":thread(FIRST,"private"),"messages":{"items":messages,"page":page,"total_pages":3,"total_count":60}})).unwrap()
}

fn message(id: &str, seq: u64, output: &str) -> Value {
    json!({"id":id,"seq":seq,"kind":"tool","body":"","author_name":"","inserted_at":"2027-06-07T10:00:00Z","tool_output":output})
}

#[test]
fn history_reconciliation_orders_by_server_sequence_and_preserves_older_pages() {
    let (id, model) = opened();
    let mut state = model.state.lock().unwrap();
    state.snapshot.selection_id = Some(FIRST.into());
    state.snapshot.selected = Some(thread(FIRST, "private"));
    assert!(reconcile_history(
        &mut state,
        history_page(1, vec![message(SECOND, 2, "running")]),
        0,
        false
    ));
    assert!(reconcile_history(
        &mut state,
        history_page(2, vec![message(FIRST, 1, "older")]),
        0,
        true
    ));
    assert!(reconcile_history(
        &mut state,
        history_page(1, vec![message(SECOND, 2, "finished")]),
        0,
        false
    ));
    assert_eq!(state.snapshot.messages.len(), 2);
    assert_eq!(state.snapshot.messages[0].id, FIRST);
    assert_eq!(state.snapshot.messages[1].tool_output, "finished");
    assert_eq!(state.history_page, 2);
    assert!(state.snapshot.has_older);
    drop(state);
    execute(Action::Close { connection: id }).unwrap();
}

#[test]
fn a_late_history_result_cannot_restore_a_revoked_or_superseded_thread() {
    let (id, model) = opened();
    let mut state = model.state.lock().unwrap();
    state.snapshot.selection_id = Some(FIRST.into());
    state.snapshot.selected = Some(thread(FIRST, "private"));
    state.generation = 1;
    assert!(!reconcile_history(
        &mut state,
        history_page(1, vec![message(FIRST, 1, "confidential")]),
        0,
        false
    ));
    state.snapshot.selection_id = None;
    state.snapshot.selected = None;
    assert!(!reconcile_history(
        &mut state,
        history_page(1, vec![message(FIRST, 1, "confidential")]),
        1,
        false
    ));
    assert!(state.snapshot.messages.is_empty());
    drop(state);
    execute(Action::Close { connection: id }).unwrap();
}

#[test]
fn invalid_drafts_and_cross_instance_session_are_rejected() {
    let (id, model) = opened();
    assert!(draft(&model, FIRST.into(), "x".repeat(16001)).is_err());
    assert!(draft(&model, "../admin".into(), "Hello".into()).is_err());
    let mut session = saved();
    session.registration.server = "https://different.example".into();
    session.registration.authorization_endpoint =
        "https://different.example/oauth/authorize".into();
    session.registration.token_endpoint = "https://different.example/oauth/token".into();
    assert!(
        execute(Action::Request {
            connection: id.clone(),
            session,
            command: Command::Load { kind: None }
        })
        .is_err()
    );
    execute(Action::Close { connection: id }).unwrap();
}

struct InspectTransport<F>(F);

impl<F> Transport for InspectTransport<F>
where
    F: Fn(&url::Url, crate::transport::Body<'_>) -> Result<Value>,
{
    fn request<T: DeserializeOwned>(
        &self,
        url: &url::Url,
        body: crate::transport::Body<'_>,
    ) -> Result<T> {
        serde_json::from_value((self.0)(url, body)?).map_err(|_| invalid())
    }
}

const UNSEEN: &str = "01922cc0-0000-7000-8000-000000000099";

fn response(id: &str) -> Value {
    json!({"thread":thread(id,"shared"),"messages":{"items":[message(id,1,"protected evidence")],"page":1,"total_pages":1,"total_count":1}})
}

fn assert_messages_request(url: &url::Url, body: crate::transport::Body<'_>, id: &str) {
    assert_eq!(
        url.as_str(),
        format!("https://atlas.example/api/native/orbit/threads/{id}/messages?page=1")
    );
    match body {
        crate::transport::Body::Api {
            method,
            token,
            payload,
            ..
        } => {
            assert_eq!(method, reqwest::Method::GET);
            assert_eq!(token, "atlas-access");
            assert!(payload.is_none());
        }
        _ => panic!("expected a protected read"),
    }
}

#[test]
fn private_creation_refreshes_capability_then_replays_uuid_and_creates_distinct_histories() {
    use std::cell::{Cell, RefCell};
    let (connection, model) = opened();
    set_list_kind(&model, Some("private".into())).unwrap();
    select_using(
        &model,
        Some(UNSEEN.into()),
        None,
        &InspectTransport(|_: &url::Url, _: crate::transport::Body<'_>| {
            Ok(json!({"thread":thread(UNSEEN,"private"),"messages":{"items":[],"page":1,"total_pages":1,"total_count":0}}))
        }),
    )
    .unwrap();
    draft(&model, UNSEEN.into(), "Existing private draft".into()).unwrap();
    let draft_key = model.state.lock().unwrap().drafts[UNSEEN].client_id.clone();
    let requests = RefCell::new(Vec::<String>::new());
    let committed = RefCell::new(BTreeMap::<String, String>::new());
    let lose_first_response = Cell::new(true);
    let capability = Cell::new(None);
    let fail_preflight = Cell::new(false);
    let list_calls = Cell::new(0);
    let network = InspectTransport(|url: &url::Url, body: crate::transport::Body<'_>| {
        let crate::transport::Body::Api {
            method,
            token,
            payload,
            ..
        } = body
        else {
            panic!("expected bearer transport")
        };
        assert_eq!(token, "atlas-access");
        if method == reqwest::Method::GET && url.path() == "/api/native/orbit/threads" {
            assert_eq!(url.query(), Some("page=1&kind=private"));
            assert!(payload.is_none());
            list_calls.set(list_calls.get() + 1);
            if fail_preflight.get() {
                return Err(error("transport", "The connection was interrupted."));
            }
            let mut assistant = json!({"name":"Pip","configured":true});
            if let Some(supported) = capability.get() {
                assistant["can_create_private"] = json!(supported);
            }
            return Ok(
                json!({"assistant":assistant,"threads":{"items":[thread(UNSEEN,"private")],"page":1,"total_pages":1,"total_count":1}}),
            );
        }
        if method == reqwest::Method::POST {
            assert_eq!(
                url.as_str(),
                "https://atlas.example/api/native/orbit/threads"
            );
            let payload = payload.unwrap();
            assert_eq!(payload["kind"], "private");
            assert_eq!(payload.as_object().unwrap().len(), 2);
            let request_id = payload["request_id"].as_str().unwrap().to_owned();
            crate::time_off::validate_id(&request_id).unwrap();
            requests.borrow_mut().push(request_id.clone());
            let mut committed = committed.borrow_mut();
            let id = if committed.is_empty() { FIRST } else { SECOND };
            let id = committed
                .entry(request_id)
                .or_insert_with(|| id.into())
                .clone();
            assert!(
                create_using(
                    &model,
                    Command::CreatePrivate,
                    &crate::tests::MockTransport::new(vec![])
                )
                .is_err()
            );
            if lose_first_response.replace(false) {
                return Err(error("transport", "The connection was interrupted."));
            }
            Ok(json!({"thread":thread(&id, "private")}))
        } else {
            let id = if url.path().contains(FIRST) {
                FIRST
            } else {
                SECOND
            };
            Ok(
                json!({"thread":thread(id,"private"),"messages":{"items":[message(id,1,id)],"page":1,"total_pages":1,"total_count":1}}),
            )
        }
    });
    let command = || serde_json::from_value::<Command>(json!({"action":"create_private"})).unwrap();
    load_using(&model, false, &network).unwrap();
    assert_eq!(
        snapshot(&model).unwrap()["assistant"]["can_create_private"],
        false
    );
    let original = snapshot(&model).unwrap();
    for advertised in [None, Some(false)] {
        capability.set(advertised);
        create_using(&model, command(), &network).unwrap();
        let value = snapshot(&model).unwrap();
        assert_eq!(
            value["error"],
            "This Atlas server does not support new private conversations yet. Update the server, then try again."
        );
        for field in [
            "selection_id",
            "selected",
            "messages",
            "threads",
            "draft",
            "has_drafts",
        ] {
            assert_eq!(value[field], original[field], "preserve {field}");
        }
        assert_eq!(
            model.state.lock().unwrap().drafts[UNSEEN].client_id,
            draft_key
        );
        assert!(model.state.lock().unwrap().private_request_id.is_none());
        assert!(requests.borrow().is_empty());
        assert!(committed.borrow().is_empty());
    }
    fail_preflight.set(true);
    create_using(&model, command(), &network).unwrap();
    let value = snapshot(&model).unwrap();
    assert_eq!(value["error"], "The connection was interrupted.");
    for field in [
        "selection_id",
        "selected",
        "messages",
        "threads",
        "draft",
        "has_drafts",
    ] {
        assert_eq!(value[field], original[field], "preserve {field}");
    }
    assert_eq!(value["loading"], false);
    assert_eq!(
        model.state.lock().unwrap().drafts[UNSEEN].client_id,
        draft_key
    );
    assert!(model.state.lock().unwrap().private_request_id.is_none());
    assert!(requests.borrow().is_empty());
    assert!(committed.borrow().is_empty());
    fail_preflight.set(false);
    capability.set(Some(true));
    create_using(&model, command(), &network).unwrap();
    assert_eq!(
        snapshot(&model).unwrap()["assistant"]["can_create_private"],
        true
    );
    assert!(snapshot(&model).unwrap()["error"].is_string());
    assert!(model.state.lock().unwrap().private_request_id.is_some());
    create_using(&model, command(), &network).unwrap();
    assert_eq!(snapshot(&model).unwrap()["selected"]["id"], FIRST);
    assert_eq!(
        snapshot(&model).unwrap()["messages"][0]["tool_output"],
        FIRST
    );
    execute(Action::Draft {
        connection: connection.clone(),
        id: FIRST.into(),
        body: "First private draft".into(),
    })
    .unwrap();
    create_using(&model, command(), &network).unwrap();
    assert_eq!(snapshot(&model).unwrap()["selected"]["id"], SECOND);
    assert_eq!(
        snapshot(&model).unwrap()["messages"][0]["tool_output"],
        SECOND
    );
    assert_eq!(snapshot(&model).unwrap()["draft"], "");
    execute(Action::Draft {
        connection: connection.clone(),
        id: SECOND.into(),
        body: "Second private draft".into(),
    })
    .unwrap();
    select_using(&model, Some(FIRST.into()), None, &network).unwrap();
    assert_eq!(snapshot(&model).unwrap()["draft"], "First private draft");
    assert_eq!(
        snapshot(&model).unwrap()["messages"][0]["tool_output"],
        FIRST
    );
    select_using(&model, Some(SECOND.into()), None, &network).unwrap();
    assert_eq!(snapshot(&model).unwrap()["draft"], "Second private draft");
    assert_eq!(committed.borrow().len(), 2);
    assert_eq!(requests.borrow()[0], requests.borrow()[1]);
    assert_ne!(requests.borrow()[1], requests.borrow()[2]);
    assert!(model.state.lock().unwrap().private_request_id.is_none());
    assert_eq!(list_calls.get(), 5);
    assert_eq!(
        model.state.lock().unwrap().drafts[UNSEEN].body,
        "Existing private draft"
    );
    assert_eq!(
        model.state.lock().unwrap().drafts[UNSEEN].client_id,
        draft_key
    );
    execute(Action::Close { connection }).unwrap();
}

#[test]
fn private_list_filter_survives_pagination_refresh_and_shared_direct_selection() {
    use std::cell::Cell;
    let (connection, model) = opened();
    set_list_kind(&model, Some("private".into())).unwrap();
    let expected_page = Cell::new(1);
    let network = InspectTransport(|url: &url::Url, _: crate::transport::Body<'_>| {
        assert_eq!(
            url.query(),
            Some(format!("page={}&kind=private", expected_page.get()).as_str())
        );
        Ok(
            json!({"assistant":{"name":"Pip","configured":true},"threads":{"items":[thread(if expected_page.get()==1 {FIRST} else {SECOND},"private")],"page":expected_page.get(),"total_pages":2,"total_count":2}}),
        )
    });
    load_using(&model, false, &network).unwrap();
    expected_page.set(2);
    load_using(&model, true, &network).unwrap();
    assert_eq!(
        snapshot(&model).unwrap()["threads"]
            .as_array()
            .unwrap()
            .len(),
        2
    );
    expected_page.set(1);
    load_using(&model, false, &network).unwrap();
    assert_eq!(model.state.lock().unwrap().list_page, 1);
    assert_eq!(
        snapshot(&model).unwrap()["threads"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    select_using(
        &model,
        Some(UNSEEN.into()),
        None,
        &InspectTransport(|_: &url::Url, _: crate::transport::Body<'_>| Ok(response(UNSEEN))),
    )
    .unwrap();
    assert_eq!(snapshot(&model).unwrap()["selected"]["kind"], "shared");
    assert!(set_list_kind(&model, Some("invalid".into())).is_err());
    let Command::Load { kind } =
        serde_json::from_value::<Command>(json!({"action":"load"})).unwrap()
    else {
        panic!("expected legacy load")
    };
    set_list_kind(&model, kind).unwrap();
    assert_eq!(model.state.lock().unwrap().list_page, 0);
    load_using(&model, false, &InspectTransport(|url: &url::Url, _: crate::transport::Body<'_>| {
        assert_eq!(url.query(), Some("page=1"));
        Ok(json!({"assistant":{"name":"Pip","configured":true},"threads":{"items":[thread(UNSEEN,"shared")],"page":1,"total_pages":1,"total_count":1}}))
    })).unwrap();
    assert_eq!(snapshot(&model).unwrap()["threads"][0]["kind"], "shared");
    execute(Action::Close { connection }).unwrap();
}

#[test]
fn late_private_creation_never_replaces_a_newer_selection_and_close_discards_retry_identity() {
    for close in [false, true] {
        let (connection, model) = opened();
        let network = InspectTransport(|url: &url::Url, body: crate::transport::Body<'_>| {
            assert_eq!(
                url.as_str(),
                "https://atlas.example/api/native/orbit/threads?page=1"
            );
            let crate::transport::Body::Api { method, .. } = body else {
                panic!("expected bearer transport")
            };
            assert_eq!(method, reqwest::Method::GET);
            if close {
                execute(Action::Close {
                    connection: connection.clone(),
                })
                .unwrap();
            } else {
                select_using(
                    &model,
                    Some(SECOND.into()),
                    None,
                    &InspectTransport(|_: &url::Url, _: crate::transport::Body<'_>| {
                        Ok(response(SECOND))
                    }),
                )
                .unwrap();
            }
            Ok(
                json!({"assistant":{"name":"Pip","configured":true,"can_create_private":true},"threads":{"items":[],"page":1,"total_pages":1,"total_count":0}}),
            )
        });
        create_using(&model, Command::CreatePrivate, &network).unwrap();
        assert!(model.state.lock().unwrap().private_request_id.is_none());
        assert!(snapshot(&model).unwrap()["assistant"].is_null());
        if !close {
            assert_eq!(snapshot(&model).unwrap()["selected"]["id"], SECOND);
            execute(Action::Close { connection }).unwrap();
        }
    }
    let (connection, model) = opened();
    load_using(&model, false, &InspectTransport(|_: &url::Url, _: crate::transport::Body<'_>| {
        Ok(json!({"assistant":{"name":"Pip","configured":true,"can_create_private":true},"threads":{"items":[],"page":1,"total_pages":1,"total_count":0}}))
    })).unwrap();
    let network = InspectTransport(|_: &url::Url, _: crate::transport::Body<'_>| {
        select_using(
            &model,
            Some(SECOND.into()),
            None,
            &InspectTransport(|_: &url::Url, _: crate::transport::Body<'_>| Ok(response(SECOND))),
        )
        .unwrap();
        Ok(json!({"thread":thread(UNSEEN,"private")}))
    });
    create_using(&model, Command::CreatePrivate, &network).unwrap();
    assert_eq!(snapshot(&model).unwrap()["selected"]["id"], SECOND);
    let uncertain = InspectTransport(|_: &url::Url, _: crate::transport::Body<'_>| {
        Err(error("transport", "Try again."))
    });
    create_using(&model, Command::CreatePrivate, &uncertain).unwrap();
    assert!(model.state.lock().unwrap().private_request_id.is_some());
    execute(Action::Close { connection }).unwrap();
    assert!(model.state.lock().unwrap().private_request_id.is_none());
}

#[test]
fn promoted_creation_conflict_allows_an_explicit_new_attempt_without_replaying_forever() {
    let (connection, model) = opened();
    load_using(&model, false, &InspectTransport(|_: &url::Url, _: crate::transport::Body<'_>| {
        Ok(json!({"assistant":{"name":"Pip","configured":true,"can_create_private":true},"threads":{"items":[],"page":1,"total_pages":1,"total_count":0}}))
    })).unwrap();
    let attempts = std::cell::RefCell::new(Vec::new());
    let network = InspectTransport(|_: &url::Url, body: crate::transport::Body<'_>| {
        let crate::transport::Body::Api {
            method, payload, ..
        } = body
        else {
            panic!("expected bearer transport")
        };
        if method == reqwest::Method::GET {
            return Ok(response(UNSEEN));
        }
        let payload = payload.unwrap();
        let id = payload["request_id"].as_str().unwrap().to_owned();
        let mut attempts = attempts.borrow_mut();
        attempts.push(id);
        match attempts.len() {
            1 => Err(error("transport", "The connection was interrupted.")),
            2 => {
                assert_eq!(attempts[0], attempts[1]);
                Err(error(
                    "conflict",
                    "This thread changed. Refresh it and try again.",
                ))
            }
            3 => {
                assert_ne!(attempts[1], attempts[2]);
                Ok(json!({"thread":thread(UNSEEN, "private")}))
            }
            _ => panic!("creation must never retry automatically"),
        }
    });
    create_using(&model, Command::CreatePrivate, &network).unwrap();
    create_using(&model, Command::CreatePrivate, &network).unwrap();
    assert_eq!(attempts.borrow().len(), 2);
    assert!(snapshot(&model).unwrap()["selected"].is_null());
    create_using(&model, Command::CreatePrivate, &network).unwrap();
    assert_eq!(snapshot(&model).unwrap()["selected"]["id"], UNSEEN);
    assert_eq!(attempts.borrow().len(), 3);
    execute(Action::Close { connection }).unwrap();
}

#[test]
fn unseen_selection_reads_exact_id_before_exposing_any_thread_or_mutations() {
    let (connection, model) = opened();
    draft(&model, FIRST.into(), "Retained draft".into()).unwrap();
    let calls = std::cell::Cell::new(0);
    let network = InspectTransport(|url: &url::Url, body: crate::transport::Body<'_>| {
        calls.set(calls.get() + 1);
        assert_messages_request(url, body, UNSEEN);
        let pending = snapshot(&model).unwrap();
        assert_eq!(pending["selection_id"], UNSEEN);
        assert!(pending["selected"].is_null());
        assert_eq!(pending["messages"], json!([]));
        assert_eq!(pending["history_loading"], true);
        assert_eq!(pending["has_drafts"], true);
        // Even an early native Send cannot turn an unverified target into a mutation.
        send(&model, UNSEEN.into(), "No write before read".into(), true).unwrap();
        assert!(!model.state.lock().unwrap().snapshot.saving);
        Ok(response(UNSEEN))
    });
    select_using(&model, Some(UNSEEN.into()), None, &network).unwrap();
    assert_eq!(calls.get(), 1); // No list lookup or pagination.
    let selected = snapshot(&model).unwrap();
    assert_eq!(selected["selected"]["id"], UNSEEN);
    assert_eq!(selected["selected"]["title"], "A purpose");
    assert_eq!(selected["messages"][0]["tool_output"], "protected evidence");
    assert_eq!(
        model.state.lock().unwrap().drafts[FIRST].body,
        "Retained draft"
    );
    select_using(&model, None, Some(UNSEEN.into()), &network).unwrap();
    assert!(snapshot(&model).unwrap()["selection_id"].is_null());
    execute(Action::Close { connection }).unwrap();
}

#[test]
fn unavailable_direct_reads_revoke_cached_state_and_allow_explicit_retry_and_back() {
    for status in [403, 404] {
        let (connection, model) = opened();
        draft(&model, FIRST.into(), "Must revoke".into()).unwrap();
        let denied = InspectTransport(|url: &url::Url, body: crate::transport::Body<'_>| {
            assert_eq!(
                url.path(),
                format!("/api/native/orbit/threads/{FIRST}/messages")
            );
            let crate::transport::Body::Api { failure, .. } = body else {
                panic!("expected bearer read")
            };
            Err(failure(status, b"private server diagnostics"))
        });
        select_using(&model, Some(FIRST.into()), None, &denied).unwrap();
        let unavailable = snapshot(&model).unwrap();
        assert_eq!(unavailable["selection_id"], FIRST);
        assert!(unavailable["selected"].is_null());
        assert_eq!(unavailable["messages"], json!([]));
        assert_eq!(unavailable["has_drafts"], false);
        assert!(
            !unavailable["error"]
                .as_str()
                .unwrap()
                .contains("diagnostics")
        );
        let state = model.state.lock().unwrap();
        assert!(!state.snapshot.threads.iter().any(|item| item.id == FIRST));
        assert!(!state.drafts.contains_key(FIRST));
        drop(state);
        let retry = crate::tests::MockTransport::new(vec![response(FIRST)]);
        history_using(&model, false, &retry).unwrap();
        assert_eq!(snapshot(&model).unwrap()["selected"]["id"], FIRST);
        select_using(&model, None, Some(FIRST.into()), &retry).unwrap();
        assert!(snapshot(&model).unwrap()["selection_id"].is_null());
        execute(Action::Close { connection }).unwrap();
    }
}

#[test]
fn superseded_protected_reads_cannot_select_revoke_or_error_the_new_target() {
    for status in [200, 403, 404, 500] {
        let (connection, model) = opened();
        let network = InspectTransport(|url: &url::Url, body: crate::transport::Body<'_>| {
            assert_eq!(
                url.path(),
                format!("/api/native/orbit/threads/{UNSEEN}/messages")
            );
            let newer = crate::tests::MockTransport::new(vec![response(SECOND)]);
            select_using(&model, Some(SECOND.into()), None, &newer).unwrap();
            if status == 200 {
                Ok(response(UNSEEN))
            } else {
                let crate::transport::Body::Api { failure, .. } = body else {
                    panic!("expected bearer read")
                };
                Err(failure(status, b"must not leak"))
            }
        });
        select_using(&model, Some(UNSEEN.into()), None, &network).unwrap();
        let current = snapshot(&model).unwrap();
        assert_eq!(current["selected"]["id"], SECOND);
        assert_eq!(current["messages"][0]["id"], SECOND);
        assert!(current["error"].is_null());
        assert!(
            !current["threads"]
                .as_array()
                .unwrap()
                .iter()
                .any(|item| item["id"] == UNSEEN)
        );
        execute(Action::Close { connection }).unwrap();
    }
}

#[test]
fn revocation_invalidates_an_older_list_read_at_the_shared_transport_boundary() {
    let (connection, model) = opened();
    let network = InspectTransport(|_: &url::Url, _: crate::transport::Body<'_>| {
        let denied = InspectTransport(|_: &url::Url, body: crate::transport::Body<'_>| {
            let crate::transport::Body::Api { failure, .. } = body else {
                panic!("expected bearer read")
            };
            Err(failure(403, b""))
        });
        select_using(&model, Some(FIRST.into()), None, &denied).unwrap();
        Ok(
            json!({"assistant":{"name":"Pip","configured":true},"threads":{"items":[thread(FIRST,"private")],"page":1,"total_pages":1,"total_count":1}}),
        )
    });
    load_using(&model, false, &network).unwrap();
    let current = snapshot(&model).unwrap();
    assert!(current["selected"].is_null());
    assert!(current["error"].is_string());
    assert!(
        !current["threads"]
            .as_array()
            .unwrap()
            .iter()
            .any(|item| item["id"] == FIRST)
    );
    execute(Action::Close { connection }).unwrap();
}

#[test]
fn mismatched_failed_and_closed_direct_reads_never_publish_authoritative_metadata() {
    for status in [200, 401, 500, 0] {
        let (connection, model) = opened();
        let network = InspectTransport(
            |_: &url::Url, body: crate::transport::Body<'_>| match status {
                200 => Ok(response(SECOND)), // A well-formed response for the wrong ID is still rejected.
                0 => {
                    execute(Action::Close {
                        connection: connection.clone(),
                    })
                    .unwrap();
                    Ok(response(UNSEEN))
                }
                _ => {
                    let crate::transport::Body::Api { failure, .. } = body else {
                        panic!("expected bearer read")
                    };
                    Err(failure(status, b""))
                }
            },
        );
        select_using(&model, Some(UNSEEN.into()), None, &network).unwrap();
        let current = snapshot(&model).unwrap();
        assert!(current["selected"].is_null());
        assert_eq!(current["messages"], json!([]));
        assert_eq!(current["needs_session"], status == 401);
        if status != 0 {
            assert_eq!(current["selection_id"], UNSEEN);
            assert!(current["error"].is_string());
        }
        execute(Action::Close {
            connection: connection.clone(),
        })
        .unwrap();
    }
}

fn attachment() -> Attachment {
    Attachment {
        id: UNSEEN.into(),
        filename: "report.txt".into(),
        content_type: "text/plain".into(),
        byte_size: 5,
    }
}

fn attachment_model() -> (String, Arc<Model>) {
    let (connection, model) = opened();
    select_using(
        &model,
        Some(FIRST.into()),
        None,
        &InspectTransport(|_: &url::Url, _: crate::transport::Body<'_>| Ok(response(FIRST))),
    )
    .unwrap();
    model.state.lock().unwrap().active = true;
    (connection, model)
}

fn pick_mention(
    connection: &str,
    model: &Arc<Model>,
    query: &str,
    user_id: &str,
    name: &str,
) -> Value {
    people_using(
        model,
        FIRST.into(),
        query.into(),
        &crate::tests::MockTransport::new(vec![
            json!({"people":[{"id":user_id,"name":name,"email":"must-not-forward"}]}),
        ]),
    )
    .unwrap();
    execute(
        serde_json::from_value(
            json!({"action":"mention","connection":connection,"id":FIRST,"user_id":user_id}),
        )
        .unwrap(),
    )
    .unwrap()
}

#[test]
fn mention_candidates_fence_queries_selection_access_and_local_actions_without_losing_drafts() {
    for stale_failure in [false, true] {
        let (connection, model) = attachment_model();
        draft(&model, FIRST.into(), "Please @Al".into()).unwrap();
        {
            let mut state = model.state.lock().unwrap();
            state.snapshot.error = Some("Keep the message error".into());
            state.drafts.get_mut(FIRST).unwrap().attachments = vec![attachment()];
        }
        let older = InspectTransport(|url: &url::Url, body: crate::transport::Body<'_>| {
            assert_eq!(
                url.as_str(),
                format!("https://atlas.example/api/native/orbit/threads/{FIRST}/people?query=Al")
            );
            let crate::transport::Body::Api {
                method,
                token,
                payload,
                ..
            } = body
            else {
                panic!()
            };
            assert_eq!(method, reqwest::Method::GET);
            assert_eq!(token, "atlas-access");
            assert!(payload.is_none());
            let pending = snapshot(&model).unwrap();
            assert_eq!(pending["loading"], false);
            assert_eq!(pending["saving"], false);
            assert_eq!(pending["mention_loading"], true);
            draft(&model, FIRST.into(), "Please @Ali".into()).unwrap();
            people_using(&model, FIRST.into(), "Ali".into(), &crate::tests::MockTransport::new(vec![
                json!({"people":[{"id":SECOND,"name":"Alice Smith","email":"must-not-forward"}]})
            ])).unwrap();
            if stale_failure {
                Err(error("unavailable", "Stale denial"))
            } else {
                Ok(json!({"people":[{"id":UNSEEN,"name":"Old result"}]}))
            }
        });
        people_using(&model, FIRST.into(), "Al".into(), &older).unwrap();
        let current = snapshot(&model).unwrap();
        assert_eq!(
            current["mention_candidates"],
            json!([{"id":SECOND,"name":"Alice Smith"}])
        );
        assert_eq!(current["draft"], "Please @Ali");
        assert_eq!(current["error"], "Keep the message error");
        assert!(current["mention_error"].is_null());
        assert!(mention(&model, FIRST.into(), UNSEEN.into()).is_err());
        assert!(mention(&model, SECOND.into(), SECOND.into()).is_err());
        assert!(mention(&model, FIRST.into(), "../user".into()).is_err());
        model.state.lock().unwrap().active = false;
        assert!(mention(&model, FIRST.into(), SECOND.into()).is_err());
        model.state.lock().unwrap().active = true;
        let value = execute(
            serde_json::from_value(
                json!({"action":"mention","connection":connection,"id":FIRST,"user_id":SECOND}),
            )
            .unwrap(),
        )
        .unwrap();
        assert_eq!(value["draft"], "Please @Alice Smith ");
        assert_eq!(
            value["draft_mentions"],
            json!([{"id":SECOND,"name":"Alice Smith"}])
        );
        assert_eq!(value["draft_attachments"], json!([attachment()]));
        assert_eq!(value["mention_candidates"], json!([]));
        for id in [SECOND, FIRST] {
            begin_selection(&mut model.state.lock().unwrap(), Some(id.into()));
            history_using(
                &model,
                false,
                &crate::tests::MockTransport::new(vec![response(id)]),
            )
            .unwrap();
        }
        assert_eq!(
            snapshot(&model).unwrap()["draft_mentions"],
            value["draft_mentions"]
        );
        draft(&model, FIRST.into(), "Please @Alice Smithson ".into()).unwrap();
        assert_eq!(snapshot(&model).unwrap()["draft_mentions"], json!([]));
        draft(&model, FIRST.into(), "Please @Alice Smith ".into()).unwrap();
        assert_eq!(snapshot(&model).unwrap()["draft_mentions"], json!([])); // Plain text never grants a mention.
        assert_eq!(
            snapshot(&model).unwrap()["draft_attachments"],
            json!([attachment()])
        );
        execute(Action::Close { connection }).unwrap();
    }
    for status in [403, 404, 501, 500] {
        let (connection, model) = attachment_model();
        draft(&model, FIRST.into(), "Ask @Ali".into()).unwrap();
        pick_mention(&connection, &model, "Ali", SECOND, "Alice Smith");
        draft(&model, FIRST.into(), "Ask @Alice Smith @Bo".into()).unwrap();
        {
            let mut state = model.state.lock().unwrap();
            state.snapshot.error = Some("Keep the message error".into());
            state.drafts.get_mut(FIRST).unwrap().attachments = vec![attachment()];
            publish(&model, &mut state);
        }
        let before = snapshot(&model).unwrap();
        let denial = InspectTransport(|_: &url::Url, body: crate::transport::Body<'_>| {
            let crate::transport::Body::Api { failure, .. } = body else {
                panic!()
            };
            Err(failure(status, b"must-not-forward"))
        });
        people_using(&model, FIRST.into(), "Bo".into(), &denial).unwrap();
        let after = snapshot(&model).unwrap();
        for field in [
            "selected",
            "selection_id",
            "messages",
            "threads",
            "draft",
            "draft_mentions",
            "draft_attachments",
            "error",
        ] {
            assert_eq!(
                after[field], before[field],
                "People {status} must preserve {field}"
            );
        }
        assert!(after["mention_error"].is_string());
        assert!(!after.to_string().contains("must-not-forward"));
        assert_eq!(after["mention_loading"], false);
        let never = crate::tests::MockTransport::new(vec![]);
        assert!(people_using(&model, "../thread".into(), "Bo".into(), &never).is_err());
        assert!(people_using(&model, FIRST.into(), "x".repeat(101), &never).is_err());
        assert!(never.requests.borrow().is_empty());
        history_using(
            &model,
            false,
            &InspectTransport(|_: &url::Url, body: crate::transport::Body<'_>| {
                let crate::transport::Body::Api { failure, .. } = body else {
                    panic!()
                };
                Err(failure(404, b"must-not-forward"))
            }),
        )
        .unwrap();
        assert!(snapshot(&model).unwrap()["selected"].is_null());
        assert_eq!(snapshot(&model).unwrap()["draft_mentions"], json!([]));
        assert!(model.state.lock().unwrap().drafts.is_empty());
        execute(Action::Close { connection }).unwrap();
    }
    for fence in ["selection", "access", "background", "revoke", "close"] {
        let (connection, model) = attachment_model();
        draft(&model, FIRST.into(), "@A".into()).unwrap();
        let network = InspectTransport(|_: &url::Url, _: crate::transport::Body<'_>| {
            match fence {
                "selection" => {
                    begin_selection(&mut model.state.lock().unwrap(), Some(SECOND.into()));
                }
                "access" => {
                    set_list_kind(&model, Some("shared".into())).unwrap();
                }
                "background" => {
                    set_active(&model, false).unwrap();
                }
                "revoke" => {
                    history_using(
                        &model,
                        false,
                        &InspectTransport(|_: &url::Url, _: crate::transport::Body<'_>| {
                            Err(error("unavailable", "Access revoked"))
                        }),
                    )
                    .unwrap();
                }
                _ => {
                    execute(Action::Close {
                        connection: connection.clone(),
                    })
                    .unwrap();
                }
            }
            Ok(json!({"people":[{"id":SECOND,"name":"Alice Smith"}]}))
        });
        people_using(&model, FIRST.into(), "A".into(), &network).unwrap();
        assert_eq!(snapshot(&model).unwrap()["mention_candidates"], json!([]));
        assert!(mention(&model, FIRST.into(), SECOND.into()).is_err());
        if fence == "revoke" {
            assert!(model.state.lock().unwrap().drafts.is_empty());
            assert!(model.state.lock().unwrap().outbox.is_empty());
        }
        execute(Action::Close { connection }).unwrap();
    }
}

#[test]
fn mentioned_sends_replay_captured_ids_preserve_newer_drafts_and_reconcile_server_promotion() {
    use std::cell::{Cell, RefCell};
    let (connection, model) = attachment_model();
    model.state.lock().unwrap().snapshot.selected = Some(thread(FIRST, "private"));
    draft(&model, FIRST.into(), "Coordinate @Ali".into()).unwrap();
    model
        .state
        .lock()
        .unwrap()
        .drafts
        .get_mut(FIRST)
        .unwrap()
        .attachments = vec![attachment()];
    let selected = pick_mention(&connection, &model, "Ali", SECOND, "Alice Smith");
    let captured = selected["draft"].as_str().unwrap().to_owned();
    let key = RefCell::new(String::new());
    let uncertain = InspectTransport(|_: &url::Url, body: crate::transport::Body<'_>| {
        let crate::transport::Body::Api {
            payload: Some(payload),
            ..
        } = body
        else {
            panic!()
        };
        assert_eq!(payload["body"], captured);
        assert_eq!(payload["mention_ids"], json!([SECOND]));
        assert_eq!(payload["attachment_ids"], json!([UNSEEN]));
        assert_eq!(payload["address_agent"], true);
        *key.borrow_mut() = payload["client_id"].as_str().unwrap().into();
        Err(error("network", "Try the same message again."))
    });
    send_using(
        &model,
        FIRST.into(),
        captured.clone(),
        None,
        None,
        false,
        &uncertain,
    )
    .unwrap();
    assert_eq!(
        snapshot(&model).unwrap()["draft_mentions"],
        selected["draft_mentions"]
    );
    let edit_during_send = Cell::new(true);
    let replay = InspectTransport(|url: &url::Url, body: crate::transport::Body<'_>| {
        let crate::transport::Body::Api {
            method, payload, ..
        } = body
        else {
            panic!()
        };
        if method == reqwest::Method::GET {
            assert_eq!(
                url.as_str(),
                format!("https://atlas.example/api/native/orbit/threads/{FIRST}/messages?page=1")
            );
            let mut promoted = thread(FIRST, "shared");
            promoted.title = "Initial task title".into();
            return Ok(
                json!({"thread":promoted,"messages":{"items":[{"id":SECOND,"seq":2,"kind":"system","body":"Pip is handing off to the participants.","author_name":"Pip","inserted_at":"2027-06-07T10:00:00Z","notice_kind":"handoff","mentioned_user_ids":[]}],"page":1,"total_pages":1,"total_count":1}}),
            );
        }
        let payload = payload.unwrap();
        assert_eq!(payload["client_id"], *key.borrow());
        assert_eq!(payload["body"], captured);
        assert_eq!(payload["mention_ids"], json!([SECOND]));
        if edit_during_send.replace(false) {
            draft(&model, FIRST.into(), "Next @Bo".into()).unwrap();
            pick_mention(&connection, &model, "Bo", UNSEEN, "Bob Jones");
        }
        Ok(json!({"message":message(UNSEEN,1,"")}))
    });
    send_using(
        &model,
        FIRST.into(),
        captured.clone(),
        Some(vec![UNSEEN.into()]),
        Some(vec![SECOND.into()]),
        false,
        &replay,
    )
    .unwrap();
    let value = snapshot(&model).unwrap();
    assert_eq!(value["draft"], "Next @Bob Jones ");
    assert_eq!(
        value["draft_mentions"],
        json!([{"id":UNSEEN,"name":"Bob Jones"}])
    );
    assert_eq!(value["draft_attachments"], json!([]));
    assert_eq!(value["selected"]["kind"], "shared");
    assert_eq!(value["selected"]["title"], "Initial task title");
    assert_eq!(value["threads"][0]["kind"], "shared");
    assert_eq!(value["messages"][0]["notice_kind"], "handoff");
    // Another candidate can have the same display name without sharing the replay identity.
    draft(&model, FIRST.into(), "Coordinate @Ali".into()).unwrap();
    pick_mention(&connection, &model, "Ali", UNSEEN, "Alice Smith");
    assert_eq!(snapshot(&model).unwrap()["draft"], captured);
    // A captured retry must not borrow a different invitee from the same visible text.
    let newer = snapshot(&model).unwrap();
    send_using(
        &model,
        FIRST.into(),
        captured.clone(),
        Some(vec![UNSEEN.into()]),
        Some(vec![SECOND.into()]),
        false,
        &replay,
    )
    .unwrap();
    assert_eq!(snapshot(&model).unwrap()["draft"], newer["draft"]);
    assert_eq!(
        snapshot(&model).unwrap()["draft_mentions"],
        newer["draft_mentions"]
    );
    let different_invitee = InspectTransport(|_: &url::Url, body: crate::transport::Body<'_>| {
        let crate::transport::Body::Api {
            payload: Some(payload),
            ..
        } = body
        else {
            panic!()
        };
        assert_ne!(payload["client_id"], *key.borrow());
        assert_eq!(payload["mention_ids"], json!([UNSEEN]));
        Err(error("network", "Try again."))
    });
    send_using(
        &model,
        FIRST.into(),
        captured,
        None,
        None,
        false,
        &different_invitee,
    )
    .unwrap();
    let never = crate::tests::MockTransport::new(vec![]);
    for ids in [
        vec!["../user".into()],
        vec![SECOND.into(); 11],
        vec![SECOND.into()],
    ] {
        assert!(
            send_using(
                &model,
                FIRST.into(),
                "@Unknown ".into(),
                None,
                Some(ids),
                false,
                &never
            )
            .is_err()
        );
    }
    assert!(never.requests.borrow().is_empty());
    execute(Action::Close { connection }).unwrap();
    assert!(model.state.lock().unwrap().drafts.is_empty());
    assert!(model.state.lock().unwrap().outbox.is_empty());
}

fn upload_command() -> Command {
    Command::UploadAttachment {
        id: FIRST.into(),
        client_id: None,
        filename: ".report.txt".into(),
        content_type: "text/plain".into(),
        data: "aGVsbG8=".into(),
    }
}

#[test]
fn attachment_upload_and_attachment_only_send_retries_own_identity_and_preserve_newer_text() {
    use std::cell::RefCell;
    let (connection, model) = attachment_model();
    let upload_id = RefCell::new(String::new());
    let uncertain = InspectTransport(|url: &url::Url, body: crate::transport::Body<'_>| {
        assert!(url.path().ends_with(&format!("/{FIRST}/attachments")));
        let crate::transport::Body::Api {
            method,
            payload: Some(payload),
            ..
        } = body
        else {
            panic!()
        };
        assert_eq!(method, reqwest::Method::POST);
        assert_eq!(payload["data"], "aGVsbG8=");
        *upload_id.borrow_mut() = payload["client_id"].as_str().unwrap().into();
        assert_eq!(snapshot(&model).unwrap()["attachment_busy"], true);
        Err(error(
            "network",
            "Could not connect securely to Atlas. Try again.",
        ))
    });
    upload_using(&model, upload_command(), &uncertain).unwrap();
    let pending = snapshot(&model).unwrap();
    assert_eq!(pending["has_drafts"], true);
    assert_eq!(pending["upload_pending"], true);
    assert_eq!(pending["upload_filename"], ".report.txt");
    assert!(!pending.to_string().contains("aGVsbG8="));
    assert!(
        send_using(
            &model,
            FIRST.into(),
            "Caption".into(),
            None,
            None,
            false,
            &crate::tests::MockTransport::new(vec![])
        )
        .is_err()
    );
    let retry = InspectTransport(|_: &url::Url, body: crate::transport::Body<'_>| {
        let crate::transport::Body::Api {
            payload: Some(payload),
            ..
        } = body
        else {
            panic!()
        };
        assert_eq!(payload["client_id"], *upload_id.borrow());
        assert_eq!(payload["data"], "aGVsbG8=");
        // Atlas canonicalizes display names (for example, removes leading dots).
        // Accept the validated server name, without weakening content-type/size checks.
        Ok(json!({"attachment":attachment()}))
    });
    retry_upload_using(&model, FIRST.into(), &retry).unwrap();
    assert_eq!(
        snapshot(&model).unwrap()["draft_attachments"],
        json!([attachment()])
    );
    draft(&model, FIRST.into(), "A caption".into()).unwrap();
    draft(&model, FIRST.into(), "".into()).unwrap();
    assert_eq!(snapshot(&model).unwrap()["has_drafts"], true);
    let send_id = RefCell::new(String::new());
    let failed_send = InspectTransport(|_: &url::Url, body: crate::transport::Body<'_>| {
        let crate::transport::Body::Api {
            payload: Some(payload),
            ..
        } = body
        else {
            panic!()
        };
        assert_eq!(payload["attachment_ids"], json!([UNSEEN]));
        assert_eq!(payload["body"], "");
        *send_id.borrow_mut() = payload["client_id"].as_str().unwrap().into();
        Err(error(
            "network",
            "Could not connect securely to Atlas. Try again.",
        ))
    });
    send_using(
        &model,
        FIRST.into(),
        "".into(),
        None,
        None,
        false,
        &failed_send,
    )
    .unwrap();
    let successful_send = InspectTransport(|_: &url::Url, body: crate::transport::Body<'_>| {
        let crate::transport::Body::Api {
            method, payload, ..
        } = body
        else {
            panic!()
        };
        if method == reqwest::Method::GET {
            return Ok(response(FIRST));
        }
        let payload = payload.unwrap();
        assert_eq!(payload["client_id"], *send_id.borrow());
        draft(&model, FIRST.into(), "New thought while sending".into()).unwrap();
        Ok(json!({"message":message(UNSEEN,2,"")}))
    });
    send_using(
        &model,
        FIRST.into(),
        "".into(),
        Some(vec![UNSEEN.into()]),
        None,
        false,
        &successful_send,
    )
    .unwrap();
    let final_snapshot = snapshot(&model).unwrap();
    assert_eq!(final_snapshot["draft"], "New thought while sending");
    assert_eq!(final_snapshot["draft_attachments"], json!([]));
    assert!(model.state.lock().unwrap().upload_attempt.is_none());
    execute(Action::Close { connection }).unwrap();
}

#[test]
fn attachment_deletion_is_confirmed_and_text_updates_never_drop_pending_chips() {
    let (connection, model) = attachment_model();
    upload_using(
        &model,
        upload_command(),
        &crate::tests::MockTransport::new(vec![json!({"attachment":attachment()})]),
    )
    .unwrap();
    draft(&model, FIRST.into(), "caption".into()).unwrap();
    let failed = InspectTransport(|_: &url::Url, _: crate::transport::Body<'_>| {
        Err(error("network", "Try again."))
    });
    delete_using(&model, FIRST.into(), UNSEEN.into(), &failed).unwrap();
    assert_eq!(
        snapshot(&model).unwrap()["draft_attachments"],
        json!([attachment()])
    );
    let confirmed = InspectTransport(|url: &url::Url, body: crate::transport::Body<'_>| {
        assert!(
            url.path()
                .ends_with(&format!("/{FIRST}/attachments/{UNSEEN}"))
        );
        let crate::transport::Body::Api { method, .. } = body else {
            panic!()
        };
        assert_eq!(method, reqwest::Method::DELETE);
        assert_eq!(
            snapshot(&model).unwrap()["draft_attachments"],
            json!([attachment()])
        );
        Ok(json!({"deleted":true}))
    });
    delete_using(&model, FIRST.into(), UNSEEN.into(), &confirmed).unwrap();
    assert_eq!(snapshot(&model).unwrap()["draft"], "caption");
    assert_eq!(snapshot(&model).unwrap()["draft_attachments"], json!([]));
    execute(Action::Close { connection }).unwrap();
}

#[test]
fn attachment_download_requires_protected_metadata_and_fences_lifecycle_revocation_and_selection() {
    for mode in [
        "ok",
        "unseen",
        "superseded",
        "background",
        "revoked",
        "closed",
        "denied",
        "expired",
        "wrong_size",
        "wrong_id",
    ] {
        let (connection, model) = attachment_model();
        if mode != "unseen" {
            model.state.lock().unwrap().snapshot.messages[0].attachments = vec![attachment()];
        }
        let network = InspectTransport(|url: &url::Url, body: crate::transport::Body<'_>| {
            assert!(
                url.path()
                    .ends_with(&format!("/{FIRST}/attachments/{UNSEEN}"))
            );
            let crate::transport::Body::Attachment { token, failure } = body else {
                panic!()
            };
            assert_eq!(token, "atlas-access");
            match mode {
                "unseen" => panic!("unseen metadata must not reach network"),
                "superseded" => {
                    model.state.lock().unwrap().active = false;
                    select_using(
                        &model,
                        None,
                        Some(FIRST.into()),
                        &crate::tests::MockTransport::new(vec![]),
                    )
                    .unwrap();
                }
                "background" => {
                    let mut state = model.state.lock().unwrap();
                    state.active = false;
                    state.lifecycle += 1;
                    state.active = true;
                }
                "revoked" => revoke(&mut model.state.lock().unwrap(), FIRST),
                "closed" => {
                    execute(Action::Close {
                        connection: connection.clone(),
                    })
                    .unwrap();
                }
                "denied" => return Err(failure(403, b"private bytes")),
                "expired" => return Err(failure(401, b"private bytes")),
                _ => (),
            }
            let mut file = attachment();
            if mode == "wrong_id" {
                file.id = SECOND.into();
            }
            Ok(
                json!({"attachment":{"id":file.id,"filename":file.filename,"content_type":file.content_type,"byte_size":file.byte_size,"data":if mode=="wrong_size" {"YQ=="} else {"aGVsbG8="}}}),
            )
        });
        let result = download_using(&model, FIRST.into(), UNSEEN.into(), &network);
        assert_eq!(result.is_ok(), mode == "ok", "{mode}");
        if let Ok(value) = result {
            assert_eq!(value["thread_id"], FIRST);
            assert_eq!(value["attachment"]["data"], "aGVsbG8=");
        }
        assert!(!snapshot(&model).unwrap().to_string().contains("aGVsbG8="));
        if mode == "denied" {
            assert!(snapshot(&model).unwrap()["selected"].is_null());
        }
        if mode == "expired" {
            assert_eq!(snapshot(&model).unwrap()["needs_session"], true);
        }
        execute(Action::Close { connection }).unwrap();
    }
}

#[test]
fn superseded_uploads_never_publish_files_and_close_clears_uncertain_bytes() {
    let (connection, model) = attachment_model();
    let network = InspectTransport(|_: &url::Url, _: crate::transport::Body<'_>| {
        model.state.lock().unwrap().active = false;
        select_using(
            &model,
            None,
            Some(FIRST.into()),
            &crate::tests::MockTransport::new(vec![]),
        )
        .unwrap();
        Ok(json!({"attachment":attachment()}))
    });
    upload_using(&model, upload_command(), &network).unwrap();
    assert!(snapshot(&model).unwrap()["selected"].is_null());
    assert_eq!(snapshot(&model).unwrap()["draft_attachments"], json!([]));
    assert!(model.state.lock().unwrap().drafts.is_empty());
    execute(Action::Close { connection }).unwrap();
    assert!(model.state.lock().unwrap().upload_attempt.is_none());
}

#[test]
fn only_upload_bridge_envelopes_may_exceed_one_mebibyte() {
    let large = "A".repeat(1024 * 1024 + 4);
    for value in [
        json!({"operation":"default_themes","padding":large}),
        json!({"operation":"orbit_session","action":"open","session":saved(),"padding":large}),
    ] {
        let result: Value =
            serde_json::from_str(&crate::bridge::execute(&value.to_string())).unwrap();
        assert_eq!(result["error"]["kind"], "invalid_response");
    }
    let upload = json!({"operation":"orbit_session","action":"request","connection":"not-open","session":saved(),"command":{"action":"upload_attachment","id":FIRST,"filename":"big.txt","content_type":"text/plain","data":large}});
    let result: Value = serde_json::from_str(&crate::bridge::execute(&upload.to_string())).unwrap();
    assert_eq!(result["error"]["kind"], "closed"); // Allowed through the bounded bridge; no handle means no HTTP.
}
