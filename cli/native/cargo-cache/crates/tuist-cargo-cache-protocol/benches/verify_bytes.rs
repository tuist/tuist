//! Measure repeated verification of in-memory cache records.
use sha2::Digest as _;
use std::hint::black_box;
use std::time::{Duration, Instant};
use tuist_cargo_cache_protocol::Digest;
fn main() {
    for size in [0, 64, 1024] {
        let bytes = vec![b'x'; size];
        for digest in [
            Digest::blake3(&bytes),
            Digest {
                algorithm: "sha256".into(),
                hash: hex::encode(sha2::Sha256::digest(&bytes)),
                size: size as u64,
            },
        ] {
            let mut samples = Vec::new();
            for _ in 0..7 {
                let start = Instant::now();
                let mut iterations = 0;
                while start.elapsed() < Duration::from_millis(150) {
                    assert!(black_box(&digest).matches_bytes(black_box(&bytes)).unwrap());
                    iterations += 1;
                }
                samples.push(start.elapsed().as_secs_f64() * 1e9 / iterations as f64);
            }
            samples.sort_by(f64::total_cmp);
            println!(
                "{} {size} bytes: median {:.1} ns, range {:.1}..{:.1} ns",
                digest.algorithm, samples[3], samples[0], samples[6]
            );
        }
    }
}
