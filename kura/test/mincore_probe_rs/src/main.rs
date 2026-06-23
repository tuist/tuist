//! Reproduce kura's mmap residency gate (`src/mmap.rs`) with the exact crates
//! and code path, so we can see what `mincore` reports for the precise scenario
//! the failing tests use (a tiny file mapped at a sub-page offset via memmap2)
//! on different filesystems/runners.
//!
//! Run: `cargo run --release -- <dir>` (defaults to $TEST_TMPDIR / $TMPDIR / /tmp).

use std::fs::OpenOptions;
use std::io::Write;
use std::os::raw::c_void;

use memmap2::{Mmap, MmapOptions};

fn page_size() -> Option<usize> {
    let size = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
    usize::try_from(size).ok().filter(|size| size.is_power_of_two())
}

/// Verbatim from kura `src/mmap.rs::mapping_is_resident`, but also returns the
/// raw mincore rc and resident/total page counts for diagnostics.
fn mapping_residency(mmap: &Mmap) -> (i32, usize, usize) {
    let len = mmap.len();
    if len == 0 {
        return (0, 0, 0);
    }
    let page_size = page_size().expect("page size");

    let addr = mmap.as_ptr() as usize;
    let aligned = addr & !(page_size - 1);
    let prefix = addr - aligned;
    let total = prefix + len;
    let pages = total.div_ceil(page_size);
    let mut residency = vec![0u8; pages];

    let rc = unsafe { libc::mincore(aligned as *mut c_void, total, residency.as_mut_ptr().cast()) };
    let resident = residency.iter().filter(|page| *page & 1 == 1).count();
    (rc, resident, pages)
}

fn probe(dir: &str, file_size: usize, offset: u64, len: u64) {
    let path = format!("{dir}/.mincore_probe_rs.bin");
    let data = vec![0xABu8; file_size];

    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(true)
        .open(&path)
        .expect("open");
    (&file).write_all(&data).expect("write");
    file.sync_all().expect("sync");

    // Same call kura's map_file_region makes.
    let mmap = unsafe {
        MmapOptions::new()
            .offset(offset)
            .len(len as usize)
            .map(&file)
            .expect("mmap")
    };

    let (rc, resident, pages) = mapping_residency(&mmap);
    let verdict = if rc == 0 && resident == pages {
        "Some (RESIDENT -> mmap served, test passes)"
    } else {
        "None (NOT resident -> falls back, test PANICS)"
    };
    println!(
        "  file_size={file_size:>7}  offset={offset}  len={len}  ->  mincore_rc={rc}  resident={resident}/{pages}  map_file_region={verdict}"
    );

    drop(mmap);
    let _ = std::fs::remove_file(&path);
}

fn main() {
    let dir = std::env::args()
        .nth(1)
        .or_else(|| std::env::var("TEST_TMPDIR").ok())
        .or_else(|| std::env::var("TMPDIR").ok())
        .unwrap_or_else(|| "/tmp".to_string());

    println!("dir={dir}");
    // The EXACT failing kura test: 16-byte file, sub-page region (offset 3, len 8).
    probe(&dir, 16, 3, 8);
    // Brackets to find where (if anywhere) residency flips.
    probe(&dir, 1, 0, 1);
    probe(&dir, 4096, 3, 8);
    probe(&dir, 4096, 0, 4096);
    probe(&dir, 256 * 1024, 0, 256 * 1024);
}
