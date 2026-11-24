// The node is three crates below this one, so Bazel compiles and tests them as separate actions:
// kura-core (the storage engine), kura-node (state, HTTP, replication) and kura-reapi (the REAPI
// services). Importing their modules under their old names keeps every `crate::store::...` path
// in this crate working.
#[cfg(test)]
use kura_core::backpressure;
use kura_core::{
    artifact, bandwidth, certificate_trust, config, connectivity, constants, control_plane_http,
    enrollment, io, memory, metrics, node_location, request_observability, store, utils,
};
#[cfg(test)]
use kura_node::test_support;
use kura_node::{
    analytics, analytics_forwarder, auth, backfill, bazel_test_artifacts, handover, http, peer_tls,
    replication, runtime, serving_authority, state, sync, telemetry, usage,
};
use kura_reapi as reapi;

mod accelerated_file_serving;
mod app;
mod mesh_heartbeat;
mod registration;
mod startup;

pub use app::run;

pub const VERSION: &str = env!("CARGO_PKG_VERSION");

#[cfg(test)]
mod version_tests {
    use super::VERSION;

    #[test]
    fn build_version_is_configured() {
        assert_ne!(VERSION, "0.0.0");
    }
}
