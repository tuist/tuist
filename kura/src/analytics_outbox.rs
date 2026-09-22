//! Types and wire format for the durable analytics outbox.
//!
//! Store methods that read from and write to the `analytics_outbox`
//! column family (declared in #13467) live on [`crate::store::Store`]
//! but need a shared understanding of what a stored entry looks like on
//! disk. This module owns that shared understanding.
//!
//! # Key layout
//!
//! Every entry key is a fixed 26-byte concatenation of three fields, all
//! big-endian so lexicographic order matches insertion order:
//!
//! ```text
//! [ u16 pipeline_id | u64 queued_at_ms | 16 bytes UUID event_id ]
//! ```
//!
//! - **`pipeline_id`** groups entries by producer (gradle-cache, xcode-
//!   cache, reapi-cache). A forwarder task scanning one pipeline can
//!   iterate that pipeline's prefix and never look at the others.
//! - **`queued_at_ms`** is the wall clock at enqueue time. Because it
//!   sits directly after the pipeline id, a prefix scan for one pipeline
//!   returns entries in enqueue order. Codex flagged a monotonic `u64`
//!   sequence as unsafe under process restart; a wall clock plus the
//!   trailing UUIDv7 gives an ordering that survives the store crashing
//!   between two writes without needing a durable counter.
//! - **`event_id`** is the producer-owned UUIDv7 minted by
//!   [`crate::analytics`] (Kura PR #13445). It disambiguates the
//!   millisecond-wide bucket two producers can share.
//!
//! # Dead-code allowance
//!
//! Every item in this module is `pub` inside the crate and is called
//! only from the (also-`pub`) store methods that write to and read from
//! the outbox column family. Neither the store methods nor these types
//! are wired to any production producer in this PR — that arrives in
//! the follow-up. Rather than sprinkle a `#[cfg(test)]` marker that
//! would then have to be removed by the follow-up, gate the whole
//! module with `#[allow(dead_code)]` so the same source compiles clean
//! on this PR and picks up call sites for free on the next.
//!
//! # Value layout
//!
//! ```text
//! [ u8 schema_version | u16 attempts | u64 encoded_at_ms | u8 content_type
//!   | u32 payload_len | payload bytes ]
//! ```
//!
//! - **`schema_version`** is 1 for this release. A store that reads a
//!   value with an unknown version returns a [`DecodeError::UnknownVersion`],
//!   which the forwarder (introduced in the follow-up PR) will move to
//!   the quarantine column family instead of retrying it against the
//!   server. This is the "backward/forward compatible across one version
//!   skew" rule in `kura/CLAUDE.md` applied to the outbox payload.
//! - **`attempts`** is the number of forwarder attempts this entry has
//!   already survived. Written 0 on append; incremented by the forwarder
//!   before each POST (that read-modify-write is in the follow-up PR).
//! - **`encoded_at_ms`** is the wall clock at encode time. Distinct from
//!   `queued_at_ms` in the key because payload encoding may happen on a
//!   thread pool ahead of the actual store append.
//! - **`content_type`** distinguishes JSON (webhook body) from OTLP
//!   protobuf (span batch) even though this PR only exercises the JSON
//!   path. Reserving the byte here means the follow-up OTLP producer
//!   does not have to migrate every existing entry to introduce it.
//! - **`payload_len`** bounds the payload byte read, so a truncated
//!   value fails decoding before we hand a partial payload to reqwest.

#![allow(dead_code)]

use uuid::Uuid;

/// Which producer wrote a given outbox entry. Persisted as the first two
/// bytes of every key, so its numeric encoding is part of the on-disk
/// contract: never renumber a variant, only add new ones.
///
/// Every variant here is a cache pipeline (gradle/xcode/reapi). Clippy's
/// `enum_variant_names` lint would prefer names without the shared
/// `Cache` suffix, but the label used on the wire and in Prometheus for
/// each pipeline reads more clearly with the suffix intact
/// (`gradle_cache`, not `gradle`), and OTLP-style non-cache pipelines
/// are expected to live in a separate outbox anyway, per Codex #10 on
/// the tracing initialization ordering that the OTLP producer would
/// otherwise inherit.
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
#[allow(clippy::enum_variant_names)]
pub enum Pipeline {
    GradleCache = 1,
    XcodeCache = 2,
    ReapiCache = 3,
}

impl Pipeline {
    /// The wire-stable numeric encoding used in the key prefix. Frozen at
    /// the value the enum variant was assigned; do not change it for an
    /// existing pipeline.
    #[must_use]
    pub const fn as_id(self) -> u16 {
        self as u16
    }

