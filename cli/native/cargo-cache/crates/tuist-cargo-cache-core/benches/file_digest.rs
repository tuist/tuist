//! Compare content hashing with the additional C/C++ timestamp-macro scan.
use std::hint::black_box;
use std::time::{Duration, Instant};
use tuist_cargo_cache_core::{FileDigestScope, digest_file};

fn main() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("input.h");
    for size in [4096, 65536, 4 * 1024 * 1024] {
        let line = b"#define __example_value(x) ((x) + 1) /* header declaration */\n";
        let bytes: Vec<_> = line.iter().copied().cycle().take(size).collect();
        std::fs::write(&path, &bytes).unwrap();
        for scope in [FileDigestScope::Content, FileDigestScope::CcInput] {
            let expected = digest_file(FileDigestScope::Content, &path).unwrap();
            assert_eq!(digest_file(scope, &path).unwrap(), expected);
            let mut samples = Vec::new();
            for _ in 0..7 {
                let start = Instant::now();
                let mut iterations = 0;
                while start.elapsed() < Duration::from_millis(150) {
                    black_box(digest_file(scope, black_box(&path)).unwrap());
                    iterations += 1;
                }
                samples.push(start.elapsed().as_secs_f64() / iterations as f64);
            }
            samples.sort_by(f64::total_cmp);
            println!(
                "{scope:?} {size} bytes: median {:.3} us, range {:.3}..{:.3} us",
                samples[3] * 1e6,
                samples[0] * 1e6,
                samples[6] * 1e6
            );
        }
    }
}
