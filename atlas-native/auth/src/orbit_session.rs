//! Shared thread state. Platform adapters render snapshots and own only
//! credential persistence, foreground/background notifications and native views.
use crate::orbit::{self, Assistant, Created, History, Message, Overview, Thread};
use crate::orbit_live;
use crate::{Result, Session, error, invalid};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use serde_json::{Value, json};
use std::collections::{BTreeMap, HashMap};
use std::sync::{Arc, Condvar, Mutex, OnceLock};
use std::time::{Duration, Instant};

#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub(crate) enum Action {
    Open {
        session: Session,
    },
    Request {
        connection: String,
        session: Session,
        command: Command,
    },
    Draft {
        connection: String,
        id: String,
        body: String,
    },
    Active {
        connection: String,
        active: bool,
    },
    Next {
        connection: String,
        after: u64,
    },
    #[serde(rename = "component_action")]
    CardEvent {
        connection: String,
        id: String,
        message_id: String,
        event: String,
    },
    Close {
        connection: String,
    },
}

#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum Command {
    Load,
    LoadMore,
    Private,
    Create {
        title: String,
        participant_ids: Vec<String>,
    },
    Select {
        id: String,
    },
    Leave {
        id: String,
    },
    History {
        older: bool,
    },
    Send {
        id: String,
        body: String,
        address_agent: bool,
    },
    Refresh,
    Active {
        active: bool,
    },
}

#[derive(Default, Serialize)]
struct Snapshot {
    sequence: u64,
    assistant: Option<Assistant>,
    threads: Vec<Thread>,
    selected: Option<Thread>,
    messages: Vec<Message>,
    people: Vec<Viewer>,
    draft: String,
    loading: bool,
    history_loading: bool,
    saving: bool,
    has_more: bool,
    has_older: bool,
    error: Option<String>,
    live_message: Option<String>,
    needs_session: bool,
}

#[derive(Deserialize, Serialize)]
struct Viewer {
    id: String,
    name: String,
    typing: bool,
}

struct Draft {
    body: String,
    client_id: String,
}

struct State {
    snapshot: Snapshot,
    session: Session,
    drafts: BTreeMap<String, Draft>,
    outbox: BTreeMap<String, Draft>,
    generation: u64,
    list_page: u32,
    list_pending: bool,
    history_page: u32,
    history_pending: bool,
    live: Option<String>,
    active: bool,
    closed: bool,
    last_typing: Option<Instant>,
}

struct Model {
    state: Mutex<State>,
    changed: Condvar,
}

fn models() -> &'static Mutex<HashMap<String, Arc<Model>>> {
    static MODELS: OnceLock<Mutex<HashMap<String, Arc<Model>>>> = OnceLock::new();
    MODELS.get_or_init(Default::default)
}