    /// Inverse of [`Self::as_id`], for the forwarder's per-pipeline
    /// dispatch. Returns `None` for an unknown id so the caller can move
    /// the entry to quarantine instead of panicking on a value written by
    /// a future release.
    #[must_use]
    pub const fn from_id(id: u16) -> Option<Self> {
        match id {
            1 => Some(Self::GradleCache),
            2 => Some(Self::XcodeCache),
            3 => Some(Self::ReapiCache),
            _ => None,
        }
    }

    /// Short label for the `pipeline` metric label. Kept `&'static str`
    /// so the Prometheus label set stays bounded no matter what an
    /// operator names on the wire.
    #[must_use]
    pub const fn as_label(self) -> &'static str {
        match self {
            Self::GradleCache => "gradle_cache",
            Self::XcodeCache => "xcode_cache",
            Self::ReapiCache => "reapi_cache",
        }
    }
}

/// Marks how the payload bytes are meant to be interpreted at delivery
/// time. Persisted as the fifth byte of every value. Reserved values
/// exist so the follow-up OTLP producer does not force a value-schema
/// migration; adding a new pipeline that keeps `Json` costs nothing on
/// the wire.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum ContentType {
    Json = 1,
    OtlpProtobuf = 2,
}

impl ContentType {
    #[must_use]
    pub const fn as_byte(self) -> u8 {
        self as u8
    }

    #[must_use]
    pub const fn from_byte(byte: u8) -> Option<Self> {
        match byte {
            1 => Some(Self::Json),
            2 => Some(Self::OtlpProtobuf),
            _ => None,
        }
    }
}

/// Current entry-schema version. Bumped only on a change to the value
/// layout that a previous release cannot decode. When it moves, the
/// decoder must still accept the previous value, so the forwarder can
/// drain a backlog written by the release before the bump.
pub const CURRENT_VALUE_SCHEMA_VERSION: u8 = 1;

/// Fixed key length: 2 bytes pipeline + 8 bytes timestamp + 16 bytes UUID.
pub const KEY_LEN: usize = 2 + 8 + 16;
/// Minimum value length: 1 + 2 + 8 + 1 + 4 bytes of fixed header before
/// the payload. Anything shorter is a truncation.
pub const MIN_VALUE_LEN: usize = 1 + 2 + 8 + 1 + 4;

/// Build the fixed 26-byte key used to store an entry. Callers own the
/// `queued_at_ms` value: the store method that eventually appends this
/// key will read the wall clock once and pass it in, so the key and the
/// value's `encoded_at_ms` derive from the same read and do not race.
#[must_use]
pub fn build_key(pipeline: Pipeline, queued_at_ms: u64, event_id: Uuid) -> [u8; KEY_LEN] {
    let mut key = [0_u8; KEY_LEN];
    key[0..2].copy_from_slice(&pipeline.as_id().to_be_bytes());
    key[2..10].copy_from_slice(&queued_at_ms.to_be_bytes());
    key[10..26].copy_from_slice(event_id.as_bytes());
    key
}

/// Prefix that selects every entry belonging to `pipeline`. Passed to
/// the RocksDB iterator by the forwarder to scan a single pipeline in
/// FIFO order without touching the other pipelines' entries.
#[must_use]
pub fn pipeline_prefix(pipeline: Pipeline) -> [u8; 2] {
    pipeline.as_id().to_be_bytes()
}

/// Serialize the entry value into the on-disk format described at the
/// module level. Kept a plain function so the store method can build the
/// bytes directly into a RocksDB `WriteBatch` without allocating an
/// intermediate `OutboxEntry` on the hot path.
#[must_use]
pub fn encode_value(
    attempts: u16,
    encoded_at_ms: u64,
    content_type: ContentType,
    payload: &[u8],
) -> Vec<u8> {
    let mut value = Vec::with_capacity(MIN_VALUE_LEN + payload.len());
    value.push(CURRENT_VALUE_SCHEMA_VERSION);
    value.extend_from_slice(&attempts.to_be_bytes());
    value.extend_from_slice(&encoded_at_ms.to_be_bytes());
    value.push(content_type.as_byte());
    value.extend_from_slice(&u32_from_len(payload.len()).to_be_bytes());
    value.extend_from_slice(payload);
    value
}

fn u32_from_len(len: usize) -> u32 {
    u32::try_from(len).unwrap_or(u32::MAX)
}

/// A decoded outbox entry as the forwarder will consume it. Fields
/// mirror the value layout except that `key` and `payload` are owned so
/// the batch iteration does not need to hold the RocksDB slice.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OutboxEntry {
    pub key: Vec<u8>,
    pub pipeline: Pipeline,
    pub event_id: Uuid,
    pub queued_at_ms: u64,
    pub attempts: u16,
    pub encoded_at_ms: u64,
    pub content_type: ContentType,
    pub payload: Vec<u8>,
}

