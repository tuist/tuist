//! Hand-rolled Prometheus remote_write v1 `WriteRequest` decoder.
//!
//! Reference: `prometheus/prometheus` repo, `prompb/types.proto` plus
//! `prompb/remote.proto`. The subset we care about:
//!
//! ```proto
//! message WriteRequest {
//!   repeated TimeSeries timeseries = 1 [(gogoproto.nullable) = false];
//!   repeated MetricMetadata metadata = 3 [(gogoproto.nullable) = false];
//! }
//!
//! message MetricMetadata {
//!   MetricType type = 1; string metric_family_name = 2;
//!   string help = 4; string unit = 5;
//! }
//!
//! message TimeSeries {
//!   repeated Label   labels    = 1 [(gogoproto.nullable) = false];
//!   repeated Sample  samples   = 2 [(gogoproto.nullable) = false];
//!   // exemplars (3), native histograms (4) explicitly counted as rejected
//! }
//!
//! message Label  { string name = 1; string value = 2; }
//! message Sample { double value = 1; int64  timestamp = 2; }
//! ```
//!
//! The wire bytes come to us Snappy-compressed (block format, same as
//! Loki push). Our contract matches `loki::decode`: we read sub-slices
//! of the decompressed buffer and never allocate per label/sample so
//! downstream code can turn them into Erlang sub-binaries. Semantic
//! errors (missing timestamp, out-of-range sample, non-UTF-8 label) are
//! counted in `rejected` rather than failing the whole batch — a
//! wire-level corruption (bad varint, truncated field) still fails
//! the whole request.
//!
//! Timestamp units: Prometheus remote_write v1 timestamps are
//! **milliseconds** since epoch. We leave that unchanged in the
//! decoded `Sample` and let the Elixir caller scale to nanoseconds
//! at the storage boundary.

use crate::exemplar::{self, Exemplar};
use crate::native_histogram::{self, Histogram};
use crate::wire::{Reader, Value};

pub struct Sample {
    pub value: f64,
    pub timestamp_ms: i64,
    pub start_timestamp_ms: Option<i64>,
}

pub struct Series<'a> {
    pub labels: Vec<(&'a [u8], &'a [u8])>,
    pub samples: Vec<Sample>,
    /// Native histograms with their millisecond timestamps.
    pub histograms: Vec<(Histogram, i64, Option<i64>)>,
    pub exemplars: Vec<Exemplar<'a>>,
}

/// One `MetricMetadata` entry: family name, Prometheus type name, help, unit.
pub struct Metadata<'a> {
    pub name: &'a [u8],
    pub kind: &'static str,
    pub help: &'a [u8],
    pub unit: &'a [u8],
}

pub struct Decoded<'a> {
    pub series: Vec<Series<'a>>,
    pub rejected: u64,
    pub metadata: Vec<Metadata<'a>>,
}

pub fn decode(input: &[u8]) -> Option<Decoded<'_>> {
    let mut reader = Reader::new(input);
    let mut decoded = Decoded {
        series: Vec::new(),
        rejected: 0,
        metadata: Vec::new(),
    };

    loop {
        match reader.next_field()? {
            None => break,
            Some((1, Value::Bytes(bytes))) => match decode_series(bytes) {
                Ok((s, rejected)) => {
                    decoded.series.push(s);
                    decoded.rejected = decoded.rejected.saturating_add(rejected);
                }
                Err(rejected) => decoded.rejected = decoded.rejected.saturating_add(rejected),
            },
            // Metadata without a valid UTF-8 family name and known type is
            // dropped; it never fails the samples of the request.
            Some((3, Value::Bytes(bytes))) => {
                if let Some(entry) = decode_metadata(bytes) {
                    decoded.metadata.push(entry);
                }
            }
            // Other fields are ignored.
            _ => {}
        }
    }

    Some(decoded)
}

// Prometheus `MetricMetadata.MetricType` names, as `/api/v1/metadata` reports them.
const METRIC_TYPES: [&str; 8] = [
    "unknown",
    "counter",
    "gauge",
    "histogram",
    "gaugehistogram",
    "summary",
    "info",
    "stateset",
];

