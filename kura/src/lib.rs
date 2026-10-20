mod accelerated_file_serving;
mod action_cache_refs;
mod action_cache_removals;
mod analytics;
mod analytics_forwarder;
mod analytics_outbox;
mod app;
mod artifact;
mod auth;
mod backfill;
mod backpressure;
mod bandwidth;
mod bazel_test_artifacts;
mod config;
mod connectivity;
mod constants;
mod control_plane_http;
mod enrollment;
mod failpoints;
mod file_cache;
mod handover;
mod http;
mod io;
mod memory;
mod mesh_heartbeat;
mod metrics;
mod mmap;
mod multipart;
mod node_location;
mod peer_tls;
mod peer_topology;
mod reapi;
mod registration;
mod replication;
mod request_observability;
mod runtime;
mod segment;
mod serving_authority;
mod startup;
mod state;
mod store;
mod sync;
mod telemetry;
mod usage;
mod utils;

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
