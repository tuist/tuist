//! Optional, publication-derived label -> canonical-series -> row-group postings.
//!
//! Ordinals identify complete canonical label bytes, never the caller's series
//! hash. Each indexed label is a complete partition (including missing = "").
//! Indexes are written inside the same immutable Parquet object as their rows;
//! there is no second publication, mutable catalog, or extra provider request.
//! Unknown versions, malformed metadata and exhausted optional budgets scan.

use super::metric_segment_parquet::{Matcher, MatcherOp};
use parquet::file::metadata::ParquetMetaData;
use std::collections::{BTreeMap, BTreeSet};
use xxhash_rust::xxh64::xxh64;

pub(crate) const KEY: &str = "pulse.metric.postings.v1";
const MAGIC: &[u8; 8] = b"PULSEMP1";
// Read historical objects in place; new indexes use only KEY and MAGIC.
const LEGACY_KEY: &str = "pulso.metric.postings.v1";
const LEGACY_MAGIC: &[u8; 8] = b"PULSOMP1";
const MAX_TEXT: usize = 65_536;
const MAX_RAW: usize = MAX_TEXT / 2;
const COMPRESSED: &str = "s1:";
const MAX_SERIES: usize = 512;
const MAX_GROUPS: usize = 128;
const MAX_ROWS: usize = 100_000;
const MAX_LABELS: usize = 16;
const MAX_FIELD: usize = 256;
const MAX_CANONICAL: usize = 4096;
const MAX_DICTIONARY: usize = 131_072;
const MAX_PROBES: usize = 16 * 1024 * 1024;
type Bits = Vec<u8>;
type Values = BTreeMap<Vec<u8>, Bits>;

struct Index {
    series: usize,
    rows: usize,
    groups: Vec<(usize, Bits)>,
    labels: BTreeMap<Vec<u8>, Values>,
}

fn set(bits: &mut [u8], ordinal: usize) {
    bits[ordinal / 8] |= 1 << (ordinal % 8);
}

fn universe(series: usize) -> Bits {
    let mut bits = vec![0; series.div_ceil(8)];
    for ordinal in 0..series {
        set(&mut bits, ordinal);
    }
    bits
}

fn pairs(bytes: &[u8]) -> Option<Vec<(&[u8], &[u8])>> {
    if bytes.len() > MAX_CANONICAL {
        return None;
    }
    let mut fields = bytes.split(|b| *b == 0xff);
    let mut out = Vec::new();
    let mut previous: Option<&[u8]> = None;
    loop {
        let name = fields.next()?;
        // A canonical sequence ends with a separator, including no labels.
        if name.is_empty() && fields.clone().next().is_none() {
            return Some(out);
        }
        let value = fields.next()?;
        if previous.is_some_and(|p| p >= name)
            || std::str::from_utf8(name).is_err()
            || std::str::from_utf8(value).is_err()
        {
            return None;
        }
        previous = Some(name);
        out.push((name, value));
    }
}

