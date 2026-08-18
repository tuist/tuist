//! The wire half of the promote gate: a runner's teardown asks the proxy over
//! the socket whether this CAS store still owes the remote anything, and the
//! answer decides whether the cache image it is folded into may become the
//! account's master. The unit tests cover what `drain_publications` counts;
//! this one covers that the question and the answer survive the socket, since
//! the caller is a different process (and, on a runner, a shell script).

use std::os::unix::net::UnixListener;
use std::time::Duration;

use tuist_cas_plugin::proxy::Proxy;
use tuist_cas_plugin::proxy_proto::ProxyClient;
use tuist_cas_plugin::token::TokenProvider;

fn serving_proxy(dir: &std::path::Path) -> ProxyClient {
    let socket_path = dir.join("proxy.sock").to_string_lossy().into_owned();
    let listener = UnixListener::bind(&socket_path).expect("bind");
    let proxy = Proxy::new(
        "http://127.0.0.1:1".into(),
        TokenProvider::from_env(),
        String::new(),
        Some(dir.join("registry")),
        None,
    );
    std::thread::spawn(move || proxy.serve(listener));
    ProxyClient { socket_path }
}

#[test]
fn a_drain_over_the_socket_separates_owed_from_drained() {
    let dir = std::env::temp_dir().join(format!("tuist-drain-wire-{}", std::process::id()));
    std::fs::remove_dir_all(&dir).ok();
    std::fs::create_dir_all(&dir).expect("temp dir");
    let client = serving_proxy(&dir);

    // A store that never published: no spool at all, which is what a job that
    // used the builtin lane leaves behind. It has to read as drained, or every
    // such job would withhold a promote it has no reason to.
    let untouched = dir.join("untouched-cas");
    assert_eq!(
        client
            .drain(&untouched.to_string_lossy(), "", Duration::from_millis(500))
            .expect("drain answered"),
        0
    );

    // A store holding a record nothing published. The proxy knows no instance
    // for this path, so there is nowhere for it to go: it is owed, and the
    // count comes back across the socket rather than collapsing into "drained".
    let owing = dir.join("owing-cas");
    let spool = owing.join("tuist-spool");
    std::fs::create_dir_all(&spool).expect("spool");
    std::fs::write(spool.join("1234-0"), b"record").expect("record");
    std::fs::write(spool.join("1234-0.tags"), b"main\nmain").expect("sidecar");
    assert_eq!(
        client
            .drain(&owing.to_string_lossy(), "", Duration::from_millis(500))
            .expect("drain answered"),
        1,
        "the sidecar is not a record, and the record is not drained"
    );

    std::fs::remove_dir_all(&dir).ok();
}

/// Nothing listening is not an answer. A caller that read it as "drained" would
/// promote exactly the images this gate exists to hold back, so the client has
/// to keep an unreachable proxy distinct from a clean one.
#[test]
fn an_unreachable_proxy_is_an_error_and_not_a_clean_drain() {
    let client = ProxyClient {
        socket_path: "/tmp/tuist-cas-proxy-that-is-not-there.sock".to_string(),
    };
    assert!(client
        .drain("/cas", "", Duration::from_millis(200))
        .is_err());
}
