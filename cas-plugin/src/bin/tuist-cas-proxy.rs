//! Per-machine proxy daemon. See proxy.rs for the architecture.
//!
//! The proxy is not bound to a single project: it multiplexes REAPI clients
//! per `account/project` instance, which each connection declares (or which
//! the proxy recalls from the persisted registry for an Xcode ⌘B build).
//!
//! Environment:
//! - TUIST_CAS_PROXY_SOCKET: unix socket path to listen on
//!   (default /tmp/tuist-cas-proxy.sock)
//! - TUIST_CAS_REMOTE_GRPC_URL: REAPI endpoint (required)
//! - TUIST_CAS_TOKEN: initial bearer (set directly on CI). Absent on a dev
//!   machine: the proxy fetches one via the CLI (see TUIST_CAS_TUIST_BIN).
//! - TUIST_CAS_TUIST_BIN, TUIST_CAS_SERVER_URL: how to fetch/refresh the bearer
//!   by shelling out to the CLI; the CLI owns keychain + refresh.
//! - TUIST_CAS_PROXY_REGISTRY: path to persist the cas_path->instance map
//!   (default: alongside the socket)
//! - TUIST_CAS_UPSTREAM_PLUGIN: path to libToolchainCASPlugin.dylib
//! - TUIST_CAS_LOG: append stats/diagnostics

use std::os::unix::net::UnixListener;

use tuist_cas_plugin::proxy::Proxy;
use tuist_cas_plugin::token::TokenProvider;

// Token refresh cadence, in units of the 10s maintenance tick (~3 minutes):
// long-lived proxys stay ahead of expiry without shelling out every tick.
const TOKEN_REFRESH_TICKS: u64 = 18;

fn main() {
    let socket_path = std::env::var("TUIST_CAS_PROXY_SOCKET")
        .ok()
        .filter(|socket| !socket.is_empty())
        .unwrap_or_else(tuist_cas_plugin::default_proxy_socket);
    let Ok(grpc_url) = std::env::var("TUIST_CAS_REMOTE_GRPC_URL") else {
        eprintln!("TUIST_CAS_REMOTE_GRPC_URL is required");
        std::process::exit(2);
    };
    let tokens = TokenProvider::from_env();
    let upstream_plugin = std::env::var("TUIST_CAS_UPSTREAM_PLUGIN").unwrap_or_else(|_| {
        let developer_dir = std::env::var("DEVELOPER_DIR")
            .unwrap_or_else(|_| "/Applications/Xcode.app/Contents/Developer".into());
        format!("{developer_dir}/usr/lib/libToolchainCASPlugin.dylib")
    });
    let registry_path = std::env::var("TUIST_CAS_PROXY_REGISTRY")
        .unwrap_or_else(|_| format!("{socket_path}.registry"));

    use std::os::unix::fs::PermissionsExt;
    if let Some(parent) = std::path::Path::new(&socket_path).parent() {
        let _ = std::fs::create_dir_all(parent);
        // Owner-only: the socket carries this user's cache token, so no other
        // user on the machine may reach it.
        let _ = std::fs::set_permissions(parent, std::fs::Permissions::from_mode(0o700));
    }
    let _ = std::fs::remove_file(&socket_path);
    let listener = match UnixListener::bind(&socket_path) {
        Ok(listener) => listener,
        Err(error) => {
            eprintln!("bind {socket_path}: {error}");
            std::process::exit(2);
        }
    };
    let _ = std::fs::set_permissions(&socket_path, std::fs::Permissions::from_mode(0o600));

    // Per-node transfer analytics into cas_analytics.db, for parity with the
    // legacy daemon; the CLI ships this db with the build report.
    let analytics = std::env::var("TUIST_CAS_ANALYTICS_DB")
        .ok()
        .filter(|path| !path.is_empty())
        .and_then(|path| tuist_cas_plugin::analytics::Analytics::open(&path));

    let proxy = Proxy::new(
        grpc_url,
        tokens,
        upstream_plugin,
        Some(std::path::PathBuf::from(registry_path)),
        analytics,
    );

    // Periodic sweep of orphaned publication records + token refresh + stats.
    std::thread::spawn(move || {
        let mut tick: u64 = 0;
        loop {
            std::thread::sleep(std::time::Duration::from_secs(10));
            proxy.sweep();
            proxy.enforce_cache_bounds();
            tick += 1;
            if tick % TOKEN_REFRESH_TICKS == 0 {
                proxy.refresh_token();
            }
            let stats = proxy.stats_line();
            if !stats.is_empty() {
                tuist_cas_plugin::log_line(&format!("proxy stats: {stats}"));
            }
        }
    });

    eprintln!("tuist-cas-proxy listening on {socket_path}");
    proxy.serve(listener);
}