fn decode_metadata(input: &[u8]) -> Option<Metadata<'_>> {
    let mut reader = Reader::new(input);
    let mut entry = Metadata {
        name: &[],
        kind: METRIC_TYPES[0],
        help: &[],
        unit: &[],
    };
    loop {
        match reader.next_field()? {
            None => break,
            Some((1, Value::Varint(t))) => {
                entry.kind = METRIC_TYPES.get(usize::try_from(t).ok()?)?;
            }
            Some((2, Value::Bytes(b))) => entry.name = b,
            Some((4, Value::Bytes(b))) => entry.help = b,
            Some((5, Value::Bytes(b))) => entry.unit = b,
            _ => {}
        }
    }
    let valid = |b: &[u8]| simdutf8::basic::from_utf8(b).is_ok();
    (!entry.name.is_empty() && valid(entry.name) && valid(entry.help) && valid(entry.unit))
        .then_some(entry)
}

fn decode_series(input: &[u8]) -> Result<(Series<'_>, u64), u64> {
    let mut reader = Reader::new(input);
    let mut labels: Vec<(&[u8], &[u8])> = Vec::new();
    let mut parts = Parts::default();

    loop {
        match reader.next_field().ok_or(parts.total.max(1))? {
            None => break,
            Some((1, Value::Bytes(bytes))) => {
                let label = decode_label(bytes).ok_or(parts.total.max(1))?;
                labels.push(label);
            }
            Some((2, Value::Bytes(bytes))) => parts.sample(bytes, None)?,
            Some((3, Value::Bytes(bytes))) => parts.exemplar(exemplar::decode_v1(bytes)),
            Some((4, Value::Bytes(bytes))) => parts.histogram(bytes, None),
            _ => {}
        }
    }

    let rejected = parts.rejected;
    let series = finish_series(labels, parts)?;
    Ok((series, rejected))
}

// What one series carries, shared by both protocol versions. `total` counts
// supplied samples and histograms, so a rejected series reports all of them;
// invalid histograms count as rejected, invalid exemplars are dropped (they
// are not samples), as in Prometheus.
#[derive(Default)]
struct Parts<'a> {
    samples: Vec<Sample>,
    histograms: Vec<(Histogram, i64, Option<i64>)>,
    exemplars: Vec<Exemplar<'a>>,
    total: u64,
    rejected: u64,
}

impl<'a> Parts<'a> {
    fn sample(&mut self, bytes: &[u8], start: Option<i64>) -> Result<(), u64> {
        self.total = self.total.saturating_add(1);
        let mut sample = decode_sample(bytes).ok_or(self.total)?;
        sample.start_timestamp_ms = start;
        self.samples.push(sample);
        Ok(())
    }

    fn histogram(&mut self, bytes: &[u8], start: Option<i64>) {
        self.total = self.total.saturating_add(1);
        let decoded = native_histogram::decode_wire(bytes).map(|(h, ts)| (h, ts, start));
        match decoded {
            Some(histogram) => self.histograms.push(histogram),
            None => self.rejected = self.rejected.saturating_add(1),
        }
    }

    fn exemplar(&mut self, exemplar: Option<Exemplar<'a>>) {
        self.exemplars.extend(exemplar);
    }
}

