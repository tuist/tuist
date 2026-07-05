//! Per-machine broker daemon. See broker.rs for the architecture.
//!
//! Environment:
//! - TUIST_CAS_BROKER_SOCKET: unix socket path to listen on
//!   (default /tmp/tuist-cas-broker.sock)
//! - TUIST_CAS_REMOTE_GRPC_URL, TUIST_CAS_ACCOUNT, TUIST_CAS_PROJECT: REAPI
//!   endpoint (required)
//! - TUIST_CAS_UPSTREAM_PLUGIN: path to libToolchainCASPlugin.dylib
//! - TUIST_CAS_LOG: append stats/diagnostics

use std::os::unix::net::UnixListener;

use tuist_cas_plugin::broker::Broker;
use tuist_cas_plugin::reapi::{Remote, RemoteConfig};

fn main() {
    let socket_path = std::env::var("TUIST_CAS_BROKER_SOCKET")
        .unwrap_or_else(|_| "/tmp/tuist-cas-broker.sock".into());
    let Some(config) = RemoteConfig::from_env() else {
        eprintln!("TUIST_CAS_REMOTE_GRPC_URL is required");
        std::process::exit(2);
    };
    let upstream_plugin = std::env::var("TUIST_CAS_UPSTREAM_PLUGIN").unwrap_or_else(|_| {
        let developer_dir = std::env::var("DEVELOPER_DIR")
            .unwrap_or_else(|_| "/Applications/Xcode.app/Contents/Developer".into());
        format!("{developer_dir}/usr/lib/libToolchainCASPlugin.dylib")
    });

    let _ = std::fs::remove_file(&socket_path);
    let listener = match UnixListener::bind(&socket_path) {
        Ok(listener) => listener,
        Err(error) => {
            eprintln!("bind {socket_path}: {error}");
            std::process::exit(2);
        }
    };

    let broker = Broker::new(Remote::new(config), upstream_plugin);

    // Periodic sweep of orphaned publication records + stats heartbeat.
    std::thread::spawn(move || loop {
        std::thread::sleep(std::time::Duration::from_secs(10));
        broker.sweep();
        let stats = broker.stats_line();
        if !stats.is_empty() {
            tuist_cas_plugin::log_line(&format!("broker stats: {stats}"));
        }
    });

    eprintln!("tuist-cas-broker listening on {socket_path}");
    broker.serve(listener);
}