/// Bound optional work before allocating dictionaries or expanding postings.
/// The caller writes one batch with exactly this maximum row-group size.
pub(crate) fn build<'a>(
    rows: impl ExactSizeIterator<Item = &'a [u8]>,
    group_size: usize,
) -> Option<String> {
    let count = rows.len();
    if count == 0 || count > MAX_ROWS || group_size == 0 {
        return None;
    }
    let groups = count.div_ceil(group_size);
    if groups > MAX_GROUPS {
        return None;
    }
    let mut dictionary = BTreeMap::<Vec<u8>, usize>::new();
    let mut dictionary_bytes = 0usize;
    let mut probes = 0usize;
    let mut previous = None;
    // At most 200,000 ordinal bytes. Shared consecutive label buffers need
    // no repeated byte probe, while all rows still spend bounded fixed work.
    let mut ordinals = Vec::<u16>::with_capacity(count);
    for canonical in rows {
        let identity = (canonical.as_ptr(), canonical.len());
        let ordinal = match previous {
            Some((pointer, length, ordinal)) if (pointer, length) == identity => ordinal,
            _ => {
                probes = probes.checked_add(canonical.len())?;
                if canonical.len() > MAX_CANONICAL || probes > MAX_PROBES {
                    return None;
                }
                match dictionary.get(canonical) {
                    Some(ordinal) => *ordinal,
                    None => {
                        if dictionary.len() >= MAX_SERIES {
                            return None;
                        }
                        dictionary_bytes = dictionary_bytes.checked_add(canonical.len())?;
                        if dictionary_bytes > MAX_DICTIONARY {
                            return None;
                        }
                        let ordinal = dictionary.len();
                        dictionary.insert(canonical.to_vec(), ordinal);
                        ordinal
                    }
                }
            }
        };
        previous = Some((identity.0, identity.1, ordinal));
        ordinals.push(ordinal as u16);
    }
    let series = dictionary.len();
    let width = series.div_ceil(8);
    let mut row_groups = vec![(0usize, vec![0u8; width]); groups];
    for (row, ordinal) in ordinals.into_iter().enumerate() {
        let group = &mut row_groups[row / group_size];
        group.0 += 1;
        set(&mut group.1, ordinal as usize);
    }
    let parsed: Vec<_> = dictionary
        .iter()
        .map(|(canonical, ordinal)| Some((*ordinal, pairs(canonical)?)))
        .collect::<Option<_>>()?;
    let mut names: BTreeSet<&[u8]> = parsed
        .iter()
        .flat_map(|(_, labels)| labels.iter().map(|(name, _)| *name))
        .filter(|name| name.len() <= MAX_FIELD)
        .collect();
    let mut index = Index {
        series,
        rows: count,
        groups: row_groups,
        labels: BTreeMap::new(),
    };
    // Try the metric name first, then byte order. Cap examined names, not
    // just successes: thousands of omitted names must not multiply work.
    // Only complete partitions fit; subsequent selected names may still fit.
    let metric_name = names.take(&b"__name__"[..]);
    let mut size = 8 + 2 + 4 + 2 + groups * (4 + width) + 2 + 8;
    for name in metric_name.into_iter().chain(names).take(MAX_LABELS) {
        let mut values = Values::new();
        let mut valid = true;
        for (ordinal, labels) in &parsed {
            let value = labels
                .iter()
                .find(|(key, _)| *key == name)
                .map_or(&b""[..], |(_, value)| *value);
            if value.len() > MAX_FIELD {
                valid = false;
                break;
            }
            set(
                values.entry(value.to_vec()).or_insert(vec![0; width]),
                *ordinal,
            );
        }
        if !valid {
            continue;
        }
        let bytes = 2
            + name.len()
            + 2
            + values
                .keys()
                .map(|value| 2 + value.len() + width)
                .sum::<usize>();
        if size + bytes > MAX_RAW {
            continue;
        }
        size += bytes;
        index.labels.insert(name.to_vec(), values);
    }
    if index.labels.is_empty() {
        return None;
    }
    Some(encode(&index))
}

fn u16_bytes(out: &mut Vec<u8>, value: usize) {
    out.extend_from_slice(&(value as u16).to_le_bytes());
}
fn field(out: &mut Vec<u8>, value: &[u8]) {
    u16_bytes(out, value.len());
    out.extend_from_slice(value);
}
fn encode(index: &Index) -> String {
    let mut out = MAGIC.to_vec();
    u16_bytes(&mut out, index.series);
    out.extend_from_slice(&(index.rows as u32).to_le_bytes());
    u16_bytes(&mut out, index.groups.len());
    for (rows, bits) in &index.groups {
        out.extend_from_slice(&(*rows as u32).to_le_bytes());
        out.extend_from_slice(bits);
    }
    u16_bytes(&mut out, index.labels.len());
    for (name, values) in &index.labels {
        field(&mut out, name);
        u16_bytes(&mut out, values.len());
        for (value, bits) in values {
            field(&mut out, value);
            out.extend_from_slice(bits);
        }
    }
    // Accidental-corruption detection, not authentication or a proof against
    // a writer forging metadata. Like Parquet statistics, coverage derives
    // from the first-party writer, not from this noncryptographic checksum.
    out.extend_from_slice(&xxh64(&out, 0).to_le_bytes());
    // Parquet column compression does not compress key/value footer metadata.
    // Small indexes keep their old encoding; larger ones use bounded raw
    // Snappy only when the complete versioned envelope is actually smaller.
    if out.len() >= 1024 {
        if let Ok(compressed) = snap::raw::Encoder::new().compress_vec(&out) {
            if COMPRESSED.len() + compressed.len() * 2 < out.len() * 2 {
                return format!("{COMPRESSED}{}", hex(&compressed));
            }
        }
    }
    hex(&out)
}

