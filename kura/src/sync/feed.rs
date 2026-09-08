//! The intra-region arrival feed: a bounded, trimmed change log a sibling
//! reads forward with long-polling (design §3.1).
//!
//! On disk it is one row per change under `sync/fwd/{seq}` in the
//! `key_value` column family, staged into the same WriteBatch as the change
//! it describes. This module owns the row codec, the position (`incarnation`
//! + `seq`) codec, and the in-memory head/floor/consumer state that decides
//! what a reader may be served; the store owns the batches.
//!
//! Head is the *contiguous committed* head. A seq is allocated at staging
//! time, before its batch lands, and batches commit in any order, so a reader
//! served everything up to the newest committed seq could skip a lower seq
//! whose batch is still in flight and never see it. Serving only up to the
//! lowest in-flight seq minus one closes that gap; an aborted batch releases
//! its seq so a gap never pins the head.

use std::{
    collections::{BTreeSet, HashMap},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
    time::Instant,
};

use tokio::sync::Notify;

use crate::utils::BackfillRecordKind;

/// Key prefix of the feed rows: `sync/fwd/` ++ seq (8-byte big-endian).
pub const SYNC_FEED_PREFIX: &str = "sync/fwd/";
/// Key prefix of the feed's persistent markers (`incarnation`, `floor`,
/// `enabled`). Kept out of the row prefix so a row scan never meets them.
pub const SYNC_META_PREFIX: &str = "sync/meta/";
/// Key prefix of the forward cursors this node holds against its siblings:
/// `sync/cursor/{peer node url}`.
pub const SYNC_CURSOR_PREFIX: &str = "sync/cursor/";
/// Key prefix of the region watermarks: `sync/wm/{origin region}`.
pub const SYNC_WM_PREFIX: &str = "sync/wm/";

pub const SYNC_META_INCARNATION: &str = "incarnation";
pub const SYNC_META_FLOOR: &str = "floor";
pub const SYNC_META_ENABLED: &str = "enabled";

/// Wire kind byte of a watermark row; record rows reuse
/// [`BackfillRecordKind::as_byte`] (1..=3).
const FEED_KIND_WATERMARK: u8 = 4;

/// What a feed row describes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SyncFeedKind {
    Record(BackfillRecordKind),
    /// A region-watermark advance (design §4.3): `record_id` is the origin
    /// region, `version_ms` the watermark.
    Watermark,
}

impl SyncFeedKind {
    pub fn as_byte(self) -> u8 {
        match self {
            Self::Record(kind) => kind.as_byte(),
            Self::Watermark => FEED_KIND_WATERMARK,
        }
    }

    pub fn from_byte(byte: u8) -> Option<Self> {
        if byte == FEED_KIND_WATERMARK {
            return Some(Self::Watermark);
        }
        BackfillRecordKind::from_byte(byte).map(Self::Record)
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Record(kind) => kind.as_str(),
            Self::Watermark => "watermark",
        }
    }

    pub fn from_wire_name(name: &str) -> Option<Self> {
        if name == "watermark" {
            return Some(Self::Watermark);
        }
        BackfillRecordKind::from_wire_name(name).map(Self::Record)
    }
}

/// One decoded feed row: the backfill listing descriptor plus the commit's
/// wall-clock time, so lag can be reported in seconds as well as rows.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SyncFeedRow {
    pub seq: u64,
    pub kind: SyncFeedKind,
    pub record_id: String,
    pub version_ms: u64,
    /// `None` for tombstones and watermark rows.
    pub size: Option<u64>,
    pub arrived_at_ms: u64,
}

pub fn sync_feed_key(seq: u64) -> Vec<u8> {
    let mut key = Vec::with_capacity(SYNC_FEED_PREFIX.len() + 8);
    key.extend_from_slice(SYNC_FEED_PREFIX.as_bytes());
    key.extend_from_slice(&seq.to_be_bytes());
    key
}

