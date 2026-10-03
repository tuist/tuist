use super::*;
use std::{
    future::pending,
    sync::atomic::{AtomicUsize, Ordering},
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpListener,
};

fn private_address() -> SocketAddr {
    "10.96.0.20:80".parse().unwrap()
}

#[test]
fn profiles_are_fixed_and_include_absolute_names() {
    for (environment, namespace) in [
        ("production", "tuist"),
        ("staging", "tuist-staging"),
        ("canary", "tuist-canary"),
    ] {
        let host = profile_host(environment).unwrap();
        assert_eq!(
            host,
            format!("tuist-tuist-server.{namespace}.svc.cluster.local")
        );
        assert_eq!(
            profile_samples(host),
            [
                (host.into(), Duration::from_secs(1)),
                (host.into(), Duration::from_secs(3)),
                (format!("{host}."), Duration::from_secs(1)),
                (format!("{host}."), Duration::from_secs(3)),
            ]
        );
    }
    for invalid in ["", "prod", "http://example.com", "production --url=x"] {
        assert!(profile_host(invalid).is_none());
        assert!(start(Some(invalid)).is_none());
    }
    assert!(start(None).is_none());
}

#[test]
fn worker_panic_does_not_propagate_to_its_owner() {
    let mut diagnostics = spawn_worker(|_| panic!("injected diagnostic failure")).unwrap();
    assert!(diagnostics._thread.take().unwrap().join().is_ok());
    // The guard's owner continues after a failed diagnostic worker.
    drop(diagnostics);
}

#[test]
fn owner_shutdown_signals_worker_without_joining_it() {
    let (stopped, observed) = std::sync::mpsc::channel();
    let (release, blocked) = std::sync::mpsc::channel();
    let mut diagnostics = spawn_worker(move |stop| {
        let _ = stop.blocking_recv();
        stopped.send(()).unwrap();
        let _ = blocked.recv();
    })
    .unwrap();
    let thread = diagnostics._thread.take().unwrap();
    drop(diagnostics);
    observed.recv_timeout(Duration::from_secs(2)).unwrap();
    release.send(()).unwrap();
    thread.join().unwrap();
}

#[test]
fn resolver_records_only_emit_on_changes() {
    let mut state = ResolverRecord::default();
    assert!(state.changed("nameserver 10.0.0.1".into(), true));
    assert!(!state.changed("nameserver 10.0.0.1".into(), true));
    assert!(state.changed("nameserver 10.0.0.2".into(), true));
    assert!(state.changed("".into(), false));
    assert!(!state.changed("".into(), false));
    assert!(state.changed("".into(), true));
}

#[tokio::test]
async fn cancelled_dns_cannot_accumulate_blocking_workers() {
    let resolver = Arc::new(Resolver::default());
    let (entered, started) = oneshot::channel();
    let (release, wait) = std::sync::mpsc::channel();
    let first = tokio::spawn({
        let resolver = resolver.clone();
        async move {
            resolver
                .lookup_using("unused".into(), move |_| {
                    let _ = entered.send(());
                    let _ = wait.recv();
                    Ok(vec![private_address()])
                })
                .await
        }
    });
    started.await.unwrap();
    first.abort();
    let _ = first.await;
    assert!(
        resolver
            .lookup_using("unused".into(), |_| panic!("queued a second DNS worker"))
            .await
            .is_err()
    );
    release.send(()).unwrap();
    tokio::time::timeout(Duration::from_secs(2), async {
        while resolver.in_flight.available_permits() == 0 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert!(
        resolver
            .lookup_using("unused".into(), |_| Ok(vec![private_address()]))
            .await
            .is_ok()
    );
}

async fn exchange(host: &str, response: String, overall: Duration) -> Sample {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let expected_host = host.to_owned();
    let server = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        let mut request = Vec::new();
        while !request.ends_with(b"\r\n\r\n") {
            request.push(socket.read_u8().await.unwrap());
            assert!(request.len() < 8192);
        }
        let request = String::from_utf8(request).unwrap().to_lowercase();
        assert!(request.starts_with("get /ready http/1.1\r\n"));
        assert!(request.contains(&format!("host: {expected_host}\r\n")));
        for forbidden in [
            "authorization:",
            "cookie:",
            "accept-encoding:",
            "proxy-authorization:",
        ] {
            assert!(!request.contains(forbidden));
        }
        let _ = socket.write_all(response.as_bytes()).await;
        if response.is_empty() {
            // The request deadline must close even a server withholding headers.
            let mut byte = [0u8];
            let _ = socket.read(&mut byte).await;
        }
    });
    let result = measure(
        host,
        Duration::from_secs(1),
        overall,
        |_| async { Ok(vec![private_address()]) },
        move |target| {
            assert_eq!(target, private_address());
            TcpStream::connect(address)
        },
    )
    .await;
    tokio::time::timeout(Duration::from_secs(2), server)
        .await
        .unwrap()
        .unwrap();
    result
}

