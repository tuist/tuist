//! Per-machine cache proxy. See proxy.rs for the architecture.
//!
//! The proxy is not bound to a single project: it multiplexes REAPI clients
//! per `account/project` instance, which each connection declares (or which
//! the proxy recalls from the persisted registry for an Xcode ⌘B build).
//!
//! Environment:
//! - TUIST_CAS_PROXY_SOCKET: unix socket path to listen on
//!   (default ~/.local/state/tuist/cas-proxy.sock; see `default_proxy_socket`)
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
use tuist_cas_plugin::proxy_proto::ProxyClient;
use tuist_cas_plugin::token::TokenProvider;

// Refresh the bearer only inside this window before its JWT expiry, checked
// every maintenance tick. Kept under the CLI's own 30s refresh threshold so a
// proactive fetch mints a fresh token instead of returning the still-valid one,
// and above the 10s tick interval so a tick cannot step over the window (see
// token::TokenProvider::refresh_if_expiring).
const TOKEN_REFRESH_LEAD: std::time::Duration = std::time::Duration::from_secs(25);


/// `--drain <cas-path> [--timeout-ms <n>]`: ask the RUNNING proxy whether every
/// publication it holds for that CAS path has reached the remote, and wait for
/// it. The caller is a runner VM's teardown, deciding whether the cache image
/// this store is folded into may be promoted as the account's master.
///
/// Exit codes are the three answers a caller must keep apart:
///   0 - drained; nothing this store recorded is missing from the remote.
///   3 - records remain; promoting this store hands other hosts associations
///       whose objects nothing can produce.
///   * - could not ask (no proxy listening, one too old to know the op, or this
///       binary never ran at all). Not an answer: the caller falls back to
///       watching the spool itself.
///
/// "Records remain" is deliberately NOT exit 1. That is what every wrapper,
/// shim and startup failure between the caller and this binary returns, and a
/// caller that read one of those as an authoritative answer would act on a
/// verdict nothing produced.
fn drain(arguments: &[String]) -> i32 {
    let value_of = |name: &str| {
        arguments
            .iter()
            .position(|argument| argument == name)
            .and_then(|at| arguments.get(at + 1))
            .cloned()
    };
    let Some(cas_path) = value_of("--drain") else {
        eprintln!("--drain requires a CAS path");
        return 1;
    };
    let timeout = value_of("--timeout-ms")
        .and_then(|millis| millis.parse::<u64>().ok())
        .map_or(DEFAULT_DRAIN_TIMEOUT, std::time::Duration::from_millis);
    let socket_path = value_of("--socket").unwrap_or_else(|| {
        std::env::var("TUIST_CAS_PROXY_SOCKET")
            .ok()
            .filter(|socket| !socket.is_empty())
            .unwrap_or_else(tuist_cas_plugin::default_proxy_socket)
    });
    // No instance: the proxy resolves the path's own from its registry, which
    // the build that wrote the spool primed.
    match (ProxyClient { socket_path }).drain(&cas_path, "", timeout) {
        Ok(0) => {
            eprintln!("cas publications drained for {cas_path}");
            0
        }
        Ok(owed) => {
            eprintln!("{owed} cas publication(s) never reached the remote for {cas_path}");
            3
        }
        Err(reason) => {
            eprintln!("cas drain could not run ({reason})");
            1
        }
    }
}

const DEFAULT_DRAIN_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(120);

