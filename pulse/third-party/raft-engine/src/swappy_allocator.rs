// Copyright (c) 2017-present, PingCAP, Inc. Licensed under Apache-2.0.

//! # Swappy Allocator

use std::alloc::{AllocError, Allocator, Global, Layout};
use std::fs::{File, OpenOptions};
use std::path::{Path, PathBuf};
use std::ptr::{self, NonNull};
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicUsize, Ordering};
use std::sync::Arc;
use std::vec::Vec;

use log::{error, warn};
use memmap2::MmapMut;
use parking_lot::Mutex;

use crate::metrics::SWAP_FILE_COUNT;

const DEFAULT_PAGE_SIZE: usize = 64 * 1024 * 1024; // 64MB

struct SwappyAllocatorCore<A = Global>
where
    A: Allocator + Send + Sync,
{
    budget: usize,
    path: PathBuf,

    mem_usage: AtomicUsize,
    mem_allocator: A,

    maybe_swapped: AtomicBool,
    page_seq: AtomicU32,
    pages: Mutex<Vec<Page>>,
}

/// An [`Allocator`] implementation that has a memory budget and can be swapped
/// out.
///
/// The allocations of its internal metadata are not managed (i.e. allocated via
/// `std::alloc::Global`). Do NOT use it as the global allocator.
#[derive(Clone)]
pub struct SwappyAllocator<A: Allocator + Send + Sync>(Arc<SwappyAllocatorCore<A>>);

impl<A: Allocator + Send + Sync> SwappyAllocator<A> {
    pub fn new_over(path: &Path, budget: usize, alloc: A) -> SwappyAllocator<A> {
        if path.exists() {
            if let Err(e) = std::fs::remove_dir_all(path) {
                error!(
                    "Failed to clean up old swap directory: {e}. \
                    There might be obsolete swap files left in {}.",
                    path.display()
                );
            }
        }
        let core = SwappyAllocatorCore {
            budget,
            path: path.into(),
            mem_usage: AtomicUsize::new(0),
            mem_allocator: alloc,
            maybe_swapped: AtomicBool::new(false),
            page_seq: AtomicU32::new(0),
            pages: Mutex::new(Vec::new()),
        };
        SwappyAllocator(Arc::new(core))
    }

    #[inline]
    pub fn memory_usage(&self) -> usize {
        self.0.mem_usage.load(Ordering::Relaxed)
    }

    #[inline]
    fn is_swapped(&self, ptr: NonNull<u8>, exhaustive_check: bool) -> bool {
        // Ordering: `maybe_swapped` must be read after the pointer is available.
        std::sync::atomic::fence(Ordering::Acquire);
        self.0.maybe_swapped.load(Ordering::Relaxed)
            && (!exhaustive_check || self.0.pages.lock().iter().any(|page| page.contains(ptr)))
    }

    #[inline]
    fn allocate_swapped(&self, layout: Layout) -> Result<NonNull<[u8]>, AllocError> {
        let mut pages = self.0.pages.lock();
        match pages.last_mut().and_then(|p| p.allocate(layout)) {
            None => {
                self.0.maybe_swapped.store(true, Ordering::Relaxed);
                // Ordering: `maybe_swapped` must be set before the page is created.
                std::sync::atomic::fence(Ordering::Release);
                pages.push(
                    Page::new(
                        &self.0.path,
                        self.0.page_seq.fetch_add(1, Ordering::Relaxed),
                        std::cmp::max(DEFAULT_PAGE_SIZE, layout.size()),
                    )
                    .ok_or(AllocError)?,
                );
                pages.last_mut().unwrap().allocate(layout).ok_or(AllocError)
            }
            Some(r) => Ok(r),
        }
    }
}

impl SwappyAllocator<Global> {
    pub fn new(path: &Path, budget: usize) -> SwappyAllocator<Global> {
        Self::new_over(path, budget, Global)
    }
}

unsafe impl<A: Allocator + Send + Sync> Allocator for SwappyAllocator<A> {
    #[inline]
    fn allocate(&self, layout: Layout) -> Result<NonNull<[u8]>, AllocError> {
        // Always use mem_allocator to allocate empty pointer.
        if layout.size() > 0
            && self.0.mem_usage.fetch_add(layout.size(), Ordering::Relaxed) + layout.size()
                > self.0.budget
        {
            let swap_r = self.allocate_swapped(layout);
            if swap_r.is_ok() {
                self.0.mem_usage.fetch_sub(layout.size(), Ordering::Relaxed);
                return swap_r;
            }
        }
        self.0.mem_allocator.allocate(layout).map_err(|e| {
            self.0.mem_usage.fetch_sub(layout.size(), Ordering::Relaxed);
            e
        })
    }

    #[inline]
    unsafe fn deallocate(&self, ptr: NonNull<u8>, layout: Layout) {
        if self.is_swapped(ptr, false) {
            let mut pages = self.0.pages.lock();
            // Find the page it belongs to, then deallocate itself.
            for i in 0..pages.len() {
                if pages[i].contains(ptr) {
                    if pages[i].deallocate(ptr) {
                        let page = pages.remove(i);
                        page.release(&self.0.path);
                    }
                    if pages.is_empty() {
                        self.0.maybe_swapped.store(false, Ordering::Relaxed);
                    }
                    return;
                }
            }
        }
        self.0.mem_usage.fetch_sub(layout.size(), Ordering::Relaxed);
        self.0.mem_allocator.deallocate(ptr, layout)
    }

