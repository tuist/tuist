use bazel_remote_apis::build::bazel::remote::execution::v2 as reapi;
use std::{
    fs,
    time::{Instant, SystemTime, UNIX_EPOCH},
};
use tuist_cas_plugin::{
    reapi::{
        blob_digest, compress_frame, compress_frame_in_chunks, encode_frame, Remote, RemoteConfig,
    },
    token::TokenProvider,
};

fn corpus() -> Vec<u8> {
    let mut state = 0x12345678_u64;
    (0..8 * 1024 * 1024)
        .map(|_| {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            state as u8
        })
        .collect()
}

#[test]
fn chunk_boundaries_resynchronize_after_insertions_and_deletions() {
    let bytes = corpus();
    let chunks = |bytes: &[u8]| {
        fastcdc::v2020::FastCDC::with_level(
            bytes,
            128 * 1024,
            512 * 1024,
            2 * 1024 * 1024,
            fastcdc::v2020::Normalization::Level2,
        )
        .map(|c| (c.offset, c.length))
        .collect::<Vec<_>>()
    };
    let original = chunks(&bytes);
    println!(
        "chunk vector: {:?}",
        original
            .iter()
            .map(|(_, length)| length)
            .collect::<Vec<_>>()
    );
    let mut inserted = bytes.clone();
    inserted.splice(1_000_000..1_000_000, b"an insertion".iter().copied());
    let mut deleted = bytes.clone();
    deleted.drain(1_000_000..1_001_000);
    let known: std::collections::HashSet<_> = original
        .iter()
        .map(|(offset, length)| blob_digest(&bytes[*offset..offset + length]).hash)
        .collect();
    for changed in [inserted, deleted] {
        let reused: usize = chunks(&changed)
            .iter()
            .filter(|(offset, length)| {
                known.contains(&blob_digest(&changed[*offset..offset + length]).hash)
            })
            .map(|(_, length)| length)
            .sum();
        assert!(reused > bytes.len() * 3 / 4, "only {reused} bytes reused");
    }
}

/// Uses the production transport and a locally running Kura. No stand-in cache.
#[test]
#[ignore = "requires TUIST_CHUNKING_TEST_URL pointing at a local Kura"]
fn uploads_and_legacy_reads_against_kura() {
    let url = std::env::var("TUIST_CHUNKING_TEST_URL").expect("local Kura URL");
    assert!(url.starts_with("http://127.0.0.1:"));
    let instance = format!(
        "chunking-rust-{}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    );
    let remote = Remote::new(
        RemoteConfig {
            grpc_url: url.clone(),
            instance: instance.clone(),
        },
        TokenProvider::from_env(),
    );
    let original = corpus();
    let mut changed = original.clone();
    changed.splice(1_000_000..1_000_000, b"an insertion".iter().copied());
    for (name, data) in [("cold", original), ("insertion", changed)] {
        let frame = encode_frame(&[], &data);
        let blob = compress_frame_in_chunks(&frame);
        assert_eq!(zstd::stream::decode_all(blob.as_slice()).unwrap(), frame);
        let digest = blob_digest(&blob);
        let before = remote.uploaded_blob_bytes();
        let started = Instant::now();
        remote
            .batch_update(vec![(digest.clone(), blob.clone())])
            .expect("chunked publication");
        let elapsed = started.elapsed();
        let sent = remote.uploaded_blob_bytes() - before;
        println!(
            "BENCH xcode {name} legacy_bytes={} whole_bytes={} uploaded_bytes={sent} elapsed_ms={:.3}",
            compress_frame(&frame).len(),
            blob.len(),
            elapsed.as_secs_f64() * 1000.0
        );
        if name == "insertion" {
            assert!(sent < blob.len() as u64 / 2);
        }
        assert!(remote
            .find_missing(vec![digest.clone()])
            .unwrap()
            .is_empty());
        let downloaded = remote
            .batch_read(&[digest.clone()])
            .expect("legacy whole-blob read");
        assert_eq!(downloaded[&digest.hash], blob);
        let runtime = tokio::runtime::Runtime::new().unwrap();
        runtime.block_on(async {
            let mut client = reapi::content_addressable_storage_client::ContentAddressableStorageClient::connect(url.clone()).await.unwrap();
            let recipe = client.split_blob(reapi::SplitBlobRequest { instance_name: instance.clone(), blob_digest: Some(digest), ..Default::default() }).await.unwrap().into_inner();
            assert!(recipe.chunk_digests.len() > 1);
            assert_eq!(recipe.chunking_function, reapi::chunking_function::Value::FastCdc2020 as i32);
        });
    }
    // Optional real compiler artifacts, supplied by the reproducible benchmark driver.
    if let Ok(paths) = std::env::var("TUIST_CHUNKING_ARTIFACTS") {
        for path in paths.split(':') {
            let data = fs::read(path).unwrap();
            let frame = encode_frame(&[], &data);
            let original_compressed = compress_frame(&frame);
            let blob = compress_frame_in_chunks(&frame);
            let before = remote.uploaded_blob_bytes();
            let started = Instant::now();
            remote
                .batch_update(vec![(blob_digest(&blob), blob.clone())])
                .unwrap();
            println!("BENCH xcode_file path={path} legacy_compressed_bytes={} whole_bytes={} uploaded_bytes={} elapsed_ms={:.3}", original_compressed.len(), blob.len(), remote.uploaded_blob_bytes() - before, started.elapsed().as_secs_f64() * 1000.0);
        }
    }
}
