// The storage engine and the modules it stands on are the kura-core crate (crates/kura-core), so its
// build and tests run in parallel with this crate's. Importing them under their old names keeps
// every `crate::store::...` path in this crate working.
use kura_core::{
    action_cache_removals, analytics_outbox, artifact, backpressure, bandwidth, certificate_trust,
    config, connectivity, constants, control_plane_http, enrollment, failpoints, file_cache, io,
    memory, metrics, multipart, node_location, peer_topology, request_observability, segment,
    store, utils,
};

mod accelerated_file_serving;
mod analytics;
mod analytics_forwarder;
mod app;
mod auth;
mod backfill;
mod bazel_test_artifacts;
mod handover;
mod http;
mod mesh_heartbeat;
mod migration;
mod peer_tls;
mod reapi;
mod registration;
mod replication;
mod runtime;
mod serving_authority;
mod startup;
mod state;
mod sync;
mod telemetry;
mod usage;

#[cfg(test)]
mod peer_topology_tests;
#[cfg(test)]
mod test_support;

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