pub(crate) fn execute(action: Action) -> Result<Value> {
    match action {
        Action::Open { session } => {
            crate::validate_registration(&session.registration)?;
            if session.expires_at <= crate::now() || session.access_token.is_empty() {
                return Err(error("sign_in_required", "Sign in to Atlas again."));
            }
            let connection = random_id()?;
            let model = Arc::new(Model {
                state: Mutex::new(State {
                    snapshot: Snapshot::default(),
                    session,
                    drafts: BTreeMap::new(),
                    outbox: BTreeMap::new(),
                    generation: 0,
                    list_page: 0,
                    list_pending: false,
                    history_page: 0,
                    history_pending: false,
                    live: None,
                    active: false,
                    closed: false,
                    last_typing: None,
                }),
                changed: Condvar::new(),
            });
            let mut models = models().lock().map_err(|_| invalid())?;
            if models.len() >= 8 {
                return Err(error("internal", "Too many thread sessions."));
            }
            models.insert(connection.clone(), model);
            Ok(json!({"connection":connection}))
        }
        Action::Request {
            connection,
            session,
            command,
        } => {
            let model = get(&connection)?;
            {
                let mut state = model.state.lock().map_err(|_| invalid())?;
                if session.registration.server != state.session.registration.server
                    || session.registration.client_id != state.session.registration.client_id
                {
                    return Err(invalid());
                }
                state.session = session;
            }
            perform(&model, command)?;
            snapshot(&model)
        }
        Action::Draft {
            connection,
            id,
            body,
        } => {
            let model = get(&connection)?;
            draft(&model, id, body)?;
            snapshot(&model)
        }
        Action::Active { connection, active } => {
            let model = get(&connection)?;
            set_active(&model, active)?;
            snapshot(&model)
        }
        Action::Next { connection, after } => {
            let model = get(&connection)?;
            let state = model.state.lock().map_err(|_| invalid())?;
            let (state, _) = model
                .changed
                .wait_timeout_while(state, Duration::from_secs(30), |state| {
                    state.snapshot.sequence <= after && !state.closed
                })
                .map_err(|_| invalid())?;
            serde_json::to_value(&state.snapshot).map_err(|_| invalid())
        }
        Action::CardEvent {
            connection,
            id,
            message_id,
            event,
        } => {
            let model = get(&connection)?;
            let state = model.state.lock().map_err(|_| invalid())?;
            if state.closed
                || !state.active
                || state.snapshot.needs_session
                || state
                    .snapshot
                    .selected
                    .as_ref()
                    .map(|item| item.id.as_str())
                    != Some(id.as_str())
            {
                return Err(invalid());
            }
            let allowed = state.snapshot.messages.iter().any(|message| {
                message.id == message_id
                    && message.kind == "tool"
                    && message.tool_status.as_deref() == Some("succeeded")
                    && message
                        .component
                        .as_ref()
                        .is_some_and(|card| card.allows(&event))
            });
            if !allowed {
                return Err(invalid());
            }
            Ok(json!({"effect":"show_evidence","thread_id":id,"message_id":message_id}))
        }
        Action::Close { connection } => {
            if let Some(model) = models().lock().map_err(|_| invalid())?.remove(&connection) {
                let live = {
                    let mut state = model.state.lock().map_err(|_| invalid())?;
                    state.closed = true;
                    state.generation += 1;
                    state.drafts.clear();
                    state.outbox.clear();
                    state.snapshot = Snapshot::default();
                    publish(&model, &mut state);
                    state.live.take()
                };
                close_live(live);
            }
            Ok(json!({"closed":true}))
        }
    }
}

fn get(id: &str) -> Result<Arc<Model>> {
    models()
        .lock()
        .map_err(|_| invalid())?
        .get(id)
        .cloned()
        .ok_or_else(|| error("closed", "This Orbit session is closed."))
}

fn snapshot(model: &Model) -> Result<Value> {
    serde_json::to_value(&model.state.lock().map_err(|_| invalid())?.snapshot)
        .map_err(|_| invalid())
}

fn publish(model: &Model, state: &mut State) {
    state.snapshot.draft = state
        .snapshot
        .selected
        .as_ref()
        .and_then(|item| state.drafts.get(&item.id))
        .map(|draft| draft.body.clone())
        .unwrap_or_default();
    state.snapshot.sequence += 1;
    model.changed.notify_all();
}

fn api<T: DeserializeOwned>(session: Session, action: orbit::Action) -> Result<T> {
    orbit::request(session, action)
}