fn hex(raw: &[u8]) -> String {
    let hex = b"0123456789abcdef";
    let mut text = String::with_capacity(raw.len() * 2);
    for byte in raw {
        text.push(hex[(byte >> 4) as usize] as char);
        text.push(hex[(byte & 15) as usize] as char);
    }
    text
}

struct Cursor<'a>(&'a [u8]);
impl<'a> Cursor<'a> {
    fn take(&mut self, count: usize) -> Option<&'a [u8]> {
        let value = self.0.get(..count)?;
        self.0 = &self.0[count..];
        Some(value)
    }
    fn u16(&mut self) -> Option<usize> {
        Some(u16::from_le_bytes(self.take(2)?.try_into().ok()?) as usize)
    }
    fn u32(&mut self) -> Option<usize> {
        Some(u32::from_le_bytes(self.take(4)?.try_into().ok()?) as usize)
    }
    fn field(&mut self) -> Option<Vec<u8>> {
        let count = self.u16()?;
        if count > MAX_FIELD {
            return None;
        }
        let bytes = self.take(count)?;
        std::str::from_utf8(bytes).ok()?;
        Some(bytes.to_vec())
    }
    fn bits(&mut self, universe: &[u8]) -> Option<Bits> {
        let bits = self.take(universe.len())?;
        if bits.iter().zip(universe).any(|(b, u)| b & !u != 0) || bits.iter().all(|b| *b == 0) {
            return None;
        }
        Some(bits.to_vec())
    }
}

