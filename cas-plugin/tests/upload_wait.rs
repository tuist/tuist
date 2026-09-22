//! The wire half of synchronous uploads: a compiler's put asks the proxy to
//! publish its record and waits for the answer. The unit tests cover when the
//! proxy waits; this one covers the answers a plugin acts on. A proxy that took
//! the record answers either way and the put is done. A proxy that could not take
//! it (none listening, or one older than the op) has to read as an error, because
//! that is what makes the plugin fall back to an ordinary PUBLISH instead of
//! leaving the record unannounced.

use std::io::Read;
use std::os::unix::net::UnixListener;
use std::time::Duration;

use tuist_cas_plugin::proxy::Proxy;
use tuist_cas_plugin::proxy_proto::{read_request, write_response, ProxyClient, STATUS_ERROR};
use tuist_cas_plugin::token::TokenProvider;

fn temp_dir(name: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("tuist-upload-wait-wire-{name}-{}", std::process::id()));
    std::fs::remove_dir_all(&dir).ok();
    std::fs::create_dir_all(&dir).expect("temp dir");
    dir
}

#[test]
fn a_proxy_that_took_the_record_answers_over_the_socket() {
    let dir = temp_dir("answered");
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

    // No instance declared and none registered for the path: the proxy keeps the
    // record for a later sweep and says it is still owed, without waiting.
    let spool = dir.join("cas").join("tuist-spool");
    std::fs::create_dir_all(&spool).expect("spool");
    let record = spool.join("1234-0");
    std::fs::write(&record, b"record").expect("record");
    let answer = ProxyClient { socket_path }
        .publish_and_wait(
            &dir.join("cas").to_string_lossy(),
            "",
            &record.to_string_lossy(),
            Duration::from_secs(5),
        )
        .expect("the proxy answered");

    assert!(!answer);
    assert!(record.exists());
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn a_proxy_older_than_the_op_is_an_error() {
    let dir = temp_dir("old-proxy");
    let socket_path = dir.join("proxy.sock").to_string_lossy().into_owned();
    let listener = UnixListener::bind(&socket_path).expect("bind");
    // What every proxy before PUBLISH_WAIT answers to an op it does not know.
    std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().expect("accept");
        read_request(&mut stream).expect("request");
        write_response(&mut stream, STATUS_ERROR, b"bad op").expect("response");
        let _ = stream.read(&mut [0u8; 1]);
    });

    let answer = ProxyClient { socket_path }.publish_and_wait(
        "/cas",
        "tuist/mastodon",
        "/cas/tuist-spool/1234-0",
        Duration::from_secs(5),
    );

    assert!(answer.is_err());
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn no_proxy_listening_is_an_error() {
    let answer = ProxyClient {
        socket_path: "/tmp/tuist-cas-proxy-that-is-not-there.sock".to_string(),
    }
    .publish_and_wait(
        "/cas",
        "tuist/mastodon",
        "/cas/tuist-spool/1234-0",
        Duration::from_secs(5),
    );

    assert!(answer.is_err());
}
