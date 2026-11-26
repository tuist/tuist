//! The local store: everything the person has seen, so the app renders before
//! the network answers and stays navigable offline.
//!
//! The model lives here, in Rust, on SQLite, and runs unchanged on every
//! platform: rusqlite bundles SQLite natively and uses `sqlite-wasm-rs` in the
//! browser. Hosts only say which directory to keep it in. Each profile has its
//! own database file (`{profile}.sqlite3`), so signing out deletes one file.
//!
//! Tables:
//! - `inboxes` and `threads`: an account's inbox as last seen, in server order.
//! - `conversations` and `messages`: a conversation as last seen, with its
//!   latest messages; older pages stay on the server.
//! - `outbox`: writes made offline, oldest first. Each keeps the `request_id`
//!   the server deduplicates by, so replaying it is safe.
//!
//! Only server responses write `threads`, `conversations` and `messages`;
//! reads overlay the outbox on them, and every view says how fresh it is:
//! `live`, `cached` (with `as_of`), `never_loaded` or `queued`.
use rusqlite::{Connection, OptionalExtension, params};
use serde_json::{Value, json};

use crate::client::{Result, segment};
use crate::threads::new_request_id;

/// The error for a request that couldn't reach the server: the host reported
/// no connectivity (`{"error":"offline"}`). Other host failures, such as a bad
/// certificate, are real errors and are never answered from the store.
pub const OFFLINE: &str = "Network unavailable";

/// The schema, as ordered migrations. Append only: never edit or reorder a
/// shipped entry. Each runs once per database, in its own transaction, and
/// `PRAGMA user_version` records how many have run. `outbox` holds writes not
/// yet on the server, so a migration must keep its rows; the other tables can
/// be rebuilt from the server.
pub const MIGRATIONS: &[(&str, &str)] = &[
    (
        "create_local_store",
        "
CREATE TABLE inboxes (
    account TEXT PRIMARY KEY,
    synced_at INTEGER NOT NULL
);
CREATE TABLE threads (
    account TEXT NOT NULL,
    id TEXT NOT NULL,
    position INTEGER NOT NULL,
    data TEXT NOT NULL,
    PRIMARY KEY (account, id)
);
CREATE TABLE conversations (
    id TEXT PRIMARY KEY,
    data TEXT NOT NULL,
    synced_at INTEGER NOT NULL
);
CREATE TABLE messages (
    thread_id TEXT NOT NULL,
    position INTEGER NOT NULL,
    data TEXT NOT NULL,
    PRIMARY KEY (thread_id, position)
);
CREATE TABLE outbox (
    seq INTEGER PRIMARY KEY AUTOINCREMENT,
    request_id TEXT NOT NULL UNIQUE,
    operation TEXT NOT NULL,
    account TEXT NOT NULL,
    thread_id TEXT NOT NULL,
    content TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    failed INTEGER NOT NULL DEFAULT 0
);
",
    ),
    (
        // A thread started offline has a local id until the server assigns
        // one; open views and queued replies keep using it.
        "create_thread_aliases",
        "
CREATE TABLE thread_aliases (
    local_id TEXT PRIMARY KEY,
    server_id TEXT NOT NULL
);
",
    ),
    (
        // Where paging continues after the last thread loaded, so a refreshed
        // first page keeps the pages loaded after it.
        "add_inbox_next_cursor",
        "ALTER TABLE inboxes ADD COLUMN next_cursor TEXT;",
    ),
];

const READ: &str = "Could not read local data";
const SAVE: &str = "Could not save local data";
const MIGRATE: &str = "Could not update local data";

pub struct Store {
    db: Connection,
}

/// A profile's database file, last, after its `-wal` and `-shm` siblings.
pub fn files(directory: &str, profile: &str) -> Result<Vec<String>> {
    if !segment(profile) {
        return Err("Invalid profile");
    }
    let base = format!("{}/{profile}.sqlite3", directory.trim_end_matches('/'));
    Ok(vec![format!("{base}-wal"), format!("{base}-shm"), base])
}

