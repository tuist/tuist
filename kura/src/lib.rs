mod accelerated_file_serving;
mod action_cache_refs;
mod analytics;
mod app;
mod artifact;
mod auth;
mod backfill;
mod backpressure;
mod bandwidth;
mod config;
mod constants;
mod enrollment;
mod failpoints;
mod file_cache;
mod http;
mod io;
mod memory;
mod mesh_heartbeat;
mod metrics;
mod mmap;
mod multipart;
mod node_location;
mod peer_tls;
mod reapi;
mod registration;
mod replication;
mod request_observability;
mod runtime;
mod segment;
mod state;
mod store;
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
