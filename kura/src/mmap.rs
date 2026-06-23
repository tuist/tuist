use std::fs::File;

use bytes::Bytes;
use tokio::sync::OwnedSemaphorePermit;

#[cfg(unix)]
use std::os::raw::c_void;

#[cfg(unix)]
use memmap2::{Mmap, MmapOptions};

/// A region mapped for zero-copy serving plus a note on *why* the residency
/// gate admitted it.
#[derive(Debug)]
pub struct MmapServe {
    /// The mapped, page-cache-resident bytes (owns the mapping and the
    /// memory-budget permit).
    pub bytes: Bytes,
    /// True when the only reason this region passed the residency gate is that
    /// the file's final partial page was exempted while its `mincore` bit was
    /// clear. This is the one path that can fault a single cold page on a tokio
    /// worker, so the store meters how often it happens.
    pub partial_page_exempted: bool,
}

/// Maps `len` bytes of `file` starting at `offset` into a read-only `Bytes`
/// whose lifetime owns both the mapping and the memory-budget `permit`.
///
/// Returns `Ok(None)` when the region is mappable but **not already resident in
/// the page cache**, so the caller serves it through the streaming reader path
/// instead. See the residency note below.
///
/// # Safety and concurrency
///
/// A `MAP_PRIVATE`/`PROT_READ` mapping aliases the page cache for the backing
/// file. Reads are sound only while the mapped region keeps existing on disk:
/// unlinking the file is safe (the inode survives until the mapping drops), but
/// **truncating or shrinking the file in place would fault any live mapping with
/// SIGBUS and crash the process**. This is sound here only because Kura segment
/// and blob files are append-only and are reclaimed by unlink, never by
/// `truncate`/`set_len`. If that invariant ever changes (for example, in-place
/// segment compaction), this mapping becomes unsound. See `Store` for the
/// callers that uphold it.
///
/// Touching a non-resident mapped page faults synchronous, kernel-side disk I/O
/// on whatever thread reads it, and that thread is a tokio worker once the
/// `Bytes` is written to a socket. Under concurrency, cold faults across many
/// streams would starve the worker pool. mmap serving is only ever a win when
/// the pages are already resident, so we gate on `mincore`: a fully-resident
/// region maps and serves zero-copy without faulting, and anything cold returns
/// `Ok(None)` so the caller falls back to `Store::read_artifact_bytes`, which
/// keeps cold disk reads off the async workers with `spawn_blocking`.
///
/// The `mincore` check is point-in-time: a page can be evicted between the
/// check and a socket write. That is benign and distinct from the truncation
/// case above. Eviction does not remove the file's backing (the mapping pins the
/// inode, and the file is append-only), so the access re-faults cleanly from
/// disk: correct bytes, just a brief blocking re-read for that chunk. The only
/// behavior that differs from the reader path is a genuine disk **read error**
/// during a fault, which mmap surfaces as SIGBUS (process crash) rather than a
/// recoverable `io::Error`. That is inherent to serving from a mapping; the
/// residency gate minimizes how often we fault at all, and a crashed node is
/// recoverable because peers keep serving and the artifact re-replicates.
#[cfg(unix)]
pub fn map_file_region(
    file: &File,
    offset: u64,
    len: u64,
    permit: OwnedSemaphorePermit,
) -> Result<Option<MmapServe>, String> {
    if len == 0 {
        return Ok(Some(MmapServe {
            bytes: Bytes::new(),
            partial_page_exempted: false,
        }));
    }

    let file_len = file
        .metadata()
        .map_err(|error| format!("failed to stat mmap source file: {error}"))?
        .len();
    let end = offset
        .checked_add(len)
        .ok_or_else(|| "mmap region offset overflows file size".to_string())?;
    if end > file_len {
        return Err(format!(
            "mmap region {offset}..{end} exceeds file size {file_len}"
        ));
    }

    let len =
        usize::try_from(len).map_err(|_| "mmap region length does not fit in usize".to_string())?;

    // SAFETY: the region is in-bounds (checked above) and stays valid for the
    // lifetime of the mapping because the backing file is append-only and is
    // only ever removed by unlink, never truncated. See the module-level note.
    let mmap = unsafe {
        MmapOptions::new()
            .offset(offset)
            .len(len)
            .map(file)
            .map_err(|error| format!("failed to mmap file region {offset}..{end}: {error}"))?
    };

    let verdict = mapping_is_resident(&mmap, offset, file_len);
    if !verdict.serve {
        return Ok(None);
    }

    Ok(Some(MmapServe {
        bytes: Bytes::from_owner(MmapRegion {
            mmap,
            _permit: permit,
        }),
        partial_page_exempted: verdict.partial_page_exempted,
    }))
}

#[cfg(not(unix))]
pub fn map_file_region(
    _file: &File,
    _offset: u64,
    _len: u64,
    _permit: OwnedSemaphorePermit,
) -> Result<Option<MmapServe>, String> {
    Ok(None)
}