impl Store {
    /// Opens a database and brings its schema up to date, returning the
    /// migrations that ran. A database from a newer build is refused rather
    /// than guessed at.
    pub fn open(path: &str) -> Result<(Self, Vec<&'static str>)> {
        let mut db = Connection::open(path).map_err(|_| READ)?;
        // WAL lets screens read while a sync writes. VFSs without it (the
        // browser's) keep their default journal; the store works either way.
        let _ = db.query_row("PRAGMA journal_mode = WAL", [], |_| Ok(()));
        let version: i64 = db
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .map_err(|_| READ)?;
        let version = usize::try_from(version).map_err(|_| READ)?;
        if version > MIGRATIONS.len() {
            return Err("Local data is from a newer version of the app");
        }
        let mut applied = Vec::new();
        for (index, (name, sql)) in MIGRATIONS.iter().enumerate().skip(version) {
            let tx = db.transaction().map_err(|_| MIGRATE)?;
            tx.execute_batch(sql).map_err(|_| MIGRATE)?;
            tx.pragma_update(None, "user_version", index as i64 + 1)
                .map_err(|_| MIGRATE)?;
            tx.commit().map_err(|_| MIGRATE)?;
            applied.push(*name);
        }
        Ok((Self { db }, applied))
    }

    /// The account's inbox as last seen, with threads started offline first.
    pub fn inbox(&mut self, account: &str) -> Result<Value> {
        let (synced_at, next_cursor): (Option<i64>, Option<String>) = self
            .db
            .query_row(
                "SELECT synced_at, next_cursor FROM inboxes WHERE account = ?1",
                [account],
                |r| Ok((Some(r.get(0)?), r.get(1)?)),
            )
            .optional()
            .map_err(|_| READ)?
            .unwrap_or_default();
        let mut threads: Vec<Value> = self
            .outbox()?
            .iter()
            .rev()
            .filter(|e| e["operation"] == "start_thread" && e["account"] == account)
            .map(queued_thread)
            .collect();
        threads.extend(self.json_rows(
            "SELECT data FROM threads WHERE account = ?1 ORDER BY position",
            account,
        )?);
        Ok(json!({
            "available": true,
            "threads": threads,
            "next_cursor": next_cursor,
            "freshness": freshness(synced_at),
        }))
    }

    /// Records a page of the inbox and the cursor after it; later pages
    /// append. The first page goes on top, and the threads loaded after it
    /// stay, with the cursor that continues after them: the server pages by
    /// latest change, so a thread that changed since moves into the first
    /// page, and the rest keep their order. When the first page is all there
    /// is, it replaces what was known, so threads the server no longer lists
    /// disappear.
    pub fn save_inbox(
        &mut self,
        account: &str,
        page: &Value,
        next_cursor: Option<&str>,
        first: bool,
        now: i64,
    ) -> Result<()> {
        let threads = page.as_array().map(Vec::as_slice).unwrap_or_default();
        let tx = self.db.transaction().map_err(|_| SAVE)?;
        let mut cursor = next_cursor.map(str::to_string);
        let start: i64 = if first {
            let stored: Option<Option<String>> = tx
                .query_row(
                    "SELECT next_cursor FROM inboxes WHERE account = ?1",
                    [account],
                    |r| r.get(0),
                )
                .optional()
                .map_err(|_| SAVE)?;
            match stored {
                Some(stored) if next_cursor.is_some() => {
                    for thread in threads {
                        let id = thread["id"].as_str().ok_or("Invalid thread")?;
                        tx.execute(
                            "DELETE FROM threads WHERE account = ?1 AND id = ?2",
                            params![account, id],
                        )
                        .map_err(|_| SAVE)?;
                    }
                    let (kept, top): (i64, i64) = tx
                        .query_row(
                            "SELECT COUNT(*), COALESCE(MIN(position), 0) FROM threads WHERE account = ?1",
                            [account],
                            |r| Ok((r.get(0)?, r.get(1)?)),
                        )
                        .map_err(|_| SAVE)?;
                    if kept > 0 {
                        cursor = stored;
                    }
                    top - threads.len() as i64
                }
                _ => {
                    tx.execute("DELETE FROM threads WHERE account = ?1", [account])
                        .map_err(|_| SAVE)?;
                    0
                }
            }
        } else {
            tx.query_row(
                "SELECT COALESCE(MAX(position) + 1, 0) FROM threads WHERE account = ?1",
                [account],
                |r| r.get(0),
            )
            .map_err(|_| SAVE)?
        };
        for (position, thread) in (start..).zip(threads) {
            let id = thread["id"].as_str().ok_or("Invalid thread")?;
            tx.execute(
                "INSERT OR REPLACE INTO threads (account, id, position, data) VALUES (?1, ?2, ?3, ?4)",
                params![account, id, position, thread.to_string()],
            )
            .map_err(|_| SAVE)?;
        }
        tx.execute(
            "INSERT OR REPLACE INTO inboxes (account, synced_at, next_cursor) VALUES (?1, ?2, ?3)",
            params![account, now, cursor],
        )
        .map_err(|_| SAVE)?;
        tx.commit().map_err(|_| SAVE)
    }