// Shared by both protocol versions, after the whole series was read so
// rejected counts include every supplied sample.
fn finish_series<'a>(
    mut labels: Vec<(&'a [u8], &'a [u8])>,
    parts: Parts<'a>,
) -> Result<Series<'a>, u64> {
    let total_samples = parts.total;
    // Prometheus requires at least `__name__` and one sample per series.
    // Treat a labels- or samples-empty series as rejected rather than
    // feeding a nameless point into storage. Senders put exemplars in
    // series entries of their own, so exemplars alone are enough.
    let empty =
        parts.samples.is_empty() && parts.histograms.is_empty() && parts.exemplars.is_empty();
    if labels.is_empty() || empty {
        return Err(total_samples.max(1));
    }

    // UTF-8 validation also excludes the 0xff byte used as the canonical
    // label separator in storage.
    if labels.iter().any(|(name, value)| {
        name.is_empty()
            || simdutf8::basic::from_utf8(name).is_err()
            || simdutf8::basic::from_utf8(value).is_err()
    }) {
        return Err(total_samples.max(1));
    }
    labels.sort_by(|a, b| a.0.cmp(b.0));
    if labels.windows(2).any(|pair| pair[0].0 == pair[1].0) {
        return Err(total_samples.max(1));
    }
    // Empty-valued labels are absent from Prometheus series identities.
    // Validate names, UTF-8 and duplicates first: removing a losing label
    // must not conceal an invalid series. Raw admission already charged it.
    labels.retain(|(_, value)| !value.is_empty());
    if labels.is_empty() {
        return Err(total_samples.max(1));
    }
    Ok(Series {
        labels,
        samples: parts.samples,
        histograms: parts.histograms,
        exemplars: parts.exemplars,
    })
}

/// Decode a Remote Write 2.0 `io.prometheus.write.v2.Request`:
///
/// ```proto
/// message Request { repeated string symbols = 4; repeated TimeSeries timeseries = 5; }
/// message TimeSeries {
///   repeated uint32 labels_refs = 1;   // name/value pairs of symbol indexes
///   repeated Sample samples = 2;
///   repeated Histogram histograms = 3; // native histograms: rejected
///   repeated Exemplar exemplars = 4;   // not stored: reported as unwritten
///   Metadata metadata = 5;             // type = 1, help_ref = 3, unit_ref = 4
/// }
/// ```
///
/// Series and samples follow the v1 rules. A series whose label or metadata
/// references fall outside the symbol table is rejected whole, as Prometheus's
/// receiver does. Metadata is reported once per distinct entry, under the
/// series' metric family name (OpenMetrics suffixes trimmed by type, as Mimir
/// does), and only when it carries a type, help or unit.
pub fn decode_v2(input: &[u8]) -> Option<Decoded<'_>> {
    // Symbols may appear anywhere in the message, so collect them first.
    let mut symbols: Vec<&[u8]> = Vec::new();
    let mut reader = Reader::new(input);
    while let Some((field, value)) = reader.next_field()? {
        if let (4, Value::Bytes(symbol)) = (field, value) {
            symbols.push(symbol);
        }
    }
    // The reserved empty symbol is a request-level RW2 invariant, not a
    // per-series reference error. Reject before exposing samples or metadata.
    if symbols.first().is_some_and(|symbol| !symbol.is_empty()) {
        return None;
    }

    let mut decoded = Decoded {
        series: Vec::new(),
        rejected: 0,
        metadata: Vec::new(),
    };
    let mut seen = std::collections::HashSet::new();
    let mut reader = Reader::new(input);
    while let Some((field, value)) = reader.next_field()? {
        let (5, Value::Bytes(bytes)) = (field, value) else {
            continue;
        };
        match decode_series_v2(bytes, &symbols) {
            Ok(Some((series, rejected, metadata))) => {
                decoded.series.push(series);
                decoded.rejected = decoded.rejected.saturating_add(rejected);
                if let Some(m) = metadata {
                    if seen.insert((m.name, m.kind, m.help, m.unit)) {
                        decoded.metadata.push(m);
                    }
                }
            }
            Ok(None) => return None,
            Err(rejected) => decoded.rejected = decoded.rejected.saturating_add(rejected),
        }
    }
    Some(decoded)
}

type SeriesV2<'a> = (Series<'a>, u64, Option<Metadata<'a>>);

