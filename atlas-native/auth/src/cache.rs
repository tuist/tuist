//! Disposable read projections, never credentials, drafts or authorization grants.
//! Native adapters supply a private, backup-excluded directory and call off the UI
//! thread. Connections are shared per database; no network runs under this lock.
use crate::{Session, now};
use rusqlite::{Connection, OptionalExtension, TransactionBehavior, params};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock, Weak};
use std::time::Duration;

const MAX_BYTES: usize = 1024 * 1024;
const RETENTION: u64 = 7 * 24 * 60 * 60;
const MAX_ENTRIES: usize = 32;

// Append migrations; never edit a released entry. The array index + 1 is its
// schema version. DDL and user_version advance in the same transaction.
const MIGRATIONS: &[&str] = &[include_str!("cache_migrations/001_snapshots.sql")];

type Database = Arc<Mutex<Connection>>;

pub(crate) struct Cache {
    database: Database,
    namespace: String,
}

fn migrate(connection: &mut Connection, migrations: &[&str]) -> rusqlite::Result<()> {
    let transaction = connection.transaction_with_behavior(TransactionBehavior::Immediate)?;
    let version: i64 = transaction.pragma_query_value(None, "user_version", |row| row.get(0))?;
    if !(0..=migrations.len() as i64).contains(&version) {
        // A downgraded app must neither rewrite nor delete a newer database.
        return Err(rusqlite::Error::InvalidQuery);
    }
    for (index, sql) in migrations.iter().enumerate().skip(version as usize) {
        transaction.execute_batch(sql)?;
        transaction.pragma_update(None, "user_version", (index + 1) as i64)?;
    }
    transaction.commit()
}

fn database(directory: &str) -> Option<Database> {
    static DATABASES: OnceLock<Mutex<HashMap<PathBuf, Weak<Mutex<Connection>>>>> = OnceLock::new();
    let directory = Path::new(directory);
    if !directory.is_absolute() {
        return None;
    }
    let path = directory.join("reads.sqlite3");
    let mut databases = DATABASES.get_or_init(Default::default).lock().ok()?;
    if let Some(database) = databases.get(&path).and_then(Weak::upgrade) {
        return Some(database);
    }
    std::fs::create_dir_all(directory).ok()?;
    let mut connection = Connection::open(&path).ok()?;
    connection.busy_timeout(Duration::from_millis(250)).ok()?;
    migrate(&mut connection, MIGRATIONS).ok()?;
    connection
        .execute_batch(
            "PRAGMA foreign_keys = ON;
             PRAGMA secure_delete = ON;
             PRAGMA max_page_count = 4096;",
        )
        .ok()?;
    let database = Arc::new(Mutex::new(connection));
    databases.retain(|_, database| database.strong_count() > 0);
    databases.insert(path, Arc::downgrade(&database));
    Some(database)
}

impl Cache {
    pub(crate) fn open(directory: &str, session: &Session) -> Option<Self> {
        let id = session.cache_id.as_ref()?;
        if id.len() != 43
            || !id
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || b"_-".contains(&byte))
        {
            return None;
        }
        let origin = crate::server_url(&session.registration.server).ok()?;
        let namespace = format!(
            "{:x}",
            Sha256::digest(format!("{}{id}", origin.origin().ascii_serialization()))
        );
        let database = database(directory)?;
        {
            let connection = database.lock().ok()?;
            connection
                .execute(
                    "INSERT OR IGNORE INTO cache_namespaces (id) VALUES (?1)",
                    [&namespace],
                )
                .ok()?;
            connection
                .execute(
                    "DELETE FROM read_snapshots WHERE fetched_at < ?1",
                    [now().saturating_sub(RETENTION) as i64],
                )
                .ok()?;
        }
        Some(Self {
            database,
            namespace,
        })
    }

    pub(crate) fn generation(&self) -> Option<i64> {
        self.database
            .lock()
            .ok()?
            .query_row(
                "SELECT generation FROM cache_namespaces WHERE id = ?1 AND retired = 0",
                [&self.namespace],
                |row| row.get(0),
            )
            .ok()
    }

    pub(crate) fn read(&self, key: &str) -> Option<String> {
        self.database
            .lock()
            .ok()?
            .query_row(
                "SELECT payload FROM read_snapshots JOIN cache_namespaces ON namespace = id
             WHERE namespace = ?1 AND query_key = ?2 AND retired = 0
             AND fetched_at BETWEEN ?3 AND ?4 AND length(CAST(payload AS BLOB)) <= ?5",
                params![
                    self.namespace,
                    key,
                    now().saturating_sub(RETENTION) as i64,
                    now() as i64,
                    MAX_BYTES as i64
                ],
                |row| row.get(0),
            )
            .optional()
            .ok()
            .flatten()
    }

    pub(crate) fn write(&self, key: &str, payload: &str, generation: i64) {
        if payload.len() > MAX_BYTES {
            return;
        }
        let Ok(mut connection) = self.database.lock() else {
            return;
        };
        let Ok(transaction) = connection.transaction() else {
            return;
        };
        let result = transaction
            .execute(
                "INSERT OR REPLACE INTO read_snapshots (namespace, query_key, payload, fetched_at)
             SELECT id, ?2, ?3, ?4 FROM cache_namespaces
             WHERE id = ?1 AND generation = ?5 AND retired = 0",
                params![self.namespace, key, payload, now() as i64, generation],
            )
            .and_then(|_| {
                transaction.execute(
                    "DELETE FROM read_snapshots WHERE rowid NOT IN
             (SELECT rowid FROM read_snapshots ORDER BY fetched_at DESC, rowid DESC LIMIT ?1)",
                    [MAX_ENTRIES as i64],
                )
            });
        if result.is_ok() {
            let _ = transaction.commit();
        }
    }

    pub(crate) fn invalidate(&self, retire: bool) {
        let Ok(mut connection) = self.database.lock() else {
            return;
        };
        let Ok(transaction) = connection.transaction() else {
            return;
        };
        let result = transaction.execute(
            "UPDATE cache_namespaces SET generation = generation + 1, retired = max(retired, ?2) WHERE id = ?1",
            params![self.namespace, retire],
        ).and_then(|_| transaction.execute(
            "DELETE FROM read_snapshots WHERE namespace = ?1", [&self.namespace],
        ));
        if result.is_ok() {
            let _ = transaction.commit();
        }
    }
}