fn perform(model: &Arc<Model>, command: Command) -> Result<()> {
    match command {
        Command::Load | Command::LoadMore => load(model, matches!(command, Command::LoadMore)),
        Command::Private | Command::Create { .. } => {
            let (session, action) = {
                let mut state = model.state.lock().map_err(|_| invalid())?;
                if state.snapshot.loading {
                    return Err(error(
                        "busy",
                        "Wait for the current thread request to finish.",
                    ));
                }
                state.snapshot.loading = true;
                publish(model, &mut state);
                let action = match command {
                    Command::Create {
                        title,
                        participant_ids,
                    } => orbit::Action::Create {
                        title,
                        participant_ids,
                    },
                    _ => orbit::Action::Private,
                };
                (state.session.clone(), action)
            };
            let result = api::<Created>(session, action);
            let selected = {
                let mut state = model.state.lock().map_err(|_| invalid())?;
                state.snapshot.loading = false;
                if state.closed {
                    return Ok(());
                }
                let selected = match result {
                    Ok(value) => {
                        let id = value.thread.id.clone();
                        merge_thread(&mut state.snapshot.threads, value.thread);
                        state.snapshot.error = None;
                        Some(id)
                    }
                    Err(failure) => {
                        note_failure(&mut state, failure);
                        None
                    }
                };
                publish(model, &mut state);
                selected
            };
            if let Some(id) = selected {
                select(model, Some(id), None)?;
            }
            Ok(())
        }
        Command::Select { id } => {
            crate::time_off::validate_id(&id)?;
            select(model, Some(id), None)
        }
        Command::Leave { id } => {
            select(model, None, Some(id))?;
            start_live(model)
        }
        Command::History { older } => history(model, older),
        Command::Send {
            id,
            body,
            address_agent,
        } => send(model, id, body, address_agent),
        Command::Active { active } => set_active(model, active),
        Command::Refresh => {
            let live = {
                let mut state = model.state.lock().map_err(|_| invalid())?;
                state.snapshot.needs_session = false;
                let live = state.live.take();
                publish(model, &mut state);
                live
            };
            close_live(live);
            if model
                .state
                .lock()
                .map_err(|_| invalid())?
                .snapshot
                .selected
                .is_some()
            {
                history(model, false)?;
            } else {
                load(model, false)?;
            }
            start_live(model)
        }
    }
}

fn load(model: &Arc<Model>, more: bool) -> Result<()> {
    let (session, page) = {
        let mut state = model.state.lock().map_err(|_| invalid())?;
        if state.closed {
            return Ok(());
        }
        if state.snapshot.loading {
            state.list_pending |= !more;
            return Ok(());
        }
        state.snapshot.loading = true;
        publish(model, &mut state);
        (
            state.session.clone(),
            if more { state.list_page + 1 } else { 1 },
        )
    };
    let result = api::<Overview>(session, orbit::Action::List { page });
    let mut state = model.state.lock().map_err(|_| invalid())?;
    state.snapshot.loading = false;
    if state.closed {
        return Ok(());
    }
    match result {
        Ok(value) => {
            state.snapshot.assistant = Some(value.assistant);
            if !more {
                state.snapshot.threads.clear();
            }
            for item in value.threads.items {
                merge_thread(&mut state.snapshot.threads, item);
            }
            state.list_page = value.threads.page;
            state.snapshot.has_more = state.list_page < value.threads.total_pages;
            state.snapshot.error = None;
        }
        Err(failure) => {
            if failure.kind == "unavailable" {
                state.snapshot.threads.clear();
            }
            note_failure(&mut state, failure);
        }
    }
    let pending = state.list_pending;
    state.list_pending = false;
    publish(model, &mut state);
    drop(state);
    if pending {
        load(model, false)?;
    }
    Ok(())
}

fn merge_thread(items: &mut Vec<Thread>, incoming: Thread) {
    items.retain(|item| item.id != incoming.id);
    items.push(incoming);
    items.sort_by(|a, b| {
        (b.kind == "private")
            .cmp(&(a.kind == "private"))
            .then_with(|| b.updated_at.cmp(&a.updated_at))
            .then_with(|| a.id.cmp(&b.id))
    });
}

fn select(model: &Arc<Model>, id: Option<String>, expected: Option<String>) -> Result<()> {
    let live = {
        let mut state = model.state.lock().map_err(|_| invalid())?;
        if state.closed
            || expected.as_ref().is_some_and(|id| {
                state
                    .snapshot
                    .selected
                    .as_ref()
                    .is_none_or(|selected| &selected.id != id)
            })
        {
            return Ok(());
        }
        let selected = match id {
            Some(id) => Some(
                state
                    .snapshot
                    .threads
                    .iter()
                    .find(|item| item.id == id)
                    .cloned()
                    .ok_or_else(invalid)?,
            ),
            None => None,
        };
        state.generation += 1;
        state.snapshot.selected = selected;
        state.snapshot.messages.clear();
        state.snapshot.people.clear();
        state.snapshot.error = None;
        state.snapshot.live_message = None;
        state.snapshot.has_older = false;
        state.history_page = 0;
        state.snapshot.history_loading = false;
        state.history_pending = false;
        publish(model, &mut state);
        state.live.take()
    };
    close_live(live);
    history(model, false)?;
    start_live(model)
}

