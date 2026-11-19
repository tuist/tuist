//! The running Kura node below its REAPI service: the shared `AppState`, the HTTP API, replication
//! (sync, backfill, handover, migration), authentication, analytics, usage, telemetry and the
//! serving authority. The `kura-reapi` crate builds the REAPI/gRPC services on top of it and the
//! `kura` crate wires both into the process.
//!
//! It is a separate crate so Bazel compiles the REAPI services and their tests in parallel with
//! this crate's tests. `AppState` therefore holds the REAPI snapshot cache only as an opaque slot
//! (`AppState::snapshot_cache`) that `kura-reapi` fills.
//!
//! Test helpers and test-only behaviour are compiled with `cfg(test)` for this crate's own tests
//! and with the `test-support` feature for the tests of the crates above it.

// The storage engine and the modules it stands on are the kura-core crate. Importing them under
// their old names keeps every `crate::store::...` path in this crate working.
use kura_core::{
    VERSION, analytics_outbox, artifact, backpressure, bandwidth, certificate_trust, config,
    constants, control_plane_http, failpoints, file_cache, io, memory, metrics, multipart,
    node_location, peer_topology, request_observability, segment, store, utils,
};

pub mod analytics;
pub mod analytics_forwarder;
pub mod auth;
pub mod backfill;
pub mod bazel_test_artifacts;
pub mod handover;
pub mod http;
pub mod migration;
pub mod peer_tls;
pub mod replication;
pub mod runtime;
pub mod serving_authority;
pub mod state;
pub mod sync;
pub mod telemetry;
pub mod usage;

#[cfg(test)]
mod peer_topology_tests;
#[cfg(any(test, feature = "test-support"))]
pub mod test_support;