/// `--prune <cas-path> [--limit-bytes <n>]`: bound that store on disk -- rotate
/// its generation chain against the limit and delete the generations that fall
/// off it. The caller is a runner VM's teardown, run after the build's handles
/// are closed and before the cache image is measured and promoted, because
/// nothing else ever collects those generations: `COMPILATION_CACHE_LIMIT_SIZE`
/// alone bounds a generation, not the directory, so an uncollected store grows
/// without bound (measured to 9.4x its limit, still climbing).
///
/// It asks the RUNNING proxy first and only prunes in-process if the proxy says
/// it holds no handle on the path. That order is load-bearing rather than an
/// optimisation: llcas rotates a store as its LAST handle closes, so on a
/// machine where the proxy holds one, a prune driven from here would find the
/// chain still live and collect nothing while reporting success.
///
/// Exit 0 pruned (or found nothing to collect), 1 could not. There is no third
/// answer to keep apart the way `--drain` has one: a prune that did not run
/// costs the volume space, and the caller's own fill gauge is what acts on that.
fn prune(arguments: &[String]) -> i32 {
    let value_of = |name: &str| {
        arguments
            .iter()
            .position(|argument| argument == name)
            .and_then(|at| arguments.get(at + 1))
            .cloned()
    };
    let Some(cas_path) = value_of("--prune") else {
        eprintln!("--prune requires a CAS path");
        return 1;
    };
    // 0 = impose no budget: prune against whatever limit the store carries.
    let limit_bytes = value_of("--limit-bytes")
        .and_then(|bytes| bytes.parse::<u64>().ok())
        .unwrap_or(0);
    let socket_path = value_of("--socket").unwrap_or_else(|| {
        std::env::var("TUIST_CAS_PROXY_SOCKET")
            .ok()
            .filter(|socket| !socket.is_empty())
            .unwrap_or_else(tuist_cas_plugin::default_proxy_socket)
    });

    let why_local = match (ProxyClient { socket_path }).prune(&cas_path, limit_bytes) {
        Ok(Some(reclaimed)) => {
            eprintln!("proxy pruned {cas_path}, reclaiming {reclaimed} bytes");
            return 0;
        }
        Ok(None) => "the proxy holds no handle on it",
        // Not an answer about whether a handle is held. Try anyway -- the common
        // case is no proxy at all -- but say why the result may be a no-op.
        Err(reason) => {
            eprintln!("cas prune could not ask the proxy ({reason})");
            "the proxy could not be asked"
        }
    };
    match tuist_cas_plugin::proxy::prune_store(
        &tuist_cas_plugin::upstream_path(),
        &cas_path,
        limit_bytes,
    ) {
        Ok(reclaimed) => {
            eprintln!("pruned {cas_path} directly ({why_local}), reclaiming {reclaimed} bytes");
            0
        }
        Err(reason) => {
            eprintln!("cas prune failed for {cas_path} ({why_local}): {reason}");
            1
        }
    }
}

fn main() {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    if arguments.iter().any(|argument| argument == "--drain") {
        std::process::exit(drain(&arguments));
    }
    if arguments.iter().any(|argument| argument == "--prune") {
        std::process::exit(prune(&arguments));
    }

    let socket_path = std::env::var("TUIST_CAS_PROXY_SOCKET")
        .ok()
        .filter(|socket| !socket.is_empty())
        .unwrap_or_else(tuist_cas_plugin::default_proxy_socket);
    let Ok(grpc_url) = std::env::var("TUIST_CAS_REMOTE_GRPC_URL") else {
        eprintln!("TUIST_CAS_REMOTE_GRPC_URL is required");
        std::process::exit(2);
    };
    let tokens = TokenProvider::from_env();
    // Resolve the upstream via the shared `upstream_path()` so the proxy gets the
    // same `xcode-select` fallback as the plugin. The proxy is launched by
    // launchd/`tuist cache-proxy` with no DEVELOPER_DIR, so without this it would
    // fall back to the hardcoded `/Applications/Xcode.app` and fail to load
    // Apple's plugin on any versioned Xcode install (every resolve then misses).
    let upstream_plugin = tuist_cas_plugin::upstream_path();
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
    // Swift `CASAnalyticsDatabase`; the CLI ships this db with the build report.
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

    // Snapshots for every instance the persisted registry knows start
    // fetching now, so the first build after a proxy restart begins with the
    // snapshot (and its bulk warm) already in flight.
    proxy.prefetch_known_snapshots();

    // Periodic sweep of orphaned publication records + token refresh + stats.
    std::thread::spawn(move || loop {
        std::thread::sleep(std::time::Duration::from_secs(10));
        proxy.sweep();
        proxy.enforce_cache_bounds();
        proxy.reclaim_idle();
        proxy.maintain_token(TOKEN_REFRESH_LEAD);
        proxy.refresh_endpoint();
        proxy.refresh_snapshots();
        proxy.refresh_view_keys();
        let stats = proxy.stats_line();
        if !stats.is_empty() {
            tuist_cas_plugin::log_line(&format!("proxy stats: {stats}"));
        }
    });

    eprintln!("tuist-cas-proxy listening on {socket_path}");
    proxy.serve(listener);
}
