//! Offline receiver-only measurements. Workers have no target file or sender state.
mod bitstream_probe;
use bitstream_probe::segments::{Segments, Source};
use std::borrow::Cow;

use serde::{Deserialize, Serialize};
use std::{
    fs,
    io::{Read, Write},
    path::Path,
    process::Command,
    time::Instant,
};
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
    group_bytes: usize,
    residual: bool,
    fast_hash: bool,
    compact_layout: bool,
    compact_columns: bool,
    #[serde(default)]
    receiver_segments: bool,
    #[serde(default)]
    receiver_release: bool,
}

#[derive(Serialize, Deserialize)]
struct Expected {
    size: usize,
    original_hash: String,
    blob_hash: String,
    blob_size: i64,
}

fn read(path: impl AsRef<Path>, limit: usize) -> Vec<u8> {
    let file = fs::File::open(path).unwrap();
    assert!(file.metadata().unwrap().len() <= limit as u64);
    let mut bytes = Vec::new();
    file.take(limit as u64 + 1).read_to_end(&mut bytes).unwrap();
    assert!(bytes.len() <= limit);
    bytes
}

fn write_new(path: impl AsRef<Path>, bytes: &[u8]) {
    fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .unwrap()
        .write_all(bytes)
        .unwrap();
}

fn prepare(bytes: &[u8], config: &Config) -> Vec<u8> {
    assert!(config.fields && config.group_bytes > 0);
    if !config.compact_layout && !config.compact_columns {
        return bitstream_probe::prepare(bytes, config.delta, config.column_cap).unwrap();
    }
    bitstream_probe::prepare_compact(
        bytes,
        config.delta,
        config.column_cap,
        config.compact_layout,
        config.compact_columns,
    )
    .unwrap()
}

fn compressed(bytes: &[u8]) -> Vec<u8> {
    compress_frame_for_transfer(
        &encode_frame(&[vec![0x47; 32], vec![0x62; 64]], bytes),
        true,
    )
    .0
}

