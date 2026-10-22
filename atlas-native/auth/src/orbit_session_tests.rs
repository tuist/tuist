use super::*;
use crate::tests::registration;

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
        },
    );
    assert_eq!(prepare_send(&mut state, FIRST, "At tap time").unwrap(), key);
    assert_eq!(state.drafts[FIRST].body, "New thought");
    assert_ne!(prepare_send(&mut state, FIRST, "New thought").unwrap(), key);
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
    state.snapshot.selected = Some(thread(FIRST, "private"));
    state.generation = 1;
    assert!(!reconcile_history(
        &mut state,
        history_page(1, vec![message(FIRST, 1, "confidential")]),
        0,
        false
    ));
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
            command: Command::Load
        })
        .is_err()
    );
    execute(Action::Close { connection: id }).unwrap();
}