// None is wire corruption and fails the request; Err counts semantic rejects.
// Do not rely on admission preflight alone for malformed start atomicity.
fn decode_series_v2<'a>(
    input: &'a [u8],
    symbols: &[&'a [u8]],
) -> Result<Option<SeriesV2<'a>>, u64> {
    let mut reader = Reader::new(input);
    let mut refs: Vec<u64> = Vec::new();
    let mut metadata: &[u8] = &[];
    let mut parts = Parts::default();
    let mut created_timestamp = None;

    loop {
        let Some(field) = reader.next_field() else {
            return Ok(None);
        };
        match field {
            None => break,
            // Repeated scalars may arrive packed or one varint per element.
            Some((1, Value::Bytes(packed))) => {
                let mut pos = 0;
                while pos < packed.len() {
                    let (r, consumed) = read_varint(packed, pos).ok_or(parts.total.max(1))?;
                    refs.push(r);
                    pos += consumed;
                }
            }
            Some((1, Value::Varint(r))) => refs.push(r),
            Some((2, Value::Bytes(bytes))) => {
                let Some(start) = start_timestamp(bytes, 3) else {
                    return Ok(None);
                };
                parts.sample(bytes, start)?;
            }
            Some((3, Value::Bytes(bytes))) => {
                let Some(start) = start_timestamp(bytes, 17) else {
                    return Ok(None);
                };
                parts.histogram(bytes, start);
            }
            Some((4, Value::Bytes(bytes))) => parts.exemplar(exemplar::decode_v2(bytes, symbols)),
            Some((5, Value::Bytes(bytes))) => metadata = bytes,
            // rc.3 (Prometheus <=3.7): per-series created timestamp. rc.4+
            // reserves this field and moves it onto each sample/histogram.
            Some((6, Value::Varint(v))) => created_timestamp = Some(v as i64),
            Some((6, _)) => return Ok(None),
            _ => {}
        }
    }

    // Preserve the full signed int64 wire domain in milliseconds. Do not
    // rescale to ns, clamp, synthesize zero rows or consult node-local history.
    // A present modern field wins, including explicit zero (unset).
    for sample in &mut parts.samples {
        sample.start_timestamp_ms = sample
            .start_timestamp_ms
            .or(created_timestamp)
            .filter(|v| *v != 0);
    }
    for (_, _, start) in &mut parts.histograms {
        *start = start.or(created_timestamp).filter(|v| *v != 0);
    }

    let fail = parts.total.max(1);
    let rejected = parts.rejected;
    let symbol = |r: u64| -> Result<&'a [u8], u64> {
        usize::try_from(r)
            .ok()
            .filter(|_| r <= u64::from(u32::MAX))
            .and_then(|i| symbols.get(i).copied())
            .ok_or(fail)
    };
    if !refs.len().is_multiple_of(2) {
        return Err(fail);
    }
    let mut labels = Vec::with_capacity(refs.len() / 2);
    for pair in refs.as_chunks::<2>().0 {
        let name = symbol(pair[0])?;
        if name.is_empty() {
            return Err(fail);
        }
        labels.push((name, symbol(pair[1])?));
    }

    let (mut kind, mut help_ref, mut unit_ref) = (0u64, 0u64, 0u64);
    let mut meta = Reader::new(metadata);
    while let Some(field) = meta.next_field().ok_or(fail)? {
        match field {
            (1, Value::Varint(v)) => kind = v,
            (3, Value::Varint(v)) => help_ref = v,
            (4, Value::Varint(v)) => unit_ref = v,
            _ => {}
        }
    }
    // An empty symbol table resolves nothing, but unset references are zero.
    let optional = |r: u64| {
        if r == 0 && symbols.is_empty() {
            Ok(&[][..])
        } else {
            symbol(r)
        }
    };
    let (help, unit) = (optional(help_ref)?, optional(unit_ref)?);

    let series = finish_series(labels, parts)?;
    let family = series
        .labels
        .iter()
        .find(|(name, _)| *name == b"__name__")
        .map(|(_, value)| *value);
    let kind = usize::try_from(kind)
        .ok()
        .and_then(|k| METRIC_TYPES.get(k))
        .copied()
        .unwrap_or(METRIC_TYPES[0]);
    let entry = family
        .map(|name| family_name(name, kind))
        .filter(|name| !name.is_empty())
        .filter(|_| kind != METRIC_TYPES[0] || !help.is_empty() || !unit.is_empty())
        .filter(|_| {
            simdutf8::basic::from_utf8(help).is_ok() && simdutf8::basic::from_utf8(unit).is_ok()
        })
        .map(|name| Metadata {
            name,
            kind,
            help,
            unit,
        });
    Ok(Some((series, rejected, entry)))
}