fn peak_bytes() -> u64 {
    let mut usage = std::mem::MaybeUninit::<libc::rusage>::uninit();
    // The operating system initializes this output structure.
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

fn median(values: &mut [f64]) -> f64 {
    values.sort_by(f64::total_cmp);
    values[values.len() / 2]
}

fn worker(arguments: &[&str]) -> serde_json::Value {
    let output = Command::new(std::env::current_exe().unwrap())
        .args(arguments)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice(&output.stdout).unwrap()
}

fn receive(paths: &[String], config: &Config) -> serde_json::Value {
    assert_eq!(paths.len(), 4);
    let start = Instant::now();
    let base = read(&paths[0], bitstream_probe::MAX_INPUT);
    let patch = read(&paths[1], bitstream_probe::MAX_PREPARED + 8 * 1024 * 1024);
    let expected: Expected = serde_json::from_slice(&read(&paths[2], 4096)).unwrap();
    let base_prepared = if config.receiver_segments {
        bitstream_probe::prepare_segments(
            &base,
            config.delta,
            config.column_cap,
            config.compact_layout,
            config.compact_columns,
        )
        .unwrap()
    } else {
        let mut parts = Segments::default();
        parts.push(Cow::Owned(prepare(&base, config))).unwrap();
        parts
    };
    let prepare_peak = peak_bytes();
    if config.receiver_release {
        drop(base);
    }
    let prepared = if config.receiver_segments {
        bitstream_probe::grouped::decode_segments(&base_prepared, &patch, config.fast_hash).unwrap()
    } else {
        let mut parts = Segments::default();
        let base_bytes = base_prepared.range(0, base_prepared.len()).unwrap();
        parts
            .push(Cow::Owned(
                bitstream_probe::grouped::decode(&base_bytes, &patch, config.fast_hash).unwrap(),
            ))
            .unwrap();
        parts
    };
    let restored = bitstream_probe::restore_source(&prepared, expected.size).unwrap();
    let owned_prepared = base_prepared.owned_bytes() + prepared.owned_bytes();
    if config.receiver_release {
        drop(prepared);
        drop(base_prepared);
    }
    assert_eq!(blob_digest(&restored).hash, expected.original_hash);
    let blob = compressed(&restored);
    let digest = blob_digest(&blob);
    assert_eq!(digest.hash, expected.blob_hash);
    assert_eq!(digest.size_bytes, expected.blob_size);
    write_new(&paths[3], &restored);
    serde_json::json!({"receiver_ms":start.elapsed().as_secs_f64()*1000.0,
        "receiver_peak_bytes":peak_bytes(), "prepare_peak_bytes":prepare_peak,
        "owned_prepared_bytes":owned_prepared})
}

fn main() {
    let config: Config = serde_json::from_slice(&read(
        std::env::var("AUTORESEARCH_CONFIG").unwrap_or_else(|_| "autoresearch.swift.json".into()),
        4096,
    ))
    .unwrap();
    let arguments: Vec<_> = std::env::args().collect();
    if arguments.get(1).map(String::as_str) == Some("send") {
        let base = read(&arguments[2], bitstream_probe::MAX_INPUT);
        let next = read(&arguments[3], bitstream_probe::MAX_INPUT);
        if base == next {
            println!("{{\"identical\":true}}");
            return;
        }
        let blob = compressed(&next);
        let digest = blob_digest(&blob);
        let expected = Expected {
            size: next.len(),
            original_hash: blob_digest(&next).hash,
            blob_hash: digest.hash,
            blob_size: digest.size_bytes,
        };
        let base_prepared = prepare(&base, &config);
        let next_prepared = prepare(&next, &config);
        let patch = bitstream_probe::grouped::encode(
            &base_prepared,
            &next_prepared,
            config.group_bytes,
            config.level,
            config.residual,
            config.fast_hash,
        )
        .unwrap();
        let restored_prepared =
            bitstream_probe::grouped::decode(&base_prepared, &patch.bytes, config.fast_hash)
                .unwrap();
        assert_eq!(restored_prepared, next_prepared);
        let restored = bitstream_probe::restore(&restored_prepared, next.len()).unwrap();
        assert_eq!(restored, next);
        assert_eq!(compressed(&restored), blob);
        write_new(&arguments[4], &patch.bytes);
        write_new(&arguments[5], &serde_json::to_vec(&expected).unwrap());
        println!(
            "{}",
            serde_json::json!({"identical":false,
            "warm_bytes":(patch.bytes.len() + 192).min(blob.len()),
            "groups":patch.groups, "metadata_bytes":patch.metadata_bytes(),
            "prepared_bytes":next_prepared.len()})
        );
        return;
    }
    if arguments.get(1).map(String::as_str) == Some("receive") {
        println!("{}", receive(&arguments[2..], &config));
        return;
    }
    if arguments.get(1).map(String::as_str) == Some("receive-many") {
        let jobs: Vec<[String; 4]> =
            serde_json::from_slice(&read(&arguments[2], 1024 * 1024)).unwrap();
        assert!(!jobs.is_empty() && jobs.len() <= 128);
        let results: Vec<_> = jobs.iter().map(|paths| receive(paths, &config)).collect();
        println!(
            "{}",
            serde_json::json!({"jobs":results, "receiver_peak_bytes":peak_bytes()})
        );
        return;
    }
    let fixtures: Vec<Fixture> = serde_json::from_slice(&read(
        std::env::var("AUTORESEARCH_FIXTURES").unwrap(),
        1024 * 1024,
    ))
    .unwrap();
    let directory = std::env::var("AUTORESEARCH_RECEIVER_DIR").unwrap();
    let (mut warm, mut prepared_bytes, mut receiver_ms, mut worker_ms, mut peak) =
        (0, 0, 0.0, 0.0, 0.0f64);
    for fixture in fixtures {
        assert!(
            !fixture.name.is_empty()
                && fixture
                    .name
                    .bytes()
                    .all(|c| c.is_ascii_alphanumeric() || c == b'_')
        );
        let patch = format!("{directory}/{}.patch", fixture.name);
        let expected = format!("{directory}/{}.json", fixture.name);
        let sent = worker(&["send", &fixture.base, &fixture.edited, &patch, &expected]);
        if sent["identical"] == true {
            println!("CASE {} identical=true selected_bytes=0", fixture.name);
            continue;
        }
        let mut timings = Vec::new();
        let mut walls = Vec::new();
        let mut peaks = Vec::new();
        for repetition in 0..3 {
            let restored = format!("{directory}/{}-{repetition}.restored", fixture.name);
            let start = Instant::now();
            let received = worker(&["receive", &fixture.base, &patch, &expected, &restored]);
            walls.push(start.elapsed().as_secs_f64() * 1000.0);
            timings.push(received["receiver_ms"].as_f64().unwrap());
            peaks.push(received["receiver_peak_bytes"].as_f64().unwrap());
            assert_eq!(
                read(&restored, bitstream_probe::MAX_INPUT),
                read(&fixture.edited, bitstream_probe::MAX_INPUT)
            );
        }
        let elapsed = median(&mut timings);
        let wall = median(&mut walls);
        let case_peak = median(&mut peaks);
        let selected = sent["warm_bytes"].as_u64().unwrap();
        warm += selected;
        prepared_bytes += sent["prepared_bytes"].as_u64().unwrap();
        receiver_ms += elapsed;
        worker_ms += wall;
        peak = peak.max(case_peak);
        println!("CASE {} selected_bytes={selected} receiver_ms={elapsed:.3} worker_ms={wall:.3} receiver_peak_bytes={case_peak}", fixture.name);
    }
    println!("METRIC warm_bytes={warm}\nMETRIC prepared_bytes={prepared_bytes}\nMETRIC receiver_ms={receiver_ms}\nMETRIC worker_ms={worker_ms}\nMETRIC receiver_peak_bytes={peak}");
}
