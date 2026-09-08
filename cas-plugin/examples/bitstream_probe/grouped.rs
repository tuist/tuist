//! Offline grouped patch experiment. No server capability advertises this format.
use super::{require, Cursor, Result, MAX_COLUMNS, MAX_INPUT, MAX_PREPARED};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};

type Key = [i32; 5];
const MAX_GROUPS: usize = 131_072;
const HEADER_SIZE: usize = 88;
const DESCRIPTOR_SIZE: usize = 29;

pub struct Patch {
    pub bytes: Vec<u8>,
    pub groups: usize,
    pub copied_bytes: usize,
}

impl Patch {
    pub fn metadata_bytes(&self) -> usize {
        HEADER_SIZE + self.groups * DESCRIPTOR_SIZE
    }
}

fn groups(data: &[u8], limit: usize) -> Result<Vec<(Key, &[u8])>> {
    require(
        (1024..=8 * 1024 * 1024).contains(&limit),
        "group size limit",
    )?;
    require(data.len() <= MAX_PREPARED, "prepared size limit")?;
    let mut input = Cursor { data, at: 0 };
    require(input.take(8)? == b"BCOL0001", "unknown prepared format")?;
    require(input.u64()? <= MAX_INPUT as u64, "original size limit")?;
    let layout_size = input.u32()? as usize;
    let blob_size = input.u32()? as usize;
    let count = input.u32()? as usize;
    require(count <= MAX_COLUMNS, "column count limit")?;
    require(
        input.u32()? <= 1024 && input.u32()? <= 1,
        "invalid parameters",
    )?;
    let mut descriptors = Vec::with_capacity(count);
    let mut keys = BTreeSet::new();
    for _ in 0..count {
        let key = [
            3,
            input.u32()? as i32,
            input.u32()? as i32,
            input.u32()? as i32,
            0,
        ];
        let size = input.u32()? as usize;
        require(size.is_multiple_of(8), "invalid column size")?;
        require(keys.insert(key), "duplicate column")?;
        descriptors.push((key, size));
    }
    let mut sections = vec![
        ([0, 0, 0, 0, 0], &data[..input.at]),
        ([1, 0, 0, 0, 0], input.take(layout_size)?),
        ([2, 0, 0, 0, 0], input.take(blob_size)?),
    ];
    for (key, size) in descriptors {
        sections.push((key, input.take(size)?));
    }
    require(input.at == data.len(), "trailing prepared bytes")?;
    let mut output = Vec::new();
    for (mut key, bytes) in sections {
        for (page, bytes) in bytes.chunks(limit).enumerate() {
            require(output.len() < MAX_GROUPS, "group count limit")?;
            key[4] = page as i32;
            output.push((key, bytes));
        }
    }
    Ok(output)
}

pub fn encode(
    base: &[u8],
    target: &[u8],
    limit: usize,
    level: i32,
    residual: bool,
) -> Result<Patch> {
    let base_groups: BTreeMap<_, _> = groups(base, limit)?.into_iter().collect();
    let target_groups = groups(target, limit)?;
    let mut patch = Patch {
        bytes: Vec::new(),
        groups: target_groups.len(),
        copied_bytes: 0,
    };
    patch.bytes.extend(b"BPG00001");
    patch.bytes.extend(Sha256::digest(base));
    patch.bytes.extend(Sha256::digest(target));
    for value in [base.len(), target.len(), limit, target_groups.len()] {
        patch.bytes.extend((value as u32).to_le_bytes());
    }
    for (key, bytes) in target_groups {
        let prefix = base_groups.get(&key).copied().unwrap_or_default();
        let (mut mode, mut payload) = if prefix == bytes {
            patch.copied_bytes += bytes.len();
            (0, Vec::new())
        } else {
            let mut compressor = zstd::zstd_safe::CCtx::create();
            compressor
                .set_parameter(zstd::zstd_safe::CParameter::CompressionLevel(level))
                .map_err(|e| format!("compression level: {e}"))?;
            // Cover both bounded pages, without indexing the entire expanded base.
            compressor
                .set_parameter(zstd::zstd_safe::CParameter::WindowLog(
                    (limit * 2).next_power_of_two().ilog2(),
                ))
                .map_err(|e| format!("compression window: {e}"))?;
            compressor
                .set_parameter(zstd::zstd_safe::CParameter::EnableLongDistanceMatching(
                    true,
                ))
                .map_err(|e| format!("long distance matching: {e}"))?;
            compressor
                .ref_prefix(prefix)
                .map_err(|e| format!("prefix: {e}"))?;
            let mut compressed = Vec::with_capacity(zstd::zstd_safe::compress_bound(bytes.len()));
            compressor
                .compress2(&mut compressed, bytes)
                .map_err(|e| format!("compress: {e}"))?;
            if compressed.len() < bytes.len() {
                (1, compressed)
            } else {
                (2, bytes.to_vec())
            }
        };
        if residual && mode != 0 && prefix.len() == bytes.len() {
            // A numeric-reference change may be sparse without containing long
            // exact matches. Keep a bytewise difference only when it is smaller.
            let difference: Vec<_> = bytes
                .iter()
                .zip(prefix)
                .map(|(new, old)| new.wrapping_sub(*old))
                .collect();
            let compressed = zstd::bulk::compress(&difference, level)
                .map_err(|e| format!("compress difference: {e}"))?;
            if compressed.len() < payload.len() {
                mode = 3;
                payload = compressed;
            }
        }
        for value in key {
            patch.bytes.extend(value.to_le_bytes());
        }
        patch.bytes.extend((bytes.len() as u32).to_le_bytes());
        patch.bytes.push(mode);
        patch.bytes.extend((payload.len() as u32).to_le_bytes());
        patch.bytes.extend(payload);
    }
    Ok(patch)
}