/// Exclusive upper bound of the whole row keyspace (`/` + 1 = `0`).
pub fn sync_feed_prefix_upper_bound() -> Vec<u8> {
    let mut bound = SYNC_FEED_PREFIX.as_bytes().to_vec();
    let last = bound.last_mut().expect("prefix is non-empty");
    *last += 1;
    bound
}

pub fn sync_feed_seq_from_key(key: &[u8]) -> Option<u64> {
    let tail = key.strip_prefix(SYNC_FEED_PREFIX.as_bytes())?;
    let bytes: [u8; 8] = tail.try_into().ok()?;
    Some(u64::from_be_bytes(bytes))
}

/// Row value: `kind(1) ++ version_ms(8 BE) ++ size(8 BE, u64::MAX when
/// absent) ++ arrived_at_ms(8 BE) ++ record_id`.
pub fn encode_sync_feed_value(
    kind: SyncFeedKind,
    record_id: &str,
    version_ms: u64,
    size: Option<u64>,
    arrived_at_ms: u64,
) -> Vec<u8> {
    let mut value = Vec::with_capacity(25 + record_id.len());
    value.push(kind.as_byte());
    value.extend_from_slice(&version_ms.to_be_bytes());
    value.extend_from_slice(&size.unwrap_or(u64::MAX).to_be_bytes());
    value.extend_from_slice(&arrived_at_ms.to_be_bytes());
    value.extend_from_slice(record_id.as_bytes());
    value
}

pub fn decode_sync_feed_row(key: &[u8], value: &[u8]) -> Result<SyncFeedRow, String> {
    let seq =
        sync_feed_seq_from_key(key).ok_or_else(|| "sync feed key is malformed".to_string())?;
    let (&kind_byte, rest) = value
        .split_first()
        .ok_or_else(|| "sync feed row is empty".to_string())?;
    let kind = SyncFeedKind::from_byte(kind_byte)
        .ok_or_else(|| format!("unknown sync feed kind byte {kind_byte}"))?;
    let (version, rest) = rest
        .split_at_checked(8)
        .ok_or_else(|| "sync feed row is missing its version".to_string())?;
    let (size, rest) = rest
        .split_at_checked(8)
        .ok_or_else(|| "sync feed row is missing its size".to_string())?;
    let (arrived, record_id) = rest
        .split_at_checked(8)
        .ok_or_else(|| "sync feed row is missing its arrival stamp".to_string())?;
    let size = u64::from_be_bytes(size.try_into().expect("split at 8"));
    Ok(SyncFeedRow {
        seq,
        kind,
        record_id: std::str::from_utf8(record_id)
            .map_err(|error| format!("invalid sync feed record id: {error}"))?
            .to_owned(),
        version_ms: u64::from_be_bytes(version.try_into().expect("split at 8")),
        size: (size != u64::MAX).then_some(size),
        arrived_at_ms: u64::from_be_bytes(arrived.try_into().expect("split at 8")),
    })
}

pub fn sync_meta_key(name: &str) -> String {
    format!("{SYNC_META_PREFIX}{name}")
}

pub fn sync_cursor_key(peer: &str) -> String {
    format!("{SYNC_CURSOR_PREFIX}{peer}")
}

pub fn sync_wm_key(region: &str) -> String {
    format!("{SYNC_WM_PREFIX}{region}")
}

pub fn sync_wm_prefix_upper_bound() -> Vec<u8> {
    let mut bound = SYNC_WM_PREFIX.as_bytes().to_vec();
    let last = bound.last_mut().expect("prefix is non-empty");
    *last += 1;
    bound
}

/// A position in one node's feed: which copy of the data (`incarnation`)
/// and how far into it (`seq`). Wire form `{incarnation:016x}:{seq}`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SyncPosition {
    pub incarnation: u64,
    pub seq: u64,
}

impl SyncPosition {
    pub fn encode(self) -> String {
        format!("{:016x}:{}", self.incarnation, self.seq)
    }

