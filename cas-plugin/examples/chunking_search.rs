//! Offline search of compression boundaries; never changes compiler-visible bytes.
//! The transfer chunker and threshold stay identical to the production protocol.
use fastcdc::v2020::{FastCDC, Normalization};
use serde::Deserialize;
use std::{collections::HashSet, fs, time::Instant};
use tuist_cas_plugin::reapi::{blob_digest, compress_frame, encode_frame};

#[derive(Deserialize)]
struct Config {
    average: u32,
    level: i32,
    sections: bool,
}
#[derive(Deserialize)]
struct Fixture {
    name: String,
    base: String,
    edited: String,
}

fn boundaries(bytes: &[u8], average: u32) -> Vec<(usize, usize)> {
    FastCDC::with_level(
        bytes,
        average / 4,
        average,
        average * 4,
        Normalization::Level2,
    )
    .map(|c| (c.offset, c.length))
    .collect()
}

fn section_boundaries(bytes: &[u8]) -> Option<Vec<usize>> {
    // Only little-endian, 64-bit Mach object files. Every boundary is validated
    // before use; unfamiliar containers fall back to ordinary compression.
    if bytes.get(..4)? != [0xcf, 0xfa, 0xed, 0xfe] {
        return None;
    }
    let u32_at = |at: usize| -> Option<usize> {
        Some(u32::from_le_bytes(bytes.get(at..at.checked_add(4)?)?.try_into().ok()?) as usize)
    };
    let u64_at = |at: usize| -> Option<usize> {
        usize::try_from(u64::from_le_bytes(
            bytes.get(at..at.checked_add(8)?)?.try_into().ok()?,
        ))
        .ok()
    };
    if u32_at(12)? != 1 {
        return None;
    }
    let count = u32_at(16)?;
    let commands_end = 32usize.checked_add(u32_at(20)?)?;
    if count > 4096 || commands_end > bytes.len() {
        return None;
    }
    let mut offset = 32;
    let mut cuts = vec![0, commands_end, bytes.len()];
    for _ in 0..count {
        let command = u32_at(offset)?;
        let end = offset.checked_add(u32_at(offset + 4)?)?;
        if end < offset.checked_add(8)? || end > commands_end || !end.is_multiple_of(8) {
            return None;
        }
        if command == 0x19 {
            let sections = u32_at(offset + 64)?;
            if sections > 4096 || offset.checked_add(72 + sections * 80)? > end {
                return None;
            }
            for index in 0..sections {
                let section = offset + 72 + index * 80;
                let flags = u32_at(section + 64)? & 0xff;
                if matches!(flags, 1 | 0xc | 0x12) {
                    continue;
                }
                let size = u64_at(section + 40)?;
                let start = u32_at(section + 48)?;
                let finish = start.checked_add(size)?;
                if size > 0 {
                    if start < commands_end || finish > bytes.len() {
                        return None;
                    }
                    cuts.extend([start, finish]);
                }
                let relocations = u32_at(section + 60)?;
                if relocations > 0 {
                    let start = u32_at(section + 56)?;
                    let finish = start.checked_add(relocations.checked_mul(8)?)?;
                    if start < commands_end || finish > bytes.len() {
                        return None;
                    }
                    cuts.extend([start, finish]);
                }
                if cuts.len() > 65_536 {
                    return None;
                }
            }
        }
        offset = end;
    }
    if offset != commands_end {
        return None;
    }
    cuts.sort_unstable();
    cuts.dedup();
    Some(cuts)
}

fn compress(frame: &[u8], config: &Config) -> Vec<u8> {
    if frame.len() < 2 * 1024 * 1024 {
        return compress_frame(frame);
    }
    let cuts = if config.sections {
        section_boundaries(&frame[8..]).map(|offsets| {
            let mut cuts = vec![0];
            cuts.extend(offsets.into_iter().map(|o| o + 8));
            cuts
        })
    } else {
        None
    }
    .unwrap_or_else(|| vec![0, frame.len()]);
    let mut result = Vec::new();
    for pair in cuts.windows(2) {
        let section = &frame[pair[0]..pair[1]];
        for (offset, size) in boundaries(section, config.average) {
            result.extend(
                zstd::stream::encode_all(&section[offset..offset + size], config.level).unwrap(),
            );
        }
    }
    if result.len() < 2 * 1024 * 1024 {
        compress_frame(frame)
    } else {
        result
    }
}

