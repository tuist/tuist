mod accelerated_file_serving;
mod analytics;
mod app;
mod artifact;
mod bandwidth;
mod config;
mod constants;
mod enrollment;
mod extension;
mod failpoints;
mod geoip;
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
