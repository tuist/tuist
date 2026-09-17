//! CAS analytics parity with the Swift `CASAnalyticsDatabase`.
//!
//! The proxy records per-node transfer metadata into `cas_analytics.db` at the
//! path the CLI's `UploadBuildRunService` already ships with the build report,
//! using the existing Swift `CASAnalyticsDatabase` schema. The standalone server
//! activity-log parser joins those records to compiler output remarks.
//!
//! The server joins build-log node id -> `nodes.checksum` -> `cas_outputs.key`.
//! Record both sides together using Apple's printed node id and the REAPI blob's
//! checksum. The plugin owns the transfer representation; Apple's legacy remote
//! serialization is not present in the compiler nodes we upload.
//! `keyvalue_metadata` records per action-cache op durations.
//!
//! All durations are MILLISECONDS, matching the schema the Swift
//! `CASAnalyticsDatabase` established and the units the server renders.
//!
//! Writes go through a background thread so the resolve/publish hot path never
//! blocks on SQLite.

use std::sync::mpsc::{Receiver, Sender};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use base64::Engine;
use rusqlite::Connection;

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS cas_outputs (
    key TEXT PRIMARY KEY,
    size INTEGER NOT NULL,
    duration REAL NOT NULL,
    compressed_size INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    transfer_duration REAL NOT NULL DEFAULT 0,
    codec_duration REAL NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS nodes (
    key TEXT PRIMARY KEY,
    checksum TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS keyvalue_metadata (
    key TEXT NOT NULL,
    operation_type TEXT NOT NULL,
    duration REAL NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY (key, operation_type)
);
";

enum Record {
    CasOutput {
        node_id: String,
        checksum: String,
        size: i64,
        compressed_size: i64,
        duration: f64,
        transfer: f64,
        codec: f64,
    },
    KeyValue {
        key: String,
        operation_type: String,
        duration: f64,
    },
}

pub struct Analytics {
    sender: Sender<Record>,
}

impl Analytics {
    /// Opens (or creates) the analytics database and starts its writer thread.
    /// Returns `None` if the database cannot be opened, in which case recording
    /// is silently skipped — analytics are best-effort and never block caching.
    pub fn open(path: &str) -> Option<Analytics> {
        let conn = Connection::open(path).ok()?;
        // WAL so the CLI's `checkpoint`+copy at upload time can read a consistent
        // snapshot while the proxy keeps writing.
        conn.pragma_update(None, "journal_mode", "WAL").ok()?;
        conn.busy_timeout(std::time::Duration::from_secs(5)).ok()?;
        conn.execute_batch(SCHEMA).ok()?;
        let (sender, receiver) = std::sync::mpsc::channel();
        std::thread::spawn(move || writer_loop(conn, receiver));
        Some(Analytics { sender })
    }

    /// Record a transferred node and its lookup mapping atomically. `node_id`
    /// comes from llcas_digest_print, not base64 of the internal digest (which
    /// includes a version byte the printed payload omits). `checksum` names the
    /// encoded REAPI blob we actually transferred.
    pub fn record_cas_output(
        &self,
        node_id: String,
        checksum: &str,
        size: i64,
        compressed_size: i64,
        transfer: f64,
        codec: f64,
    ) {
        let _ = self.sender.send(Record::CasOutput {
            node_id,
            checksum: checksum.to_uppercase(),
            size,
            compressed_size,
            duration: transfer + codec,
            transfer,
            codec,
        });
    }

    /// A `keyvalue_metadata` row for an action-cache op. `operation_type` is
    /// "read" (resolve) or "write" (publish); the key is encoded for the server
    /// reader by `keyvalue_key_for`. `duration` is milliseconds.
    pub fn record_keyvalue(&self, key: &[u8], operation_type: &str, duration: f64) {
        let _ = self.sender.send(Record::KeyValue {
            key: keyvalue_key_for(key),
            operation_type: operation_type.to_string(),
            duration,
        });
    }
}

/// The action-cache key as the server reads it: `"0~"` + URL-safe base64 of the
/// key with its first byte dropped.
fn keyvalue_key_for(key: &[u8]) -> String {
    let rest = key.get(1..).unwrap_or(&[]);
    format!("0~{}", base64::engine::general_purpose::URL_SAFE.encode(rest))
}

/// A duration as the milliseconds every analytics column stores.
pub fn millis(duration: Duration) -> f64 {
    duration.as_secs_f64() * 1_000.0
}

/// Uppercase hex of a content digest.
pub fn hex_upper(bytes: &[u8]) -> String {
    let mut hex = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        hex.push_str(&format!("{byte:02X}"));
    }
    hex
}

/// `created_at` as SQLite.swift serializes a `Date`: a UTC `"yyyy-MM-dd'T'HH:mm:ss.SSS"`
/// TEXT string (no offset), which is what the Swift [`CASAnalyticsDatabase`] writes.
/// The proxy and the Swift writer share the same `cas_analytics.db`, so the
/// column type and format must match or one side's inserts land in a schema the
/// other created.
const CREATED_AT_FORMAT: &[time::format_description::FormatItem<'_>] = time::macros::format_description!(
    "[year]-[month]-[day]T[hour]:[minute]:[second].[subsecond digits:3]"
);

fn now_iso8601() -> String {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    iso8601_from_unix(now.as_secs(), now.subsec_millis())
}

fn iso8601_from_unix(secs: u64, millis: u32) -> String {
    let nanos = i128::from(secs) * 1_000_000_000 + i128::from(millis) * 1_000_000;
    time::OffsetDateTime::from_unix_timestamp_nanos(nanos)
        .ok()
        .and_then(|dt| dt.format(CREATED_AT_FORMAT).ok())
        .unwrap_or_default()
}

fn writer_loop(mut conn: Connection, receiver: Receiver<Record>) {
    // Block for the first record, then drain the burst and commit it in one
    // transaction to keep per-op SQLite cost off the build's critical path.
    while let Ok(first) = receiver.recv() {
        let mut batch = vec![first];
        while let Ok(record) = receiver.try_recv() {
            batch.push(record);
            if batch.len() >= 1000 {
                break;
            }
        }
        let created_at = now_iso8601();
        let Ok(tx) = conn.transaction() else { continue };
        for record in &batch {
            let _ = write_record(&tx, record, &created_at);
        }
        let _ = tx.commit();
    }
}

fn write_record(
    tx: &rusqlite::Transaction,
    record: &Record,
    created_at: &str,
) -> rusqlite::Result<usize> {
    match record {
        Record::CasOutput {
            node_id,
            checksum,
            size,
            compressed_size,
            duration,
            transfer,
            codec,
        } => {
            tx.execute(
                "INSERT OR REPLACE INTO nodes (key, checksum, created_at) VALUES (?1, ?2, ?3)",
                rusqlite::params![node_id, checksum, created_at],
            )?;
            tx.execute(
                "INSERT OR REPLACE INTO cas_outputs \
                 (key, size, duration, compressed_size, created_at, transfer_duration, codec_duration) \
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                rusqlite::params![checksum, size, duration, compressed_size, created_at, transfer, codec],
            )
        }
        Record::KeyValue {
            key,
            operation_type,
            duration,
        } => tx.execute(
            "INSERT OR REPLACE INTO keyvalue_metadata (key, operation_type, duration, created_at) \
             VALUES (?1, ?2, ?3, ?4)",
            rusqlite::params![key, operation_type, duration, created_at],
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keyvalue_id_uses_url_safe_base64_without_the_version_byte() {
        assert_eq!(keyvalue_key_for(&[0x00, 0xFB, 0xFF]), "0~-_8=");
    }

    #[test]
    fn created_at_matches_sqlite_swift_date_text() {
        // SQLite.swift serializes a `Date` as UTC "yyyy-MM-dd'T'HH:mm:ss.SSS";
        // the proxy shares cas_analytics.db with the Swift CASAnalyticsDatabase,
        // so its created_at must be byte-compatible with that column.
        assert_eq!(iso8601_from_unix(0, 0), "1970-01-01T00:00:00.000");
        // 1_000_000_000 unix seconds is the well-known 2001-09-09T01:46:40 UTC.
        assert_eq!(iso8601_from_unix(1_000_000_000, 500), "2001-09-09T01:46:40.500");
    }

    #[test]
    fn records_into_a_swift_created_canonical_schema() {
        // Regression for the schema-divergence bug: the proxy shares
        // cas_analytics.db with the Swift CASAnalyticsDatabase, whose SQLite.swift
        // `migrate()` creates these exact tables (created_at as TEXT, double-quoted
        // identifiers, defaults). If the proxy's rows are not compatible with that
        // pre-existing schema, its INSERTs silently drop and nothing is recorded.
        // This creates the table the Swift way first, then drives the proxy's
        // recording against it.
        let path = std::env::temp_dir().join(format!("cas-swift-schema-{}.db", std::process::id()));
        let path = path.to_str().unwrap().to_string();
        let _ = std::fs::remove_file(&path);
        {
            let conn = Connection::open(&path).unwrap();
            conn.execute_batch(
                "CREATE TABLE \"cas_outputs\" (\"key\" TEXT PRIMARY KEY NOT NULL, \"size\" INTEGER NOT NULL, \"duration\" REAL NOT NULL, \"compressed_size\" INTEGER NOT NULL, \"created_at\" TEXT NOT NULL DEFAULT ('2026-01-01T00:00:00.000'), \"transfer_duration\" REAL NOT NULL DEFAULT (0.0), \"codec_duration\" REAL NOT NULL DEFAULT (0.0));
                 CREATE TABLE \"nodes\" (\"key\" TEXT PRIMARY KEY NOT NULL, \"checksum\" TEXT NOT NULL, \"created_at\" TEXT NOT NULL DEFAULT ('2026-01-01T00:00:00.000'));
                 CREATE TABLE \"keyvalue_metadata\" (\"key\" TEXT NOT NULL, \"operation_type\" TEXT NOT NULL, \"duration\" REAL NOT NULL, \"created_at\" TEXT NOT NULL DEFAULT ('2026-01-01T00:00:00.000'), PRIMARY KEY (\"key\", \"operation_type\"));",
            )
            .unwrap();
        }
        {
            let (sender, receiver) = std::sync::mpsc::channel();
            let analytics = Analytics { sender };
            analytics.record_cas_output("0~3q2-7w==".into(), "abc123", 100, 40, 0.3, 0.2);
            analytics.record_keyvalue(&[0x00, 0xFB, 0xFF], "write", 0.1);
            drop(analytics);
            writer_loop(Connection::open(&path).unwrap(), receiver);
        }

        let conn = Connection::open(&path).unwrap();
        let node_checksum: String = conn
            .query_row("SELECT checksum FROM nodes WHERE key = '0~3q2-7w=='", [], |row| row.get(0))
            .expect("node row must land in the Swift-created table");
        assert_eq!(node_checksum, "ABC123");
        let (size, kind): (i64, String) = conn
            .query_row(
                "SELECT c.size, k.operation_type FROM cas_outputs c, keyvalue_metadata k WHERE c.key = 'ABC123'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .expect("cas_output + keyvalue rows must land in the Swift-created tables");
        assert_eq!(size, 100);
        assert_eq!(kind, "write");
        // created_at written as TEXT (not a REAL), so it matches the column type.
        let created_at_type: String = conn
            .query_row("SELECT typeof(created_at) FROM nodes LIMIT 1", [], |row| row.get(0))
            .unwrap();
        assert_eq!(created_at_type, "text");

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn records_outputs_without_a_parent_reference_and_updates_the_blob_mapping() {
        let mut conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(SCHEMA).unwrap();
        for (checksum, size) in [("old-encoding", 100), ("new-encoding", 120)] {
            let tx = conn.transaction().unwrap();
            write_record(
                &tx,
                &Record::CasOutput {
                    node_id: "0~compiler-output".into(),
                    checksum: checksum.into(),
                    size,
                    compressed_size: 40,
                    duration: 3.5,
                    transfer: 3.0,
                    codec: 0.5,
                },
                "2026-09-17T00:00:00.000",
            )
            .unwrap();
            tx.commit().unwrap();
        }
        let (checksum, size, duration): (String, i64, f64) = conn
            .query_row(
                "SELECT n.checksum, c.size, c.duration FROM nodes n \
             JOIN cas_outputs c ON c.key = n.checksum WHERE n.key = '0~compiler-output'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .unwrap();
        assert_eq!(checksum, "new-encoding");
        assert_eq!(size, 120);
        assert_eq!(duration, 3.5);
    }

    #[test]
    fn durations_are_recorded_in_milliseconds() {
        // The schema, the Swift writer that created it, and the server's
        // renderer all read these columns as milliseconds.
        assert_eq!(millis(Duration::from_secs(1)), 1_000.0);
        assert_eq!(millis(Duration::from_millis(250)), 250.0);
    }
}