fn parse(text: &str) -> Option<Index> {
    if text.len() > MAX_TEXT {
        return None;
    }
    let (compressed, text) = match text.strip_prefix(COMPRESSED) {
        Some(payload) => (true, payload),
        None => (false, text),
    };
    if !text.len().is_multiple_of(2) || text.len() < 16 {
        return None;
    }
    let raw: Vec<u8> = text
        .as_bytes()
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| {
            let nibble = |b| match b {
                b'0'..=b'9' => Some(b - b'0'),
                b'a'..=b'f' => Some(b - b'a' + 10),
                _ => None,
            };
            Some(nibble(pair[0])? * 16 + nibble(pair[1])?)
        })
        .collect::<Option<_>>()?;
    let raw = if compressed {
        // Inspect the declared decoded length before allocating. Compression
        // never expands the index's original independent 32 KiB admission cap.
        if snap::raw::decompress_len(&raw).ok()? > MAX_RAW {
            return None;
        }
        snap::raw::Decoder::new().decompress_vec(&raw).ok()?
    } else {
        raw
    };
    let body = raw.get(..raw.len().checked_sub(8)?)?;
    let digest = u64::from_le_bytes(raw.get(body.len()..)?.try_into().ok()?);
    if xxh64(body, 0) != digest {
        return None;
    }
    let mut cursor = Cursor(body);
    let magic = cursor.take(MAGIC.len())?;
    if magic != MAGIC && magic != LEGACY_MAGIC {
        return None;
    }
    let series = cursor.u16()?;
    let rows = cursor.u32()?;
    let groups = cursor.u16()?;
    if series == 0
        || series > MAX_SERIES
        || rows == 0
        || rows > MAX_ROWS
        || groups == 0
        || groups > MAX_GROUPS
    {
        return None;
    }
    let all = universe(series);
    let mut group_bits = Vec::with_capacity(groups);
    let mut covered = vec![0u8; all.len()];
    let mut group_rows = 0usize;
    for _ in 0..groups {
        let count = cursor.u32()?;
        let bits = cursor.bits(&all)?;
        let population: usize = bits.iter().map(|byte| byte.count_ones() as usize).sum();
        if count == 0 || count > rows || population > count {
            return None;
        }
        group_rows = group_rows.checked_add(count)?;
        for (seen, bits) in covered.iter_mut().zip(&bits) {
            *seen |= bits;
        }
        group_bits.push((count, bits));
    }
    if group_rows != rows || covered != all {
        return None;
    }
    let label_count = cursor.u16()?;
    if label_count == 0 || label_count > MAX_LABELS {
        return None;
    }
    let mut labels = BTreeMap::new();
    let mut previous_name: Option<Vec<u8>> = None;
    for _ in 0..label_count {
        let name = cursor.field()?;
        if previous_name.as_ref().is_some_and(|p| p >= &name) {
            return None;
        }
        previous_name = Some(name.clone());
        let count = cursor.u16()?;
        if count == 0 || count > series {
            return None;
        }
        let mut values = Values::new();
        let mut covered = vec![0u8; all.len()];
        let mut previous_value: Option<Vec<u8>> = None;
        for _ in 0..count {
            let value = cursor.field()?;
            if previous_value.as_ref().is_some_and(|p| p >= &value) {
                return None;
            }
            previous_value = Some(value.clone());
            let bits = cursor.bits(&all)?;
            for (seen, bits) in covered.iter_mut().zip(&bits) {
                if *seen & bits != 0 {
                    return None;
                }
                *seen |= bits;
            }
            values.insert(value, bits);
        }
        if covered != all {
            return None;
        }
        labels.insert(name, values);
    }
    if !cursor.0.is_empty() {
        return None;
    }
    Some(Index {
        series,
        rows,
        groups: group_bits,
        labels,
    })
}