#[tokio::test]
async fn http_bounds_and_absolute_host_are_preserved() {
    for host in [
        "tuist-tuist-server.tuist.svc.cluster.local",
        "tuist-tuist-server.tuist.svc.cluster.local.",
    ] {
        for (response, status, outcome) in [
            ("HTTP/1.1 100 Continue\r\n\r\n".into(), Some(100), "informational_response"),
            ("HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nsecret".into(), Some(200), "ok"),
            ("HTTP/1.1 302 Found\r\nLocation: http://169.254.169.254/latest/meta-data/\r\nContent-Length: 0\r\n\r\n".into(), Some(302), "ok"),
            (format!("HTTP/1.1 200 OK\r\nContent-Length: 6000\r\n\r\n{}", "x".repeat(6000)), Some(200), "ok"),
            ("HTTP/1.1 200 OK\r\nContent-Length: 99\r\n\r\nx".into(), Some(200), "ok"),
            (format!("HTTP/1.1 200 OK\r\nX-Large: {}\r\n\r\n", "x".repeat(16384)), None, "http_error"),
            ("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n6\r\nsecret\r\n0\r\n\r\n".into(), Some(200), "ok"),
        ] {
            let sample = exchange(host, response, Duration::from_secs(2)).await;
            assert_eq!(sample.status, status);
            assert_eq!(sample.outcome, outcome);
            assert!(sample.connect_ms.unwrap() >= sample.dns_ms.unwrap());
            assert!(sample.total_ms >= sample.connect_ms.unwrap());
            let json = serde_json::to_string(&sample).unwrap();
            assert!(!json.contains("secret") && !json.contains("169.254"));
        }
    }
}

#[tokio::test]
async fn invalid_addresses_fail_before_dial_including_mixed_answers() {
    for address in [
        "127.0.0.1:80",
        "169.254.169.254:80",
        "0.0.0.0:80",
        "8.8.8.8:80",
        "224.0.0.1:80",
        "[::1]:80",
        "[fe80::1]:80",
        "[::ffff:169.254.169.254]:80",
        "[fd00::1%2]:80",
    ] {
        let forbidden = address.parse().unwrap();
        let sample = measure(
            "fixed",
            Duration::from_secs(1),
            Duration::from_secs(1),
            move |_| async move { Ok(vec![private_address(), forbidden]) },
            |_| async {
                panic!("dialed disallowed answer");
                #[allow(unreachable_code)]
                Err(std::io::Error::other("unexpected dial"))
            },
        )
        .await;
        assert_eq!(sample.outcome, "address_error");
    }
}

#[tokio::test(start_paused = true)]
async fn dns_and_tcp_share_the_budget() {
    let dials = Arc::new(AtomicUsize::new(0));
    let started = tokio::time::Instant::now();
    let sample = measure(
        "fixed",
        Duration::from_secs(1),
        Duration::from_secs(5),
        |_| async {
            tokio::time::sleep(Duration::from_millis(700)).await;
            Ok(vec![private_address()])
        },
        {
            let dials = dials.clone();
            move |_| async move {
                dials.fetch_add(1, Ordering::Relaxed);
                tokio::time::sleep(Duration::from_millis(700)).await;
                Err(std::io::Error::other("dial expired"))
            }
        },
    )
    .await;
    assert_eq!(sample.outcome, "connect_error");
    assert_eq!(dials.load(Ordering::Relaxed), 1);
    assert_eq!(started.elapsed(), Duration::from_secs(1));
    assert!(sample.connect_ms.is_none());
}

#[tokio::test(start_paused = true)]
async fn stuck_dns_stops_without_dial() {
    let sample = measure(
        "fixed",
        Duration::from_secs(1),
        Duration::from_secs(5),
        |_| pending(),
        |_| async {
            panic!("dial after failed DNS");
            #[allow(unreachable_code)]
            Err(std::io::Error::other("unexpected dial"))
        },
    )
    .await;
    assert_eq!(sample.outcome, "dns_error");
}

#[tokio::test]
async fn overall_timeout_closes_stalled_http() {
    let sample = exchange("fixed", String::new(), Duration::from_millis(30)).await;
    assert_eq!(sample.outcome, "http_error");
    assert_eq!(sample.status, None);
}

#[tokio::test]
async fn malformed_host_is_a_diagnostic_error_not_a_panic() {
    let sample = measure(
        "bad\r\nhost",
        Duration::from_secs(1),
        Duration::from_secs(1),
        |_| pending(),
        |_| pending(),
    )
    .await;
    assert_eq!(sample.outcome, "request_error");
}

#[tokio::test]
async fn stopping_mid_profile_drops_the_current_sample_and_skips_the_rest() {
    struct Cancelled(Option<oneshot::Sender<()>>);
    impl Drop for Cancelled {
        fn drop(&mut self) {
            let _ = self.0.take().unwrap().send(());
        }
    }
    let (stop, stopped) = oneshot::channel();
    let (entered, started) = oneshot::channel();
    let (cancelled, cancellation) = oneshot::channel();
    let attempts = Arc::new(AtomicUsize::new(0));
    let observed = attempts.clone();
    let worker = tokio::spawn(until_stopped(stopped, async move {
        let mut entered = Some(entered);
        let mut cancelled = Some(cancelled);
        for _ in profile_samples("fixed") {
            observed.fetch_add(1, Ordering::Relaxed);
            let _guard = Cancelled(cancelled.take());
            entered.take().unwrap().send(()).unwrap();
            pending::<()>().await;
        }
    }));
    started.await.unwrap();
    stop.send(()).unwrap();
    worker.await.unwrap();
    cancellation.await.unwrap();
    assert_eq!(attempts.load(Ordering::Relaxed), 1);
}