pub fn decode(base: &[u8], patch: &[u8]) -> Result<Vec<u8>> {
    require(base.len() <= MAX_PREPARED, "base size limit")?;
    require(
        patch.len() <= MAX_PREPARED + HEADER_SIZE + MAX_GROUPS * DESCRIPTOR_SIZE,
        "patch size limit",
    )?;
    let mut input = Cursor { data: patch, at: 0 };
    require(input.take(8)? == b"BPG00001", "unknown patch format")?;
    require(
        input.take(32)? == Sha256::digest(base).as_slice(),
        "wrong base digest",
    )?;
    let target_digest = input.take(32)?;
    require(input.u32()? as usize == base.len(), "wrong base size")?;
    let size = input.u32()? as usize;
    require(size <= MAX_PREPARED, "target size limit")?;
    let limit = input.u32()? as usize;
    let count = input.u32()? as usize;
    require(count <= MAX_GROUPS, "group count limit")?;
    let base_groups: BTreeMap<_, _> = groups(base, limit)?.into_iter().collect();
    // Allocate only after validating the complete envelope and base groups.
    let mut output = Vec::with_capacity(size);
    let mut seen = BTreeSet::new();
    for _ in 0..count {
        let mut key = [0; 5];
        for value in &mut key {
            *value = input.u32()? as i32;
        }
        require(seen.insert(key), "duplicate group")?;
        let decoded_size = input.u32()? as usize;
        require(
            decoded_size <= limit && decoded_size <= size.saturating_sub(output.len()),
            "group output limit",
        )?;
        let mode = input.take(1)?[0];
        let payload_size = input.u32()? as usize;
        require(payload_size <= limit, "group payload limit")?;
        let payload = input.take(payload_size)?;
        let prefix = base_groups.get(&key).copied().unwrap_or_default();
        match mode {
            0 => {
                require(
                    payload.is_empty() && prefix.len() == decoded_size,
                    "invalid copy group",
                )?;
                output.extend(prefix);
            }
            1 => {
                let mut decoder = zstd::zstd_safe::DCtx::create();
                decoder
                    .ref_prefix(prefix)
                    .map_err(|e| format!("decode prefix: {e}"))?;
                let mut decoded = Vec::with_capacity(decoded_size);
                decoder
                    .decompress(&mut decoded, payload)
                    .map_err(|e| format!("decompress: {e}"))?;
                require(decoded.len() == decoded_size, "incorrect group size")?;
                output.extend(decoded);
            }
            2 => {
                require(payload.len() == decoded_size, "incorrect literal size")?;
                output.extend(payload);
            }
            3 => {
                require(prefix.len() == decoded_size, "difference base size")?;
                let difference = zstd::bulk::decompress(payload, decoded_size)
                    .map_err(|e| format!("decompress difference: {e}"))?;
                require(difference.len() == decoded_size, "difference output size")?;
                output.extend(
                    difference
                        .iter()
                        .zip(prefix)
                        .map(|(change, old)| change.wrapping_add(*old)),
                );
            }
            _ => return Err("unknown group mode".into()),
        }
    }
    require(
        output.len() == size && input.at == patch.len(),
        "incomplete or trailing patch data",
    )?;
    require(
        Sha256::digest(&output).as_slice() == target_digest,
        "wrong target digest",
    )?;
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn prepared(column: &[u8], code: i32) -> Vec<u8> {
        let mut bytes = Vec::from(&b"BCOL0001"[..]);
        bytes.extend(4u64.to_le_bytes());
        for value in [0u32, 0, 1, 32, 1, 8, code as u32, 0, column.len() as u32] {
            bytes.extend(value.to_le_bytes());
        }
        bytes.extend(column);
        bytes
    }

    #[test]
    fn restores_changed_identical_and_new_groups_with_pages() {
        let base = prepared(&vec![11; 4096], 7);
        for code in [7, 8] {
            let mut values = vec![11; 4096];
            values[1800] = 19;
            let target = prepared(&values, code);
            let patch = encode(&base, &target, 1024, 3, true).unwrap();
            assert_eq!(decode(&base, &patch.bytes).unwrap(), target);
            if code == 7 {
                assert!(patch.copied_bytes >= 3072);
            }
        }
        let patch = encode(&base, &base, 1024, 3, true).unwrap();
        assert_eq!(patch.copied_bytes, base.len());
        assert_eq!(patch.bytes.len(), patch.metadata_bytes());
    }

    #[test]
    fn rejects_wrong_bases_truncation_and_trailing_bytes() {
        let base = prepared(&vec![11; 4096], 7);
        let target = prepared(&vec![19; 4096], 7);
        let patch = encode(&base, &target, 1024, 3, true).unwrap().bytes;
        assert!(decode(&target, &patch).is_err());
        for end in 0..patch.len() {
            assert!(decode(&base, &patch[..end]).is_err());
        }
        for index in 0..patch.len() {
            let mut changed = patch.clone();
            changed[index] ^= 0xff;
            // Metadata that is unused by a literal may change harmlessly.
            // A mutation must never produce different accepted output.
            if let Ok(restored) = decode(&base, &changed) {
                assert_eq!(restored, target);
            }
        }
        let mut extra = patch;
        extra.push(0);
        assert!(decode(&base, &extra).is_err());
        assert!(encode(&base, &target, 0, 3, true).is_err());
        assert!(encode(&base, &target, 16 * 1024 * 1024, 3, true).is_err());
    }
}