    #[inline]
    fn allocate_zeroed(&self, layout: Layout) -> Result<NonNull<[u8]>, AllocError> {
        let ptr = self.allocate(layout)?;
        unsafe { ptr.as_non_null_ptr().as_ptr().write_bytes(0, ptr.len()) }
        Ok(ptr)
    }

    #[inline]
    unsafe fn grow(
        &self,
        ptr: NonNull<u8>,
        old_layout: Layout,
        new_layout: Layout,
    ) -> Result<NonNull<[u8]>, AllocError> {
        let diff = new_layout.size() - old_layout.size();
        let mem_usage = self.0.mem_usage.fetch_add(diff, Ordering::Relaxed) + diff;
        if mem_usage > self.0.budget || self.is_swapped(ptr, false) {
            self.0.mem_usage.fetch_sub(diff, Ordering::Relaxed);
            // Copied from std's blanket implementation //
            debug_assert!(
                new_layout.size() >= old_layout.size(),
                "`new_layout.size()` must be greater than or equal to `old_layout.size()`"
            );

            let new_ptr = self.allocate(new_layout)?;

            // SAFETY: because `new_layout.size()` must be greater than or equal to
            // `old_layout.size()`, both the old and new memory allocation are valid for
            // reads and writes for `old_layout.size()` bytes. Also, because the
            // old allocation wasn't yet deallocated, it cannot overlap
            // `new_ptr`. Thus, the call to `copy_nonoverlapping` is
            // safe. The safety contract for `dealloc` must be upheld by the caller.
            #[allow(unused_unsafe)]
            unsafe {
                ptr::copy_nonoverlapping(ptr.as_ptr(), new_ptr.as_mut_ptr(), old_layout.size());
                self.deallocate(ptr, old_layout);
            }

            Ok(new_ptr)
        } else {
            self.0
                .mem_allocator
                .grow(ptr, old_layout, new_layout)
                .map_err(|e| {
                    self.0.mem_usage.fetch_sub(diff, Ordering::Relaxed);
                    e
                })
        }
    }

    #[inline]
    unsafe fn grow_zeroed(
        &self,
        ptr: NonNull<u8>,
        old_layout: Layout,
        new_layout: Layout,
    ) -> Result<NonNull<[u8]>, AllocError> {
        let ptr = self.grow(ptr, old_layout, new_layout)?;
        ptr.as_non_null_ptr().as_ptr().write_bytes(0, ptr.len());
        Ok(ptr)
    }

    #[inline]
    unsafe fn shrink(
        &self,
        ptr: NonNull<u8>,
        old_layout: Layout,
        new_layout: Layout,
    ) -> Result<NonNull<[u8]>, AllocError> {
        if self.is_swapped(ptr, true) {
            // This is a swapped page.
            if self.0.mem_usage.load(Ordering::Relaxed) + new_layout.size() <= self.0.budget {
                // It's probably okay to reallocate to memory.
                // Copied from std's blanket implementation //
                debug_assert!(
                    new_layout.size() <= old_layout.size(),
                    "`new_layout.size()` must be smaller than or equal to `old_layout.size()`"
                );

                let new_ptr = self.allocate(new_layout)?;

                // SAFETY: because `new_layout.size()` must be lower than or equal to
                // `old_layout.size()`, both the old and new memory allocation are valid for
                // reads and writes for `new_layout.size()` bytes. Also, because the
                // old allocation wasn't yet deallocated, it cannot overlap
                // `new_ptr`. Thus, the call to `copy_nonoverlapping` is
                // safe. The safety contract for `dealloc` must be upheld by the caller.
                #[allow(unused_unsafe)]
                unsafe {
                    ptr::copy_nonoverlapping(ptr.as_ptr(), new_ptr.as_mut_ptr(), new_layout.size());
                    self.deallocate(ptr, old_layout);
                }

                Ok(new_ptr)
            } else {
                // The new layout should still be mapped to disk. Reuse old pointer.
                Ok(NonNull::slice_from_raw_parts(
                    NonNull::new_unchecked(ptr.as_ptr()),
                    new_layout.size(),
                ))
            }
        } else {
            self.0
                .mem_allocator
                .shrink(ptr, old_layout, new_layout)
                .map(|p| {
                    self.0
                        .mem_usage
                        .fetch_sub(old_layout.size() - new_layout.size(), Ordering::Relaxed);
                    p
                })
        }
    }
}

/// A page of memory that is backed by an owned file.
struct Page {
    seq: u32,
    _f: File,
    mmap: MmapMut,
    /// The start offset of bytes that are free to use.
    tail: usize,
    /// Number of active pointers to this page.
    ref_counter: usize,
}

impl Page {
    fn new(root: &Path, seq: u32, size: usize) -> Option<Page> {
        fail::fail_point!("swappy::page::new_failure", |_| None);
        if !root.exists() {
            // Create directory only when it's needed.
            std::fs::create_dir_all(root)
                .map_err(|e| error!("Failed to create swap directory: {e}."))
                .ok()?;
        }
        let path = root.join(Self::page_file_name(seq));
        let f = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(true)
            .open(path)
            .map_err(|e| error!("Failed to open swap file: {e}"))
            .ok()?;
        f.set_len(size as u64)
            .map_err(|e| error!("Failed to extend swap file: {e}"))
            .ok()?;
        let mmap = unsafe {
            MmapMut::map_mut(&f)
                .map_err(|e| error!("Failed to mmap swap file: {e}"))
                .ok()?
        };
        SWAP_FILE_COUNT.inc();
        Some(Self {
            seq,
            _f: f,
            mmap,
            tail: 0,
            ref_counter: 0,
        })
    }