fn history(model: &Arc<Model>, older: bool) -> Result<()> {
    let (session, id, page, generation) = {
        let mut state = model.state.lock().map_err(|_| invalid())?;
        if state.closed {
            return Ok(());
        }
        let Some(id) = state.snapshot.selected.as_ref().map(|item| item.id.clone()) else {
            return Ok(());
        };
        if state.snapshot.history_loading {
            state.history_pending |= !older;
            return Ok(());
        }
        state.snapshot.history_loading = true;
        publish(model, &mut state);
        (
            state.session.clone(),
            id,
            if older { state.history_page + 1 } else { 1 },
            state.generation,
        )
    };
    let result = api::<History>(
        session,
        orbit::Action::Messages {
            id: id.clone(),
            page,
        },
    );
    let (pending, live) = {
        let mut state = model.state.lock().map_err(|_| invalid())?;
        if state.generation != generation || state.closed {
            return Ok(());
        }
        state.snapshot.history_loading = false;
        let mut live = None;
        match result {
            Ok(value) => {
                if !reconcile_history(&mut state, value, generation, older) {
                    state.snapshot.error = Some("Atlas returned a different thread.".into());
                }
            }
            Err(failure) => {
                if failure.kind == "unavailable" {
                    revoke(&mut state, &id);
                    live = state.live.take();
                }
                note_failure(&mut state, failure);
            }
        }
        let pending = state.history_pending;
        state.history_pending = false;
        publish(model, &mut state);
        (pending, live)
    };
    close_live(live);
    if pending {
        history(model, false)?;
    }
    Ok(())
}

fn reconcile_history(state: &mut State, value: History, generation: u64, older: bool) -> bool {
    if state.closed
        || state.generation != generation
        || state
            .snapshot
            .selected
            .as_ref()
            .is_none_or(|item| item.id != value.thread.id)
    {
        return false;
    }
    merge_thread(&mut state.snapshot.threads, value.thread.clone());
    state.snapshot.selected = Some(value.thread);
    let disconnected_page = !older
        && !state.snapshot.messages.is_empty()
        && !value.messages.items.is_empty()
        && !value.messages.items.iter().any(|incoming| {
            state
                .snapshot
                .messages
                .iter()
                .any(|known| known.id == incoming.id)
        });
    if disconnected_page {
        state.snapshot.messages.clear();
        state.history_page = 0;
    }
    for message in value.messages.items {
        state
            .snapshot
            .messages
            .retain(|known| known.id != message.id);
        state.snapshot.messages.push(message);
    }
    state
        .snapshot
        .messages
        .sort_by(|a, b| (a.seq, &a.inserted_at, &a.id).cmp(&(b.seq, &b.inserted_at, &b.id)));
    if older || state.history_page == 0 {
        state.history_page = value.messages.page;
    }
    state.snapshot.has_older = state.history_page < value.messages.total_pages;
    state.snapshot.error = None;
    true
}

