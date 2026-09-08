//! Offline research only. Never advertised through the existing chunk capability.
mod bitstream_probe;

use serde::Deserialize;
use std::{fs, time::Instant};
use tuist_cas_plugin::reapi::{blob_digest, compress_frame_for_transfer, encode_frame};

#[derive(Deserialize)]
struct Fixture {
    name: String,
    base: String,
    edited: String,
}
#[derive(Deserialize)]
struct Config {
    fields: bool,
    delta: bool,
    column_cap: u32,
    level: i32,
    window_log: u32,
}

fn prepare(bytes: &[u8], config: &Config) -> Vec<u8> {
    if config.fields {
        bitstream_probe::prepare(bytes, config.delta, config.column_cap).unwrap()
    } else {
        bytes.to_vec()
    }
}

fn elapsed(start: Instant) -> f64 {
    start.elapsed().as_secs_f64() * 1000.0
}
fn median(values: &mut [f64]) -> f64 {
    values.sort_by(f64::total_cmp);
    values[values.len() / 2]
}

fn peak_bytes() -> u64 {
    let mut usage = std::mem::MaybeUninit::<libc::rusage>::uninit();
    // The operating system initializes this fixed-size output structure.
    unsafe {
        assert_eq!(libc::getrusage(libc::RUSAGE_SELF, usage.as_mut_ptr()), 0);
        let bytes = usage.assume_init().ru_maxrss as u64;
        if cfg!(target_os = "macos") {
            bytes
        } else {
            bytes * 1024
        }
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
                .unwrap_or_else(|_| "autoresearch.swift.json".into()),
        )
        .unwrap(),
    )
    .unwrap();
    assert!(config.window_log == 0 || (19..=25).contains(&config.window_log));
    assert!((1..=9).contains(&config.level));
    let (mut warm, mut cold, mut prepared_bytes) = (0usize, 0usize, 0usize);
    let (mut base_ms, mut target_ms, mut patch_ms, mut restore_ms, mut verify_ms) =
        (0.0, 0.0, 0.0, 0.0, 0.0);
    for fixture in fixtures {
        let base = fs::read(&fixture.base).unwrap();
        let next = fs::read(&fixture.edited).unwrap();
        assert!(
            base.len() <= bitstream_probe::MAX_INPUT && next.len() <= bitstream_probe::MAX_INPUT
        );
        // A nonempty reference list makes this check cover the complete node
        // frame, not only the module file. These are synthetic graph references.
        let references = vec![vec![0x47; 32], vec![0x62; 64]];
        let expected_frame = encode_frame(&references, &next);
        let expected_blob = compress_frame_for_transfer(&expected_frame, true).0;
        let expected_digest = blob_digest(&expected_blob);
        cold += expected_blob.len();
        if base == next {
            println!(
                "CASE {} identical=true whole_bytes={} selected_bytes=0",
                fixture.name,
                expected_blob.len()
            );
            continue;
        }
        let mut samples = [Vec::new(), Vec::new(), Vec::new(), Vec::new(), Vec::new()];
        let mut patch_size = 0;
        let mut prepared_size = 0;
        let mut selected = 0;
        for repetition in 0..3 {
            let start = Instant::now();
            let base_prepared = prepare(&base, &config);
            samples[0].push(elapsed(start));
            let start = Instant::now();
            let next_prepared = prepare(&next, &config);
            samples[1].push(elapsed(start));
            prepared_size = next_prepared.len();
            let start = Instant::now();
            let mut compressor =
                zstd::bulk::Compressor::with_dictionary(config.level, &base_prepared).unwrap();
            if config.window_log != 0 {
                compressor
                    .set_parameter(zstd::zstd_safe::CParameter::WindowLog(config.window_log))
                    .unwrap();
            }
            let patch = compressor.compress(&next_prepared).unwrap();
            samples[2].push(elapsed(start));
            drop(compressor);
            if repetition != 0 {
                assert_eq!(patch_size, patch.len());
            }
            patch_size = patch.len();
            // Account for a conservative fixed envelope estimate: base/target
            // digests, sizes, codec parameters. This is not a deployed protocol.
            selected = (patch.len() + 192).min(expected_blob.len());
            let start = Instant::now();
            let mut decoder = zstd::bulk::Decompressor::with_dictionary(&base_prepared).unwrap();
            let prepared = decoder
                .decompress(&patch, bitstream_probe::MAX_PREPARED)
                .unwrap();
            let restored = if config.fields {
                bitstream_probe::restore(&prepared, next.len()).unwrap()
            } else {
                prepared
            };
            samples[3].push(elapsed(start));
            let start = Instant::now();
            assert_eq!(restored, next);
            let frame = encode_frame(&references, &restored);
            let blob = compress_frame_for_transfer(&frame, true).0;
            assert_eq!(blob_digest(&blob), expected_digest);
            assert_eq!(blob, expected_blob);
            samples[4].push(elapsed(start));
            if repetition == 0 && config.fields {
                assert_eq!(
                    bitstream_probe::restore(&base_prepared, base.len()).unwrap(),
                    base
                );
            }
            if repetition == 0 {
                if let Ok(directory) = std::env::var("SWIFT_PATCH_RESTORED_DIR") {
                    use std::io::Write;
                    let extension = std::path::Path::new(&fixture.edited)
                        .extension()
                        .unwrap()
                        .to_str()
                        .unwrap();
                    let path = std::path::Path::new(&directory)
                        .join(format!("{}.{}", fixture.name, extension));
                    fs::OpenOptions::new()
                        .write(true)
                        .create_new(true)
                        .open(path)
                        .unwrap()
                        .write_all(&restored)
                        .unwrap();
                }
            }
        }
        let timings: Vec<_> = samples.iter_mut().map(|values| median(values)).collect();
        base_ms += timings[0];
        target_ms += timings[1];
        patch_ms += timings[2];
        restore_ms += timings[3];
        verify_ms += timings[4];
        warm += selected;
        prepared_bytes += prepared_size;
        println!("CASE {} whole_bytes={} patch_bytes={} selected_bytes={} prepared_bytes={} base_ms={:.3} target_ms={:.3} patch_ms={:.3} restore_ms={:.3} verify_ms={:.3}", fixture.name, expected_blob.len(), patch_size, selected, prepared_size, timings[0], timings[1], timings[2], timings[3], timings[4]);
    }
    println!("METRIC warm_bytes={warm}\nMETRIC cold_bytes={cold}\nMETRIC prepared_bytes={prepared_bytes}\nMETRIC base_prepare_ms={base_ms}\nMETRIC target_prepare_ms={target_ms}\nMETRIC patch_ms={patch_ms}\nMETRIC restore_ms={restore_ms}\nMETRIC verify_ms={verify_ms}\nMETRIC peak_rss_bytes={}", peak_bytes());
}
