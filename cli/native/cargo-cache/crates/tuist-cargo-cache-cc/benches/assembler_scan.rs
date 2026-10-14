//! Measure safety scanning of preprocessed assembly inputs.
use std::ffi::OsString;
use std::hint::black_box;
use std::time::{Duration, Instant};
use tuist_cargo_cache_cc::CcInvocation;

fn main() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("input.S");
    let arguments: Vec<_> = ["-c", "input.S", "-o", "input.o"]
        .map(OsString::from)
        .into();
    let invocation = CcInvocation::parse(&arguments).unwrap();
    for size in [4096, 65536, 4 * 1024 * 1024] {
        for (name, line) in [
            (
                "typical",
                b".Lloop: add %rax, %rbx; jmp .Lloop /* assembly */\n".as_slice(),
            ),
            ("dot-heavy", b"................................\n"),
        ] {
            let bytes: Vec<_> = line.iter().copied().cycle().take(size).collect();
            std::fs::write(&path, &bytes).unwrap();
            invocation
                .validate_discovered_inputs([path.as_path()])
                .unwrap();
            let mut samples = Vec::new();
            for _ in 0..7 {
                let start = Instant::now();
                let mut iterations = 0;
                while start.elapsed() < Duration::from_millis(150) {
                    invocation
                        .validate_discovered_inputs([black_box(path.as_path())])
                        .unwrap();
                    iterations += 1;
                }
                samples.push(start.elapsed().as_secs_f64() / iterations as f64);
            }
            samples.sort_by(f64::total_cmp);
            println!(
                "{name} {size} bytes: median {:.3} us, range {:.3}..{:.3} us",
                samples[3] * 1e6,
                samples[0] * 1e6,
                samples[6] * 1e6
            );
        }
    }
}