/// Computes a residency verdict for `mmap`: whether every page **fully backed by
/// file data** is currently resident in the page cache (so reading the mapping
/// will not fault disk I/O), and whether the final partial-page exemption was
/// the deciding factor. A conservative non-serving verdict (page size
/// unavailable, `mincore` failure) routes the caller to the reader path, which
/// is always correct.
///
/// `file_offset` is the file offset the mapping starts at (`map_file_region`'s
/// `offset`) and `file_len` the file's size; together they identify the file's
/// final **partial** page. A file whose size is not a multiple of the page size
/// has a last page that extends past EOF, and some filesystems — notably
/// virtio-fs — report that partial page as non-resident even when its bytes are
/// cached. Requiring it would needlessly disable mmap serving for sub-page (and
/// unaligned-tail) files, so the partial page is exempt: at worst its data
/// faults once as a single small read, while every fully-backed page still gates
/// normally.
#[cfg(unix)]
struct ResidencyVerdict {
    /// Every fully-backed page is resident, so the mapping can be served zero-copy.
    serve: bool,
    /// `serve` is true only because the final partial page was exempted while its
    /// `mincore` bit was clear. Surfaced for observability.
    partial_page_exempted: bool,
}

#[cfg(unix)]
fn mapping_is_resident(mmap: &Mmap, file_offset: u64, file_len: u64) -> ResidencyVerdict {
    const NOT_RESIDENT: ResidencyVerdict = ResidencyVerdict {
        serve: false,
        partial_page_exempted: false,
    };
    let len = mmap.len();
    if len == 0 {
        return ResidencyVerdict {
            serve: true,
            partial_page_exempted: false,
        };
    }
    let Some(page_size) = page_size() else {
        return NOT_RESIDENT;
    };

    // `mincore` requires a page-aligned base. memmap2 maps from the page-aligned
    // offset and exposes a slice that may start mid-page, so round the exposed
    // pointer down to the mapped base and extend the queried length to cover the
    // sub-page prefix.
    let addr = mmap.as_ptr() as usize;
    let aligned = addr & !(page_size - 1);
    let prefix = addr - aligned;
    let Some(total) = prefix.checked_add(len) else {
        return NOT_RESIDENT;
    };
    let pages = total.div_ceil(page_size);
    let mut residency = vec![0u8; pages];

    // SAFETY: `aligned` is the page-aligned base that memmap2 mapped from and
    // `total` spans only pages within that mapping; `residency` holds one byte
    // per queried page. `mincore` performs a read-only residency query and does
    // not touch (fault) the mapped pages.
    let result =
        unsafe { libc::mincore(aligned as *mut c_void, total, residency.as_mut_ptr().cast()) };
    if result != 0 {
        return NOT_RESIDENT;
    }

    // The mapping's first queried page starts at this page-aligned file offset.
    let page_size = page_size as u64;
    let aligned_file_offset = file_offset & !(page_size - 1);
    let serve = fully_backed_pages_resident(&residency, aligned_file_offset, file_len, page_size);
    let partial_page_exempted = serve
        && partial_page_exemption_applied(&residency, aligned_file_offset, file_len, page_size);
    ResidencyVerdict {
        serve,
        partial_page_exempted,
    }
}

/// Returns true when every page that is **fully backed by file data** has its
/// `mincore` resident bit set. The file's final partial page (one whose end
/// exceeds `file_len`) is exempt — see [`mapping_is_resident`].
#[cfg(unix)]
fn fully_backed_pages_resident(
    residency: &[u8],
    aligned_file_offset: u64,
    file_len: u64,
    page_size: u64,
) -> bool {
    residency.iter().enumerate().all(|(index, page)| {
        let page_end =
            aligned_file_offset.saturating_add((index as u64 + 1).saturating_mul(page_size));
        page_end > file_len || page & 1 == 1
    })
}

/// Returns true when the final partial page (one whose end exceeds `file_len`)
/// has a **clear** `mincore` resident bit — i.e. the partial-page exemption in
/// [`fully_backed_pages_resident`] is what admitted the mapping, rather than the
/// page being resident on its own. The store meters this for observability: it
/// is the path that may fault one cold page on a tokio worker.
#[cfg(unix)]
fn partial_page_exemption_applied(
    residency: &[u8],
    aligned_file_offset: u64,
    file_len: u64,
    page_size: u64,
) -> bool {
    residency.iter().enumerate().any(|(index, page)| {
        let page_end =
            aligned_file_offset.saturating_add((index as u64 + 1).saturating_mul(page_size));
        page_end > file_len && page & 1 == 0
    })
}

#[cfg(unix)]
fn page_size() -> Option<usize> {
    let size = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
    usize::try_from(size)
        .ok()
        .filter(|size| size.is_power_of_two())
}

#[cfg(unix)]
struct MmapRegion {
    mmap: Mmap,
    _permit: OwnedSemaphorePermit,
}

#[cfg(unix)]
impl AsRef<[u8]> for MmapRegion {
    fn as_ref(&self) -> &[u8] {
        self.mmap.as_ref()
    }
}