impl Index {
    fn candidates(&self, matchers: &[Matcher<'_>]) -> Option<Vec<bool>> {
        let mut selected = universe(self.series);
        let mut used = false;
        for matcher in matchers {
            if !matches!(matcher.op, MatcherOp::Eq) {
                continue;
            }
            let Some(values) = self.labels.get(matcher.name) else {
                continue;
            };
            used = true;
            if let Some(bits) = values.get(matcher.value) {
                for (selected, bits) in selected.iter_mut().zip(bits) {
                    *selected &= bits;
                }
            } else {
                selected.fill(0);
            }
        }
        used.then(|| {
            self.groups
                .iter()
                .map(|(_, group)| {
                    group
                        .iter()
                        .zip(&selected)
                        .any(|(group, selected)| group & selected != 0)
                })
                .collect()
        })
    }
}

/// None means unknown, not an empty result. Validate the complete index even
/// when the first equality could already prove an empty intersection.
pub(crate) fn candidate_groups(
    metadata: &ParquetMetaData,
    matchers: &[Matcher<'_>],
) -> Option<Vec<bool>> {
    if !matchers.iter().any(|m| matches!(m.op, MatcherOp::Eq)) {
        return None;
    }
    let entries = metadata.file_metadata().key_value_metadata()?;
    let mut entries = entries
        .iter()
        .filter(|entry| entry.key == KEY || entry.key == LEGACY_KEY);
    let text = entries.next()?.value.as_ref()?;
    if entries.next().is_some() {
        return None;
    }
    let index = parse(text)?;
    if metadata.file_metadata().num_rows() != index.rows as i64
        || metadata.num_row_groups() != index.groups.len()
        || metadata
            .row_groups()
            .iter()
            .zip(&index.groups)
            .any(|(group, (rows, _))| group.num_rows() != *rows as i64)
    {
        return None;
    }
    index.candidates(matchers)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eq<'a>(name: &'a [u8], value: &'a [u8]) -> Matcher<'a> {
        Matcher {
            name,
            value,
            op: MatcherOp::Eq,
        }
    }

    #[test]
    fn large_complete_postings_use_less_footer_text_and_keep_exact_candidates() {
        let rows: Vec<Vec<u8>> = (0..256)
            .map(|i| {
                let mut row = Vec::new();
                for bit in 0..8 {
                    row.extend_from_slice(&[b'a' + bit, 0xff, b'0' + ((i >> bit) & 1) as u8, 0xff]);
                }
                row
            })
            .collect();
        let text = build(rows.iter().map(Vec::as_slice), 16).unwrap();
        assert!(
            text.starts_with("s1:"),
            "uncompressed footer: {} bytes",
            text.len()
        );
        let compressed: Vec<u8> = text.as_bytes()[COMPRESSED.len()..]
            .as_chunks::<2>()
            .0
            .iter()
            .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).unwrap(), 16).unwrap())
            .collect();
        let raw = snap::raw::Decoder::new()
            .decompress_vec(&compressed)
            .unwrap();
        let legacy = hex(&raw);
        assert!(text.len() < legacy.len() / 2);
        // Isolate footer cost: identical compressed data pages and row groups,
        // with only the optional metadata text changed between the two files.
        let files = [&legacy, &text].map(|text| {
            use arrow::array::{ArrayRef, Int64Array, RecordBatch};
            use parquet::arrow::{arrow_reader::ParquetRecordBatchReaderBuilder, ArrowWriter};
            use parquet::file::properties::WriterProperties;
            let values: ArrayRef = std::sync::Arc::new(Int64Array::from_iter_values(0..256));
            let batch = RecordBatch::try_from_iter([("value", values)]).unwrap();
            let props = WriterProperties::builder()
                .set_compression(parquet::basic::Compression::ZSTD(
                    parquet::basic::ZstdLevel::try_new(6).unwrap(),
                ))
                .set_max_row_group_size(16)
                .set_key_value_metadata(Some(vec![parquet::format::KeyValue {
                    key: KEY.into(),
                    value: Some(text.to_string()),
                }]))
                .build();
            let mut bytes = Vec::new();
            let mut writer = ArrowWriter::try_new(&mut bytes, batch.schema(), Some(props)).unwrap();
            writer.write(&batch).unwrap();
            writer.close().unwrap();
            let size = bytes.len();
            let reader =
                ParquetRecordBatchReaderBuilder::try_new(bytes::Bytes::from(bytes)).unwrap();
            let metadata = reader.metadata().clone();
            let batches = reader
                .build()
                .unwrap()
                .collect::<Result<Vec<_>, _>>()
                .unwrap();
            (size, metadata, batches)
        });
        assert!(files[1].0 < files[0].0);
        assert_eq!(files[1].2, files[0].2);
        eprintln!(
            "postings text: {} -> {} bytes; isolated Parquet: {} -> {} bytes",
            legacy.len(),
            text.len(),
            files[0].0,
            files[1].0
        );
        let index = parse(&text).unwrap();
        let old_index = parse(&legacy).unwrap();
        for (bit, name) in (b'a'..=b'h').enumerate() {
            for value in 0..=1 {
                let expected: Vec<bool> = (0..256)
                    .collect::<Vec<_>>()
                    .chunks(16)
                    .map(|group| group.iter().any(|i| ((i >> bit) & 1) == value))
                    .collect();
                let name = [name];
                let value = [b'0' + value as u8];
                let matchers = [eq(&name, &value)];
                assert_eq!(index.candidates(&matchers), Some(expected.clone()));
                assert_eq!(index.candidates(&matchers), old_index.candidates(&matchers));
                assert_eq!(candidate_groups(&files[0].1, &matchers), Some(expected));
                assert_eq!(
                    candidate_groups(&files[0].1, &matchers),
                    candidate_groups(&files[1].1, &matchers)
                );
            }
        }
        for end in 0..compressed.len() {
            assert!(parse(&format!("{COMPRESSED}{}", hex(&compressed[..end]))).is_none());
        }
        let mut corrupt = raw;
        corrupt[30] ^= 1;
        let damaged = snap::raw::Encoder::new().compress_vec(&corrupt).unwrap();
        assert!(parse(&format!("{COMPRESSED}{}", hex(&damaged))).is_none());
        let oversized = snap::raw::Encoder::new()
            .compress_vec(&vec![0; MAX_RAW + 1])
            .unwrap();
        assert!(parse(&format!("{COMPRESSED}{}", hex(&oversized))).is_none());
        assert!(parse(&text.replacen(COMPRESSED, "s2:", 1)).is_none());
    }

    #[test]
    fn historical_postings_reject_duplicate_and_conflicting_aliases() {
        use parquet::arrow::arrow_reader::ParquetRecordBatchReaderBuilder;
        use parquet::file::metadata::{FileMetaData, KeyValue};
        let bytes = bytes::Bytes::from_static(include_bytes!(
            "../../../test/fixtures/metrics/legacy_1_38/indexed.parquet"
        ));
        let reader = ParquetRecordBatchReaderBuilder::try_new(bytes).unwrap();
        let metadata = reader.metadata();
        let file = metadata.file_metadata();
        let legacy = file
            .key_value_metadata()
            .unwrap()
            .iter()
            .find(|kv| kv.key == LEGACY_KEY)
            .unwrap();
        let matchers = [eq(b"host", b"missing")];
        assert_eq!(candidate_groups(metadata, &matchers), Some(vec![false]));
        for extra in [
            legacy.clone(),
            KeyValue::new(KEY.into(), legacy.value.clone()),
            KeyValue::new(KEY.into(), "invalid".to_owned()),
        ] {
            let mut entries = file.key_value_metadata().unwrap().clone();
            entries.push(extra);
            let file = FileMetaData::new(
                file.version(),
                file.num_rows(),
                file.created_by().map(str::to_owned),
                Some(entries),
                file.schema_descr_ptr(),
                file.column_orders().cloned(),
            );
            let ambiguous = ParquetMetaData::new(file, metadata.row_groups().to_vec());
            assert!(candidate_groups(&ambiguous, &matchers).is_none());
        }
    }

    #[test]
    fn intersections_use_canonical_identity_missing_empty_and_complete_labels() {
        let rows: Vec<&[u8]> = vec![
            b"a\xffone\xffb\xffprod\xff",
            b"a\xfftwo\xffb\xffdev\xff",
            b"a\xff\xff",                 // explicit empty and missing b
            b"",                          // both missing
            b"a\xffone\xffb\xffprod\xff", // one series in two groups
        ];
        let text = build(rows.iter().copied(), 2).unwrap();
        let index = parse(&text).unwrap();
        assert_eq!(index.series, 4);
        assert_eq!(
            index.candidates(&[eq(b"a", b"one")]),
            Some(vec![true, false, true])
        );
        // Per-label dictionaries contain both values, but no series has both.
        assert_eq!(
            index.candidates(&[eq(b"a", b"one"), eq(b"b", b"dev")]),
            Some(vec![false; 3])
        );
        assert_eq!(
            index.candidates(&[eq(b"a", b"")]),
            Some(vec![false, true, false])
        );
        assert_eq!(
            index.candidates(&[eq(b"b", b"")]),
            Some(vec![false, true, false])
        );
        assert_eq!(index.candidates(&[eq(b"unknown", b"")]), None);
        assert_eq!(
            index.candidates(&[eq(b"a", b"absent")]),
            Some(vec![false; 3])
        );
        assert_eq!(
            index.candidates(&[Matcher {
                name: b"a",
                value: b"one",
                op: MatcherOp::Neq
            }]),
            None
        );
    }

    #[test]
    fn optional_work_and_payload_budgets_never_publish_partial_partitions() {
        // Many series with tiny complete partitions still fit the byte cap.
        let rows: Vec<Vec<u8>> = (0..MAX_SERIES + 1)
            .map(|i| {
                let mut row = Vec::new();
                for bit in 0..10 {
                    row.extend_from_slice(&[b'a' + bit, 0xff, b'0' + ((i >> bit) & 1) as u8, 0xff]);
                }
                row
            })
            .collect();
        assert!(build(rows[..MAX_SERIES].iter().map(Vec::as_slice), 8192).is_some());
        assert!(build(rows.iter().map(Vec::as_slice), 8192).is_none());
        assert!(build(std::iter::repeat_n(&b"a\xffb\xff"[..], MAX_ROWS), 8192).is_some());
        assert!(build(std::iter::repeat_n(&b"a\xffb\xff"[..], MAX_ROWS + 1), 8192).is_none());
        assert!(build(std::iter::repeat_n(&b"a\xffb\xff"[..], 128), 1).is_some());
        assert!(build(std::iter::repeat_n(&b"a\xffb\xff"[..], 129), 1).is_none());
        assert!(build([&b"a\xffb\xff"[..]].into_iter(), 0).is_none());
        assert!(build([&b"a\xffb"[..]].into_iter(), 8192).is_none());
        assert!(build([&b"b\xffx\xffa\xffy\xff"[..]].into_iter(), 8192).is_none());
        let mut long = b"a\xff".to_vec();
        long.extend(vec![b'x'; 257]);
        long.extend_from_slice(b"\xffb\xffsafe\xff");
        let index = parse(&build([long.as_slice()].into_iter(), 8192).unwrap()).unwrap();
        assert_eq!(index.candidates(&[eq(b"a", b"x")]), None);
        assert_eq!(index.candidates(&[eq(b"b", b"no")]), Some(vec![false]));

        let mut canonical = Vec::new();
        for name in b'a'..=b'j' {
            canonical.extend_from_slice(&[name, 0xff]);
            canonical.extend(vec![b'x'; 100]);
            canonical.push(0xff);
        }
        let allowed = MAX_PROBES / canonical.len();
        let twin = canonical.clone();
        let input = |n| {
            (0..n).map(|i| {
                if i % 2 == 0 {
                    canonical.as_slice()
                } else {
                    twin.as_slice()
                }
            })
        };
        assert!(build(input(allowed), 8192).is_some());
        assert!(build(input(allowed + 1), 8192).is_none());
        // Shared runs do not turn ordinary 100k-row compactions into a
        // byte-probe overflow: pointer identity avoids touching label bytes.
        assert!(build(std::iter::repeat_n(canonical.as_slice(), MAX_ROWS), 8192).is_some());
        assert!(build([vec![b'x'; MAX_CANONICAL + 1].as_slice()].into_iter(), 8192).is_none());

        // No partial dictionary is published if every complete label exceeds
        // the shared footer ceiling, even below the series/scratch ceilings.
        let rows: Vec<Vec<u8>> = (0..512)
            .map(|i| {
                let mut row = b"a\xff".to_vec();
                row.extend_from_slice(format!("{i:0256}").as_bytes());
                row.push(0xff);
                row
            })
            .collect();
        assert!(build(rows.iter().map(Vec::as_slice), 8192).is_none());

        // Unique canonical scratch is independently bounded. The value
        // partition itself fits; crossing 128 KiB alone drops the index.
        let rows: Vec<Vec<u8>> = (0..45)
            .map(|i| {
                let mut row = Vec::new();
                for name in b'a'..=b'l' {
                    row.extend_from_slice(&[name, 0xff]);
                    row.extend_from_slice(format!("{i:0240}").as_bytes());
                    row.push(0xff);
                }
                row
            })
            .collect();
        assert_eq!(rows[0].len(), 2916);
        assert!(build(rows[..44].iter().map(Vec::as_slice), 8192).is_some());
        assert!(build(rows.iter().map(Vec::as_slice), 8192).is_none());
    }

    #[test]
    fn randomized_equalities_never_exclude_a_matching_source_group() {
        let mut seed = 1337u64;
        let mut next = || {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1);
            seed >> 32
        };
        let values: [&[u8]; 4] = [b"", b"x", b"y", "\"µ\\\n".as_bytes()];
        let mut series = Vec::new();
        for _ in 0..200 {
            let mut canonical = Vec::new();
            for name in b'a'..=b'd' {
                let choice = next() as usize % 5;
                if choice < 4 {
                    canonical.extend_from_slice(&[name, 0xff]);
                    canonical.extend_from_slice(values[choice]);
                    canonical.push(0xff);
                }
            }
            series.push(canonical);
        }
        let rows: Vec<_> = (0..1000)
            .map(|_| series[next() as usize % series.len()].as_slice())
            .collect();
        let text = build(rows.iter().copied(), 17).unwrap();
        assert!(text.len() <= MAX_TEXT);
        let index = parse(&text).unwrap();
        for name1 in *b"abcdz" {
            for name2 in *b"abcdz" {
                for value1 in values {
                    for value2 in values {
                        let name1 = [name1];
                        let name2 = [name2];
                        let matchers = [eq(&name1, value1), eq(&name2, value2)];
                        let planned = index
                            .candidates(&matchers)
                            .unwrap_or(vec![true; index.groups.len()]);
                        for (group, rows) in rows.chunks(17).enumerate() {
                            let matches = rows.iter().any(|row| {
                                crate::metric_segment_parquet::matches_canonical_for_test(
                                    row, &matchers,
                                )
                            });
                            assert!(!matches || planned[group]);
                            if name1 != *b"z" && name2 != *b"z" {
                                assert_eq!(matches, planned[group]);
                            }
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn malformed_or_unknown_index_is_unknown_even_after_checksum_repair() {
        let text = build([&b"a\xffb\xff"[..]].into_iter(), 8192).unwrap();
        for i in 0..text.len() {
            assert!(parse(&text[..i]).is_none());
            let mut corrupt = text.as_bytes().to_vec();
            corrupt[i] = if corrupt[i] == b'0' { b'1' } else { b'0' };
            assert!(parse(std::str::from_utf8(&corrupt).unwrap()).is_none());
        }
        let mut raw: Vec<u8> = text
            .as_bytes()
            .as_chunks::<2>()
            .0
            .iter()
            .map(|p| u8::from_str_radix(std::str::from_utf8(p).unwrap(), 16).unwrap())
            .collect();
        let original = raw.clone();
        // Version, series count, total rows, group count, group row count,
        // group bitmap, label count and label-value partition coverage.
        for offset in [7, 8, 10, 14, 16, 20, 21, 22, 30] {
            raw.clone_from(&original);
            raw[offset] ^= 0xff;
            let length = raw.len() - 8;
            let digest = xxh64(&raw[..length], 0).to_le_bytes();
            raw[length..].copy_from_slice(&digest);
            let text: String = raw.iter().map(|byte| format!("{byte:02x}")).collect();
            assert!(parse(&text).is_none(), "accepted corrupt byte {offset}");
        }
        assert!(parse(&"0".repeat(MAX_TEXT + 2)).is_none());

        // Re-encoding repairs the checksum, but structural coverage failures
        // must still be unknown, never an empty-result proof.
        let text = build([&b"a\xffx\xff"[..], &b"a\xffy\xff"[..]].into_iter(), 8192).unwrap();
        let mutations: [fn(&mut Index); 6] = [
            |index| {
                index.groups[0].1[0] = 1;
            }, // missing a series
            |index| {
                index.groups[0].1[0] = 0x83;
            }, // padding bit outside universe
            |index| {
                index
                    .labels
                    .get_mut(&b"a"[..])
                    .unwrap()
                    .get_mut(&b"x"[..])
                    .unwrap()[0] = 3;
            }, // overlapping values
            |index| {
                index.labels.get_mut(&b"a"[..]).unwrap().remove(&b"x"[..]);
            }, // incomplete partition
            |index| {
                index.groups[0].0 = 1;
                index.rows = 1;
            }, // population exceeds group rows, independently of row-sum checks
            |index| {
                index.rows = 3;
            }, // total/group row count disagreement
        ];
        for mutate in mutations {
            let mut index = parse(&text).unwrap();
            mutate(&mut index);
            assert!(parse(&encode(&index)).is_none());
        }
    }
}