    /// Replaces a thread's row in the account's inbox, where it is, without its
    /// messages. A thread the inbox doesn't list stays out of it.
    pub fn update_in_inbox(&mut self, account: &str, thread: &Value) -> Result<()> {
        let id = thread["id"].as_str().ok_or("Invalid thread")?;
        let mut row = thread.clone();
        if let Some(object) = row.as_object_mut() {
            object.remove("messages");
            object.remove("freshness");
        }
        self.db
            .execute(
                "UPDATE threads SET data = ?3 WHERE account = ?1 AND id = ?2",
                params![account, id, row.to_string()],
            )
            .map_err(|_| SAVE)?;
        Ok(())
    }

    /// A conversation as last seen, with replies sent offline appended. A
    /// thread started offline exists only in the outbox until it is sent.
    pub fn conversation(&mut self, id: &str) -> Result<Value> {
        let id = self.resolve(id)?;
        let id = id.as_str();
        let cached = self.cached(id)?;
        let outbox: Vec<Value> = self
            .outbox()?
            .into_iter()
            .filter(|e| e["thread_id"] == id)
            .collect();
        let synced_at = cached.as_ref().map(|(_, at)| *at);
        let mut thread = match (cached, outbox.first()) {
            (Some((thread, _)), _) => thread,
            (None, Some(entry)) if entry["operation"] == "start_thread" => queued_thread(entry),
            (None, _) => json!({"id": id, "working": false, "messages": []}),
        };
        let messages = thread["messages"]
            .as_array_mut()
            .expect("messages is an array");
        // A reply the server already has (a live diff brought it back) shows
        // once, as the server's, even before its queued entry is settled.
        let arrived: Vec<Value> = messages
            .iter()
            .filter_map(|m| m.get("request_id").cloned())
            .collect();
        for entry in outbox
            .iter()
            .filter(|e| e["operation"] == "send_message" && !arrived.contains(&e["request_id"]))
        {
            messages.push(queued_message(entry));
        }
        thread["freshness"] = match synced_at {
            None if !outbox.is_empty() => json!({"state": "queued"}),
            synced_at => freshness(synced_at),
        };
        Ok(thread)
    }

