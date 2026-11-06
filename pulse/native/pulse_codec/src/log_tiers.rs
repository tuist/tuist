//! Stream-grouped log segments.
//!
//! Ingested and compacted log segments hold a slice of time of every stream,
//! so a stream selector cannot skip any of them. A `Grouper` regroups the
//! rows of many such segments by service (by the whole stream, its stored
//! resource labels, for rows without one) into new segments: a group with
//! at least a target's worth of rows fills whole segments of its own, and
//! smaller groups are packed together, in group order, into segments of at
//! most `pack_bytes` decoded string bytes, so a small service shares an
//! object with few others. Every output has the encoder's schema,
//! `(service, timestamp_ns)` order and writer settings
//! (`segment_parquet::encode_sorted`), and rows never become Erlang terms.
//!
//! Sources are added one at a time; rows are held natively by group until
//! `next` encodes them. Without `finish`, `next` encodes only a full group
//! or, while held rows exceed `max_held` decoded string bytes, the largest
//! group or a pack, so memory stays near `max_held` plus one source.

use crate::segment_parquet::{self, CompactError};
use arrow::array::{Array, Int64Array, StringArray, UInt32Array};
use arrow::compute::take_record_batch;
use arrow::record_batch::RecordBatch;
use bytes::Bytes;
use rustler::{Binary, Env};
use std::collections::{BTreeMap, BTreeSet, HashMap};

/// A row's group: its nonempty service, or else its whole stream (resource
/// labels). Rows without a service sort first, as the encoder sorts them.
type GroupKey = (Option<String>, Option<String>);
/// A distinct stream of an output: `(service, resource)`.
type StreamKey = (Option<String>, String);

#[derive(Default)]
struct Group {
    batches: Vec<RecordBatch>,
    rows: usize,
    bytes: usize,
}

pub struct Grouper {
    groups: BTreeMap<GroupKey, Group>,
    held: usize,
    target_rows: usize,
    target_bytes: usize,
    pack_bytes: usize,
    max_held: usize,
}

/// One encoded output and its summaries: the complete nonempty service set
/// (`None` when unknown, as for compaction), its distinct streams (`None`
/// above `MAX_STREAMS`) and its line counts per minute bucket (`None` when a
/// row has no timestamp or above `MAX_MINUTES` buckets).
pub struct Output<'a> {
    pub payload: Binary<'a>,
    pub min_ts: i64,
    pub max_ts: i64,
    pub rows: usize,
    pub services: Option<Vec<String>>,
    pub streams: Option<Vec<StreamKey>>,
    pub minutes: Option<Vec<(i64, u64)>>,
}

const MAX_STREAMS: usize = 4096;
// Twice `Segment.log_minutes/1`'s bound, as for merged segments.
const MAX_MINUTES: usize = 2 * 1440;
const MINUTE_NS: i64 = 60_000_000_000;

impl Grouper {
    pub fn new(
        target_rows: usize,
        target_bytes: usize,
        pack_bytes: usize,
        max_held: usize,
    ) -> Self {
        Grouper {
            groups: BTreeMap::new(),
            held: 0,
            target_rows,
            target_bytes,
            pack_bytes: pack_bytes.min(target_bytes),
            max_held,
        }
    }

    /// Split one stored segment's rows by group; returns its row count.
    pub fn add(&mut self, bytes: Bytes) -> Result<usize, CompactError> {
        let (_declared, batches) = segment_parquet::segment_batches(bytes, 8192)?;
        let mut rows = 0;
        for batch in batches {
            let batch = batch?;
            rows += batch.num_rows();
            let service = strings(&batch, "service")?;
            let resource = strings(&batch, "resource")?;
            let mut indices: HashMap<(Option<&str>, Option<&str>), Vec<u32>> = HashMap::new();
            for row in 0..batch.num_rows() {
                let key = match (!service.is_null(row)).then(|| service.value(row)) {
                    Some(name) if !name.is_empty() => (Some(name), None),
                    _ => (None, Some(resource.value(row))),
                };
                let row = u32::try_from(row).map_err(|_| CompactError::Invalid)?;
                indices.entry(key).or_default().push(row);
            }
            for ((service, resource), rows) in indices {
                let part = if rows.len() == batch.num_rows() {
                    batch.clone()
                } else {
                    take_record_batch(&batch, &UInt32Array::from(rows))
                        .map_err(|_| CompactError::Invalid)?
                };
                let bytes = segment_parquet::string_bytes(&part);
                let group = self
                    .groups
                    .entry((service.map(str::to_owned), resource.map(str::to_owned)))
                    .or_default();
                group.rows += part.num_rows();
                group.bytes += bytes;
                group.batches.push(part);
                self.held += bytes;
            }
        }
        Ok(rows)
    }

