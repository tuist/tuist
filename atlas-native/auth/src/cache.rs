//! Disposable read projections, never credentials, drafts or authorization grants.
//! Native adapters supply a private, backup-excluded directory and call off the UI
//! thread. Connections are shared per database; no network runs under this lock.
use crate::{Session, now};
use rusqlite::{Connection, OptionalExtension, TransactionBehavior, params};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
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

#[cfg(test)]
#[path = "cache_tests.rs"]
mod tests;
