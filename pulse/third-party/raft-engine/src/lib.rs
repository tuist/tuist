// Copyright (c) 2017-present, PingCAP, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// See the License for the specific language governing permissions and
// limitations under the License.

//! # Raft Engine

#![cfg_attr(feature = "nightly", feature(test))]
#![cfg_attr(feature = "swap", feature(allocator_api))]
#![cfg_attr(feature = "swap", feature(slice_ptr_get))]
// Though the new nightly rust stablized this feature, keep it anyway
// because some other project (like TiKV) is still using the old.
#![cfg_attr(feature = "swap", feature(nonnull_slice_from_raw_parts))]
#![cfg_attr(feature = "swap", feature(slice_ptr_len))]
#![cfg_attr(feature = "swap", feature(alloc_layout_extra))]
#![cfg_attr(all(test, feature = "swap"), feature(alloc_error_hook))]
#![cfg_attr(all(test, feature = "swap"), feature(cfg_sanitize))]

#[macro_use]
extern crate lazy_static;
extern crate scopeguard;
#[cfg(feature = "nightly")]
extern crate test;

macro_rules! box_err {
    ($e:expr) => ({
        use std::error::Error;
        let e: Box<dyn Error + Send + Sync> = format!("[{}:{}]: {}", file!(), line!(),  $e).into();
        e.into()
    });
    ($f:tt, $($arg:expr),+) => ({
        box_err!(format!($f, $($arg),+))
    });
}

mod codec;
mod config;
mod consistency;
mod engine;
mod errors;
mod event_listener;
mod file_pipe_log;
#[cfg(feature = "scripting")]
mod filter;
mod fork;
mod log_batch;
mod memtable;
mod metrics;
mod pipe_log;
mod purge;
#[cfg(feature = "swap")]
mod swappy_allocator;
#[cfg(test)]
mod test_util;
mod util;
mod write_barrier;

pub mod env;

pub use config::{Config, RecoveryMode};
pub use engine::Engine;
pub use errors::{Error, Result};
pub use log_batch::{Command, LogBatch, MessageExt};
pub use metrics::{get_perf_context, set_perf_context, take_perf_context, PerfContext};
pub use pipe_log::Version;
pub use util::ReadableSize;

#[cfg(feature = "internals")]
pub mod internals {
    //! A selective view of key components in Raft Engine. Exported under the
    //! `internals` feature only.
    pub use crate::event_listener::*;
    pub use crate::file_pipe_log::*;
    pub use crate::memtable::*;
    pub use crate::pipe_log::*;
    pub use crate::purge::*;
    #[cfg(feature = "swap")]
    pub use crate::swappy_allocator::*;
    pub use crate::write_barrier::*;
}

use std::sync::atomic::{AtomicUsize, Ordering};

#[derive(Default)]
pub struct GlobalStats {
    live_append_entries: AtomicUsize,
    rewrite_entries: AtomicUsize,
    deleted_rewrite_entries: AtomicUsize,
}

impl GlobalStats {
    #[inline]
    pub fn add(&self, queue: pipe_log::LogQueue, count: usize) {
        match queue {
            pipe_log::LogQueue::Append => {
                self.live_append_entries.fetch_add(count, Ordering::Relaxed);
            }
            pipe_log::LogQueue::Rewrite => {
                self.rewrite_entries.fetch_add(count, Ordering::Relaxed);
            }
        }
    }

    #[inline]
    pub fn delete(&self, queue: pipe_log::LogQueue, count: usize) {
        match queue {
            pipe_log::LogQueue::Append => {
                self.live_append_entries.fetch_sub(count, Ordering::Relaxed);
            }
            pipe_log::LogQueue::Rewrite => {
                self.deleted_rewrite_entries
                    .fetch_add(count, Ordering::Relaxed);
            }
        }
    }

    #[inline]
    pub fn rewrite_entries(&self) -> usize {
        self.rewrite_entries.load(Ordering::Relaxed)
    }

    #[inline]
    pub fn deleted_rewrite_entries(&self) -> usize {
        self.deleted_rewrite_entries.load(Ordering::Relaxed)
    }