    pub fn parse(text: &str) -> Result<Self, String> {
        let (incarnation, seq) = text
            .split_once(':')
            .ok_or_else(|| "sync position must be {incarnation}:{seq}".to_string())?;
        let incarnation = u64::from_str_radix(incarnation, 16)
            .map_err(|error| format!("invalid sync incarnation: {error}"))?;
        let seq = seq
            .parse::<u64>()
            .map_err(|error| format!("invalid sync seq: {error}"))?;
        Ok(Self { incarnation, seq })
    }

    /// Persisted cursor value: both halves 8-byte big-endian.
    pub fn encode_value(self) -> Vec<u8> {
        let mut value = Vec::with_capacity(16);
        value.extend_from_slice(&self.incarnation.to_be_bytes());
        value.extend_from_slice(&self.seq.to_be_bytes());
        value
    }

    pub fn decode_value(value: &[u8]) -> Result<Self, String> {
        let (incarnation, seq) = value
            .split_at_checked(8)
            .ok_or_else(|| format!("sync cursor value should be 16 bytes, got {}", value.len()))?;
        let seq: [u8; 8] = seq
            .try_into()
            .map_err(|_| format!("sync cursor value should be 16 bytes, got {}", value.len()))?;
        Ok(Self {
            incarnation: u64::from_be_bytes(incarnation.try_into().expect("split at 8")),
            seq: u64::from_be_bytes(seq),
        })
    }
}

/// A consumer's last reported cursor and when it last asked.
#[derive(Clone, Copy, Debug)]
pub struct FeedConsumer {
    pub cursor: u64,
    pub seen_at: Instant,
}

/// In-memory state of this node's feed. Owned by the store behind an `Arc`
/// so a staged row's ticket can release its seq from wherever the batch
/// resolves.
pub struct SyncFeedState {
    incarnation: u64,
    /// Next seq to allocate.
    next_seq: AtomicU64,
    /// Seqs allocated whose batch has not resolved yet.
    inflight: Mutex<BTreeSet<u64>>,
    /// Highest seq that has been trimmed away (exclusive lower bound of the
    /// retained range). Rows with `seq <= floor` are gone.
    floor: AtomicU64,
    enabled: AtomicBool,
    cap: u64,
    dropped_total: AtomicU64,
    /// Fires on every commit (row or not) so a long-poll wakes promptly; a
    /// missed wake only costs the poll's re-check interval.
    notify: Notify,
    consumers: Mutex<HashMap<String, FeedConsumer>>,
}

/// Seq lease for one staged row. `commit` after the batch landed; dropping
/// it unresolved releases the seq as aborted, so the head can pass the gap.
pub struct SyncFeedTicket {
    feed: Arc<SyncFeedState>,
    seq: u64,
    committed: bool,
}

impl SyncFeedTicket {
    pub fn seq(&self) -> u64 {
        self.seq
    }

    pub fn commit(mut self) {
        self.committed = true;
        self.feed.resolve(self.seq);
    }
}

impl Drop for SyncFeedTicket {
    fn drop(&mut self) {
        if !self.committed {
            self.feed.resolve(self.seq);
        }
    }
}

impl SyncFeedState {
    /// `last_seq` is the highest seq known on disk (the last row, or the floor
    /// when the feed is empty): allocation resumes strictly above it.
    pub fn new(incarnation: u64, last_seq: u64, floor: u64, enabled: bool, cap: u64) -> Self {
        Self {
            incarnation,
            next_seq: AtomicU64::new(last_seq + 1),
            inflight: Mutex::new(BTreeSet::new()),
            floor: AtomicU64::new(floor),
            enabled: AtomicBool::new(enabled),
            cap,
            dropped_total: AtomicU64::new(0),
            notify: Notify::new(),
            consumers: Mutex::new(HashMap::new()),
        }
    }

    pub fn incarnation(&self) -> u64 {
        self.incarnation
    }

    pub fn cap(&self) -> u64 {
        self.cap
    }

    pub fn enabled(&self) -> bool {
        self.enabled.load(Ordering::Acquire)
    }

