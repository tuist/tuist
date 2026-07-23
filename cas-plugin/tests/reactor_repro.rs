use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use tuist_cas_plugin::reapi::{Remote, RemoteConfig};
use tuist_cas_plugin::token::TokenProvider;

// Reproduces the proxy's threading model: an RPC issued from a plain thread
// (no ambient Tokio runtime), exactly like a proxy connection handler. The
// tonic Channel is built via connect_lazy inside Remote::channel(); if that
// construction happens outside the runtime context, the first RPC panics with
// "there is no reactor running" on the hyper connection path. In production the
// panic is swallowed at the FFI boundary and every resolve silently degrades to
// a local miss (0% remote cache), so we catch it with a global panic hook
// rather than relying on the call to abort.
#[test]
fn grpc_call_from_plain_thread_does_not_panic_no_reactor() {
    // Reserve then release a port so connections are refused immediately: the
    // channel is still driven far enough to trigger the panic in the buggy case,
    // but the fixed path returns a fast transport error instead of blocking.
    let addr = {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        listener.local_addr().unwrap()
    };

    let saw_no_reactor = Arc::new(AtomicBool::new(false));
    let flag = saw_no_reactor.clone();
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        if info.to_string().contains("no reactor running") {
            flag.store(true, Ordering::SeqCst);
        }
        previous(info);
    }));

    let remote = Remote::new(
        RemoteConfig {
            grpc_url: format!("http://{addr}"),
            instance: "test".into(),
        },
        TokenProvider::from_env(),
    );

    // Issued from this plain test thread; returns Err (transport) either way.
    let _ = remote.get_action(b"deadbeefdeadbeef");

    // Let any detached connection-driver task run and (not) panic.
    std::thread::sleep(std::time::Duration::from_millis(500));

    let _ = std::panic::take_hook();
    assert!(
        !saw_no_reactor.load(Ordering::SeqCst),
        "gRPC path panicked with 'no reactor running' (channel built outside the tokio runtime)"
    );
}
