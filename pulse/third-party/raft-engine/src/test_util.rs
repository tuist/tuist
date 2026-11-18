// Copyright (c) 2017-present, PingCAP, Inc. Licensed under Apache-2.0.

use std::panic::{self, AssertUnwindSafe};

use raft::eraftpb::Entry;

use crate::{
    memtable::EntryIndex,
    pipe_log::{FileBlockHandle, FileId},
};

pub fn generate_entries(begin_index: u64, end_index: u64, data: Option<&[u8]>) -> Vec<Entry> {
    let mut v = vec![Entry::new(); (end_index - begin_index) as usize];
    let mut index = begin_index;
    for e in v.iter_mut() {
        e.set_index(index);
        if let Some(data) = data {
            e.set_data(data.to_vec().into())
        }
        index += 1;
    }
    v
}

pub fn generate_entry_indexes(begin_idx: u64, end_idx: u64, file_id: FileId) -> Vec<EntryIndex> {
    generate_entry_indexes_opt(begin_idx, end_idx, Some(file_id))
}

pub fn generate_entry_indexes_opt(
    begin_idx: u64,
    end_idx: u64,
    file_id: Option<FileId>,
) -> Vec<EntryIndex> {
    assert!(end_idx >= begin_idx);
    let mut ents_idx = vec![];
    for idx in begin_idx..end_idx {
        let ent_idx = EntryIndex {
            index: idx,
            entries: file_id.map(|id| FileBlockHandle {
                id,
                offset: 0,
                len: 0,
            }),
            entry_len: 1,
            ..Default::default()
        };

        ents_idx.push(ent_idx);
    }
    ents_idx
}

/// Catch panic while suppressing default panic hook.
pub fn catch_unwind_silent<F, R>(f: F) -> std::thread::Result<R>
where
    F: FnOnce() -> R,
{
    let prev_hook = panic::take_hook();
    panic::set_hook(Box::new(|_| {}));
    let result = panic::catch_unwind(AssertUnwindSafe(f));
    panic::set_hook(prev_hook);
    result
}

pub struct PanicGuard {
    prev_hook: *mut (dyn Fn(&panic::PanicInfo<'_>) + Sync + Send + 'static),
}

struct PointerHolder<T: ?Sized>(*mut T);

unsafe impl<T: Send + ?Sized> Send for PointerHolder<T> {}
unsafe impl<T: Sync + ?Sized> Sync for PointerHolder<T> {}

impl PanicGuard {
    pub fn with_prompt(s: String) -> Self {
        let prev_hook = Box::into_raw(panic::take_hook());
        let sendable_prev_hook = PointerHolder(prev_hook);
        // FIXME: Use thread local hook.
        panic::set_hook(Box::new(move |info| {
            eprintln!("{s}");
            unsafe { (*sendable_prev_hook.0)(info) };
        }));
        PanicGuard { prev_hook }
    }
}

impl Drop for PanicGuard {
    fn drop(&mut self) {
        if !std::thread::panicking() {
            let _ = panic::take_hook();
            unsafe {
                panic::set_hook(Box::from_raw(self.prev_hook));
            }
        }
    }
}
