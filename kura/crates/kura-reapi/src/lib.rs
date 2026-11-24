//! Kura's REAPI services: the gRPC content-addressable storage, action cache, ByteStream, asset
//! and build-event services, with their admission control and the action-cache snapshot. It is a
//! separate crate from `kura-node`, whose state it serves, so Bazel compiles and tests it in
//! parallel with that crate's tests.

// The modules this crate stands on, under the names they had when it was the kura crate's `reapi`
// module, so every `crate::store::...` path in it keeps working.
use kura_core::{
    action_cache_removals, artifact, backpressure, certificate_trust, constants, file_cache, io,
    memory, metrics, store, utils,
};
#[cfg(test)]
use kura_core::{config, failpoints, segment};
use kura_node::{analytics, auth, bazel_test_artifacts, http, migration, serving_authority, state};
#[cfg(test)]
use kura_node::{peer_tls, test_support};

mod admission;
mod asset;
pub mod bep;
pub mod chunking;
mod protobuf_shape;
mod service;
mod snapshot;

pub use service::routes;
pub use snapshot::{SnapshotCache, SnapshotCacheExt};

#[cfg(test)]
mod auth_policy_tests;
