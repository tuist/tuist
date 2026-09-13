//! CAS analytics parity with the Swift `CASAnalyticsDatabase`.
//!
//! The proxy records per-node transfer metadata into `cas_analytics.db` at the
//! path the CLI's `UploadBuildRunService` already ships with the build report,
//! so the upload and server-side (xcactivitylog NIF) pipelines are unchanged:
//! the proxy writes the same rows and encodings the Swift `CASAnalyticsDatabase`
//! schema and the server's reader expect.
//!
//! Two tables drive the server's enrichment (see the NIF's `CASMetadataReader`):
//! - `nodes`: build-log node id -> checksum. The node id is `"0~" +
//!   base64(casID)` (matching Xcode's CAS-output remarks); the checksum is the
//!   64-hex-char digest carried alongside that casID in the parent node's
//!   reference, which is a DIFFERENT digest from the 64-byte casID itself.
//! - `cas_outputs`: checksum -> {size, compressed_size, duration, transfer,
//!   codec}.
//! `keyvalue_metadata` records per action-cache op durations.
//!
//! The server joins the two: build-log node id -> `nodes.checksum` ->
//! `cas_outputs.key`. A node's own checksum is only ever readable from its
//! PARENT's reference, so an output recorded before its parent is decoded is
//! held in `pending_outputs` until the matching `nodes` row arrives.
//!
//! All durations are MILLISECONDS, matching the schema the Swift
//! `CASAnalyticsDatabase` established and the units the server renders.
//!
//! Writes go through a background thread so the resolve/publish hot path never
//! blocks on SQLite.