// The metric family a series belongs to, cutting the suffix its type
// mandates in OpenMetrics. `_total` and `_info` stay, as Prometheus's
// metadata reports them.
fn family_name<'a>(series_name: &'a [u8], kind: &str) -> &'a [u8] {
    let suffixes: &[&[u8]] = match kind {
        "summary" => &[b"_count", b"_sum"],
        "histogram" => &[b"_bucket", b"_count", b"_sum"],
        "gaugehistogram" => &[b"_bucket", b"_gcount", b"_gsum"],
        _ => &[],
    };
    suffixes
        .iter()
        .find_map(|suffix| series_name.strip_suffix(*suffix))
        .unwrap_or(series_name)
}

fn decode_label(input: &[u8]) -> Option<(&[u8], &[u8])> {
    let mut reader = Reader::new(input);
    let mut name: &[u8] = &[];
    let mut value: &[u8] = &[];
    loop {
        match reader.next_field()? {
            None => break,
            Some((1, Value::Bytes(b))) => name = b,
            Some((2, Value::Bytes(b))) => value = b,
            _ => {}
        }
    }
    // Defer semantic name validation until every supplied point is counted.
    Some((name, value))
}

fn decode_sample(input: &[u8]) -> Option<Sample> {
    // In proto3 wire format:
    //   field 1 (double value) is wire type 1 (64-bit fixed), tag byte 0x09.
    //   field 2 (int64 timestamp) is wire type 0 (varint), tag byte 0x10.
    //
    // Our minimal `Reader` only handles varint and length-delimited;
    // fixed64 needs a tiny inline decode here. We walk the buffer by
    // hand so we don't need to extend `Reader` just for this one site.
    let mut i = 0usize;
    let mut value_bits: u64 = 0;
    let mut timestamp_ms: i64 = 0;
    while i < input.len() {
        let (field, wire, consumed) = read_tag(input, i)?;
        i += consumed;
        match (field, wire) {
            (1, 1) => {
                // fixed64 little-endian
                if i + 8 > input.len() {
                    return None;
                }
                let mut bytes = [0u8; 8];
                bytes.copy_from_slice(&input[i..i + 8]);
                value_bits = u64::from_le_bytes(bytes);
                i += 8;
            }
            (2, 0) => {
                let (v, consumed) = read_varint(input, i)?;
                i += consumed;
                timestamp_ms = v as i64;
            }
            // Skip unknown fields.
            (_, 0) => {
                let (_, consumed) = read_varint(input, i)?;
                i += consumed;
            }
            (_, 1) => {
                if i + 8 > input.len() {
                    return None;
                }
                i += 8;
            }
            (_, 2) => {
                let (len, consumed) = read_varint(input, i)?;
                i += consumed;
                let len = len as usize;
                if i + len > input.len() {
                    return None;
                }
                i += len;
            }
            (_, 5) => {
                if i + 4 > input.len() {
                    return None;
                }
                i += 4;
            }
            _ => return None,
        }
    }
    Some(Sample {
        value: f64::from_bits(value_bits),
        timestamp_ms,
        start_timestamp_ms: None,
    })
}

// Proto3 singular int64: last occurrence wins; retain presence until legacy
// fallback is resolved, since an explicit modern zero overrides rc.3 data.
fn start_timestamp(input: &[u8], number: u64) -> Option<Option<i64>> {
    let mut reader = Reader::new(input);
    let mut start = None;
    while let Some((field, value)) = reader.next_field()? {
        if field == number {
            let Value::Varint(value) = value else {
                return None;
            };
            start = Some(value as i64);
        }
    }
    Some(start)
}