    /// The next output to upload, if any (see the module documentation).
    pub fn next<'a>(
        &mut self,
        env: Env<'a>,
        finish: bool,
    ) -> Result<Option<Output<'a>>, CompactError> {
        let full = self
            .groups
            .iter()
            .find(|(_, g)| g.rows >= self.target_rows || g.bytes >= self.target_bytes)
            .map(|(key, _)| key.clone());
        if let Some(key) = full {
            let batches = self.take_chunk(&key);
            return encode(env, batches).map(Some);
        }
        if self.groups.is_empty() || !(finish || self.held > self.max_held) {
            return Ok(None);
        }
        if !finish {
            // Under memory pressure a large group leaves alone rather than
            // with a pack that would split the small groups more often.
            let largest = self
                .groups
                .iter()
                .max_by_key(|(_, g)| g.bytes)
                .filter(|(_, g)| g.bytes >= self.target_bytes / 4)
                .map(|(key, _)| key.clone());
            if let Some(key) = largest {
                let group = self.remove(&key);
                return encode(env, group.batches).map(Some);
            }
        }
        // Whole groups in group order while they fit one pack; a group
        // larger than a pack leaves alone.
        let (mut rows, mut bytes) = (0, 0);
        let mut keys = Vec::new();
        for (key, group) in &self.groups {
            if !keys.is_empty()
                && (rows + group.rows > self.target_rows || bytes + group.bytes > self.pack_bytes)
            {
                break;
            }
            rows += group.rows;
            bytes += group.bytes;
            keys.push(key.clone());
        }
        let mut batches = Vec::new();
        for key in keys {
            batches.extend(self.remove(&key).batches);
        }
        encode(env, batches).map(Some)
    }

    fn remove(&mut self, key: &GroupKey) -> Group {
        let group = self.groups.remove(key).unwrap_or_default();
        self.held -= group.bytes;
        group
    }

    // A target's worth of one group's rows, in the order they were added.
    fn take_chunk(&mut self, key: &GroupKey) -> Vec<RecordBatch> {
        let (target_rows, target_bytes) = (self.target_rows, self.target_bytes);
        let Some(group) = self.groups.get_mut(key) else {
            return Vec::new();
        };
        let (mut rows, mut bytes, mut count) = (0, 0, 0);
        for batch in &group.batches {
            let size = segment_parquet::string_bytes(batch);
            if count > 0 && (rows + batch.num_rows() > target_rows || bytes + size > target_bytes) {
                break;
            }
            rows += batch.num_rows();
            bytes += size;
            count += 1;
        }
        let taken: Vec<RecordBatch> = group.batches.drain(..count).collect();
        group.rows -= rows;
        group.bytes -= bytes;
        self.held -= bytes;
        if group.batches.is_empty() {
            self.groups.remove(key);
        }
        taken
    }
}

fn strings<'b>(batch: &'b RecordBatch, name: &str) -> Result<&'b StringArray, CompactError> {
    batch
        .column_by_name(name)
        .and_then(|c| c.as_any().downcast_ref::<StringArray>())
        .ok_or(CompactError::Invalid)
}

fn encode<'a>(env: Env<'a>, batches: Vec<RecordBatch>) -> Result<Output<'a>, CompactError> {
    let (mut min_ts, mut max_ts, mut rows) = (i64::MAX, i64::MIN, 0usize);
    let mut services = Some(BTreeSet::new());
    let mut streams = Some(BTreeSet::new());
    let mut minutes = Some(BTreeMap::<i64, u64>::new());
    for batch in &batches {
        let ts = batch
            .column_by_name("timestamp_ns")
            .and_then(|c| c.as_any().downcast_ref::<Int64Array>())
            .ok_or(CompactError::Invalid)?;
        let service = strings(batch, "service")?;
        let resource = strings(batch, "resource")?;
        for i in 0..batch.num_rows() {
            rows += 1;
            // Null timestamps bound as 0, as the encoder and compaction do.
            let value = if ts.is_null(i) { 0 } else { ts.value(i) };
            min_ts = min_ts.min(value);
            max_ts = max_ts.max(value);
            minutes = minutes.filter(|_| !ts.is_null(i)).and_then(|mut counts| {
                *counts.entry(minute(value)).or_default() += 1;
                (counts.len() <= MAX_MINUTES).then_some(counts)
            });
            let name = (!service.is_null(i)).then(|| service.value(i));
            services = services.and_then(|mut set| match name {
                Some(name) if !name.is_empty() && name.len() <= 256 => {
                    if !set.contains(name) {
                        set.insert(name.to_owned());
                    }
                    (set.len() <= 128).then_some(set)
                }
                _ => None,
            });
            streams = streams.and_then(|mut set| {
                let key = (name, resource.value(i));
                if !set.contains(&key) {
                    set.insert(key);
                }
                (set.len() <= MAX_STREAMS).then_some(set)
            });
        }
    }
    if rows == 0 {
        (min_ts, max_ts) = (0, 0);
    }
    let streams = streams.map(|set| {
        set.into_iter()
            .map(|(s, r)| (s.map(str::to_owned), r.to_owned()))
            .collect()
    });
    let services = services.map(|set| set.into_iter().collect());
    let minutes = minutes.map(|counts| counts.into_iter().collect());
    let payload = segment_parquet::encode_sorted(env, batches, rows)?;
    Ok(Output {
        payload,
        min_ts,
        max_ts,
        rows,
        services,
        streams,
        minutes,
    })
}

// `Segment.log_minute/1`: the minute bucket ending at or after `ts`.
fn minute(ts: i64) -> i64 {
    let bucket = (i128::from(ts) - 1).div_euclid(i128::from(MINUTE_NS)) + 1;
    i64::try_from(bucket).unwrap_or(i64::MAX)
}
