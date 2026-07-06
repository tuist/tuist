//! CAS analytics parity with the legacy Swift daemon.
//!
//! The broker records per-node transfer metadata into `cas_analytics.db` at the
//! path the CLI's `UploadBuildRunService` already ships with the build report,
//! so the upload and server-side (xcactivitylog NIF) pipelines are unchanged —
//! the broker just took over the writing the daemon used to do.
//!
//! Two tables drive the server's enrichment (see the NIF's `CASMetadataReader`):
//! - `nodes`: build-log node id -> checksum. The node id is `"0~" +
//!   base64(digest)` (matching Xcode's CAS-output remarks); the checksum is the
//!   uppercase hex of the same digest.
//! - `cas_outputs`: checksum -> {size, compressed_size, duration, transfer,
//!   codec}.
//! `keyvalue_metadata` records per action-cache op durations.
//!
//! Writes go through a background thread so the resolve/publish hot path never
//! blocks on SQLite.

use std::sync::mpsc::{Receiver, Sender};
use std::time::{SystemTime, UNIX_EPOCH};

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
    Node {
        node_id: String,
        checksum: String,
    },
    CasOutput {
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
        // snapshot while the broker keeps writing.
        conn.pragma_update(None, "journal_mode", "WAL").ok()?;
        conn.busy_timeout(std::time::Duration::from_secs(5)).ok()?;
        conn.execute_batch(SCHEMA).ok()?;
        let (sender, receiver) = std::sync::mpsc::channel();
        std::thread::spawn(move || writer_loop(conn, receiver));
        Some(Analytics { sender })
    }

    /// A `nodes` row: the build-log node id `"0~" + base64url(casID)` mapped to
    /// its checksum. The casID and checksum are both parsed out of a value
    /// node's bytes by [`parse_cas_references`].
    pub fn record_node(&self, cas_id: &[u8], checksum_hex: &str) {
        let _ = self.sender.send(Record::Node {
            node_id: node_id_for(cas_id),
            checksum: checksum_hex.to_uppercase(),
        });
    }

    /// A `cas_outputs` row keyed by the checksum (uppercase hex of the fetched
    /// node's content digest, which equals the checksum in that node's parent
    /// reference).
    pub fn record_cas_output(
        &self,
        checksum_hex: &str,
        size: i64,
        compressed_size: i64,
        duration: f64,
        transfer: f64,
        codec: f64,
    ) {
        let _ = self.sender.send(Record::CasOutput {
            checksum: checksum_hex.to_uppercase(),
            size,
            compressed_size,
            duration,
            transfer,
            codec,
        });
    }

    /// A `keyvalue_metadata` row for an action-cache op. `operation_type` is
    /// "read" (resolve) or "write" (publish); the key is encoded as the daemon's
    /// `convertKeyToCasID` did.
    pub fn record_keyvalue(&self, key: &[u8], operation_type: &str, duration: f64) {
        let _ = self.sender.send(Record::KeyValue {
            key: keyvalue_key_for(key),
            operation_type: operation_type.to_string(),
            duration,
        });
    }
}

/// `"0~" + base64url(casID)` — the CAS-output node id as it appears in Xcode's
/// build-log remarks and the daemon's `nodes` table (the daemon base64s the
/// casID, then maps `+`->`-`, `/`->`_`, keeping `=` padding: URL-safe base64).
fn node_id_for(cas_id: &[u8]) -> String {
    format!("0~{}", base64::engine::general_purpose::URL_SAFE.encode(cas_id))
}

/// The action-cache key as the daemon's `convertKeyToCasID`: `"0~"` + URL-safe
/// base64 of the key with its first byte dropped.
fn keyvalue_key_for(key: &[u8]) -> String {
    let rest = key.get(1..).unwrap_or(&[]);
    format!("0~{}", base64::engine::general_purpose::URL_SAFE.encode(rest))
}

/// Uppercase hex of a content digest — the `cas_outputs` key the broker derives
/// from a fetched node's llcas digest.
pub fn hex_upper(bytes: &[u8]) -> String {
    let mut hex = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        hex.push_str(&format!("{byte:02X}"));
    }
    hex
}

/// Scans a value node's bytes for the CAS-entry pattern the daemon parsed
/// (`findNextCASEntry`): `0x0A 0x41 0x00` then a 64-byte casID, then `0x12 0x40`
/// then a 64-char ASCII hex checksum. Returns each `(casID, hex)` reference.
pub fn parse_cas_references(data: &[u8]) -> Vec<(Vec<u8>, String)> {
    let mut references = Vec::new();
    let mut offset = 0;
    while offset + 67 < data.len() {
        if data[offset] == 0x0A && data[offset + 1] == 0x41 && data[offset + 2] == 0x00 {
            let cas_start = offset + 3;
            let hex_marker = cas_start + 64;
            if hex_marker + 2 + 64 <= data.len()
                && data[hex_marker] == 0x12
                && data[hex_marker + 1] == 0x40
            {
                let hex_start = hex_marker + 2;
                let hex_bytes = &data[hex_start..hex_start + 64];
                if let Ok(hex) = std::str::from_utf8(hex_bytes) {
                    if hex.bytes().all(|b| b.is_ascii_hexdigit()) {
                        references.push((data[cas_start..cas_start + 64].to_vec(), hex.to_string()));
                    }
                }
                offset = hex_start + 64;
                continue;
            }
        }
        offset += 1;
    }
    references
}

/// `created_at` as SQLite.swift serializes a `Date`: a UTC `"yyyy-MM-dd'T'HH:mm:ss.SSS"`
/// TEXT string (no offset), which is what the Swift [`CASAnalyticsDatabase`] writes.
/// The broker and the Swift writer share the same `cas_analytics.db`, so the
/// column type and format must match or one side's inserts land in a schema the
/// other created.
fn now_iso8601() -> String {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    iso8601_from_unix(now.as_secs(), now.subsec_millis())
}