fn main() {
    let fixtures: Vec<Fixture> = serde_json::from_slice(
        &fs::read(std::env::var("AUTORESEARCH_FIXTURES").expect("fixture manifest")).unwrap(),
    )
    .unwrap();
    let config: Config = serde_json::from_slice(
        &fs::read(
            std::env::var("AUTORESEARCH_CONFIG")
                .unwrap_or_else(|_| "autoresearch.config.json".into()),
        )
        .unwrap(),
    )
    .unwrap();
    assert!(
        (16 * 1024..=2 * 1024 * 1024).contains(&config.average) && config.average.is_power_of_two()
    );
    let (mut warm, mut cold, mut metadata, mut encode_ms, mut decode_ms) =
        (0usize, 0usize, 0usize, 0f64, 0f64);
    for fixture in fixtures {
        let frames = [
            encode_frame(&[], &fs::read(&fixture.base).unwrap()),
            encode_frame(&[], &fs::read(&fixture.edited).unwrap()),
        ];
        let started = Instant::now();
        let encoded: Vec<_> = frames.iter().map(|f| compress(f, &config)).collect();
        let mut encoding_samples = vec![started.elapsed().as_secs_f64() * 1000.0];
        for _ in 0..2 {
            let started = Instant::now();
            let repeated: Vec<_> = frames.iter().map(|f| compress(f, &config)).collect();
            encoding_samples.push(started.elapsed().as_secs_f64() * 1000.0);
            assert_eq!(encoded, repeated, "{} deterministic encoding", fixture.name);
        }
        encoding_samples.sort_by(f64::total_cmp);
        encode_ms += encoding_samples[1];
        let mut decoding_samples = Vec::new();
        for _ in 0..3 {
            let started = Instant::now();
            for (bytes, frame) in encoded.iter().zip(&frames) {
                assert_eq!(
                    &zstd::stream::decode_all(bytes.as_slice()).unwrap(),
                    frame,
                    "{} round trip",
                    fixture.name
                );
            }
            decoding_samples.push(started.elapsed().as_secs_f64() * 1000.0);
        }
        decoding_samples.sort_by(f64::total_cmp);
        decode_ms += decoding_samples[1];
        let chunks = |bytes: &[u8]| -> Vec<(String, usize)> {
            if bytes.len() < 2 * 1024 * 1024 {
                return vec![(blob_digest(bytes).hash, bytes.len())];
            }
            boundaries(bytes, 512 * 1024)
                .iter()
                .map(|(o, n)| (blob_digest(&bytes[*o..*o + n]).hash, *n))
                .collect()
        };
        let old: HashSet<_> = chunks(&encoded[0]).into_iter().map(|c| c.0).collect();
        let next = chunks(&encoded[1]);
        let missing: usize = next
            .iter()
            .filter(|(h, _)| !old.contains(h))
            .map(|c| c.1)
            .sum();
        let overhead = if encoded[1].len() < 2 * 1024 * 1024 {
            0
        } else {
            next.len() * 80
        };
        warm += missing + overhead;
        cold += encoded[1].len();
        metadata += overhead;
        println!(
            "CASE {} cold={} warm_payload={} chunks={} metadata={}",
            fixture.name,
            encoded[1].len(),
            missing,
            next.len(),
            overhead
        );
    }
    println!("METRIC warm_bytes={warm}\nMETRIC cold_bytes={cold}\nMETRIC metadata_bytes={metadata}\nMETRIC encode_ms={encode_ms}\nMETRIC decode_ms={decode_ms}");
}

#[test]
fn baseline_encoding_matches_the_production_encoder() {
    let mut seed = 0x1234_5678u64;
    let bytes: Vec<u8> = (0..4 * 1024 * 1024)
        .map(|_| {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            seed as u8
        })
        .collect();
    let config = Config {
        average: 512 * 1024,
        level: 1,
        sections: false,
    };
    for bytes in [bytes.as_slice(), &bytes[..64], &[0u8; 3 * 1024 * 1024]] {
        let frame = encode_frame(&[vec![1; 32]], bytes);
        assert_eq!(
            compress(&frame, &config),
            tuist_cas_plugin::reapi::compress_frame_for_transfer(&frame, true).0
        );
    }
}

#[test]
fn object_sections_and_relocations_define_byte_ranges_not_transforms() {
    let mut bytes = vec![0; 232];
    let put = |bytes: &mut [u8], at: usize, value: u32| {
        bytes[at..at + 4].copy_from_slice(&value.to_le_bytes())
    };
    put(&mut bytes, 0, 0xfeed_facf);
    put(&mut bytes, 12, 1);
    put(&mut bytes, 16, 1);
    put(&mut bytes, 20, 152);
    put(&mut bytes, 32, 0x19);
    put(&mut bytes, 36, 152);
    put(&mut bytes, 96, 1);
    put(&mut bytes, 144, 16);
    put(&mut bytes, 152, 184);
    put(&mut bytes, 160, 208);
    put(&mut bytes, 164, 2);
    assert_eq!(
        section_boundaries(&bytes).unwrap(),
        vec![0, 184, 200, 208, 224, 232]
    );
    put(&mut bytes, 152, 230);
    assert!(section_boundaries(&bytes).is_none());
    put(&mut bytes, 152, 184);
    put(&mut bytes, 160, 230);
    assert!(section_boundaries(&bytes).is_none());
}

#[test]
fn unknown_and_truncated_object_layouts_fall_back() {
    assert!(section_boundaries(b"not an object").is_none());
    assert!(section_boundaries(&[0xcf, 0xfa, 0xed, 0xfe]).is_none());
    let mut truncated = vec![0; 32];
    truncated[..4].copy_from_slice(&[0xcf, 0xfa, 0xed, 0xfe]);
    truncated[12] = 1;
    truncated[16] = 1;
    truncated[20] = 72;
    assert!(section_boundaries(&truncated).is_none());
}
