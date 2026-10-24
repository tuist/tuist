//! Shared thread state. Platform adapters render snapshots and own only
//! credential persistence, foreground/background notifications and native views.
use crate::orbit::{
    self, Assistant, Attachment, Created, History, Message, Overview, Person, Thread,
};
use crate::orbit_live;
use crate::transport::{Network, Transport};
use crate::{Result, Session, error, invalid};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
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
    Mention {
        connection: String,
        id: String,
        user_id: String,
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
    Load {
        #[serde(default)]
        kind: Option<String>,
    },
    LoadMore,
    Private,
    CreatePrivate,
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
    People {
        id: String,
        query: String,
    },
    Send {
        id: String,
        body: String,
        address_agent: bool,
        #[serde(default)]
        attachment_ids: Option<Vec<String>>,
        #[serde(default)]
        mention_ids: Option<Vec<String>>,
    },
    UploadAttachment {
        id: String,
        #[serde(default)]
        client_id: Option<String>,
        filename: String,
        content_type: String,
        data: String,
    },
    DeleteAttachment {
        id: String,
        attachment_id: String,
    },
    DownloadAttachment {
        id: String,
        attachment_id: String,
    },
    DiscardUpload {
        id: String,
    },
    RetryUpload {
        id: String,
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
    // An untrusted navigation target, not thread metadata or permission to mutate.
    selection_id: Option<String>,
    selected: Option<Thread>,
    messages: Vec<Message>,
    people: Vec<Viewer>,
    draft: String,
    draft_attachments: Vec<Attachment>,
    draft_mentions: Vec<Person>,
    mention_candidates: Vec<Person>,
    mention_loading: bool,
    mention_error: Option<String>,
    attachment_busy: bool,
    upload_pending: bool,
    upload_filename: Option<String>,
    has_drafts: bool,
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

#[derive(Clone, Default)]
struct Draft {
    body: String,
    client_id: String,
    attachments: Vec<Attachment>,
    mentions: Vec<Person>,
}

struct UploadAttempt {
    thread_id: String,
    client_id: String,
    digest: Vec<u8>,
    filename: String,
    content_type: String,
    data: String,
}

struct State {
    snapshot: Snapshot,
    session: Session,
    drafts: BTreeMap<String, Draft>,
    outbox: BTreeMap<String, Draft>,
    generation: u64,
    access_generation: u64,
    list_page: u32,
    list_kind: Option<String>,
    list_pending: bool,
    history_page: u32,
    history_pending: bool,
    live: Option<String>,
    active: bool,
    closed: bool,
    last_typing: Option<Instant>,
    lifecycle: u64,
    upload_attempt: Option<UploadAttempt>,
    private_request_id: Option<String>,
    mention_query: Option<String>,
    mention_generation: u64,
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
                    access_generation: 0,
                    list_page: 0,
                    list_kind: None,
                    list_pending: false,
                    history_page: 0,
                    history_pending: false,
                    live: None,
                    active: false,
                    closed: false,
                    last_typing: None,
                    lifecycle: 0,
                    upload_attempt: None,
                    private_request_id: None,
                    mention_query: None,
                    mention_generation: 0,
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
            if let Command::DownloadAttachment { id, attachment_id } = command {
                return download_using(&model, id, attachment_id, &Network);
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
        Action::Mention {
            connection,
            id,
            user_id,
        } => {
            let model = get(&connection)?;
            mention(&model, id, user_id)?;
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
                    state.upload_attempt = None;
                    state.private_request_id = None;
                    state.mention_query = None;
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
    let pending = state.upload_attempt.as_ref().filter(|attempt| {
        state
            .snapshot
            .selected
            .as_ref()
            .is_some_and(|item| item.id == attempt.thread_id)
    });
    state.snapshot.upload_pending = pending.is_some();
    state.snapshot.upload_filename = pending.map(|attempt| attempt.filename.clone());
    state.snapshot.draft_attachments = state
        .snapshot
        .selected
        .as_ref()
        .and_then(|item| state.drafts.get(&item.id))
        .map(|draft| draft.attachments.clone())
        .unwrap_or_default();
    state.snapshot.draft_mentions = state
        .snapshot
        .selected
        .as_ref()
        .and_then(|item| state.drafts.get(&item.id))
        .map(|draft| draft.mentions.clone())
        .unwrap_or_default();
    state.snapshot.draft = state
        .snapshot
        .selected
        .as_ref()
        .and_then(|item| state.drafts.get(&item.id))
        .map(|draft| draft.body.clone())
        .unwrap_or_default();
    state.snapshot.has_drafts = state
        .drafts
        .values()
        .any(|draft| !draft.body.trim().is_empty() || !draft.attachments.is_empty())
        || state.upload_attempt.is_some()
        || state.snapshot.attachment_busy;
    state.snapshot.sequence += 1;
    model.changed.notify_all();
}

fn perform(model: &Arc<Model>, command: Command) -> Result<()> {
    match command {
        Command::Load { kind } => {
            set_list_kind(model, kind)?;
            load(model, false)
        }
        Command::LoadMore => load(model, true),
        command @ (Command::Private | Command::CreatePrivate | Command::Create { .. }) => {
            create_using(model, command, &Network)
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
        Command::People { id, query } => people_using(model, id, query, &Network),
        Command::Send {
            id,
            body,
            address_agent,
            attachment_ids,
            mention_ids,
        } => send_using(
            model,
            id,
            body,
            attachment_ids,
            mention_ids,
            address_agent,
            &Network,
        ),
        command @ Command::UploadAttachment { .. } => upload_using(model, command, &Network),
        Command::DeleteAttachment { id, attachment_id } => {
            delete_using(model, id, attachment_id, &Network)
        }
        Command::DownloadAttachment { .. } => Err(invalid()),
        Command::RetryUpload { id } => retry_upload_using(model, id, &Network),
        Command::DiscardUpload { id } => {
            let mut state = model.state.lock().map_err(|_| invalid())?;
            attachment_access(&state, &id, true)?;
            if state.snapshot.attachment_busy {
                return Err(error("busy", "Wait for the attachment request to finish."));
            }
            if state
                .upload_attempt
                .as_ref()
                .is_some_and(|attempt| attempt.thread_id == id)
            {
                state.upload_attempt = None;
                state.snapshot.error = None;
            }
            publish(model, &mut state);
            Ok(())
        }
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
                .selection_id
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

fn create_using(model: &Arc<Model>, command: Command, network: &impl Transport) -> Result<()> {
    let new_private = matches!(command, Command::CreatePrivate);
    let (session, preflight, generation, access_generation) = {
        let mut state = model.state.lock().map_err(|_| invalid())?;
        if state.closed {
            return Ok(());
        }
        if state.snapshot.loading || state.snapshot.saving || state.snapshot.history_loading {
            return Err(error(
                "busy",
                "Wait for the current thread request to finish.",
            ));
        }
        let preflight = (new_private
            && !state
                .snapshot
                .assistant
                .as_ref()
                .is_some_and(|assistant| assistant.can_create_private))
        .then(|| orbit::Action::List {
            page: 1,
            kind: state.list_kind.clone(),
        });
        state.snapshot.loading = true;
        state.snapshot.error = None;
        publish(model, &mut state);
        (
            state.session.clone(),
            preflight,
            state.generation,
            state.access_generation,
        )
    };
    let result = (|| {
        if let Some(action) = preflight {
            let overview = orbit::request_using::<Overview>(network, session.clone(), action)?;
            let mut state = model.state.lock().map_err(|_| invalid())?;
            if state.closed
                || state.generation != generation
                || state.access_generation != access_generation
            {
                return Ok(None);
            }
            let supported = overview.assistant.can_create_private;
            state.snapshot.assistant = Some(overview.assistant);
            if !supported {
                return Err(error(
                    "unsupported",
                    "This Atlas server does not support new private conversations yet. Update the server, then try again.",
                ));
            }
        }
        let action = match command {
            Command::CreatePrivate => {
                let mut state = model.state.lock().map_err(|_| invalid())?;
                if state.closed
                    || state.generation != generation
                    || state.access_generation != access_generation
                {
                    return Ok(None);
                }
                let request_id = match &state.private_request_id {
                    Some(id) => id.clone(),
                    None => random_uuid()?,
                };
                state.private_request_id = Some(request_id.clone());
                orbit::Action::CreatePrivate { request_id }
            }
            Command::Create {
                title,
                participant_ids,
            } => orbit::Action::Create {
                title,
                participant_ids,
            },
            Command::Private => orbit::Action::Private,
            _ => return Err(invalid()),
        };
        let value = orbit::request_using::<Created>(network, session, action)?;
        crate::time_off::validate_id(&value.thread.id)?;
        if new_private && value.thread.kind != "private" {
            return Err(invalid());
        }
        Ok(Some(value))
    })();
    let (selected, live) = {
        let mut state = model.state.lock().map_err(|_| invalid())?;
        state.snapshot.loading = false;
        if state.closed {
            return Ok(());
        }
        let current =
            state.generation == generation && state.access_generation == access_generation;
        let selected = match result {
            Ok(Some(value)) => {
                if new_private {
                    state.private_request_id = None;
                }
                let id = value.thread.id.clone();
                if state.access_generation == access_generation {
                    merge_thread(&mut state.snapshot.threads, value.thread);
                }
                if current {
                    state.snapshot.error = None;
                }
                current.then_some(id)
            }
            Ok(None) => None,
            Err(failure) => {
                // A timeout or invalid response may have committed. Replay the exact UUID next time.
                if current {
                    note_failure(&mut state, failure);
                }
                None
            }
        };
        let live = selected
            .as_ref()
            .and_then(|id| begin_selection(&mut state, Some(id.clone())));
        publish(model, &mut state);
        (selected.is_some(), live)
    };
    close_live(live);
    if selected {
        history_using(model, false, network)?;
        start_live(model)?;
    }
    Ok(())
}

fn set_list_kind(model: &Arc<Model>, kind: Option<String>) -> Result<()> {
    if kind
        .as_deref()
        .is_some_and(|kind| !matches!(kind, "private" | "shared"))
    {
        return Err(invalid());
    }
    let mut state = model.state.lock().map_err(|_| invalid())?;
    if state.list_kind != kind {
        clear_candidates(&mut state);
        state.list_kind = kind;
        state.list_page = 0;
        state.access_generation += 1;
        state.snapshot.threads.clear();
        state.snapshot.has_more = false;
    }
    Ok(())
}

fn load(model: &Arc<Model>, more: bool) -> Result<()> {
    load_using(model, more, &Network)
}

fn load_using(model: &Arc<Model>, more: bool, network: &impl Transport) -> Result<()> {
    let (session, page, kind, access_generation) = {
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
            state.list_kind.clone(),
            state.access_generation,
        )
    };
    let result =
        orbit::request_using::<Overview>(network, session, orbit::Action::List { page, kind });
    let mut state = model.state.lock().map_err(|_| invalid())?;
    state.snapshot.loading = false;
    if state.closed {
        return Ok(());
    }
    if state.access_generation != access_generation {
        let pending = state.list_pending;
        state.list_pending = false;
        publish(model, &mut state);
        drop(state);
        if pending {
            load_using(model, false, network)?;
        }
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
            if state.snapshot.selection_id.is_none() {
                state.snapshot.error = None;
            }
        }
        Err(failure) => {
            if failure.kind == "unavailable" {
                state.snapshot.threads.clear();
            }
            if state.snapshot.selection_id.is_none() {
                note_failure(&mut state, failure);
            }
        }
    }
    let pending = state.list_pending;
    state.list_pending = false;
    publish(model, &mut state);
    drop(state);
    if pending {
        load_using(model, false, network)?;
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
    select_using(model, id, expected, &Network)
}

fn select_using(
    model: &Arc<Model>,
    id: Option<String>,
    expected: Option<String>,
    network: &impl Transport,
) -> Result<()> {
    let live = {
        let mut state = model.state.lock().map_err(|_| invalid())?;
        if state.closed
            || expected.as_ref().is_some_and(|id| {
                state
                    .snapshot
                    .selection_id
                    .as_ref()
                    .is_none_or(|selected| selected != id)
            })
        {
            return Ok(());
        }
        let live = begin_selection(&mut state, id);
        publish(model, &mut state);
        live
    };
    close_live(live);
    history_using(model, false, network)?;
    start_live(model)
}

fn begin_selection(state: &mut State, id: Option<String>) -> Option<String> {
    state.generation += 1;
    clear_candidates(state);
    state.snapshot.selection_id = id;
    state.snapshot.selected = None;
    state.snapshot.messages.clear();
    state.snapshot.people.clear();
    state.snapshot.error = None;
    state.snapshot.live_message = None;
    state.snapshot.has_older = false;
    state.history_page = 0;
    state.snapshot.history_loading = false;
    state.history_pending = false;
    state.live.take()
}

fn clear_candidates(state: &mut State) {
    state.mention_generation += 1;
    state.mention_query = None;
    state.snapshot.mention_candidates.clear();
    state.snapshot.mention_loading = false;
    state.snapshot.mention_error = None;
}

fn mention_access(state: &State, id: &str) -> bool {
    !state.closed
        && state.active
        && !state.snapshot.needs_session
        && state.snapshot.selection_id.as_deref() == Some(id)
        && state
            .snapshot
            .selected
            .as_ref()
            .is_some_and(|item| item.id == id && item.status != "archived")
}

fn trailing_mention(body: &str) -> Option<(usize, &str)> {
    let at = body.rfind('@')?;
    if at > 0 && !body[..at].ends_with(char::is_whitespace) {
        return None;
    }
    let query = &body[at + 1..];
    orbit::validate_people_query(query).ok()?;
    Some((at, query))
}

fn has_mention(body: &str, name: &str) -> bool {
    let token = format!("@{name}");
    body.match_indices(&token).any(|(at, _)| {
        (at == 0 || body[..at].ends_with(char::is_whitespace))
            && body[at + token.len()..]
                .chars()
                .next()
                .is_none_or(|next| !next.is_alphanumeric() && next != '_')
    })
}

fn people_using(
    model: &Arc<Model>,
    id: String,
    query: String,
    network: &impl Transport,
) -> Result<()> {
    crate::time_off::validate_id(&id)?;
    orbit::validate_people_query(&query)?;
    let (session, generation, access_generation, mention_generation, lifecycle) = {
        let mut state = model.state.lock().map_err(|_| invalid())?;
        if !mention_access(&state, &id)
            || state
                .drafts
                .get(&id)
                .and_then(|draft| trailing_mention(&draft.body))
                .map(|(_, query)| query)
                != Some(query.as_str())
        {
            return Ok(());
        }
        clear_candidates(&mut state);
        state.mention_query = Some(query.clone());
        state.snapshot.mention_loading = true;
        publish(model, &mut state);
        (
            state.session.clone(),
            state.generation,
            state.access_generation,
            state.mention_generation,
            state.lifecycle,
        )
    };
    let result = orbit::request_using::<orbit::People>(
        network,
        session,
        orbit::Action::People {
            id: id.clone(),
            query: query.clone(),
        },
    );
    let mut state = model.state.lock().map_err(|_| invalid())?;
    if !mention_access(&state, &id)
        || state.generation != generation
        || state.access_generation != access_generation
        || state.mention_generation != mention_generation
        || state.lifecycle != lifecycle
        || state.mention_query.as_deref() != Some(query.as_str())
    {
        return Ok(());
    }
    state.snapshot.mention_loading = false;
    match result {
        Ok(value) => state.snapshot.mention_candidates = value.people,
        Err(failure) => {
            // Older servers have no people route. Only authoritative history can revoke this thread.
            state.snapshot.needs_session |= failure.kind == "sign_in_required";
            state.snapshot.mention_error = Some(failure.message.into());
        }
    }
    publish(model, &mut state);
    Ok(())
}

fn mention(model: &Model, id: String, user_id: String) -> Result<()> {
    crate::time_off::validate_id(&id)?;
    crate::time_off::validate_id(&user_id)?;
    let mut state = model.state.lock().map_err(|_| invalid())?;
    if !mention_access(&state, &id) {
        return Err(invalid());
    }
    let person = state
        .snapshot
        .mention_candidates
        .iter()
        .find(|person| person.id == user_id)
        .cloned()
        .ok_or_else(invalid)?;
    let mut draft = state.drafts.get(&id).cloned().ok_or_else(invalid)?;
    let (at, query) = trailing_mention(&draft.body).ok_or_else(invalid)?;
    if state.mention_query.as_deref() != Some(query) {
        return Err(invalid());
    }
    let body = format!("{}@{} ", &draft.body[..at], person.name);
    if body.len() > 16000 {
        return Err(invalid());
    }
    if !draft.mentions.iter().any(|known| known.id == user_id) {
        if draft.mentions.len() >= 10 {
            return Err(invalid());
        }
        draft.mentions.push(person);
    }
    draft.body = body;
    draft.client_id = random_uuid()?;
    state.drafts.insert(id, draft);
    clear_candidates(&mut state);
    publish(model, &mut state);
    Ok(())
}

fn history(model: &Arc<Model>, older: bool) -> Result<()> {
    history_using(model, older, &Network)
}

fn history_using(model: &Arc<Model>, older: bool, network: &impl Transport) -> Result<()> {
    let (session, id, page, generation) = {
        let mut state = model.state.lock().map_err(|_| invalid())?;
        if state.closed {
            return Ok(());
        }
        let Some(id) = state.snapshot.selection_id.clone() else {
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
    let result = orbit::request_using::<History>(
        network,
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
        history_using(model, false, network)?;
    }
    Ok(())
}

fn reconcile_history(state: &mut State, value: History, generation: u64, older: bool) -> bool {
    if state.closed
        || state.generation != generation
        || state.snapshot.selection_id.as_deref() != Some(value.thread.id.as_str())
        || value.messages.items.iter().any(|message| {
            message.attachments.len() > 4
                || message
                    .attachments
                    .iter()
                    .any(|item| orbit::validate_attachment(item).is_err())
        })
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

fn attachment_access(state: &State, id: &str, write: bool) -> Result<()> {
    if state.closed
        || !state.active
        || state.snapshot.needs_session
        || state
            .snapshot
            .selected
            .as_ref()
            .is_none_or(|item| item.id != id || (write && item.status == "archived"))
    {
        return Err(error(
            "unavailable",
            "Open this thread again to access its attachments.",
        ));
    }
    Ok(())
}

fn retry_upload_using(model: &Arc<Model>, id: String, network: &impl Transport) -> Result<()> {
    let command = {
        let state = model.state.lock().map_err(|_| invalid())?;
        attachment_access(&state, &id, true)?;
        let attempt = state
            .upload_attempt
            .as_ref()
            .filter(|attempt| attempt.thread_id == id)
            .ok_or_else(invalid)?;
        Command::UploadAttachment {
            id,
            client_id: Some(attempt.client_id.clone()),
            filename: attempt.filename.clone(),
            content_type: attempt.content_type.clone(),
            data: attempt.data.clone(),
        }
    };
    upload_using(model, command, network)
}

fn upload_using(model: &Arc<Model>, command: Command, network: &impl Transport) -> Result<()> {
    let Command::UploadAttachment {
        id,
        client_id,
        filename,
        content_type,
        data,
    } = command
    else {
        return Err(invalid());
    };
    if let Some(client_id) = &client_id {
        crate::time_off::validate_id(client_id)?;
    }
    let bytes = orbit::decode_attachment(&data)?;
    orbit::validate_file(&filename, &content_type, bytes.len())?;
    let size = bytes.len();
    let digest = Sha256::digest(
        serde_json::to_vec(&json!([filename, content_type, data])).map_err(|_| invalid())?,
    )
    .to_vec();
    let (session, generation, client_id) = {
        let mut state = model.state.lock().map_err(|_| invalid())?;
        attachment_access(&state, &id, true)?;
        if state.snapshot.attachment_busy || state.snapshot.saving {
            return Err(error("busy", "Wait for the attachment request to finish."));
        }
        if let Some(attempt) = &state.upload_attempt
            && (attempt.thread_id != id
                || client_id
                    .as_ref()
                    .is_some_and(|id| attempt.client_id != *id)
                || attempt.digest != digest)
        {
            return Err(error(
                "conflict",
                "Retry the pending upload before attaching another file.",
            ));
        }
        if state
            .drafts
            .get(&id)
            .is_some_and(|draft| draft.attachments.len() >= 4)
        {
            return Err(invalid());
        }
        let client_id = state
            .upload_attempt
            .as_ref()
            .map(|attempt| attempt.client_id.clone())
            .or(client_id)
            .map_or_else(random_uuid, Ok)?;
        state.upload_attempt = Some(UploadAttempt {
            thread_id: id.clone(),
            client_id: client_id.clone(),
            digest,
            filename: filename.clone(),
            content_type: content_type.clone(),
            data: data.clone(),
        });
        state.snapshot.attachment_busy = true;
        publish(model, &mut state);
        (state.session.clone(), state.generation, client_id)
    };
    let result = orbit::request_using::<orbit::Attached>(
        network,
        session,
        orbit::Action::UploadAttachment {
            id: id.clone(),
            client_id,
            filename: filename.clone(),
            content_type: content_type.clone(),
            data,
        },
    );
    let mut state = model.state.lock().map_err(|_| invalid())?;
    state.snapshot.attachment_busy = false;
    if state.closed {
        return Ok(());
    }
    if state.generation != generation {
        publish(model, &mut state);
        return Ok(());
    }
    match result {
        Ok(value)
            if orbit::validate_attachment(&value.attachment).is_ok()
                && value.attachment.content_type == content_type
                && value.attachment.byte_size == size =>
        {
            let draft = state.drafts.entry(id).or_default();
            if !draft
                .attachments
                .iter()
                .any(|item| item.id == value.attachment.id)
            {
                draft.attachments.push(value.attachment);
            }
            draft.client_id = random_uuid()?;
            state.upload_attempt = None;
            state.snapshot.error = None;
        }
        Ok(_) => {
            state.snapshot.error =
                Some("Atlas returned an invalid attachment. Retry the upload.".into())
        }
        Err(failure) => {
            if failure.kind == "unavailable" {
                revoke(&mut state, &id);
            }
            // Definitively rejected uploads cannot have created a pending file.
            if matches!(failure.kind, "invalid_request" | "unsupported" | "conflict") {
                state.upload_attempt = None;
            }
            note_failure(&mut state, failure);
        }
    }
    publish(model, &mut state);
    Ok(())
}

fn delete_using(
    model: &Arc<Model>,
    id: String,
    attachment_id: String,
    network: &impl Transport,
) -> Result<()> {
    #[derive(Deserialize)]
    struct Deleted {
        deleted: bool,
    }
    let (session, generation) = {
        let mut state = model.state.lock().map_err(|_| invalid())?;
        attachment_access(&state, &id, true)?;
        if state.snapshot.attachment_busy || state.snapshot.saving {
            return Err(error("busy", "Wait for the attachment request to finish."));
        }
        if !state.drafts.get(&id).is_some_and(|draft| {
            draft
                .attachments
                .iter()
                .any(|item| item.id == attachment_id)
        }) {
            return Err(invalid());
        }
        state.snapshot.attachment_busy = true;
        publish(model, &mut state);
        (state.session.clone(), state.generation)
    };
    let result = orbit::request_using::<Deleted>(
        network,
        session,
        orbit::Action::DeleteAttachment {
            id: id.clone(),
            attachment_id: attachment_id.clone(),
        },
    );
    let mut state = model.state.lock().map_err(|_| invalid())?;
    state.snapshot.attachment_busy = false;
    if state.closed {
        return Ok(());
    }
    if state.generation != generation {
        publish(model, &mut state);
        return Ok(());
    }
    match result {
        Ok(value) if value.deleted => {
            if let Some(draft) = state.drafts.get_mut(&id) {
                draft.attachments.retain(|item| item.id != attachment_id);
                draft.client_id = random_uuid()?;
            }
            state.snapshot.error = None;
        }
        Ok(_) => state.snapshot.error = Some("Could not remove the attachment. Try again.".into()),
        Err(failure) => {
            if failure.kind == "unavailable" {
                revoke(&mut state, &id);
            }
            note_failure(&mut state, failure);
        }
    }
    publish(model, &mut state);
    Ok(())
}

fn download_using(
    model: &Arc<Model>,
    id: String,
    attachment_id: String,
    network: &impl Transport,
) -> Result<Value> {
    let (session, generation, lifecycle, expected) = {
        let state = model.state.lock().map_err(|_| invalid())?;
        attachment_access(&state, &id, false)?;
        let expected = state
            .snapshot
            .messages
            .iter()
            .flat_map(|message| &message.attachments)
            .chain(
                state
                    .drafts
                    .get(&id)
                    .into_iter()
                    .flat_map(|draft| &draft.attachments),
            )
            .find(|item| item.id == attachment_id)
            .cloned()
            .ok_or_else(invalid)?;
        (
            state.session.clone(),
            state.generation,
            state.lifecycle,
            expected,
        )
    };
    let result = orbit::request_using::<orbit::Downloaded>(
        network,
        session,
        orbit::Action::DownloadAttachment {
            id: id.clone(),
            attachment_id,
        },
    );
    let mut state = model.state.lock().map_err(|_| invalid())?;
    attachment_access(&state, &id, false)?;
    if state.generation != generation || state.lifecycle != lifecycle {
        return Err(error(
            "unavailable",
            "Open this thread again to access its attachments.",
        ));
    }
    let value = match result {
        Ok(value) => value,
        Err(failure) => {
            if failure.kind == "unavailable" {
                revoke(&mut state, &id);
            }
            let returned = error(failure.kind, failure.message);
            note_failure(&mut state, failure);
            publish(model, &mut state);
            return Err(returned);
        }
    };
    orbit::validate_attachment(&value.attachment.metadata)?;
    let bytes = orbit::decode_attachment(&value.attachment.data)?;
    if value.attachment.metadata != expected || bytes.len() != expected.byte_size {
        return Err(invalid());
    }
    Ok(json!({"thread_id":id,"attachment":value.attachment}))
}

#[cfg(test)]
fn send(model: &Arc<Model>, expected_id: String, body: String, address_agent: bool) -> Result<()> {
    send_using(
        model,
        expected_id,
        body,
        None,
        None,
        address_agent,
        &Network,
    )
}

fn send_using(
    model: &Arc<Model>,
    expected_id: String,
    body: String,
    ids: Option<Vec<String>>,
    mention_ids: Option<Vec<String>>,
    address_agent: bool,
    network: &impl Transport,
) -> Result<()> {
    if body.len() > 16000 {
        return Err(error("invalid_request", "Check the message and try again."));
    }
    crate::time_off::validate_id(&expected_id)?;
    if let Some(ids) = &mention_ids {
        orbit::validate_mention_ids(ids)?;
    }
    let (session, id, body, client_id, attachment_ids, mention_ids, address_agent, generation) = {
        let mut state = model.state.lock().map_err(|_| invalid())?;
        if state
            .upload_attempt
            .as_ref()
            .is_some_and(|attempt| attempt.thread_id == expected_id)
        {
            return Err(error(
                "busy",
                "Finish or discard the pending upload before sending.",
            ));
        }
        if state.snapshot.saving
            || state.snapshot.attachment_busy
            || state.closed
            || state.snapshot.needs_session
        {
            return Ok(());
        }
        let Some(selected) = &state.snapshot.selected else {
            return Ok(());
        };
        let id = selected.id.clone();
        if id != expected_id {
            return Ok(());
        }
        if selected.status == "archived" {
            return Err(invalid());
        }
        let address_agent = selected.kind == "private" || address_agent;
        let attachments = state
            .drafts
            .get(&id)
            .map(|draft| draft.attachments.clone())
            .unwrap_or_default();
        let attachment_ids =
            ids.unwrap_or_else(|| attachments.iter().map(|item| item.id.clone()).collect());
        orbit::validate_attachment_ids(&attachment_ids)?;
        if body.trim().is_empty() && attachment_ids.is_empty() {
            return Err(invalid());
        }
        let known = |key: &String| {
            attachments.iter().any(|item| &item.id == key)
                || state
                    .outbox
                    .get(&id)
                    .is_some_and(|draft| draft.attachments.iter().any(|item| &item.id == key))
        };
        if !attachment_ids.iter().all(known) {
            return Err(invalid());
        }
        let current = state.drafts.get(&id);
        let pending = state.outbox.get(&id);
        let source = current
            .filter(|draft| draft.body == body)
            .or_else(|| pending.filter(|draft| draft.body == body))
            .or(current);
        let mention_ids = mention_ids.unwrap_or_else(|| {
            source
                .map(|draft| {
                    draft
                        .mentions
                        .iter()
                        .filter(|person| has_mention(&body, &person.name))
                        .map(|person| person.id.clone())
                        .collect()
                })
                .unwrap_or_default()
        });
        orbit::validate_mention_ids(&mention_ids)?;
        let mentions = mention_ids
            .iter()
            .map(|id| {
                current
                    .into_iter()
                    .chain(pending)
                    .flat_map(|draft| &draft.mentions)
                    .find(|person| &person.id == id && has_mention(&body, &person.name))
                    .cloned()
                    .ok_or_else(invalid)
            })
            .collect::<Result<Vec<_>>>()?;
        let client_id = prepare_send_draft(&mut state, &id, &body, &attachment_ids, &mentions)?;
        let result = (
            state.session.clone(),
            id,
            body,
            client_id,
            attachment_ids,
            mention_ids,
            address_agent,
            state.generation,
        );
        state.snapshot.saving = true;
        publish(model, &mut state);
        result
    };
    let result = orbit::request_using::<orbit::Sent>(
        network,
        session,
        orbit::Action::Send {
            id: id.clone(),
            body,
            client_id: client_id.clone(),
            address_agent,
            attachment_ids: attachment_ids.clone(),
            mention_ids,
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
                    if state.generation == generation {
                        clear_candidates(&mut state);
                    }
                } else if let Some(draft) = state.drafts.get_mut(&id) {
                    // A new text draft must survive, but already-sent files must not be sent twice.
                    draft
                        .attachments
                        .retain(|item| !attachment_ids.contains(&item.id));
                }
            }
            Err(failure) => {
                if state.generation == generation {
                    if failure.kind == "unavailable" {
                        revoke(&mut state, &id);
                    }
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
        history_using(model, false, network)?;
    }
    Ok(())
}

fn note_failure(state: &mut State, failure: crate::AuthError) {
    if failure.kind == "sign_in_required" {
        clear_candidates(state);
        state.snapshot.needs_session = true;
    }
    state.snapshot.error = Some(failure.message.into());
}

fn revoke(state: &mut State, id: &str) {
    clear_candidates(state);
    state.snapshot.messages.clear();
    state.snapshot.people.clear();
    state.snapshot.threads.retain(|item| item.id != id);
    state.snapshot.selected = None;
    state.snapshot.history_loading = false;
    state.history_pending = false;
    state.drafts.remove(id);
    state.outbox.remove(id);
    if state
        .upload_attempt
        .as_ref()
        .is_some_and(|attempt| attempt.thread_id == id)
    {
        state.upload_attempt = None;
    }
    state.generation += 1;
    state.access_generation += 1;
}

#[cfg(test)]
fn prepare_send(state: &mut State, id: &str, body: &str) -> Result<String> {
    prepare_send_draft(state, id, body, &[], &[])
}

fn prepare_send_draft(
    state: &mut State,
    id: &str,
    body: &str,
    ids: &[String],
    mentions: &[Person],
) -> Result<String> {
    let matches = |draft: &&Draft| {
        draft.body == body
            && draft.attachments.iter().map(|item| &item.id).eq(ids.iter())
            && draft
                .mentions
                .iter()
                .map(|person| &person.id)
                .eq(mentions.iter().map(|person| &person.id))
    };
    let client_id = if let Some(draft) = state.drafts.get(id).filter(matches) {
        draft.client_id.clone()
    } else if let Some(attempt) = state.outbox.get(id).filter(matches) {
        return Ok(attempt.client_id.clone());
    } else {
        random_uuid()?
    };
    state.outbox.insert(
        id.into(),
        Draft {
            body: body.into(),
            client_id: client_id.clone(),
            mentions: mentions.to_vec(),
            attachments: state
                .drafts
                .get(id)
                .map(|draft| {
                    draft
                        .attachments
                        .iter()
                        .filter(|item| ids.contains(&item.id))
                        .cloned()
                        .collect()
                })
                .unwrap_or_default(),
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
            let mut updated = state.drafts.get(&id).cloned().unwrap_or_default();
            updated
                .mentions
                .retain(|person| has_mention(&body, &person.name));
            updated.body = body.clone();
            updated.client_id = random_uuid()?;
            state.drafts.insert(id, updated);
            if selected {
                clear_candidates(&mut state);
            }
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
        if !active {
            state.lifecycle += 1;
        }
        clear_candidates(&mut state);
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
    if !state.active
        || state.closed
        || state.live.is_some()
        || (state.snapshot.selection_id.is_some() && state.snapshot.selected.is_none())
    {
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
            clear_candidates(&mut state);
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
                clear_candidates(&mut state);
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
                apply_agent_status(&mut state.snapshot, &value);
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

// Activity changes do not increment the message revision. Apply every authorized
// snapshot, including idle, without waiting for an HTTP history invalidation.
fn apply_agent_status(snapshot: &mut Snapshot, value: &Value) {
    if let Some(thread) = snapshot.selected.as_mut() {
        thread.agent_status = serde_json::from_value(value["agent_status"].clone()).ok();
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