fn send(model: &Arc<Model>, expected_id: String, body: String, address_agent: bool) -> Result<()> {
    if body.trim().is_empty() || body.len() > 16000 {
        return Err(error("invalid_request", "Check the message and try again."));
    }
    let (session, id, body, client_id, address_agent, generation) = {
        let mut state = model.state.lock().map_err(|_| invalid())?;
        if state.snapshot.saving || state.closed {
            return Ok(());
        }
        let Some(selected) = &state.snapshot.selected else {
            return Ok(());
        };
        let id = selected.id.clone();
        if id != expected_id {
            return Ok(());
        }
        let address_agent = selected.kind == "private" || address_agent;
        let client_id = prepare_send(&mut state, &id, &body)?;
        let result = (
            state.session.clone(),
            id,
            body,
            client_id,
            address_agent,
            state.generation,
        );
        state.snapshot.saving = true;
        publish(model, &mut state);
        result
    };
    let result = orbit::request::<orbit::Sent>(
        session,
        orbit::Action::Send {
            id: id.clone(),
            body,
            client_id: client_id.clone(),
            address_agent,
        },
    );
    let (refresh, typing) = {
        let mut state = model.state.lock().map_err(|_| invalid())?;
        state.snapshot.saving = false;
        if state.closed {
            return Ok(());
        }
        let success = result.is_ok();
        match result {
            Ok(_) => {
                if state.generation == generation {
                    state.snapshot.error = None;
                }
                if state
                    .drafts
                    .get(&id)
                    .is_some_and(|draft| draft.client_id == client_id)
                {
                    state.drafts.remove(&id);
                }
            }
            Err(failure) => {
                if state.generation == generation {
                    note_failure(&mut state, failure);
                }
            }
        }
        let current = state.generation == generation;
        let typing = if success && current && !state.drafts.contains_key(&id) {
            state.live.clone()
        } else {
            None
        };
        publish(model, &mut state);
        (success && current, typing)
    };
    if let Some(connection) = typing {
        let _ = orbit_live::execute(orbit_live::Action::Typing {
            connection,
            typing: false,
        });
    }
    if refresh {
        history(model, false)?;
    }
    Ok(())
}

fn note_failure(state: &mut State, failure: crate::AuthError) {
    if failure.kind == "sign_in_required" {
        state.snapshot.needs_session = true;
    }
    state.snapshot.error = Some(failure.message.into());
}

fn revoke(state: &mut State, id: &str) {
    state.snapshot.messages.clear();
    state.snapshot.people.clear();
    state.snapshot.threads.retain(|item| item.id != id);
    state.snapshot.selected = None;
    state.snapshot.history_loading = false;
    state.history_pending = false;
    state.drafts.remove(id);
    state.outbox.remove(id);
    state.generation += 1;
}

fn prepare_send(state: &mut State, id: &str, body: &str) -> Result<String> {
    let client_id = if let Some(draft) = state.drafts.get(id).filter(|draft| draft.body == body) {
        draft.client_id.clone()
    } else if let Some(attempt) = state.outbox.get(id).filter(|attempt| attempt.body == body) {
        return Ok(attempt.client_id.clone());
    } else {
        random_uuid()?
    };
    state.outbox.insert(
        id.into(),
        Draft {
            body: body.into(),
            client_id: client_id.clone(),
        },
    );
    Ok(client_id)
}

fn draft(model: &Model, id: String, body: String) -> Result<()> {
    crate::time_off::validate_id(&id)?;
    if body.len() > 16000 {
        return Err(error(
            "invalid_request",
            "Messages must be at most 16,000 bytes.",
        ));
    }
    let typing = {
        let mut state = model.state.lock().map_err(|_| invalid())?;
        let selected = state
            .snapshot
            .selected
            .as_ref()
            .is_some_and(|item| item.id == id);
        if state.closed || (!selected && !state.snapshot.threads.iter().any(|item| item.id == id)) {
            return Ok(());
        }
        if state.drafts.get(&id).is_none_or(|draft| draft.body != body) {
            state.drafts.insert(
                id,
                Draft {
                    body: body.clone(),
                    client_id: random_uuid()?,
                },
            );
        }
        let typing = if selected
            && (body.is_empty()
                || state
                    .last_typing
                    .is_none_or(|last| last.elapsed() > Duration::from_secs(4)))
        {
            state.last_typing = Some(Instant::now());
            state
                .live
                .clone()
                .map(|connection| (connection, !body.is_empty()))
        } else {
            None
        };
        publish(model, &mut state);
        typing
    };
    if let Some((connection, typing)) = typing {
        let _ = orbit_live::execute(orbit_live::Action::Typing { connection, typing });
    }
    Ok(())
}

fn set_active(model: &Arc<Model>, active: bool) -> Result<()> {
    let live = {
        let mut state = model.state.lock().map_err(|_| invalid())?;
        state.active = active;
        state.snapshot.people.clear();
        let live = if active { None } else { state.live.take() };
        publish(model, &mut state);
        live
    };
    close_live(live);
    if active {
        start_live(model)?;
    }
    Ok(())
}

