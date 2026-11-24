//! Kura's storage engine and the modules it stands on: configuration, metrics, memory and I/O
//! control, segments, and the store itself. The `kura` crate builds the node on top of it.
//!
//! It is a separate crate so Bazel compiles and tests it in parallel with the much larger rest of
//! the node. Nothing here may depend on the node's HTTP, REAPI, replication or runtime state; where
//! the store needs the running node it goes through a trait the `kura` crate implements
//! (`startup::DrainSignal`, `bandwidth::PublicLoad`, `serving_authority::Publisher`).
//!
//! Test helpers and test-only behaviour are compiled with `cfg(test)` for this crate's own tests
//! and with the `test-support` feature for the `kura` crate's tests.

// These lints apply only to public APIs, which this crate's items became when it was split out of
// the kura crate, where they were crate-private. The kura crate is their only caller.
#![allow(clippy::result_unit_err, clippy::should_implement_trait)]

pub mod action_cache_refs;
pub mod action_cache_removals;
pub mod analytics_outbox;
pub mod artifact;
pub mod backpressure;
pub mod bandwidth;
pub mod certificate_trust;
pub mod commit_threads;
pub mod config;
pub mod connectivity;
pub mod constants;
pub mod control_plane_http;
pub mod enrollment;
pub mod failpoints;
pub mod file_cache;
pub mod io;
pub mod memory;
pub mod metrics;
pub mod mmap;
pub mod multipart;
pub mod node_location;
pub mod peer_topology;
pub mod request_observability;
pub mod runtime;
pub mod segment;
pub mod serving_authority;
pub mod startup;
pub mod store;
pub mod usage;
pub mod utils;

pub mod reapi {
    pub mod chunking;
}

pub mod sync {
    pub mod feed;
}

/// The kura release version, which this crate shares with the kura crate through the workspace.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