/// Only fixed, typed read projections may enter the durable cache. Credentials,
/// authorization flows, presence, attachment bytes and execution payloads cannot.
#[derive(Deserialize, Serialize)]
#[serde(tag = "surface", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum Read {
    BusinessList {
        resource: crate::business::Resource,
        page: u32,
        query: String,
        filters: BTreeMap<String, String>,
    },
    BusinessRecord {
        resource: crate::business::Resource,
        id: String,
    },
    Profile,
    TimeOff {
        requests_page: u32,
        holidays_page: u32,
    },
    AiAccounts,
    Connections,
    AutomationList {
        kind: AutomationKind,
        page: u32,
    },
    AutomationRecord {
        kind: AutomationKind,
        id: String,
    },
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum AutomationKind {
    Workflow,
    Execution,
    Approval,
}

impl Read {
    fn key(&self) -> crate::Result<String> {
        match self {
            Self::BusinessList {
                page,
                query,
                filters,
                ..
            } => {
                if *page == 0 || query.len() > 1000 || filters.len() > 8 {
                    return Err(crate::invalid());
                }
            }
            Self::BusinessRecord { id, resource } => {
                crate::time_off::validate_id(id)?;
                if matches!(resource, crate::business::Resource::Profile) {
                    return Err(crate::invalid());
                }
            }
            Self::TimeOff {
                requests_page,
                holidays_page,
            } if *requests_page == 0 || *holidays_page == 0 => {
                return Err(crate::invalid());
            }
            Self::AutomationList { page, .. } if *page == 0 => return Err(crate::invalid()),
            Self::AutomationRecord { id, .. } => crate::time_off::validate_id(id)?,
            _ => {}
        }
        let encoded = serde_json::to_vec(self).map_err(|_| crate::invalid())?;
        // Search terms, relationship IDs and filters do not become database keys.
        Ok(format!("read:v1:{:x}", Sha256::digest(encoded)))
    }

    fn fetch(&self, session: Session) -> crate::Result<Value> {
        match self {
            Self::BusinessList {
                resource,
                page,
                query,
                filters,
            } => crate::business::execute(
                session,
                *resource,
                crate::business::Action::List {
                    page: *page,
                    query: query.clone(),
                    filters: filters.clone(),
                },
            ),
            Self::BusinessRecord { resource, id } => crate::business::execute(
                session,
                *resource,
                crate::business::Action::Show { id: id.clone() },
            ),
            Self::Profile => crate::business::execute(
                session,
                crate::business::Resource::Profile,
                crate::business::Action::List {
                    page: 1,
                    query: String::new(),
                    filters: BTreeMap::new(),
                },
            ),
            Self::TimeOff {
                requests_page,
                holidays_page,
            } => crate::time_off::execute(
                session,
                crate::time_off::Action::List {
                    requests_page: *requests_page,
                    holidays_page: *holidays_page,
                },
            ),
            Self::AiAccounts => crate::accounts::execute(session, crate::accounts::Action::List),
            Self::Connections => {
                crate::connections::execute(session, crate::connections::Action::List)
            }
            Self::AutomationList { kind, page } => crate::api::execute(
                session,
                match kind {
                    AutomationKind::Workflow => {
                        crate::api::Request::Workflows { page: Some(*page) }
                    }
                    AutomationKind::Execution => {
                        crate::api::Request::Executions { page: Some(*page) }
                    }
                    AutomationKind::Approval => {
                        crate::api::Request::Approvals { page: Some(*page) }
                    }
                },
            ),
            Self::AutomationRecord { kind, id } => crate::api::execute(
                session,
                match kind {
                    AutomationKind::Workflow => crate::api::Request::Workflow { id: id.clone() },
                    AutomationKind::Execution => crate::api::Request::Execution { id: id.clone() },
                    AutomationKind::Approval => crate::api::Request::Approval { id: id.clone() },
                },
            ),
        }
    }

