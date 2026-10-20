//! tuist_cargo_cache: a build cache for Rust projects.
//!
//! Compilations are cached as individual rustc actions in a content-addressed
//! store shared by every project and worktree on a machine, and optionally
//! shared further through a remote cache.
//!
//! This library target exists so the executable and integration tests can
//! share application code; it is not an embedding API. The supported
//! interfaces are the `tuist_cargo_cache` command line -- its subcommands and its versioned
//! JSON output -- and, for anything speaking to a remote cache,
//! `tuist-cargo-cache-protocol`. `tuist-cargo-cache-core` and `tuist-cargo-cache-rustc` are internals
//! too, and say so in their own descriptions.
//!
//! Nothing here carries a compatibility guarantee, and CI's public-API check
//! skips this package for that reason -- see `UNCHECKED_PACKAGES` in
//! `.github/workflows/ci.yml`. Types the CLI alone reads may gain fields in a
//! patch release. Do not restore the check to "protect" these items: it would
//! only force a major bump every time the CLI gains a setting.
//!
//! The modules below are `#[doc(hidden)]` for the same reason. They have to
//! stay `pub` for the binary and the integration tests, but a published crate
//! whose documentation advertises `store` and `session` invites exactly the
//! dependency the paragraph above rules out.

#[cfg(target_os = "linux")]
mod cgroup;
#[doc(hidden)]
pub mod cli;
#[doc(hidden)]
pub mod config;
#[doc(hidden)]
pub mod doctor;
pub(crate) mod events;
#[doc(hidden)]
pub mod explain;
#[doc(hidden)]
pub mod logging;
pub mod phase_timing;
#[doc(hidden)]
pub mod policy;
pub mod remote;
pub(crate) mod savings;
#[doc(hidden)]
pub mod session;
pub(crate) mod stats;
#[doc(hidden)]
pub mod store;
#[doc(hidden)]
pub mod target;
mod target_seed;
mod target_units;
#[doc(hidden)]
pub mod tui;
#[doc(hidden)]
pub mod util;

mod analyze;
mod ar;
mod build_script;
mod cc;
mod digest_ledger;
mod incremental;
mod linker;
mod managed_linker;
mod materialize;
mod out_dir;
mod pressure;
mod rustc;
mod rustdoc;
mod scheduler;
mod storage;
#[doc(hidden)]
pub mod supervision;
mod tuist_observer;
mod unit_graph;
mod workspace_state;
