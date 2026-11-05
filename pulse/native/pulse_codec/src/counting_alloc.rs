// Global allocator that counts the bytes a NIF crate currently holds, so
// `Pulse.MemoryStats` can tell native heap use apart from allocator
// retention and BEAM memory. Each NIF crate keeps an identical copy (cross
// builds see only the crate directory), owns its own counter, and exports it
// through a `native_allocated_bytes` NIF.
//
// The counter is one relaxed atomic add per allocation. Freed memory goes
// back to the system allocator immediately; whether the allocator returns it
// to the operating system is a separate question that `native_trim` answers.

use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicIsize, Ordering};

pub struct CountingAlloc;

static ALLOCATED: AtomicIsize = AtomicIsize::new(0);

unsafe impl GlobalAlloc for CountingAlloc {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let ptr = System.alloc(layout);
        if !ptr.is_null() {
            ALLOCATED.fetch_add(layout.size() as isize, Ordering::Relaxed);
        }
        ptr
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        let ptr = System.alloc_zeroed(layout);
        if !ptr.is_null() {
            ALLOCATED.fetch_add(layout.size() as isize, Ordering::Relaxed);
        }
        ptr
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        System.dealloc(ptr, layout);
        ALLOCATED.fetch_sub(layout.size() as isize, Ordering::Relaxed);
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        let new = System.realloc(ptr, layout, new_size);
        if !new.is_null() {
            ALLOCATED.fetch_add(
                new_size as isize - layout.size() as isize,
                Ordering::Relaxed,
            );
        }
        new
    }
}

#[global_allocator]
static GLOBAL: CountingAlloc = CountingAlloc;

/// Bytes currently allocated through this crate's global allocator.
pub fn allocated() -> i64 {
    ALLOCATED.load(Ordering::Relaxed).max(0) as i64
}