fn read_tag(buf: &[u8], pos: usize) -> Option<(u32, u8, usize)> {
    let (v, consumed) = read_varint(buf, pos)?;
    let field = (v >> 3) as u32;
    let wire = (v & 0x7) as u8;
    Some((field, wire, consumed))
}

fn read_varint(buf: &[u8], pos: usize) -> Option<(u64, usize)> {
    let mut out: u64 = 0;
    for (idx, shift) in (0..64).step_by(7).enumerate() {
        let byte = *buf.get(pos + idx)?;
        out |= u64::from(byte & 0x7f) << shift;
        if byte & 0x80 == 0 {
            return Some((out, idx + 1));
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    // All test fields are shorter than 128 bytes, so lengths fit one varint byte.
    fn bytes_field(tag: u8, bytes: &[u8]) -> Vec<u8> {
        assert!(bytes.len() < 128);
        [vec![tag, bytes.len() as u8], bytes.to_vec()].concat()
    }

    fn series(labels: &[(&[u8], &[u8])]) -> Vec<u8> {
        let mut out = Vec::new();
        for (name, value) in labels {
            let label = [bytes_field(0x0a, name), bytes_field(0x12, value)].concat();
            out.extend(bytes_field(0x0a, &label));
        }
        for timestamp in 1..=3 {
            let sample = [
                vec![0x09],
                1.0f64.to_le_bytes().to_vec(),
                vec![0x10, timestamp],
            ]
            .concat();
            out.extend(bytes_field(0x12, &sample));
        }
        out
    }

    #[test]
    fn decodes_metric_metadata_and_drops_invalid_entries() {
        let entry = |kind: u8, name: &[u8], help: &[u8]| {
            let mut fields = vec![0x08, kind];
            fields.extend(bytes_field(0x12, name));
            fields.extend(bytes_field(0x22, help));
            fields.extend(bytes_field(0x2a, b"seconds"));
            bytes_field(0x1a, &fields)
        };
        let request = [
            entry(1, b"http_requests_total", b"Requests."),
            entry(9, b"unknown_type", b""),
            entry(2, b"", b"no name"),
            entry(3, b"latency\xff", b""),
        ]
        .concat();
        let decoded = decode(&request).unwrap();
        assert!(decoded.series.is_empty());
        assert_eq!(decoded.metadata.len(), 1);
        let m = &decoded.metadata[0];
        assert_eq!(
            (m.name, m.kind, m.help, m.unit),
            (
                &b"http_requests_total"[..],
                "counter",
                &b"Requests."[..],
                &b"seconds"[..]
            )
        );
    }

    #[test]
    fn rejects_invalid_utf8_and_duplicates_before_materializing_labels() {
        let invalid: &[&[(&[u8], &[u8])]] = &[
            &[(b"job", b"a\xffb")],
            &[(b"job", b"a\xffinjected\xffx")],
            &[(b"\xc0\xaf", b"value")],
            &[(b"job", b"\xed\xa0\x80")],
            &[(b"job", b"a"), (b"job", b"b")],
            &[(b"job", b"a"), (b"job", b"a")],
            &[(b"__name__", b"invalid"), (b"job", b"a"), (b"job", b"")],
            &[(b"__name__", b"invalid"), (b"job", b""), (b"job", b"")],
            &[(b"__name__", b"invalid"), (b"", b"value")],
            &[(b"__name__", b"invalid"), (b"", b"")],
            &[(b"__name__", b"invalid"), (b"\xff", b"")],
        ];
        let good = series(&[(b"__name__", b"safe"), (b"job", "é😀".as_bytes())]);
        for labels in invalid {
            let request = [bytes_field(0x0a, &series(labels)), bytes_field(0x0a, &good)].concat();
            let decoded = decode(&request).expect("valid protobuf");
            assert_eq!(decoded.rejected, 3);
            assert_eq!(decoded.series.len(), 1);
            assert_eq!(decoded.series[0].labels[1].1, "é😀".as_bytes());
            assert_eq!(decoded.series[0].samples.len(), 3);
        }
    }

    #[test]
    fn normalizes_empty_values_and_order_before_canonical_identity() {
        let canonical = &[
            (b"__name__".as_slice(), b"safe".as_slice()),
            (b"job", b"api"),
        ];
        let with_empty = &[
            (b"job".as_slice(), b"api".as_slice()),
            (b"empty", b""),
            (b"__name__", b"safe"),
        ];
        let request = [
            bytes_field(0x0a, &series(canonical)),
            bytes_field(0x0a, &series(with_empty)),
        ]
        .concat();
        let decoded = decode(&request).unwrap();
        assert_eq!(decoded.rejected, 0);
        assert_eq!(decoded.series.len(), 2);
        assert_eq!(decoded.series[0].labels, canonical);
        assert_eq!(decoded.series[1].labels, canonical);
    }

    const SYMBOLS: [&[u8]; 11] = [
        b"",
        b"__name__",
        b"http_requests_total",
        b"job",
        b"api",
        b"Requests.",
        b"latency_seconds_bucket",
        b"le",
        b"0.5",
        b"Latency.",
        b"seconds",
    ];

    fn sample(timestamp: u8) -> Vec<u8> {
        let fields = [
            vec![0x09],
            2.5f64.to_le_bytes().to_vec(),
            vec![0x10, timestamp],
        ]
        .concat();
        bytes_field(0x12, &fields)
    }

    // `refs` are packed (one length-delimited field) unless `unpacked`.
    fn series_v2(refs: &[u8], unpacked: bool, samples: u8, metadata: &[u8]) -> Vec<u8> {
        let mut out = if unpacked {
            refs.iter().flat_map(|r| [0x08, *r]).collect()
        } else {
            bytes_field(0x0a, refs)
        };
        for t in 1..=samples {
            out.extend(sample(t));
        }
        if !metadata.is_empty() {
            out.extend(bytes_field(0x2a, metadata));
        }
        bytes_field(0x2a, &out)
    }

    fn request_v2(series: &[Vec<u8>]) -> Vec<u8> {
        // Symbols after the series: a decoder must not depend on field order.
        let symbols: Vec<u8> = SYMBOLS.iter().flat_map(|s| bytes_field(0x22, s)).collect();
        [series.concat(), symbols].concat()
    }

    #[test]
    fn v2_rejects_nonempty_reserved_symbol_even_if_no_reference_uses_it() {
        let symbols: Vec<u8> = SYMBOLS
            .iter()
            .enumerate()
            .flat_map(|(index, symbol)| {
                bytes_field(0x22, if index == 0 { b"not empty" } else { symbol })
            })
            .collect();
        let request = [
            series_v2(&[1, 2], false, 2, &[0x08, 1, 0x18, 5, 0x20, 10]),
            symbols,
        ]
        .concat();
        assert!(decode_v2(&request).is_none());
    }

    #[test]
    fn decodes_v2_series_through_the_symbol_table() {
        let counter = [0x08, 1, 0x18, 5];
        let histogram = [0x08, 3, 0x18, 9, 0x20, 10];
        let request = request_v2(&[
            series_v2(&[3, 4, 1, 2], false, 2, &counter),
            series_v2(&[1, 2, 3, 4], true, 1, &counter),
            series_v2(&[1, 6, 7, 8], false, 1, &histogram),
        ]);
        let decoded = decode_v2(&request).unwrap();
        assert_eq!(decoded.rejected, 0);
        assert_eq!(decoded.series.len(), 3);
        let first = &decoded.series[0];
        assert_eq!(
            first.labels,
            vec![
                (&b"__name__"[..], &b"http_requests_total"[..]),
                (&b"job"[..], &b"api"[..])
            ]
        );
        assert_eq!(first.samples.len(), 2);
        assert_eq!(first.samples[1].timestamp_ms, 2);
        assert_eq!(first.samples[1].value, 2.5);

        // Identical metadata repeats per series but is reported once, and the
        // histogram family loses its `_bucket` suffix.
        let metadata: Vec<_> = decoded
            .metadata
            .iter()
            .map(|m| (m.name, m.kind, m.help, m.unit))
            .collect();
        assert_eq!(
            metadata,
            vec![
                (
                    &b"http_requests_total"[..],
                    "counter",
                    &b"Requests."[..],
                    &b""[..]
                ),
                (
                    &b"latency_seconds"[..],
                    "histogram",
                    &b"Latency."[..],
                    &b"seconds"[..]
                ),
            ]
        );
    }

    #[test]
    fn v2_malformed_starts_fail_the_request_even_without_admission_preflight() {
        let good = series_v2(&[1, 2], false, 1, &[0x08, 1]);
        let refs = bytes_field(0x0a, &[1, 2]);
        let mut legacy = sample(1);
        legacy.extend(bytes_field(0x32, b"bad"));
        for point in [
            bytes_field(
                0x12,
                &[0x09, 0, 0, 0, 0, 0, 0, 0xf0, 0x3f, 0x10, 1, 0x1a, 0],
            ),
            bytes_field(0x1a, &[0x08, 1, 0x78, 1, 0x8a, 1, 0]),
            bytes_field(0x12, &[0x18, 0x80]),
            bytes_field(0x1a, &[0x88, 1, 0x80]),
            legacy,
        ] {
            let bad = bytes_field(0x2a, &[refs.clone(), point].concat());
            assert!(decode_v2(&request_v2(&[good.clone(), bad])).is_none());
        }
    }

    #[test]
    fn v2_rejects_unresolvable_series_whole_and_counts_invalid_histograms() {
        // A float histogram (count_float = 2) with one observation, and one
        // whose span claims a bucket it never sends.
        let valid = [vec![0x11], 1.0f64.to_le_bytes().to_vec()].concat();
        let invalid = [valid.clone(), bytes_field(0x5a, &[0x08, 0x00, 0x10, 0x01])].concat();
        let histogram_only = {
            let refs = bytes_field(0x0a, &[1, 2]);
            bytes_field(0x2a, &[refs, bytes_field(0x1a, &valid)].concat())
        };
        let with_histogram = {
            let refs = bytes_field(0x0a, &[1, 2]);
            bytes_field(
                0x2a,
                &[refs, sample(1), bytes_field(0x1a, &invalid)].concat(),
            )
        };
        let request = request_v2(&[
            series_v2(&[1, 2, 3], false, 2, &[]),      // odd reference count
            series_v2(&[1, 2, 3, 99], false, 3, &[]),  // value outside the table
            series_v2(&[0, 2], false, 1, &[]),         // empty label name
            series_v2(&[1, 2], false, 1, &[0x18, 99]), // help outside the table
            series_v2(&[1, 2], false, 0, &[]),         // no samples
            histogram_only,                            // kept: a histogram is a sample
            with_histogram,                            // sample kept, histogram rejected
            series_v2(&[1, 2], false, 1, &[0x08, 42]), // unknown type stays a sample
        ]);
        let decoded = decode_v2(&request).unwrap();
        assert_eq!(decoded.series.len(), 3);
        assert_eq!(decoded.series[0].histograms.len(), 1);
        assert_eq!(decoded.series[0].histograms[0].0.count, 1.0);
        assert_eq!(decoded.rejected, 2 + 3 + 1 + 1 + 1 + 1);
        // Neither kept series carries metadata worth recording.
        assert!(decoded.metadata.is_empty());
    }

    #[test]
    fn v2_metric_families_trim_only_their_types_suffixes() {
        for (name, kind, family) in [
            (&b"rpc_seconds_count"[..], "summary", &b"rpc_seconds"[..]),
            (b"rpc_seconds_sum", "summary", b"rpc_seconds"),
            (b"rpc_seconds_bucket", "summary", b"rpc_seconds_bucket"),
            (b"queue_gcount", "gaugehistogram", b"queue"),
            (b"queue_count", "gaugehistogram", b"queue_count"),
            (b"requests_total", "counter", b"requests_total"),
            (b"build_info", "info", b"build_info"),
            (b"_bucket", "histogram", b""),
        ] {
            assert_eq!(family_name(name, kind), family);
        }
    }
}