fn start_live(model: &Arc<Model>) -> Result<()> {
    let mut state = model.state.lock().map_err(|_| invalid())?;
    if !state.active || state.closed || state.live.is_some() {
        return Ok(());
    }
    let is_list = state.snapshot.selected.is_none();
    let action = match &state.snapshot.selected {
        Some(item) => orbit_live::Action::Open {
            session: state.session.clone(),
            id: item.id.clone(),
        },
        None => orbit_live::Action::OpenList {
            session: state.session.clone(),
        },
    };
    let opened = match orbit_live::execute(action) {
        Ok(opened) => opened,
        Err(failure) if failure.kind == "sign_in_required" => {
            state.snapshot.needs_session = true;
            publish(model, &mut state);
            return Ok(());
        }
        Err(failure) => return Err(failure),
    };
    let connection = opened["connection"]
        .as_str()
        .ok_or_else(invalid)?
        .to_owned();
    state.live = Some(connection.clone());
    let generation = state.generation;
    let model = model.clone();
    std::thread::spawn(move || live_loop(model, connection, generation, is_list));
    Ok(())
}

fn live_loop(model: Arc<Model>, connection: String, generation: u64, is_list: bool) {
    let mut sequence = 0;
    let mut revision = None;
    loop {
        let result = orbit_live::execute(orbit_live::Action::Next {
            connection: connection.clone(),
            after: sequence,
        });
        let (refresh, stop) = {
            let Ok(mut state) = model.state.lock() else {
                break;
            };
            if state.closed
                || !state.active
                || state.generation != generation
                || state.live.as_deref() != Some(&connection)
            {
                break;
            }
            let Ok(value) = result else {
                break;
            };
            sequence = value["sequence"].as_u64().unwrap_or(sequence);
            if value["needs_session"] == true {
                state.snapshot.needs_session = true;
                state.snapshot.people.clear();
                publish(&model, &mut state);
                break;
            }
            let refresh = if let Some(failure) = value["error"].as_str() {
                state.snapshot.people.clear();
                state.snapshot.live_message = Some(
                    if failure == "unavailable" {
                        "This thread is no longer available."
                    } else {
                        "Reconnecting…"
                    }
                    .into(),
                );
                if failure == "unavailable" && !is_list {
                    if let Some(id) = state.snapshot.selected.as_ref().map(|item| item.id.clone()) {
                        revoke(&mut state, &id);
                    }
                    state.snapshot.error = Some("This thread is no longer available.".into());
                }
                false
            } else {
                state.snapshot.people =
                    serde_json::from_value(value["people"].clone()).unwrap_or_default();
                state.snapshot.live_message = None;
                let next = value["revision"].as_u64();
                let changed = next != revision;
                revision = next;
                changed
            };
            let stop = value["error"] == "unavailable";
            publish(&model, &mut state);
            (refresh, stop)
        };
        if stop {
            break;
        }
        if refresh {
            if is_list {
                let _ = load(&model, false);
            } else {
                let _ = history(&model, false);
            }
        }
    }
    close_live(Some(connection.clone()));
    if let Ok(mut state) = model.state.lock()
        && state.live.as_deref() == Some(&connection)
    {
        state.live = None;
    }
}

fn close_live(connection: Option<String>) {
    if let Some(connection) = connection {
        let _ = orbit_live::execute(orbit_live::Action::Close { connection });
    }
}

fn random_id() -> Result<String> {
    let mut bytes = [0_u8; 16];
    getrandom::fill(&mut bytes).map_err(|_| invalid())?;
    Ok(bytes.iter().map(|byte| format!("{byte:02x}")).collect())
}

fn random_uuid() -> Result<String> {
    let id = random_id()?;
    Ok(format!(
        "{}-{}-{}-{}-{}",
        &id[..8],
        &id[8..12],
        &id[12..16],
        &id[16..20],
        &id[20..]
    ))
}

#[cfg(test)]
#[path = "orbit_session_tests.rs"]
mod tests;