    fn saved(&self, mut value: Value) -> Value {
        // Automation transport also serves exact approval payloads, input schemas
        // and results. Persist only this explicit payload-free display projection.
        match self {
            Self::AutomationList { .. } => {
                value = json!({
                    "items": value["items"].as_array().map(|items| items.iter().take(20).map(saved_automation).collect::<Vec<_>>()).unwrap_or_default(),
                    "page": fields(&value["page"], &["current", "total", "count"]),
                });
            }
            Self::AutomationRecord { .. } => value = saved_automation(&value),
            _ => {}
        }
        // These values are display data, not a permission snapshot. Fresh requests
        // return their original capabilities; saved copies never carry write grants.
        if matches!(
            self,
            Self::BusinessList { .. } | Self::BusinessRecord { .. }
        ) && let Some(object) = value.as_object_mut()
        {
            if object.contains_key("can_write") {
                object.insert("can_write".into(), json!(false));
            }
            object.remove("options");
            // Native page decoding expects the same shape, with no editable options.
            if matches!(self, Self::BusinessList { .. }) {
                object.insert(
                    "options".into(),
                    json!({"users":[],"accounts":[],"segments":[],"statuses":[],"deal_stages":[]}),
                );
            }
            let records = object.get_mut("items").and_then(Value::as_array_mut);
            if let Some(records) = records {
                for record in records {
                    read_only_record(record);
                }
            }
            if let Some(record) = object.get_mut("item") {
                read_only_record(record);
            }
        }
        if let Some(object) = value.as_object_mut() {
            object.insert("cached".into(), json!(true));
        }
        value
    }
}

fn fields(value: &Value, names: &[&str]) -> Value {
    let mut saved = serde_json::Map::new();
    for name in names {
        if let Some(value) = value
            .get(*name)
            .filter(|value| !value.is_object() && !value.is_array())
        {
            saved.insert((*name).into(), value.clone());
        }
    }
    Value::Object(saved)
}

fn saved_automation(value: &Value) -> Value {
    let mut saved = fields(
        value,
        &[
            "id",
            "name",
            "description",
            "version",
            "status",
            "step_id",
            "run_id",
            "cursor",
            "elapsed_ms",
            "sequence",
            "inserted_at",
            "started_at",
            "completed_at",
        ],
    );
    if let Some(steps) = value["steps"].as_array() {
        saved["steps"] = json!(
            steps
                .iter()
                .take(100)
                .map(|step| fields(step, &["step_id", "status", "started_at", "completed_at"]))
                .collect::<Vec<_>>()
        );
    }
    saved["cached"] = json!(true);
    saved
}

fn read_only_record(record: &mut Value) {
    if let Some(record) = record.as_object_mut() {
        record.insert("can_edit".into(), json!(false));
        record.insert("can_delete".into(), json!(false));
    }
}

pub(crate) fn read(
    session: Session,
    directory: &str,
    request: Read,
    local: bool,
) -> crate::Result<Value> {
    read_using(session, directory, request, local, |request, session| {
        request.fetch(session)
    })
}

fn read_using(
    session: Session,
    directory: &str,
    request: Read,
    local: bool,
    fetch: impl FnOnce(&Read, Session) -> crate::Result<Value>,
) -> crate::Result<Value> {
    crate::validate_registration(&session.registration)?;
    if session.access_token.is_empty() {
        return Err(crate::invalid());
    }
    let key = request.key()?;
    let cache = Cache::open(directory, &session);
    if local {
        let value = cache
            .as_ref()
            .and_then(|cache| cache.read(&key))
            .and_then(|payload| serde_json::from_str(&payload).ok())
            .map(|value| request.saved(value));
        return Ok(json!({"value": value}));
    }
    let generation = cache.as_ref().and_then(Cache::generation);
    match fetch(&request, session) {
        Ok(value) => {
            if let (Some(cache), Some(generation)) = (cache, generation) {
                cache.write(&key, &request.saved(value.clone()).to_string(), generation);
            }
            Ok(json!({"value": value}))
        }
        Err(failure) => {
            if matches!(
                failure.kind,
                "forbidden"
                    | "unavailable"
                    | "not_found"
                    | "sign_in_required"
                    | "unauthorized"
                    | "rejected"
            ) && let Some(cache) = cache
            {
                cache.invalidate(false);
            }
            Err(failure)
        }
    }
}

#[cfg(test)]
#[path = "cache_tests.rs"]
mod tests;