    pub fn set_enabled(&self, enabled: bool) -> bool {
        self.enabled.swap(enabled, Ordering::AcqRel) != enabled
    }

    pub fn floor(&self) -> u64 {
        self.floor.load(Ordering::Acquire)
    }

    /// Raises the floor (never lowers it); returns the new floor.
    pub fn raise_floor(&self, to: u64) -> u64 {
        self.floor.fetch_max(to, Ordering::AcqRel).max(to)
    }

    /// The contiguous committed head: every seq at or below it has resolved.
    pub fn head(&self) -> u64 {
        let inflight = self.inflight.lock().unwrap_or_else(|e| e.into_inner());
        match inflight.first() {
            Some(&lowest) => lowest - 1,
            None => self.next_seq.load(Ordering::Acquire) - 1,
        }
    }

    /// Rows currently retained (head − floor), the depth gauge.
    pub fn depth(&self) -> u64 {
        self.head().saturating_sub(self.floor())
    }

    pub fn dropped_total(&self) -> u64 {
        self.dropped_total.load(Ordering::Relaxed)
    }

    pub fn record_dropped(&self, rows: u64) {
        self.dropped_total.fetch_add(rows, Ordering::Relaxed);
    }

    /// Allocates the next seq for a row being staged. The store must
    /// `commit` the ticket after the batch write or drop it on failure.
    pub fn allocate(self: &Arc<Self>) -> SyncFeedTicket {
        let seq = self.next_seq.fetch_add(1, Ordering::AcqRel);
        self.inflight
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(seq);
        SyncFeedTicket {
            feed: Arc::clone(self),
            seq,
            committed: false,
        }
    }

    fn resolve(&self, seq: u64) {
        self.inflight
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(&seq);
        self.notify.notify_waiters();
    }

    /// Wakes long-polls; called on every commit whether or not it wrote a
    /// row, so the ascending region read (which watches the index, not the
    /// feed) is woken too.
    pub fn notify_commit(&self) {
        self.notify.notify_waiters();
    }