    #[inline]
    fn allocate(&mut self, layout: Layout) -> Option<NonNull<[u8]>> {
        unsafe {
            let offset = self
                .mmap
                .as_ptr()
                .add(self.tail)
                .align_offset(layout.align());
            if self.tail + offset + layout.size() > self.mmap.len() {
                None
            } else {
                let p = self.mmap.as_ptr().add(self.tail + offset);
                self.tail += offset + layout.size();
                self.ref_counter += 1;
                Some(NonNull::slice_from_raw_parts(
                    NonNull::new_unchecked(p as *mut u8),
                    layout.size(),
                ))
            }
        }
    }

    /// Returns whether the page can be retired.
    #[inline]
    fn deallocate(&mut self, _ptr: NonNull<u8>) -> bool {
        self.ref_counter -= 1;
        self.ref_counter == 0
    }

    /// Deletes this page and cleans up owned resources.
    #[inline]
    fn release(self, root: &Path) {
        debug_assert_eq!(self.ref_counter, 0);

        // Somehow in Windows, we have to drop the mmap file handle first, otherwise
        // the following file removal will return "Access Denied (OS Error 5)".
        // Not using `#[cfg(windows)]` here is because it might do no harm in other
        // operating systems - the mmap file handle is dropped anyhow.
        drop(self.mmap);

        let path = root.join(Self::page_file_name(self.seq));
        if let Err(e) = std::fs::remove_file(path) {
            warn!("Failed to delete swap file: {e}");
        }
        SWAP_FILE_COUNT.dec();
    }

    /// Returns whether the pointer is contained in this page.
    #[inline]
    fn contains(&self, ptr: NonNull<u8>) -> bool {
        unsafe {
            let start = self.mmap.as_ptr();
            let end = (self.mmap.as_ptr()).add(self.mmap.len());
            let ptr = ptr.as_ptr() as *const u8;
            ptr >= start && ptr < end
        }
    }