fn iso8601_from_unix(secs: u64, millis: u32) -> String {
    let days = (secs / 86_400) as i64;
    let rem = secs % 86_400;
    let (hour, minute, second) = (rem / 3600, (rem % 3600) / 60, rem % 60);
    let (year, month, day) = civil_from_days(days);
    format!("{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}.{millis:03}")
}

/// Howard Hinnant's `civil_from_days`: days since 1970-01-01 -> (year, month, day).
fn civil_from_days(z: i64) -> (i64, u64, u64) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let year = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    (if month <= 2 { year + 1 } else { year }, month, day)
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
        Record::Node { node_id, checksum } => tx.execute(
            "INSERT OR REPLACE INTO nodes (key, checksum, created_at) VALUES (?1, ?2, ?3)",
            rusqlite::params![node_id, checksum, created_at],
        ),
        Record::CasOutput {
            checksum,
            size,
            compressed_size,
            duration,
            transfer,
            codec,
        } => tx.execute(
            "INSERT OR REPLACE INTO cas_outputs \
             (key, size, duration, compressed_size, created_at, transfer_duration, codec_duration) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            rusqlite::params![checksum, size, duration, compressed_size, created_at, transfer, codec],
        ),
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
    fn node_id_uses_url_safe_base64() {
        // 0xFB 0xFF -> standard base64 "+/8=" -> url-safe "-_8=".
        assert_eq!(node_id_for(&[0xFB, 0xFF]), "0~-_8=");
        // keyvalue key drops the first byte, then url-safe base64.
        assert_eq!(keyvalue_key_for(&[0x00, 0xFB, 0xFF]), "0~-_8=");
    }

    #[test]
    fn created_at_matches_sqlite_swift_date_text() {
        // SQLite.swift serializes a `Date` as UTC "yyyy-MM-dd'T'HH:mm:ss.SSS";
        // the broker shares cas_analytics.db with the Swift CASAnalyticsDatabase,
        // so its created_at must be byte-compatible with that column.
        assert_eq!(iso8601_from_unix(0, 0), "1970-01-01T00:00:00.000");
        // 1_000_000_000 unix seconds is the well-known 2001-09-09T01:46:40 UTC.
        assert_eq!(iso8601_from_unix(1_000_000_000, 500), "2001-09-09T01:46:40.500");
        assert_eq!(civil_from_days(-1), (1969, 12, 31));
    }

    #[test]
    fn parse_cas_references_extracts_the_casid_hex_pattern() {
        let cas_id = vec![0xABu8; 64];
        let hex = "AB".repeat(32); // 64 ASCII hex chars
        let mut data = vec![0x0A, 0x41, 0x00];
        data.extend_from_slice(&cas_id);
        data.extend_from_slice(&[0x12, 0x40]);
        data.extend_from_slice(hex.as_bytes());
        // trailing noise the scanner should ignore
        data.extend_from_slice(&[0x99, 0x99]);

        let references = parse_cas_references(&data);
        assert_eq!(references.len(), 1);
        assert_eq!(references[0].0, cas_id);
        assert_eq!(references[0].1, hex);
    }

    #[test]
    fn records_into_a_swift_created_canonical_schema() {
        // Regression for the schema-divergence bug: the broker shares
        // cas_analytics.db with the Swift CASAnalyticsDatabase, whose SQLite.swift
        // `migrate()` creates these exact tables (created_at as TEXT, double-quoted
        // identifiers, defaults). If the broker's rows are not compatible with that
        // pre-existing schema, its INSERTs silently drop and nothing is recorded.
        // This creates the table the Swift way first, then drives the broker's
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
            let analytics = Analytics::open(&path).unwrap();
            analytics.record_node(&[0xDEu8, 0xAD, 0xBE, 0xEF], "abc123");
            analytics.record_cas_output("abc123", 100, 40, 0.5, 0.3, 0.2);
            analytics.record_keyvalue(&[0x00, 0xFB, 0xFF], "write", 0.1);
        }
        std::thread::sleep(std::time::Duration::from_millis(300));

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
    fn writes_nodes_and_cas_outputs_matching_the_server_read_schema() {
        let cas_id = vec![0xDEu8, 0xAD, 0xBE, 0xEF];
        let checksum = "abc123";

        let path = std::env::temp_dir().join(format!("cas-analytics-{}.db", std::process::id()));
        let path = path.to_str().unwrap().to_string();
        let _ = std::fs::remove_file(&path);
        {
            let analytics = Analytics::open(&path).unwrap();
            analytics.record_node(&cas_id, checksum);
            analytics.record_cas_output(checksum, 100, 40, 0.5, 0.3, 0.2);
            // Drop closes the channel; the writer drains and commits before exit.
        }
        // The writer runs on a detached thread; give it a moment to flush.
        std::thread::sleep(std::time::Duration::from_millis(300));

        let conn = Connection::open(&path).unwrap();
        let (node_key, node_checksum): (String, String) = conn
            .query_row("SELECT key, checksum FROM nodes", [], |row| {
                Ok((row.get(0)?, row.get(1)?))
            })
            .unwrap();
        assert_eq!(node_key, "0~3q2-7w=="); // "0~" + url-safe base64(DEADBEEF) (+ -> -)
        assert_eq!(node_checksum, "ABC123"); // uppercased

        let (size, compressed): (i64, i64) = conn
            .query_row(
                "SELECT size, compressed_size FROM cas_outputs WHERE key = 'ABC123'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(size, 100);
        assert_eq!(compressed, 40);

        let _ = std::fs::remove_file(&path);
    }
}