use std::collections::{HashMap, VecDeque};
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
    Node {
        node_id: String,
        checksum: String,
    },
    CasOutput {
        node_id: String,
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

    /// A `nodes` row: the build-log node id `"0~" + base64url(casID)` mapped to
    /// its checksum. The casID and checksum are both parsed out of a value
    /// node's bytes by [`parse_cas_references`].
    pub fn record_node(&self, cas_id: &[u8], checksum_hex: &str) {
        let _ = self.sender.send(Record::Node {
            node_id: node_id_for(cas_id),
            checksum: checksum_hex.to_uppercase(),
        });
    }

    /// A `cas_outputs` row for the node `cas_id` identifies. The row is keyed by
    /// that node's checksum, which this side cannot compute: the checksum is a
    /// separate digest carried next to the casID in the PARENT's reference, not
    /// a hash of the casID. So the record travels by node id and the writer
    /// keys it once the matching `nodes` row is known — which may be after this
    /// call, since the materializer stores the value root LAST and the root is
    /// what carries its children's checksums. Durations are milliseconds.
    pub fn record_cas_output(
        &self,
        cas_id: &[u8],
        size: i64,
        compressed_size: i64,
        duration: f64,
        transfer: f64,
        codec: f64,
    ) {
        let _ = self.sender.send(Record::CasOutput {
            node_id: node_id_for(cas_id),
            size,
            compressed_size,
            duration,
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

/// `"0~" + base64url(casID)`: the CAS-output node id as it appears in Xcode's
/// build-log remarks and the `nodes` table the server reads (base64 the casID,
/// then map `+`->`-`, `/`->`_`, keeping `=` padding: URL-safe base64).
fn node_id_for(cas_id: &[u8]) -> String {
    format!("0~{}", base64::engine::general_purpose::URL_SAFE.encode(cas_id))
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

/// Scans a value node's bytes for the CAS-entry pattern in Apple's closed CAS
/// serialization: `0x0A 0x41 0x00` then a 64-byte casID, then `0x12 0x40` then a
/// 64-char ASCII hex checksum. Returns each `(casID, hex)` reference.
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

/// A `cas_outputs` row waiting on the `nodes` row that names its checksum.
struct PendingOutput {
    size: i64,
    compressed_size: i64,
    duration: f64,
    transfer: f64,
    codec: f64,
}

/// Ceiling on outputs held for a checksum that has not arrived.
const MAX_PENDING_OUTPUTS: usize = 50_000;

/// Outputs held until a parent's reference names their checksum, evicted
/// OLDEST-FIRST at the bound.
///
/// Eviction order is the load-bearing part, not the bound. Every value graph
/// leaves one permanently unresolvable entry behind — its ROOT, which no
/// reference in that graph points at — so a proxy that refused new entries at
/// the ceiling would fill it with roots over a long build and then be unable to
/// hold the children that resolve a moment later. A child's reference lands in
/// the same batch or the next one, so the oldest entry is always the safest to
/// drop.
struct PendingOutputs {
    by_node: HashMap<String, PendingOutput>,
    order: VecDeque<String>,
}

impl PendingOutputs {
    fn new() -> Self {
        PendingOutputs {
            by_node: HashMap::new(),
            order: VecDeque::new(),
        }
    }

    fn insert(&mut self, node_id: String, output: PendingOutput) {
        while self.by_node.len() >= MAX_PENDING_OUTPUTS {
            match self.order.pop_front() {
                Some(oldest) => {
                    self.by_node.remove(&oldest);
                }
                None => break,
            }
        }
        if self.by_node.insert(node_id.clone(), output).is_none() {
            self.order.push_back(node_id);
        }
    }

    /// The entry for `node_id`, if one is held. Its `order` slot is left to be
    /// skipped when eviction reaches it, so a removal costs no scan.
    fn remove(&mut self, node_id: &str) -> Option<PendingOutput> {
        self.by_node.remove(node_id)
    }
}

fn writer_loop(mut conn: Connection, receiver: Receiver<Record>) {
    let mut pending_outputs = PendingOutputs::new();
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
            let _ = write_record(&tx, record, &created_at, &mut pending_outputs);
        }
        let _ = tx.commit();
    }
}

/// The checksum recorded for `node_id`, from the `nodes` row a parent's
/// reference wrote. Read back from SQLite rather than mirrored in memory: the
/// table is already the authority, keyed, and this runs off the hot path.
fn checksum_for(tx: &rusqlite::Transaction, node_id: &str) -> Option<String> {
    tx.query_row(
        "SELECT checksum FROM nodes WHERE key = ?1",
        rusqlite::params![node_id],
        |row| row.get(0),
    )
    .ok()
}

fn write_cas_output(
    tx: &rusqlite::Transaction,
    checksum: &str,
    output: &PendingOutput,
    created_at: &str,
) -> rusqlite::Result<usize> {
    tx.execute(
        "INSERT OR REPLACE INTO cas_outputs \
         (key, size, duration, compressed_size, created_at, transfer_duration, codec_duration) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        rusqlite::params![
            checksum,
            output.size,
            output.duration,
            output.compressed_size,
            created_at,
            output.transfer,
            output.codec
        ],
    )
}

fn write_record(
    tx: &rusqlite::Transaction,
    record: &Record,
    created_at: &str,
    pending_outputs: &mut PendingOutputs,
) -> rusqlite::Result<usize> {
    match record {
        Record::Node { node_id, checksum } => {
            let written = tx.execute(
                "INSERT OR REPLACE INTO nodes (key, checksum, created_at) VALUES (?1, ?2, ?3)",
                rusqlite::params![node_id, checksum, created_at],
            )?;
            // This reference is what names the checksum an output recorded
            // earlier was missing, so drain it here rather than waiting for
            // another output to go looking.
            if let Some(output) = pending_outputs.remove(node_id) {
                write_cas_output(tx, checksum, &output, created_at)?;
            }
            Ok(written)
        }
        Record::CasOutput {
            node_id,
            size,
            compressed_size,
            duration,
            transfer,
            codec,
        } => {
            let output = PendingOutput {
                size: *size,
                compressed_size: *compressed_size,
                duration: *duration,
                transfer: *transfer,
                codec: *codec,
            };
            match checksum_for(tx, node_id) {
                Some(checksum) => write_cas_output(tx, &checksum, &output, created_at),
                None => {
                    pending_outputs.insert(node_id.clone(), output);
                    Ok(0)
                }
            }
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
    fn node_id_uses_url_safe_base64() {
        // 0xFB 0xFF -> standard base64 "+/8=" -> url-safe "-_8=".
        assert_eq!(node_id_for(&[0xFB, 0xFF]), "0~-_8=");
        // keyvalue key drops the first byte, then url-safe base64.
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
            let analytics = Analytics::open(&path).unwrap();
            analytics.record_node(&[0xDEu8, 0xAD, 0xBE, 0xEF], "abc123");
            analytics.record_cas_output(&[0xDEu8, 0xAD, 0xBE, 0xEF], 100, 40, 0.5, 0.3, 0.2);
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

    /// A casID and a checksum as they really appear in a node reference: the
    /// casID is 64 bytes, the checksum is a 64-hex-char digest of something
    /// else entirely. Hex of the casID is 128 chars and is NOT the checksum, so
    /// a `cas_outputs` row keyed off the digest can never be joined to its
    /// `nodes` row — the shape of the bug this pairing exists to catch.
    fn reference_pair() -> (Vec<u8>, String) {
        let cas_id = (0..64u8).collect::<Vec<u8>>();
        let checksum = "7C32A510A334F4F614BB51EAE35895DDEF9E3AAB9DAB8469554522B023AC2E16";
        assert_ne!(hex_upper(&cas_id), checksum);
        (cas_id, checksum.to_string())
    }

    #[test]
    fn writes_nodes_and_cas_outputs_matching_the_server_read_schema() {
        let (cas_id, checksum) = reference_pair();

        let path = std::env::temp_dir().join(format!("cas-analytics-{}.db", std::process::id()));
        let path = path.to_str().unwrap().to_string();
        let _ = std::fs::remove_file(&path);
        {
            let analytics = Analytics::open(&path).unwrap();
            analytics.record_node(&cas_id, &checksum);
            analytics.record_cas_output(&cas_id, 100, 40, 0.5, 0.3, 0.2);
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
        assert_eq!(node_key, node_id_for(&cas_id));
        assert_eq!(node_checksum, checksum);

        // The server reads node id -> nodes.checksum -> cas_outputs.key, so the
        // output must be keyed by the checksum the nodes row carries.
        let (size, compressed): (i64, i64) = conn
            .query_row(
                "SELECT size, compressed_size FROM cas_outputs WHERE key = ?1",
                rusqlite::params![checksum],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .expect("the cas_outputs row must be keyed by the nodes row's checksum");
        assert_eq!(size, 100);
        assert_eq!(compressed, 40);

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn a_cas_output_recorded_before_its_node_still_lands() {
        // The materializer stores the value ROOT last, and the root is what
        // carries its children's checksums, so a child's output is recorded
        // before the reference naming its checksum exists.
        let (cas_id, checksum) = reference_pair();

        let path = std::env::temp_dir().join(format!("cas-deferred-{}.db", std::process::id()));
        let path = path.to_str().unwrap().to_string();
        let _ = std::fs::remove_file(&path);
        {
            let analytics = Analytics::open(&path).unwrap();
            analytics.record_cas_output(&cas_id, 100, 40, 0.5, 0.3, 0.2);
            analytics.record_node(&cas_id, &checksum);
        }
        std::thread::sleep(std::time::Duration::from_millis(300));

        let conn = Connection::open(&path).unwrap();
        let size: i64 = conn
            .query_row(
                "SELECT size FROM cas_outputs WHERE key = ?1",
                rusqlite::params![checksum],
                |row| row.get(0),
            )
            .expect("the deferred output must be written once its nodes row arrives");
        assert_eq!(size, 100);

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn a_full_pending_set_evicts_the_oldest_rather_than_refusing_the_newest() {
        // Every graph leaves its root pending forever, so refusing at the
        // ceiling would let roots crowd out the children that do resolve.
        let mut pending = PendingOutputs::new();
        let output = || PendingOutput {
            size: 1,
            compressed_size: 1,
            duration: 0.0,
            transfer: 0.0,
            codec: 0.0,
        };
        for index in 0..MAX_PENDING_OUTPUTS {
            pending.insert(format!("root-{index}"), output());
        }
        pending.insert("child".to_string(), output());

        let newest_root = pending.remove(&format!("root-{}", MAX_PENDING_OUTPUTS - 1));
        assert!(pending.remove("child").is_some());
        assert!(pending.remove("root-0").is_none());
        assert!(newest_root.is_some());
    }

    #[test]
    fn durations_are_recorded_in_milliseconds() {
        // The schema, the Swift writer that created it, and the server's
        // renderer all read these columns as milliseconds.
        assert_eq!(millis(Duration::from_secs(1)), 1_000.0);
        assert_eq!(millis(Duration::from_millis(250)), 250.0);
    }
}