    #[inline]
    fn page_file_name(seq: u32) -> String {
        seq.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_util::catch_unwind_silent;

    #[derive(Default, Clone)]
    struct WrappedGlobal {
        err_mode: Arc<AtomicBool>,
        alloc: Arc<AtomicUsize>,
        dealloc: Arc<AtomicUsize>,
        grow: Arc<AtomicUsize>,
        shrink: Arc<AtomicUsize>,
    }
    impl WrappedGlobal {
        fn stats(&self) -> (usize, usize, usize, usize) {
            (
                self.alloc.load(Ordering::Relaxed),
                self.dealloc.load(Ordering::Relaxed),
                self.grow.load(Ordering::Relaxed),
                self.shrink.load(Ordering::Relaxed),
            )
        }
        fn set_err_mode(&self, e: bool) {
            self.err_mode.store(e, Ordering::Relaxed);
        }
    }
    unsafe impl Allocator for WrappedGlobal {
        fn allocate(&self, layout: Layout) -> Result<NonNull<[u8]>, AllocError> {
            self.alloc.fetch_add(1, Ordering::Relaxed);
            if self.err_mode.load(Ordering::Relaxed) {
                Err(AllocError)
            } else {
                std::alloc::Global.allocate(layout)
            }
        }
        unsafe fn deallocate(&self, ptr: NonNull<u8>, layout: Layout) {
            self.dealloc.fetch_add(1, Ordering::Relaxed);
            std::alloc::Global.deallocate(ptr, layout)
        }
        unsafe fn grow(
            &self,
            ptr: NonNull<u8>,
            old_layout: Layout,
            new_layout: Layout,
        ) -> Result<NonNull<[u8]>, AllocError> {
            self.grow.fetch_add(1, Ordering::Relaxed);
            if self.err_mode.load(Ordering::Relaxed) {
                Err(AllocError)
            } else {
                std::alloc::Global.grow(ptr, old_layout, new_layout)
            }
        }
        unsafe fn shrink(
            &self,
            ptr: NonNull<u8>,
            old_layout: Layout,
            new_layout: Layout,
        ) -> Result<NonNull<[u8]>, AllocError> {
            self.shrink.fetch_add(1, Ordering::Relaxed);
            if self.err_mode.load(Ordering::Relaxed) {
                Err(AllocError)
            } else {
                std::alloc::Global.shrink(ptr, old_layout, new_layout)
            }
        }
    }

    type TestAllocator = SwappyAllocator<WrappedGlobal>;

    /// Borrows some memory temporarily.
    struct BorrowMemory {
        allocator: TestAllocator,
        borrowed: usize,
    }

    impl Drop for BorrowMemory {
        fn drop(&mut self) {
            self.allocator
                .0
                .mem_usage
                .fetch_sub(self.borrowed, Ordering::Relaxed);
        }
    }

    impl TestAllocator {
        fn borrow_memory(&self, size: usize) -> BorrowMemory {
            let allocator = SwappyAllocator(self.0.clone());
            allocator.0.mem_usage.fetch_add(size, Ordering::Relaxed);
            BorrowMemory {
                allocator,
                borrowed: size,
            }
        }
    }

    fn file_count(p: &Path) -> usize {
        let mut files = 0;
        if let Ok(iter) = p.read_dir() {
            iter.for_each(|_| files += 1);
        }
        files
    }

    #[test]
    fn test_swappy_vec() {
        let dir = tempfile::Builder::new()
            .prefix("test_swappy_vec")
            .tempdir()
            .unwrap();

        let global = WrappedGlobal::default();
        let allocator = TestAllocator::new_over(dir.path(), 1024, global);
        let mut vec1: Vec<u8, _> = Vec::new_in(allocator.clone());
        assert_eq!(allocator.memory_usage(), 0);
        vec1.resize(1024, 0);
        assert_eq!(allocator.memory_usage(), 1024);
        // Small vec that uses swap.
        let mut vec2: Vec<u8, _> = Vec::new_in(allocator.clone());
        vec2.resize(16, 0);
        assert_eq!(allocator.memory_usage(), 1024);
        // Grow large vec to swap.
        vec1.resize(2048, 0);
        assert_eq!(allocator.memory_usage(), 0);
        // Shrink large vec to free up memory.
        vec1.truncate(4);
        vec1.shrink_to_fit();
        assert_eq!(allocator.memory_usage(), 4);
        // Grow small vec, should be in memory.
        vec2.resize(32, 0);
        assert_eq!(allocator.memory_usage(), 4 + 32);

        assert_eq!(file_count(dir.path()), 0);
    }

    #[test]
    fn test_page_refill() {
        let dir = tempfile::Builder::new()
            .prefix("test_page_refill")
            .tempdir()
            .unwrap();

        let global = WrappedGlobal::default();
        let allocator = TestAllocator::new_over(dir.path(), 0, global);

        let mut vec: Vec<u8, _> = Vec::new_in(allocator.clone());
        assert_eq!(allocator.memory_usage(), 0);
        vec.resize(DEFAULT_PAGE_SIZE, 0);
        assert_eq!(allocator.memory_usage(), 0);
        assert_eq!(file_count(dir.path()), 1);
        vec.resize(DEFAULT_PAGE_SIZE * 2, 0);
        assert_eq!(allocator.memory_usage(), 0);
        assert_eq!(file_count(dir.path()), 1);
        vec.resize(DEFAULT_PAGE_SIZE * 3, 0);
        assert_eq!(allocator.memory_usage(), 0);
        assert_eq!(file_count(dir.path()), 1);
        vec.clear();
        vec.shrink_to_fit();
        assert_eq!(allocator.memory_usage(), 0);
        assert_eq!(file_count(dir.path()), 0);
    }

    #[test]
    fn test_empty_pointer() {
        let dir = tempfile::Builder::new()
            .prefix("test_empty_pointer")
            .tempdir()
            .unwrap();
        let global = WrappedGlobal::default();
        let allocator = TestAllocator::new_over(dir.path(), 4, global.clone());
        let empty_p_1 = allocator
            .allocate(Layout::from_size_align(0, 1).unwrap())
            .unwrap();
        assert_eq!(allocator.memory_usage(), 0);
        assert_eq!(file_count(dir.path()), 0);
        assert_eq!(global.stats(), (1, 0, 0, 0));

        let borrow = allocator.borrow_memory(8);

        let empty_p_2 = allocator
            .allocate(Layout::from_size_align(0, 1).unwrap())
            .unwrap();
        assert_eq!(allocator.memory_usage(), 8);
        assert_eq!(file_count(dir.path()), 0);
        assert_eq!(global.stats(), (2, 0, 0, 0));
        unsafe {
            allocator.deallocate(
                NonNull::new_unchecked(empty_p_1.as_ptr().as_mut_ptr()),
                Layout::from_size_align(0, 1).unwrap(),
            );
            assert_eq!(allocator.memory_usage(), 8);
            assert_eq!(global.stats(), (2, 1, 0, 0));
            std::mem::drop(borrow);
            assert_eq!(allocator.memory_usage(), 0);
            allocator.deallocate(
                NonNull::new_unchecked(empty_p_2.as_ptr().as_mut_ptr()),
                Layout::from_size_align(0, 1).unwrap(),
            );
            assert_eq!(allocator.memory_usage(), 0);
            assert_eq!(global.stats(), (2, 2, 0, 0));
        }
    }

    #[test]
    fn test_shrink_reuse() {
        let dir = tempfile::Builder::new()
            .prefix("test_shrink_reuse")
            .tempdir()
            .unwrap();
        let global = WrappedGlobal::default();
        let allocator = TestAllocator::new_over(dir.path(), 16, global);
        let mut vec: Vec<u8, _> = Vec::new_in(allocator.clone());
        vec.resize(DEFAULT_PAGE_SIZE, 0);
        assert_eq!(file_count(dir.path()), 1);
        vec.resize(DEFAULT_PAGE_SIZE / 2, 0);
        // Didn't allocate new page.
        assert_eq!(file_count(dir.path()), 1);
        // Switch to memory.
        vec.resize(4, 0);
        vec.shrink_to_fit();
        assert_eq!(allocator.memory_usage(), 4);
        assert_eq!(file_count(dir.path()), 0);
        vec.clear();
        vec.shrink_to_fit();
        assert_eq!(allocator.memory_usage(), 0);
        assert_eq!(file_count(dir.path()), 0);
    }

    // Test that some grows are not routed to the underlying allocator.
    #[test]
    fn test_grow_regression() {
        let dir = tempfile::Builder::new()
            .prefix("test_grow_regression")
            .tempdir()
            .unwrap();
        let global = WrappedGlobal::default();
        let allocator = TestAllocator::new_over(dir.path(), 100, global.clone());
        let mut disk_vec: Vec<u8, _> = Vec::new_in(allocator.clone());
        assert_eq!(allocator.memory_usage(), 0);
        disk_vec.resize(400, 0);
        assert_eq!(global.stats(), (0, 0, 0, 0));
        assert_eq!(allocator.memory_usage(), 0);
        assert_eq!(global.stats(), (0, 0, 0, 0));
        let mut mem_vec: Vec<u8, _> = Vec::with_capacity_in(8, allocator.clone());
        assert_eq!(allocator.memory_usage(), 8);
        assert_eq!(global.stats(), (1, 0, 0, 0));
        // Grow calls <allocate and deallocate>.
        mem_vec.resize(16, 0);
        assert_eq!(allocator.memory_usage(), 16);
        assert_eq!(global.stats(), (2, 1, 0, 0));
        // Deallocate all pages, calls <allocate and deallocate> when memory use is low.
        disk_vec.truncate(1);
        disk_vec.shrink_to_fit();
        assert_eq!(allocator.memory_usage(), 16 + 1);
        assert_eq!(global.stats(), (3, 1, 0, 0));
        assert_eq!(file_count(dir.path()), 0);
        // Grow calls <grow> now.
        mem_vec.resize(32, 0);
        assert_eq!(allocator.memory_usage(), 32 + 1);
        assert_eq!(global.stats(), (3, 1, 1, 0));
    }

    // alloc_error_hook doesn't work well with asan.
    #[cfg(not(sanitize = "address"))]
    #[test]
    fn test_mem_allocator_failure() {
        let dir = tempfile::Builder::new()
            .prefix("test_mem_allocator_failure")
            .tempdir()
            .unwrap();
        let global = WrappedGlobal::default();
        let allocator = TestAllocator::new_over(dir.path(), usize::MAX, global.clone());
        // Replace std hook because it will abort.
        let std_hook = std::alloc::take_alloc_error_hook();
        std::alloc::set_alloc_error_hook(|_| {
            panic!("oom");
        });
        // allocate failure
        {
            let mut vec: Vec<u8, _> = Vec::new_in(allocator.clone());
            global.set_err_mode(true);
            assert!(catch_unwind_silent(|| {
                vec.resize(16, 0);
            })
            .is_err());
            assert_eq!(allocator.memory_usage(), 0);
            global.set_err_mode(false);
            vec.resize(16, 0);
            assert_eq!(allocator.memory_usage(), 16);
        }
        // grow failure
        {
            let mut vec: Vec<u8, _> = Vec::new_in(allocator.clone());
            vec.resize(16, 0);
            assert_eq!(allocator.memory_usage(), 16);
            global.set_err_mode(true);
            assert!(catch_unwind_silent(|| {
                vec.resize(32, 0);
            })
            .is_err());
            assert_eq!(allocator.memory_usage(), 16);
            global.set_err_mode(false);
            vec.resize(32, 0);
            assert_eq!(allocator.memory_usage(), 32);
        }
        // shrink failure
        {
            let mut vec: Vec<u8, _> = Vec::new_in(allocator.clone());
            vec.resize(32, 0);
            assert_eq!(allocator.memory_usage(), 32);
            global.set_err_mode(true);
            vec.resize(16, 0);
            assert!(catch_unwind_silent(|| {
                vec.shrink_to_fit();
            })
            .is_err());
            assert_eq!(allocator.memory_usage(), 32);
            global.set_err_mode(false);
            vec.shrink_to_fit();
            assert_eq!(allocator.memory_usage(), 16);
        }
        std::alloc::set_alloc_error_hook(std_hook);
    }

    // Mashup of tests from std::alloc.
    #[test]
    fn test_swappy_vec_deque() {
        type VecDeque<T> = std::collections::VecDeque<T, TestAllocator>;

        fn collect<T, A>(iter: T, a: TestAllocator) -> VecDeque<A>
        where
            T: std::iter::IntoIterator<Item = A>,
        {
            let mut vec = VecDeque::new_in(a);
            for i in iter {
                vec.push_back(i);
            }
            vec
        }

        fn collect_v<T, A>(iter: T, a: TestAllocator) -> Vec<A, TestAllocator>
        where
            T: std::iter::IntoIterator<Item = A>,
        {
            let mut vec = Vec::new_in(a);
            for i in iter {
                vec.push(i);
            }
            vec
        }

        let dir = tempfile::Builder::new()
            .prefix("test_swappy_vec_deque")
            .tempdir()
            .unwrap();
        let global = WrappedGlobal::default();
        let allocator = TestAllocator::new_over(dir.path(), 0, global);

        {
            // test_with_capacity_non_power_two
            let mut d3 = VecDeque::with_capacity_in(3, allocator.clone());
            d3.push_back(1);

            // X = None, | = lo
            // [|1, X, X]
            assert_eq!(d3.pop_front(), Some(1));
            // [X, |X, X]
            assert_eq!(d3.front(), None);

            // [X, |3, X]
            d3.push_back(3);
            // [X, |3, 6]
            d3.push_back(6);
            // [X, X, |6]
            assert_eq!(d3.pop_front(), Some(3));

            // Pushing the lo past half way point to trigger
            // the 'B' scenario for growth
            // [9, X, |6]
            d3.push_back(9);
            // [9, 12, |6]
            d3.push_back(12);

            d3.push_back(15);
            // There used to be a bug here about how the
            // VecDeque made growth assumptions about the
            // underlying Vec which didn't hold and lead
            // to corruption.
            // (Vec grows to next power of two)
            // good- [9, 12, 15, X, X, X, X, |6]
            // bug-  [15, 12, X, X, X, |6, X, X]
            assert_eq!(d3.pop_front(), Some(6));

            // Which leads us to the following state which
            // would be a failure case.
            // bug-  [15, 12, X, X, X, X, |X, X]
            assert_eq!(d3.front(), Some(&9));
        }
        {
            // test_into_iter
            // Empty iter
            {
                let d: VecDeque<i32> = VecDeque::new_in(allocator.clone());
                let mut iter = d.into_iter();

                assert_eq!(iter.size_hint(), (0, Some(0)));
                assert_eq!(iter.next(), None);
                assert_eq!(iter.size_hint(), (0, Some(0)));
            }

            // simple iter
            {
                let mut d = VecDeque::new_in(allocator.clone());
                for i in 0..5 {
                    d.push_back(i);
                }

                let b = vec![0, 1, 2, 3, 4];
                assert_eq!(d.into_iter().collect::<Vec<_>>(), b);
            }

            // wrapped iter
            {
                let mut d = VecDeque::new_in(allocator.clone());
                for i in 0..5 {
                    d.push_back(i);
                }
                for i in 6..9 {
                    d.push_front(i);
                }

                let b = vec![8, 7, 6, 0, 1, 2, 3, 4];
                assert_eq!(d.into_iter().collect::<Vec<_>>(), b);
            }

            // partially used
            {
                let mut d = VecDeque::new_in(allocator.clone());
                for i in 0..5 {
                    d.push_back(i);
                }
                for i in 6..9 {
                    d.push_front(i);
                }

                let mut it = d.into_iter();
                assert_eq!(it.size_hint(), (8, Some(8)));
                assert_eq!(it.next(), Some(8));
                assert_eq!(it.size_hint(), (7, Some(7)));
                assert_eq!(it.next_back(), Some(4));
                assert_eq!(it.size_hint(), (6, Some(6)));
                assert_eq!(it.next(), Some(7));
                assert_eq!(it.size_hint(), (5, Some(5)));
            }
        }
        {
            // test_eq_after_rotation
            // test that two deques are equal even if elements are laid out differently
            let len = 28;
            let mut ring: VecDeque<i32> = collect(0..len, allocator.clone());
            let mut shifted = ring.clone();
            for _ in 0..10 {
                // shift values 1 step to the right by pop, sub one, push
                ring.pop_front();
                for elt in &mut ring {
                    *elt -= 1;
                }
                ring.push_back(len - 1);
            }

            // try every shift
            for _ in 0..shifted.capacity() {
                shifted.pop_front();
                for elt in &mut shifted {
                    *elt -= 1;
                }
                shifted.push_back(len - 1);
                assert_eq!(shifted, ring);
                assert_eq!(ring, shifted);
            }
        }
        {
            // test_drop_with_pop
            static mut DROPS: i32 = 0;
            struct Elem;
            impl Drop for Elem {
                fn drop(&mut self) {
                    unsafe {
                        DROPS += 1;
                    }
                }
            }

            let mut ring = VecDeque::new_in(allocator.clone());
            ring.push_back(Elem);
            ring.push_front(Elem);
            ring.push_back(Elem);
            ring.push_front(Elem);

            drop(ring.pop_back());
            drop(ring.pop_front());
            assert_eq!(unsafe { DROPS }, 2);

            drop(ring);
            assert_eq!(unsafe { DROPS }, 4);
        }
        {
            // test_reserve_grow
            // test growth path A
            // [T o o H] -> [T o o H . . . . ]
            let mut ring = VecDeque::with_capacity_in(4, allocator.clone());
            for i in 0..3 {
                ring.push_back(i);
            }
            ring.reserve(7);
            for i in 0..3 {
                assert_eq!(ring.pop_front(), Some(i));
            }

            // test growth path B
            // [H T o o] -> [. T o o H . . . ]
            let mut ring = VecDeque::with_capacity_in(4, allocator.clone());
            for i in 0..1 {
                ring.push_back(i);
                assert_eq!(ring.pop_front(), Some(i));
            }
            for i in 0..3 {
                ring.push_back(i);
            }
            ring.reserve(7);
            for i in 0..3 {
                assert_eq!(ring.pop_front(), Some(i));
            }

            // test growth path C
            // [o o H T] -> [o o H . . . . T ]
            let mut ring = VecDeque::with_capacity_in(4, allocator.clone());
            for i in 0..3 {
                ring.push_back(i);
                assert_eq!(ring.pop_front(), Some(i));
            }
            for i in 0..3 {
                ring.push_back(i);
            }
            ring.reserve(7);
            for i in 0..3 {
                assert_eq!(ring.pop_front(), Some(i));
            }
        }
        {
            // test_append_permutations
            fn construct_vec_deque(
                push_back: usize,
                pop_back: usize,
                push_front: usize,
                pop_front: usize,
                allocator: TestAllocator,
            ) -> VecDeque<usize> {
                let mut out = VecDeque::new_in(allocator);
                for a in 0..push_back {
                    out.push_back(a);
                }
                for b in 0..push_front {
                    out.push_front(push_back + b);
                }
                for _ in 0..pop_back {
                    out.pop_back();
                }
                for _ in 0..pop_front {
                    out.pop_front();
                }
                out
            }

            // Miri is too slow
            let max = if cfg!(miri) { 3 } else { 5 };

            // Many different permutations of both the `VecDeque` getting appended to
            // and the one getting appended are generated to check `append`.
            // This ensures all 6 code paths of `append` are tested.
            for src_push_back in 0..max {
                for src_push_front in 0..max {
                    // doesn't pop more values than are pushed
                    for src_pop_back in 0..(src_push_back + src_push_front) {
                        for src_pop_front in 0..(src_push_back + src_push_front - src_pop_back) {
                            let src = construct_vec_deque(
                                src_push_back,
                                src_pop_back,
                                src_push_front,
                                src_pop_front,
                                allocator.clone(),
                            );

                            for dst_push_back in 0..max {
                                for dst_push_front in 0..max {
                                    for dst_pop_back in 0..(dst_push_back + dst_push_front) {
                                        for dst_pop_front in
                                            0..(dst_push_back + dst_push_front - dst_pop_back)
                                        {
                                            let mut dst = construct_vec_deque(
                                                dst_push_back,
                                                dst_pop_back,
                                                dst_push_front,
                                                dst_pop_front,
                                                allocator.clone(),
                                            );
                                            let mut src = src.clone();

                                            // Assert that appending `src` to `dst` gives the same
                                            // order
                                            // of values as iterating over both in sequence.
                                            let correct = collect_v(
                                                dst.iter().chain(src.iter()).cloned(),
                                                allocator.clone(),
                                            );
                                            dst.append(&mut src);
                                            assert_eq!(dst, correct);
                                            assert!(src.is_empty());
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        {
            // test_append_double_drop
            struct DropCounter<'a> {
                count: &'a mut u32,
            }

            impl Drop for DropCounter<'_> {
                fn drop(&mut self) {
                    *self.count += 1;
                }
            }
            let (mut count_a, mut count_b) = (0, 0);
            {
                let mut a = VecDeque::new_in(allocator.clone());
                let mut b = VecDeque::new_in(allocator.clone());
                a.push_back(DropCounter {
                    count: &mut count_a,
                });
                b.push_back(DropCounter {
                    count: &mut count_b,
                });

                a.append(&mut b);
            }
            assert_eq!(count_a, 1);
            assert_eq!(count_b, 1);
        }
        {
            // test_extend_ref
            let mut v = VecDeque::new_in(allocator.clone());
            v.push_back(1);
            v.extend(&[2, 3, 4]);

            assert_eq!(v.len(), 4);
            assert_eq!(v[0], 1);
            assert_eq!(v[1], 2);
            assert_eq!(v[2], 3);
            assert_eq!(v[3], 4);

            let mut w = VecDeque::new_in(allocator.clone());
            w.push_back(5);
            w.push_back(6);
            v.extend(&w);

            assert_eq!(v.len(), 6);
            assert_eq!(v[0], 1);
            assert_eq!(v[1], 2);
            assert_eq!(v[2], 3);
            assert_eq!(v[3], 4);
            assert_eq!(v[4], 5);
            assert_eq!(v[5], 6);
        }
        {
            // test_rotate_left_random
            let shifts = [
                6, 1, 0, 11, 12, 1, 11, 7, 9, 3, 6, 1, 4, 0, 5, 1, 3, 1, 12, 8, 3, 1, 11, 11, 9, 4,
                12, 3, 12, 9, 11, 1, 7, 9, 7, 2,
            ];
            let n = 12;
            let mut v: VecDeque<_> = collect(0..n, allocator.clone());
            let mut total_shift = 0;
            for shift in shifts.iter().cloned() {
                v.rotate_left(shift);
                total_shift += shift;
                #[allow(clippy::needless_range_loop)]
                for i in 0..n {
                    assert_eq!(v[i], (i + total_shift) % n);
                }
            }
        }
        {
            // test_drain_leak
            static mut DROPS: i32 = 0;

            #[derive(Debug, PartialEq, Eq)]
            struct D(u32, bool);

            impl Drop for D {
                fn drop(&mut self) {
                    unsafe {
                        DROPS += 1;
                    }

                    if self.1 {
                        panic!("panic in `drop`");
                    }
                }
            }

            let mut v = VecDeque::new_in(allocator.clone());
            v.push_back(D(4, false));
            v.push_back(D(5, false));
            v.push_back(D(6, false));
            v.push_front(D(3, false));
            v.push_front(D(2, true));
            v.push_front(D(1, false));
            v.push_front(D(0, false));

            assert!(catch_unwind_silent(|| {
                v.drain(1..=4);
            })
            .is_err());

            assert_eq!(unsafe { DROPS }, 4);
            assert_eq!(v.len(), 3);
            drop(v);
            assert_eq!(unsafe { DROPS }, 7);
        }
        {
            // test_zero_sized_push
            const N: usize = 8;

            // Zero sized type
            struct Zst;

            // Test that for all possible sequences of push_front / push_back,
            // we end up with a deque of the correct size

            for len in 0..N {
                let mut tester = VecDeque::with_capacity_in(len, allocator.clone());
                assert_eq!(tester.len(), 0);
                assert!(tester.capacity() >= len);
                for case in 0..(1 << len) {
                    assert_eq!(tester.len(), 0);
                    for bit in 0..len {
                        if case & (1 << bit) != 0 {
                            tester.push_front(Zst);
                        } else {
                            tester.push_back(Zst);
                        }
                    }
                    assert_eq!(tester.len(), len);
                    #[allow(clippy::iter_count)]
                    let iter_len = tester.iter().count();
                    assert_eq!(iter_len, len);
                    tester.clear();
                }
            }
        }
        {
            // issue-58952
            let c = 2;
            let bv = [2];
            let b = bv.iter().filter(|a| **a == c);

            let _a = collect(
                vec![1, 2, 3]
                    .into_iter()
                    .filter(|a| b.clone().any(|b| *b == *a))
                    .filter(|a| b.clone().any(|b| *b == *a))
                    .filter(|a| b.clone().any(|b| *b == *a))
                    .filter(|a| b.clone().any(|b| *b == *a))
                    .filter(|a| b.clone().any(|b| *b == *a))
                    .filter(|a| b.clone().any(|b| *b == *a))
                    .filter(|a| b.clone().any(|b| *b == *a))
                    .filter(|a| b.clone().any(|b| *b == *a))
                    .filter(|a| b.clone().any(|b| *b == *a))
                    .filter(|a| b.clone().any(|b| *b == *a))
                    .filter(|a| b.clone().any(|b| *b == *a))
                    .filter(|a| b.clone().any(|b| *b == *a))
                    .filter(|a| b.clone().any(|b| *b == *a))
                    .filter(|a| b.clone().any(|b| *b == *a)),
                allocator.clone(),
            );
        }
        {
            // issue-54477
            let mut vecdeque_13 = collect(vec![], allocator.clone());
            let mut vecdeque_29 = collect(vec![0], allocator.clone());
            vecdeque_29.insert(0, 30);
            vecdeque_29.insert(1, 31);
            vecdeque_29.insert(2, 32);
            vecdeque_29.insert(3, 33);
            vecdeque_29.insert(4, 34);
            vecdeque_29.insert(5, 35);

            vecdeque_13.append(&mut vecdeque_29);

            assert_eq!(
                vecdeque_13,
                collect(vec![30, 31, 32, 33, 34, 35, 0], allocator,)
            );
        }

        assert_eq!(file_count(dir.path()), 0);
    }

    fn bench_allocator<A: Allocator>(a: &A) {
        unsafe {
            let ptr = a
                .allocate_zeroed(Layout::from_size_align(8, 8).unwrap())
                .unwrap();
            let ptr = a
                .grow_zeroed(
                    NonNull::new_unchecked(ptr.as_ptr().as_mut_ptr()),
                    Layout::from_size_align(8, 8).unwrap(),
                    Layout::from_size_align(16, 8).unwrap(),
                )
                .unwrap();
            let ptr = a
                .grow_zeroed(
                    NonNull::new_unchecked(ptr.as_ptr().as_mut_ptr()),
                    Layout::from_size_align(16, 8).unwrap(),
                    Layout::from_size_align(32, 8).unwrap(),
                )
                .unwrap();
            let ptr = a
                .grow_zeroed(
                    NonNull::new_unchecked(ptr.as_ptr().as_mut_ptr()),
                    Layout::from_size_align(32, 8).unwrap(),
                    Layout::from_size_align(64, 8).unwrap(),
                )
                .unwrap();
            let ptr = a
                .grow_zeroed(
                    NonNull::new_unchecked(ptr.as_ptr().as_mut_ptr()),
                    Layout::from_size_align(64, 8).unwrap(),
                    Layout::from_size_align(128, 8).unwrap(),
                )
                .unwrap();
            let ptr = a
                .shrink(
                    NonNull::new_unchecked(ptr.as_ptr().as_mut_ptr()),
                    Layout::from_size_align(128, 8).unwrap(),
                    Layout::from_size_align(8, 8).unwrap(),
                )
                .unwrap();
            a.deallocate(
                NonNull::new_unchecked(ptr.as_ptr().as_mut_ptr()),
                Layout::from_size_align(8, 8).unwrap(),
            );
        }
    }

    #[bench]
    fn bench_allocator_std_global(b: &mut test::Bencher) {
        b.iter(move || {
            bench_allocator(&std::alloc::Global);
        });
    }

    #[bench]
    fn bench_allocator_fast_path(b: &mut test::Bencher) {
        let dir = tempfile::Builder::new()
            .prefix("bench_allocator_fast_path")
            .tempdir()
            .unwrap();
        let allocator = SwappyAllocator::new(dir.path(), usize::MAX);
        b.iter(move || {
            bench_allocator(&allocator);
        });
    }

    #[bench]
    fn bench_allocator_slow_path(b: &mut test::Bencher) {
        let dir = tempfile::Builder::new()
            .prefix("bench_allocator_slow_path")
            .tempdir()
            .unwrap();
        let allocator = SwappyAllocator::new(dir.path(), 0);
        b.iter(move || {
            bench_allocator(&allocator);
        });
    }
}