    pub fn notified(&self) -> tokio::sync::futures::Notified<'_> {
        self.notify.notified()
    }

    pub fn note_consumer(&self, peer: &str, cursor: u64) {
        self.consumers
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(
                peer.to_owned(),
                FeedConsumer {
                    cursor,
                    seen_at: Instant::now(),
                },
            );
    }

    pub fn consumers(&self) -> Vec<(String, FeedConsumer)> {
        self.consumers
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .iter()
            .map(|(peer, consumer)| (peer.clone(), *consumer))
            .collect()
    }

    pub fn forget_consumer(&self, peer: &str) {
        self.consumers
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(peer);
    }

    pub fn clear_consumers(&self) {
        self.consumers
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clear();
    }

    /// The lowest cursor among consumers seen within `stale`, or `None` when
    /// no live consumer exists. Trimming below it is safe for every reader.
    pub fn lowest_live_cursor(&self, stale: std::time::Duration) -> Option<u64> {
        let now = Instant::now();
        self.consumers
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .values()
            .filter(|consumer| now.duration_since(consumer.seen_at) <= stale)
            .map(|consumer| consumer.cursor)
            .min()
    }

    /// When the newest consumer request happened, if any.
    pub fn last_consumer_seen(&self) -> Option<Instant> {
        self.consumers
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .values()
            .map(|consumer| consumer.seen_at)
            .max()
    }

    /// Whether every live consumer has read up to the head (the drain gate,
    /// design §3.5). True with no live consumer.
    pub fn consumers_caught_up(&self, stale: std::time::Duration) -> bool {
        let head = self.head();
        self.lowest_live_cursor(stale)
            .is_none_or(|cursor| cursor >= head)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn row_codec_round_trips_every_kind() {
        for (kind, size) in [
            (
                SyncFeedKind::Record(BackfillRecordKind::SegmentArtifact),
                Some(10),
            ),
            (
                SyncFeedKind::Record(BackfillRecordKind::InlineArtifact),
                Some(0),
            ),
            (
                SyncFeedKind::Record(BackfillRecordKind::NamespaceTombstone),
                None,
            ),
            (SyncFeedKind::Watermark, None),
        ] {
            let key = sync_feed_key(42);
            let value = encode_sync_feed_value(kind, "id-1", 1234, size, 9999);
            let row = decode_sync_feed_row(&key, &value).expect("decodes");
            assert_eq!(
                row,
                SyncFeedRow {
                    seq: 42,
                    kind,
                    record_id: "id-1".into(),
                    version_ms: 1234,
                    size,
                    arrived_at_ms: 9999,
                }
            );
            assert_eq!(SyncFeedKind::from_wire_name(kind.as_str()), Some(kind));
        }
        assert!(decode_sync_feed_row(b"sync/fwd/short", &[]).is_err());
        assert!(decode_sync_feed_row(&sync_feed_key(1), &[9]).is_err());
    }

    #[test]
    fn feed_keys_sort_by_seq_and_stay_below_the_upper_bound() {
        assert!(sync_feed_key(1) < sync_feed_key(2));
        assert!(sync_feed_key(u64::MAX) < sync_feed_prefix_upper_bound());
        assert!(sync_meta_key("floor").as_bytes() > sync_feed_prefix_upper_bound().as_slice());
        assert_eq!(sync_feed_seq_from_key(&sync_feed_key(7)), Some(7));
    }

    #[test]
    fn position_codec_round_trips_and_rejects_garbage() {
        let position = SyncPosition {
            incarnation: 0xdead_beef,
            seq: 12,
        };
        assert_eq!(position.encode(), "00000000deadbeef:12");
        assert_eq!(SyncPosition::parse("00000000deadbeef:12"), Ok(position));
        assert_eq!(
            SyncPosition::decode_value(&position.encode_value()),
            Ok(position)
        );
        assert!(SyncPosition::parse("nope").is_err());
        assert!(SyncPosition::parse("zz:1").is_err());
        assert!(SyncPosition::decode_value(&[1, 2, 3]).is_err());
    }

    #[test]
    fn head_is_the_contiguous_committed_seq() {
        let feed = Arc::new(SyncFeedState::new(1, 10, 0, true, 1000));
        assert_eq!(feed.head(), 10);
        let first = feed.allocate();
        let second = feed.allocate();
        assert_eq!((first.seq(), second.seq()), (11, 12));
        // Committing the newer one first must not expose it.
        second.commit();
        assert_eq!(feed.head(), 10);
        first.commit();
        assert_eq!(feed.head(), 12);
        // An aborted batch releases its seq: the head passes the gap.
        let third = feed.allocate();
        let fourth = feed.allocate();
        drop(third);
        assert_eq!(feed.head(), 13, "an aborted seq is a gap the head passes");
        fourth.commit();
        assert_eq!(feed.head(), 14);
    }

    #[test]
    fn consumers_decide_the_trim_floor_and_the_drain_gate() {
        let feed = Arc::new(SyncFeedState::new(1, 20, 0, true, 1000));
        let stale = std::time::Duration::from_secs(60);
        assert!(
            feed.consumers_caught_up(stale),
            "no consumer means nothing to wait for"
        );
        assert_eq!(feed.lowest_live_cursor(stale), None);
        feed.note_consumer("a", 15);
        feed.note_consumer("b", 18);
        assert_eq!(feed.lowest_live_cursor(stale), Some(15));
        assert!(!feed.consumers_caught_up(stale));
        feed.note_consumer("a", 20);
        feed.note_consumer("b", 20);
        assert!(feed.consumers_caught_up(stale));
        feed.forget_consumer("a");
        assert_eq!(feed.consumers().len(), 1);
        assert_eq!(feed.raise_floor(5), 5);
        assert_eq!(feed.raise_floor(3), 5, "the floor never lowers");
        assert_eq!(feed.depth(), 15);
    }
}