#[cfg(all(test, unix))]
mod tests {
    use std::{io::Write, sync::Arc};

    use tempfile::NamedTempFile;
    use tokio::sync::Semaphore;

    use super::{fully_backed_pages_resident, map_file_region, partial_page_exemption_applied};

    #[test]
    fn maps_unaligned_file_regions() {
        let mut file = NamedTempFile::new().expect("temp file should be created");
        file.write_all(b"0123456789abcdef")
            .expect("temp file should be written");
        file.as_file()
            .sync_all()
            .expect("temp file should be flushed");
        let permit = Arc::new(Semaphore::new(16))
            .try_acquire_many_owned(8)
            .expect("permit should be acquired");

        let serve = map_file_region(file.as_file(), 3, 8, permit)
            .expect("region should map")
            .expect("freshly written region should be page-cache resident");

        assert_eq!(&serve.bytes[..], b"3456789a");
    }

    #[test]
    fn fully_backed_pages_must_all_be_resident() {
        let page_size = 4096;
        // Three full pages, all resident.
        assert!(fully_backed_pages_resident(
            &[1, 1, 1],
            0,
            3 * page_size,
            page_size
        ));
        // A cold fully-backed page disqualifies the mapping.
        assert!(!fully_backed_pages_resident(
            &[1, 0, 1],
            0,
            3 * page_size,
            page_size
        ));
    }

    #[test]
    fn final_partial_page_is_exempt() {
        let page_size = 4096;
        // A 16-byte file's only page extends past EOF, so a cleared resident bit
        // (as virtio-fs reports it) is tolerated. This is the regression case.
        assert!(fully_backed_pages_resident(&[0], 0, 16, page_size));
        // 1.5-page file: the fully-backed first page is still required, the
        // partial tail page is exempt.
        assert!(fully_backed_pages_resident(
            &[1, 0],
            0,
            page_size + page_size / 2,
            page_size
        ));
        assert!(!fully_backed_pages_resident(
            &[0, 0],
            0,
            page_size + page_size / 2,
            page_size
        ));
    }

    #[test]
    fn non_zero_offset_anchors_the_partial_page_exemption() {
        let page_size = 4096;
        // A mapping into a 2.5-page file that starts at the second page: the
        // residency slice is anchored at `aligned_file_offset == page_size`, so
        // residency[0] is the fully-backed page [page_size, 2*page_size) and
        // residency[1] is the partial tail [2*page_size, 3*page_size) past EOF.
        let aligned_file_offset = page_size;
        let file_len = 2 * page_size + 100;
        assert!(fully_backed_pages_resident(
            &[1, 0],
            aligned_file_offset,
            file_len,
            page_size
        ));
        // A cold fully-backed page is still disqualifying at a non-zero offset.
        assert!(!fully_backed_pages_resident(
            &[0, 0],
            aligned_file_offset,
            file_len,
            page_size
        ));
        // Boundary: a page ending exactly at `file_len` is fully backed, not
        // exempt, so a cleared resident bit disqualifies it.
        assert!(!fully_backed_pages_resident(&[0], 0, page_size, page_size));
    }

    #[test]
    fn partial_page_exemption_is_flagged_only_when_it_decides() {
        let page_size = 4096;
        // 16-byte file, its sole page cold: the exemption is the deciding factor.
        assert!(partial_page_exemption_applied(&[0], 0, 16, page_size));
        // Same file but the page is resident: the exemption changed nothing.
        assert!(!partial_page_exemption_applied(&[1], 0, 16, page_size));
        // 1.5-page file, fully-backed page warm, partial tail cold: exemption fired.
        assert!(partial_page_exemption_applied(
            &[1, 0],
            0,
            page_size + page_size / 2,
            page_size
        ));
        // Page-aligned file: no partial page exists, so the exemption never fires.
        assert!(!partial_page_exemption_applied(
            &[0, 0],
            0,
            2 * page_size,
            page_size
        ));
    }

    #[test]
    fn maps_empty_regions_without_mmap() {
        let file = NamedTempFile::new().expect("temp file should be created");
        let permit = Arc::new(Semaphore::new(1))
            .try_acquire_owned()
            .expect("permit should be acquired");

        let serve = map_file_region(file.as_file(), 0, 0, permit)
            .expect("empty region should map")
            .expect("empty region is trivially resident");

        assert!(serve.bytes.is_empty());
    }

    #[test]
    fn rejects_regions_beyond_file_length() {
        let mut file = NamedTempFile::new().expect("temp file should be created");
        file.write_all(b"0123")
            .expect("temp file should be written");
        file.as_file()
            .sync_all()
            .expect("temp file should be flushed");
        let permit = Arc::new(Semaphore::new(16))
            .try_acquire_many_owned(4)
            .expect("permit should be acquired");

        let error = map_file_region(file.as_file(), 2, 4, permit)
            .expect_err("region should exceed file length");

        assert!(error.contains("exceeds file size"));
    }
}
