//! Read-path microbench against a kura REAPI endpoint. Self-seeds synthetic
//! blobs sized like real CAS nodes, then measures: sequential single-blob
//! batches (per-RPC atom), one big batch (server-side batch behavior), and
//! 16 concurrent 30-blob batches (the proxy's warm-build workload shape).

use std::time::Instant;

use tuist_cas_plugin::reapi::{blob_digest, Remote, RemoteConfig};
use tuist_cas_plugin::token::TokenProvider;

fn main() {
    let Some(config) = RemoteConfig::from_env() else {
        eprintln!("TUIST_CAS_REMOTE_GRPC_URL required");
        std::process::exit(2);
    };
    let remote = Remote::new(config, TokenProvider::from_env());

    // Seed 480 blobs of ~16KB with distinct content.
    let mut blobs = Vec::new();
    let mut uploads = Vec::new();
    for index in 0u32..480 {
        let mut content = vec![0u8; 16 * 1024];
        content[..4].copy_from_slice(&index.to_be_bytes());
        for (offset, byte) in content.iter_mut().enumerate().skip(4) {
            *byte = ((offset as u32).wrapping_mul(2654435761).wrapping_add(index) >> 16) as u8;
        }
        let digest = blob_digest(&content);
        blobs.push(digest.clone());
        uploads.push((digest, content));
    }
    let started = Instant::now();
    remote.batch_update(uploads).expect("seed");
    println!("seeded 480x16KB in {:?}", started.elapsed());

    // Per-RPC atom: sequential single-blob batches.
    let started = Instant::now();
    for digest in &blobs[..100] {
        remote.batch_read(std::slice::from_ref(digest)).expect("read");
    }
    let elapsed = started.elapsed();
    println!("sequential single-blob: n=100 total={elapsed:?} per_rpc={:?}", elapsed / 100);

    // Whole set in one batch.
    let started = Instant::now();
    let contents = remote.batch_read(&blobs).expect("batch");
    println!(
        "one batch: n={} bytes={} elapsed={:?}",
        blobs.len(),
        contents.values().map(|value| value.len()).sum::<usize>(),
        started.elapsed()
    );

    // Workload shape: 16 concurrent 30-blob batches over the same channel.
    let chunks: Vec<Vec<_>> = blobs.chunks(30).map(|chunk| chunk.to_vec()).collect();
    let started = Instant::now();
    let mut per_batch = Vec::new();
    std::thread::scope(|scope| {
        let handles: Vec<_> = chunks
            .iter()
            .map(|chunk| {
                scope.spawn(|| {
                    let batch_started = Instant::now();
                    remote.batch_read(chunk).expect("chunk");
                    batch_started.elapsed()
                })
            })
            .collect();
        for handle in handles {
            per_batch.push(handle.join().expect("join"));
        }
    });
    per_batch.sort();
    println!(
        "concurrent 30-blob x{}: wall={:?} batch p50={:?} p95={:?}",
        chunks.len(),
        started.elapsed(),
        per_batch[per_batch.len() / 2],
        per_batch[per_batch.len() * 95 / 100]
    );
}