    /// A conversation and its messages as the server last said, without the
    /// outbox, and when that was.
    fn cached(&self, id: &str) -> Result<Option<(Value, i64)>> {
        let cached: Option<(String, i64)> = self
            .db
            .query_row(
                "SELECT data, synced_at FROM conversations WHERE id = ?1",
                [id],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()
            .map_err(|_| READ)?;
        let Some((data, synced_at)) = cached else {
            return Ok(None);
        };
        let mut thread: Value = serde_json::from_str(&data).map_err(|_| READ)?;
        thread["messages"] = json!(self.json_rows(
            "SELECT data FROM messages WHERE thread_id = ?1 ORDER BY position",
            id,
        )?);
        Ok(Some((thread, synced_at)))
    }

    /// The revision of thread `id` the store has, which its live socket
    /// syncs from, or `None` when it was never loaded.
    pub fn revision(&self, id: &str) -> Result<Option<u64>> {
        let revision: Option<Option<i64>> = self
            .db
            .query_row(
                "SELECT json_extract(data, '$.revision') FROM conversations WHERE id = ?1",
                [id],
                |r| r.get(0),
            )
            .optional()
            .map_err(|_| READ)?;
        Ok(revision.flatten().and_then(|r| u64::try_from(r).ok()))
    }

    /// Stores a `diff` the thread's live socket received (`Live::connect`):
    /// a `reset` is the latest page and replaces the conversation, as a load
    /// does; otherwise the thread's fields and the messages that changed merge
    /// into it by ID. Its `cursor` becomes the stored revision. Returns
    /// whether the conversation changed: not when the store is already past
    /// the diff. A delta for a conversation it doesn't have is an error.
    pub fn apply_diff(&mut self, diff: &Value, now: i64) -> Result<bool> {
        let changes = &diff["thread"];
        let id = changes["id"].as_str().ok_or("Invalid thread")?;
        let cursor = diff["cursor"].as_u64().ok_or("Invalid thread")?;
        if self.revision(id)?.is_some_and(|stored| stored >= cursor) {
            return Ok(false);
        }
        let mut thread = if diff["reset"] == true {
            changes.clone()
        } else {
            let Some((mut thread, _)) = self.cached(id)? else {
                return Err("Thread is not stored");
            };
            let mut messages = std::mem::take(&mut thread["messages"])
                .as_array()
                .cloned()
                .unwrap_or_default();
            let partial = thread["has_more"] == true;
            let oldest = messages.iter().filter_map(|m| m["position"].as_i64()).min();
            for message in changes["messages"].as_array().into_iter().flatten() {
                match messages.iter_mut().find(|m| m["id"] == message["id"]) {
                    Some(stored) => *stored = message.clone(),
                    // An edit to a message before the stored page would leave
                    // a gap; loading the earlier page brings it with the rest.
                    None if partial && message["position"].as_i64() < oldest => {}
                    None => messages.push(message.clone()),
                }
            }
            messages.sort_by_key(|m| m["position"].as_i64());
            for (key, value) in changes.as_object().ok_or("Invalid thread")? {
                thread[key] = value.clone();
            }
            thread["messages"] = json!(messages);
            thread
        };
        thread["revision"] = json!(cursor);
        crate::threads::present(&mut thread);
        self.save_conversation(&thread, now)?;
        Ok(true)
    }

    /// Replaces the conversation and its latest messages with what the
    /// server returned.
    /// A response older than what a live diff already stored is dropped.
    pub fn save_conversation(&mut self, thread: &Value, now: i64) -> Result<()> {
        let id = thread["id"].as_str().ok_or("Invalid thread")?;
        if let (Some(stored), Some(incoming)) = (self.revision(id)?, thread["revision"].as_u64())
            && stored > incoming
        {
            return Ok(());
        }
        let mut data = thread.clone();
        let messages = data
            .as_object_mut()
            .and_then(|o| o.remove("messages"))
            .unwrap_or_default();
        let tx = self.db.transaction().map_err(|_| SAVE)?;
        tx.execute(
            "INSERT OR REPLACE INTO conversations (id, data, synced_at) VALUES (?1, ?2, ?3)",
            params![id, data.to_string(), now],
        )
        .map_err(|_| SAVE)?;
        tx.execute("DELETE FROM messages WHERE thread_id = ?1", [id])
            .map_err(|_| SAVE)?;
        for (position, message) in messages.as_array().into_iter().flatten().enumerate() {
            tx.execute(
                "INSERT INTO messages (thread_id, position, data) VALUES (?1, ?2, ?3)",
                params![id, position as i64, message.to_string()],
            )
            .map_err(|_| SAVE)?;
        }
        tx.commit().map_err(|_| SAVE)
    }

    /// Writes made offline, oldest first.
    pub fn outbox(&mut self) -> Result<Vec<Value>> {
        let mut statement = self
            .db
            .prepare(
                "SELECT request_id, operation, account, thread_id, content, created_at, failed
                 FROM outbox ORDER BY seq",
            )
            .map_err(|_| READ)?;
        let rows = statement
            .query_map([], |r| {
                Ok(json!({
                    "request_id": r.get::<_, String>(0)?,
                    "operation": r.get::<_, String>(1)?,
                    "account": r.get::<_, String>(2)?,
                    "thread_id": r.get::<_, String>(3)?,
                    "content": r.get::<_, String>(4)?,
                    "created_at": r.get::<_, i64>(5)?,
                    "failed": r.get::<_, bool>(6)?,
                }))
            })
            .map_err(|_| READ)?;
        rows.collect::<std::result::Result<_, _>>()
            .map_err(|_| READ)
    }

    /// The server's id for a thread started offline and since sent, or `id`.
    pub fn resolve(&self, id: &str) -> Result<String> {
        let server: Option<String> = self
            .db
            .query_row(
                "SELECT server_id FROM thread_aliases WHERE local_id = ?1",
                [id],
                |r| r.get(0),
            )
            .optional()
            .map_err(|_| READ)?;
        Ok(server.unwrap_or_else(|| id.to_string()))
    }

    /// Whether `id` is a thread started offline that the server doesn't have yet.
    pub fn unsent(&self, id: &str) -> Result<bool> {
        self.db
            .query_row(
                "SELECT EXISTS (SELECT 1 FROM outbox WHERE operation = 'start_thread' AND thread_id = ?1)",
                [id],
                |r| r.get(0),
            )
            .map_err(|_| READ)
    }

    /// Queues a write made offline under the `request_id` it was (or would
    /// have been) sent with, so a request whose response was lost replays as
    /// the same write. A new thread gets that key as its local id until the
    /// server assigns one. Queuing the same key twice keeps one entry.
    pub fn enqueue(
        &mut self,
        operation: &str,
        account: &str,
        args: &Value,
        now: i64,
    ) -> Result<String> {
        let request_id = match args["request_id"].as_str() {
            Some(id) => id.to_string(),
            None => new_request_id(),
        };
        let thread_id = match operation {
            "start_thread" => request_id.clone(),
            _ => self.resolve(args["id"].as_str().ok_or("Invalid thread")?)?,
        };
        let content = args["content"].as_str().ok_or("Invalid message")?;
        self.db
            .execute(
                "INSERT OR IGNORE INTO outbox (request_id, operation, account, thread_id, content, created_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![request_id, operation, account, thread_id, content, now],
            )
            .map_err(|_| SAVE)?;
        Ok(thread_id)
    }

    /// Records a queued write the server accepted. For a thread started
    /// offline, its local id becomes an alias of the server's, queued replies
    /// move to the server's id, and the thread joins the cached inbox.
    pub fn sent(&mut self, request_id: &str, thread: &Value, now: i64) -> Result<()> {
        let server_id = thread["id"].as_str().ok_or("Invalid thread")?;
        let entry: Option<(String, String, String)> = self
            .db
            .query_row(
                "SELECT operation, account, thread_id FROM outbox WHERE request_id = ?1",
                [request_id],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
            .optional()
            .map_err(|_| READ)?;
        let tx = self.db.transaction().map_err(|_| SAVE)?;
        if let Some((operation, account, local_id)) = &entry
            && operation == "start_thread"
        {
            tx.execute(
                "INSERT OR REPLACE INTO thread_aliases (local_id, server_id) VALUES (?1, ?2)",
                params![local_id, server_id],
            )
            .map_err(|_| SAVE)?;
            tx.execute(
                "UPDATE outbox SET thread_id = ?2 WHERE thread_id = ?1",
                params![local_id, server_id],
            )
            .map_err(|_| SAVE)?;
            add_to_inbox(&tx, account, thread)?;
        }
        tx.execute("DELETE FROM outbox WHERE request_id = ?1", [request_id])
            .map_err(|_| SAVE)?;
        tx.commit().map_err(|_| SAVE)?;
        self.save_conversation(thread, now)
    }

    /// Removes a write the server accepted, or marks one it refused for good,
    /// so it stays visible as failed instead of silently disappearing.
    pub fn settle(&mut self, request_id: &str, failed: bool) -> Result<()> {
        let sql = if failed {
            "UPDATE outbox SET failed = 1 WHERE request_id = ?1"
        } else {
            "DELETE FROM outbox WHERE request_id = ?1"
        };
        self.db.execute(sql, [request_id]).map_err(|_| SAVE)?;
        Ok(())
    }

    /// Deletes every row, for sign-out.
    pub fn clear(self) -> Result<()> {
        self.db
            .execute_batch(
                "DELETE FROM inboxes; DELETE FROM threads; DELETE FROM conversations;
                 DELETE FROM messages; DELETE FROM outbox; DELETE FROM thread_aliases;",
            )
            .map_err(|_| SAVE)
    }

    fn json_rows(&self, sql: &str, key: &str) -> Result<Vec<Value>> {
        let mut statement = self.db.prepare(sql).map_err(|_| READ)?;
        let rows = statement
            .query_map([key], |r| r.get::<_, String>(0))
            .map_err(|_| READ)?;
        rows.map(|row| {
            row.ok()
                .and_then(|text| serde_json::from_str(&text).ok())
                .ok_or(READ)
        })
        .collect()
    }
}

/// Stores what a thread operation returned, or answers from the store when
/// the network is unreachable: reads fall back to what was last seen, writes
/// are queued. Other failures pass through unchanged.
pub fn record(
    store: &mut Store,
    operation: &str,
    account: &str,
    args: &Value,
    result: Result<Value>,
    now: i64,
) -> Result<Value> {
    match (operation, result) {
        // Threads off or not allowed here: say so, and keep what was stored.
        ("threads", Ok(mut data)) if data["available"] == false => {
            data["freshness"] = json!({"state": "live"});
            Ok(data)
        }
        ("threads", Ok(data)) => {
            let first = args.get("cursor").is_none();
            let cursor = data["next_cursor"].as_str();
            store.save_inbox(account, &data["threads"], cursor, first, now)?;
            let mut view = store.inbox(account)?;
            view["available"] = data["available"].clone();
            view["freshness"] = json!({"state": "live"});
            Ok(view)
        }
        ("threads", Err(OFFLINE)) => store.inbox(account),
        // Only the latest messages are kept; older pages stay on the server.
        ("thread", Ok(mut thread)) if args.get("before").is_some() => {
            thread["freshness"] = json!({"state": "live"});
            Ok(thread)
        }
        ("thread", Ok(thread)) => {
            store.save_conversation(&thread, now)?;
            let id = thread["id"].as_str().ok_or("Invalid thread")?.to_string();
            let mut view = store.conversation(&id)?;
            view["freshness"] = json!({"state": "live"});
            Ok(view)
        }
        // An earlier page is never stored, so offline it stays unavailable
        // rather than answering with the latest page again.
        ("thread", Err(OFFLINE)) if args.get("before").is_some() => Err(OFFLINE),
        ("thread", Err(OFFLINE)) => store.conversation(args["id"].as_str().unwrap_or_default()),
        ("start_thread" | "send_message" | "answer_question", Ok(thread)) => {
            if operation == "start_thread" {
                let tx = store.db.transaction().map_err(|_| SAVE)?;
                add_to_inbox(&tx, account, &thread)?;
                tx.commit().map_err(|_| SAVE)?;
            }
            store.save_conversation(&thread, now)?;
            let mut thread = thread;
            thread["freshness"] = json!({"state": "live"});
            Ok(thread)
        }
        // A snooze or archive needs the server; the stored thread and inbox follow it.
        ("snooze_thread" | "archive_thread" | "reauthorize_thread", Ok(thread)) => {
            store.save_conversation(&thread, now)?;
            store.update_in_inbox(account, &thread)?;
            let mut thread = thread;
            thread["freshness"] = json!({"state": "live"});
            Ok(thread)
        }
        ("start_thread" | "send_message", Err(OFFLINE)) => {
            let thread_id = store.enqueue(operation, account, args, now)?;
            store.conversation(&thread_id)
        }
        (_, result) => result,
    }
}

/// Puts a thread the person just started at the top of the account's cached
/// inbox, without its messages, until the next inbox page replaces it.
fn add_to_inbox(tx: &rusqlite::Transaction, account: &str, thread: &Value) -> Result<()> {
    let id = thread["id"].as_str().ok_or("Invalid thread")?;
    let mut row = thread.clone();
    if let Some(object) = row.as_object_mut() {
        object.remove("messages");
        object.remove("freshness");
    }
    tx.execute(
        "INSERT OR REPLACE INTO threads (account, id, position, data)
         VALUES (?1, ?2, (SELECT COALESCE(MIN(position), 0) - 1 FROM threads WHERE account = ?1), ?3)",
        params![account, id, row.to_string()],
    )
    .map_err(|_| SAVE)?;
    Ok(())
}

fn freshness(synced_at: Option<i64>) -> Value {
    match synced_at {
        Some(at) => json!({"state": "cached", "as_of": at}),
        None => json!({"state": "never_loaded"}),
    }
}

fn queued_thread(entry: &Value) -> Value {
    json!({
        "id": entry["thread_id"],
        "title": entry["content"],
        "state": if entry["failed"] == true { "failed" } else { "queued" },
        "section": "in_progress",
        "working": false,
        "pending": true,
        "failed": entry["failed"],
        "messages": [queued_message(entry)],
    })
}

/// A reply the server doesn't have yet. Its `send_state` is `offline` until
/// a flush sends it, or `failed` once the server refused it for good.
fn queued_message(entry: &Value) -> Value {
    json!({
        "id": entry["request_id"],
        "role": "user",
        "content": entry["content"],
        "pending": true,
        "failed": entry["failed"],
        "send_state": if entry["failed"] == true { "failed" } else { "offline" },
    })
}