    #[inline]
    pub fn reset_rewrite_counters(&self) {
        let dop = self.deleted_rewrite_entries.load(Ordering::Relaxed);
        self.deleted_rewrite_entries
            .fetch_sub(dop, Ordering::Relaxed);
        self.rewrite_entries.fetch_sub(dop, Ordering::Relaxed);
    }

    #[inline]
    pub fn live_entries(&self, queue: pipe_log::LogQueue) -> usize {
        match queue {
            pipe_log::LogQueue::Append => self.live_append_entries.load(Ordering::Relaxed),
            pipe_log::LogQueue::Rewrite => {
                let op = self.rewrite_entries.load(Ordering::Relaxed);
                let dop = self.deleted_rewrite_entries.load(Ordering::Relaxed);
                debug_assert!(op >= dop);
                op.saturating_sub(dop)
            }
        }
    }

    #[inline]
    pub fn flush_metrics(&self) {
        metrics::LOG_ENTRY_COUNT
            .rewrite
            .set(self.live_entries(pipe_log::LogQueue::Rewrite) as i64);
        metrics::LOG_ENTRY_COUNT
            .append
            .set(self.live_entries(pipe_log::LogQueue::Append) as i64);
    }
}

pub(crate) const INTERNAL_KEY_PREFIX: &[u8] = b"__";

#[inline]
#[cfg(test)]
pub(crate) fn make_internal_key(k: &[u8]) -> Vec<u8> {
    assert!(!k.is_empty());
    let mut v = INTERNAL_KEY_PREFIX.to_vec();
    v.extend_from_slice(k);
    v
}

#[cfg(not(test))]
pub(crate) fn make_internal_key(k: &[u8]) -> Vec<u8> {
    use log_batch::ATOMIC_GROUP_KEY;

    assert!(k == ATOMIC_GROUP_KEY);
    let mut v = INTERNAL_KEY_PREFIX.to_vec();
    v.extend_from_slice(k);
    v
}

/// We ensure internal keys are not visible to the user by:
/// (1) Writing internal keys will be rejected by `LogBatch::put`.
/// (2) Internal keys are filtered out during apply and replay of both queues.
/// This also makes sure future internal keys under the prefix won't become
/// visible after downgrading.
#[inline]
#[cfg(test)]
pub(crate) fn is_internal_key(s: &[u8], ext: Option<&[u8]>) -> bool {
    if let Some(ext) = ext {
        s.len() == INTERNAL_KEY_PREFIX.len() + ext.len()
            && s[..INTERNAL_KEY_PREFIX.len()] == *INTERNAL_KEY_PREFIX
            && s[INTERNAL_KEY_PREFIX.len()..] == *ext
    } else {
        s.len() > INTERNAL_KEY_PREFIX.len()
            && s[..INTERNAL_KEY_PREFIX.len()] == *INTERNAL_KEY_PREFIX
    }
}

#[inline]
#[cfg(not(test))]
pub(crate) fn is_internal_key(s: &[u8], ext: Option<&[u8]>) -> bool {
    use log_batch::ATOMIC_GROUP_KEY;

    if let Some(ext) = ext {
        s.len() == INTERNAL_KEY_PREFIX.len() + ext.len()
            && s[..INTERNAL_KEY_PREFIX.len()] == *INTERNAL_KEY_PREFIX
            && s[INTERNAL_KEY_PREFIX.len()..] == *ext
    } else {
        is_internal_key(s, Some(ATOMIC_GROUP_KEY))
    }
}

#[cfg(test)]
mod tests {
    use crate::log_batch::MessageExt;
    use raft::eraftpb::Entry;

    #[ctor::ctor]
    fn init() {
        env_logger::init();
    }

    impl MessageExt for Entry {
        type Entry = Entry;

        fn index(e: &Self::Entry) -> u64 {
            e.index
        }
    }

    #[test]
    fn test_internal_key() {
        let key = crate::make_internal_key(&[0]);
        assert!(crate::is_internal_key(&key, None));
        assert!(crate::is_internal_key(&key, Some(&[0])));
        assert!(!crate::is_internal_key(&key, Some(&[1])));
    }
}