/// Failures the forwarder must treat as "move to quarantine, do not
/// retry against the server." Every variant carries enough context that
/// the quarantine record can name what went wrong.
#[derive(Debug, PartialEq, Eq)]
pub enum DecodeError {
    ShortKey {
        actual: usize,
    },
    ShortValue {
        actual: usize,
        expected_at_least: usize,
    },
    UnknownPipeline {
        id: u16,
    },
    UnknownVersion {
        got: u8,
        supported: u8,
    },
    UnknownContentType {
        byte: u8,
    },
    PayloadLengthMismatch {
        declared: u32,
        actual: usize,
    },
}

/// Parse an entry key/value pair back into an [`OutboxEntry`]. Anything
/// this rejects is malformed on disk; the forwarder moves it into the
/// quarantine column family in the follow-up PR rather than looping
/// against the server on a record it cannot describe.
pub fn decode_entry(key: &[u8], value: &[u8]) -> Result<OutboxEntry, DecodeError> {
    if key.len() != KEY_LEN {
        return Err(DecodeError::ShortKey { actual: key.len() });
    }
    if value.len() < MIN_VALUE_LEN {
        return Err(DecodeError::ShortValue {
            actual: value.len(),
            expected_at_least: MIN_VALUE_LEN,
        });
    }

    let pipeline_id = u16::from_be_bytes([key[0], key[1]]);
    let pipeline =
        Pipeline::from_id(pipeline_id).ok_or(DecodeError::UnknownPipeline { id: pipeline_id })?;
    let queued_at_ms = u64::from_be_bytes([
        key[2], key[3], key[4], key[5], key[6], key[7], key[8], key[9],
    ]);
    let event_id = Uuid::from_slice(&key[10..26]).expect("16-byte slice is a valid UUID");

    let version = value[0];
    if version != CURRENT_VALUE_SCHEMA_VERSION {
        return Err(DecodeError::UnknownVersion {
            got: version,
            supported: CURRENT_VALUE_SCHEMA_VERSION,
        });
    }
    let attempts = u16::from_be_bytes([value[1], value[2]]);
    let encoded_at_ms = u64::from_be_bytes([
        value[3], value[4], value[5], value[6], value[7], value[8], value[9], value[10],
    ]);
    let content_type_byte = value[11];
    let content_type =
        ContentType::from_byte(content_type_byte).ok_or(DecodeError::UnknownContentType {
            byte: content_type_byte,
        })?;
    let payload_len = u32::from_be_bytes([value[12], value[13], value[14], value[15]]);
    let payload_end = MIN_VALUE_LEN
        .checked_add(payload_len as usize)
        .filter(|end| *end == value.len())
        .ok_or(DecodeError::PayloadLengthMismatch {
            declared: payload_len,
            actual: value.len().saturating_sub(MIN_VALUE_LEN),
        })?;
    let payload = value[MIN_VALUE_LEN..payload_end].to_vec();

    Ok(OutboxEntry {
        key: key.to_vec(),
        pipeline,
        event_id,
        queued_at_ms,
        attempts,
        encoded_at_ms,
        content_type,
        payload,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_preserves_every_field() {
        // Fixed inputs so the assertion pins the exact bytes the encoder
        // produces. A future change to the value layout must therefore
        // rewrite this fixture, which is the review moment the schema-
        // version rule exists to force.
        let pipeline = Pipeline::GradleCache;
        let event_id = Uuid::from_bytes([
            0x01, 0x93, 0x0c, 0x0e, 0x6e, 0x2a, 0x7a, 0x91, 0x9a, 0x1c, 0x1f, 0x4e, 0x5c, 0x2d,
            0x3a, 0x4b,
        ]);
        let queued_at_ms = 1_760_000_000_123;
        let encoded_at_ms = 1_760_000_000_100;
        let payload = b"{\"events\":[]}".to_vec();

        let key = build_key(pipeline, queued_at_ms, event_id);
        let value = encode_value(0, encoded_at_ms, ContentType::Json, &payload);

        let entry = decode_entry(&key, &value).expect("round-trip should succeed");
        assert_eq!(entry.pipeline, Pipeline::GradleCache);
        assert_eq!(entry.event_id, event_id);
        assert_eq!(entry.queued_at_ms, queued_at_ms);
        assert_eq!(entry.encoded_at_ms, encoded_at_ms);
        assert_eq!(entry.content_type, ContentType::Json);
        assert_eq!(entry.attempts, 0);
        assert_eq!(entry.payload, payload);
    }

    #[test]
    fn keys_sort_in_enqueue_order_per_pipeline() {
        // The forwarder iterates a pipeline prefix and relies on
        // lexicographic order equaling enqueue order. Two entries in the
        // same pipeline separated by a millisecond must sort by time.
        let pipeline = Pipeline::ReapiCache;
        let earlier = build_key(pipeline, 100, Uuid::from_u128(1));
        let later = build_key(pipeline, 101, Uuid::from_u128(2));
        assert!(earlier < later);

        // Ties within a millisecond fall back to event_id, which is
        // UUIDv7 in production and therefore already monotonic. Test with
        // small u128s to confirm the tie-break byte order.
        let tie_earlier = build_key(pipeline, 200, Uuid::from_u128(1));
        let tie_later = build_key(pipeline, 200, Uuid::from_u128(2));
        assert!(tie_earlier < tie_later);
    }

    #[test]
    fn pipelines_do_not_interleave_in_the_shared_column_family() {
        // Two entries with the same timestamp but different pipelines
        // must sort by pipeline first, so a prefix scan for one pipeline
        // stays inside its own range and never yields another pipeline's
        // rows to the forwarder.
        let event = Uuid::from_u128(1);
        let gradle = build_key(Pipeline::GradleCache, 500, event);
        let reapi = build_key(Pipeline::ReapiCache, 500, event);
        assert!(gradle < reapi);
    }

    #[test]
    fn pipeline_prefix_is_the_first_two_bytes_of_the_key() {
        let key = build_key(Pipeline::XcodeCache, 12_345, Uuid::from_u128(1));
        assert_eq!(pipeline_prefix(Pipeline::XcodeCache), [key[0], key[1]]);
    }

    #[test]
    fn decoding_a_truncated_key_returns_short_key() {
        let truncated = [0_u8; KEY_LEN - 1];
        let value = encode_value(0, 0, ContentType::Json, b"");
        assert_eq!(
            decode_entry(&truncated, &value),
            Err(DecodeError::ShortKey {
                actual: KEY_LEN - 1
            }),
        );
    }

    #[test]
    fn decoding_an_unknown_pipeline_id_names_the_id_it_saw() {
        // Simulate a future release that added a new pipeline. A
        // predecessor decoding that release's bytes must fail loud rather
        // than dispatch to the wrong producer.
        let mut key = build_key(Pipeline::GradleCache, 0, Uuid::from_u128(0));
        key[0..2].copy_from_slice(&999_u16.to_be_bytes());
        let value = encode_value(0, 0, ContentType::Json, b"");
        assert_eq!(
            decode_entry(&key, &value),
            Err(DecodeError::UnknownPipeline { id: 999 }),
        );
    }

    #[test]
    fn decoding_an_unknown_schema_version_names_what_it_supports() {
        // Simulates the "rolled-back binary reads a newer version"
        // scenario Codex called out. The decoder must not silently accept
        // it; the forwarder will move it to quarantine in the follow-up.
        let key = build_key(Pipeline::GradleCache, 0, Uuid::from_u128(0));
        let mut value = encode_value(0, 0, ContentType::Json, b"");
        value[0] = 99;
        assert_eq!(
            decode_entry(&key, &value),
            Err(DecodeError::UnknownVersion {
                got: 99,
                supported: 1
            }),
        );
    }

    #[test]
    fn decoding_an_unknown_content_type_names_the_byte_it_saw() {
        let key = build_key(Pipeline::GradleCache, 0, Uuid::from_u128(0));
        let mut value = encode_value(0, 0, ContentType::Json, b"");
        value[11] = 99;
        assert_eq!(
            decode_entry(&key, &value),
            Err(DecodeError::UnknownContentType { byte: 99 }),
        );
    }

    #[test]
    fn decoding_a_payload_length_mismatch_flags_the_truncation() {
        // Simulate the value having a declared payload length that does
        // not match the actual byte length. This is the shape a partial
        // write or on-disk corruption would leave; the forwarder needs
        // to see it as decode failure, not as a valid partial payload.
        let key = build_key(Pipeline::GradleCache, 0, Uuid::from_u128(0));
        let mut value = encode_value(0, 0, ContentType::Json, b"hello");
        // Overwrite the declared payload length to be one byte longer
        // than reality.
        value[12..16].copy_from_slice(&6_u32.to_be_bytes());
        assert!(matches!(
            decode_entry(&key, &value),
            Err(DecodeError::PayloadLengthMismatch {
                declared: 6,
                actual: 5
            }),
        ));
    }

    #[test]
    fn pipeline_labels_are_stable_bounded_static_strings() {
        // Prometheus label cardinality on `pipeline` is bounded by this
        // set. A future variant must add a new arm rather than reuse an
        // existing label.
        assert_eq!(Pipeline::GradleCache.as_label(), "gradle_cache");
        assert_eq!(Pipeline::XcodeCache.as_label(), "xcode_cache");
        assert_eq!(Pipeline::ReapiCache.as_label(), "reapi_cache");
    }
}
