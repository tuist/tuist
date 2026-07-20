
use tokio::{sync::oneshot, time::timeout};

use super::*;
use crate::test_support::test_context;

#[test]
fn http_builder_accepts_http1_and_http2() {
    let mut builder = HttpBuilder::new(TokioExecutor::new());

    configure_http_builder(&mut builder);

    // The co-hosted listener must accept HTTP/1.1 (HTTP cache clients) and
    // HTTP/2 (h2c REAPI gRPC) on the same socket.
    assert!(builder.is_http1_available());
    assert!(builder.is_http2_available());
}

#[cfg(not(target_env = "msvc"))]
#[test]
fn jemalloc_stats_snapshot_reads_live_allocator_stats() {
    // Hold a sizeable allocation so `allocated` is unambiguously non-zero
    // when we sample, exercising the real mallctl path (epoch refresh +
    // typed stat reads) rather than the hardcoded render-test values.
    let ballast: Vec<u8> = vec![7u8; 8 * 1024 * 1024];
    let stats = jemalloc_stats_snapshot().expect("jemalloc stats available under jemalloc");
    assert!(stats.allocated_bytes > 0);
    assert!(stats.resident_bytes >= stats.allocated_bytes);
    drop(ballast);
}

#[cfg(target_os = "linux")]
#[test]
fn resident_rss_splits_into_anon_and_file() {
    let status = "VmSize:\t 4194304 kB\n\
             VmRSS:\t 1048576 kB\n\
             RssAnon:\t  786432 kB\n\
             RssFile:\t  262144 kB\n\
             RssShmem:\t       0 kB\n";
    assert_eq!(parse_status_memory_kib(status, "RssAnon:"), Some(786_432));
    assert_eq!(parse_status_memory_kib(status, "RssFile:"), Some(262_144));

    // The live process snapshot must also carry the split, and the two
    // resident classes can never exceed total VmRSS (VmRSS = anon + file +
    // shmem), which is the invariant a dashboard subtracting them relies on.
    let snapshot = process_memory_snapshot().expect("linux process snapshot");
    let anon = snapshot
        .resident_anon_bytes
        .expect("RssAnon present on kernels >= 4.5");
    let file = snapshot
        .resident_file_bytes
        .expect("RssFile present on kernels >= 4.5");
    assert!(anon > 0);
    assert!(anon + file <= snapshot.resident_bytes);
}

// End-to-end proof that the co-hosted listener dispatches by path: an HTTP
// cache probe and a REAPI gRPC call both succeed against the same port. This
// is the behavior the co-hosted port exists to provide — a client that
// derives its gRPC target from the single cache URL reaches REAPI, not the
// plain-HTTP listener.
#[tokio::test]
async fn cohosted_listener_serves_http_and_grpc() {
    use bazel_remote_apis::build::bazel::remote::execution::v2::{
        GetCapabilitiesRequest, capabilities_client::CapabilitiesClient,
    };

    let context = test_context(|_| {}).await;
    let state = context.state.clone();

    // The production serving path: the accelerated per-connection loop
    // (nodelay, aging, drain), with non-accelerable requests on hyper.
    let listener = tokio::net::TcpListener::bind(SocketAddr::from((Ipv4Addr::LOCALHOST, 0)))
        .await
        .expect("bind co-hosted test listener");
    let addr = listener.local_addr().expect("co-hosted listener address");
    let (shutdown_tx, shutdown_rx) = watch::channel(false);
    let server = tokio::spawn(accelerated_file_serving::serve_public_http(
        listener,
        cohosted_router(state.clone()),
        state.clone(),
        state.config.accelerated_file_serving.clone(),
        shutdown_rx,
        configure_http_builder,
    ));

    // HTTP cache surface answers on the co-hosted port.
    let http = reqwest::Client::new()
        .get(format!("http://{addr}/up"))
        .send()
        .await
        .expect("co-hosted port should answer the HTTP /up probe");
    assert_eq!(http.status(), reqwest::StatusCode::OK);

    // Unmatched plain-HTTP paths must 404, not fall into tonic's
    // grpc-Unimplemented fallback (internal routes only exist on the
    // internal listener).
    let internal = reqwest::Client::new()
        .get(format!("http://{addr}/_internal/status"))
        .send()
        .await
        .expect("co-hosted port should answer unmatched HTTP paths");
    assert_eq!(internal.status(), reqwest::StatusCode::NOT_FOUND);

    // gRPC requests to unknown services keep the tonic semantics:
    // HTTP 200 with grpc-status Unimplemented.
    let unknown_grpc = reqwest::Client::builder()
        .http2_prior_knowledge()
        .build()
        .expect("build h2c client")
        .post(format!("http://{addr}/unknown.Service/Method"))
        .header("content-type", "application/grpc")
        .send()
        .await
        .expect("co-hosted port should answer unknown gRPC services");
    assert_eq!(unknown_grpc.status(), reqwest::StatusCode::OK);
    assert_eq!(
        unknown_grpc
            .headers()
            .get("grpc-status")
            .and_then(|value| value.to_str().ok()),
        Some("12"),
        "unknown gRPC service should map to grpc-status Unimplemented"
    );

    // REAPI gRPC (h2c) answers on the same port.
    let mut grpc_client = None;
    for _ in 0..50 {
        match tonic::transport::Endpoint::from_shared(format!("http://{addr}"))
            .expect("valid gRPC endpoint")
            .connect()
            .await
        {
            Ok(channel) => {
                grpc_client = Some(CapabilitiesClient::new(channel));
                break;
            }
            Err(_) => tokio::time::sleep(Duration::from_millis(20)).await,
        }
    }
    let mut grpc_client = grpc_client.expect("co-hosted port should accept gRPC (h2c) connections");
    let capabilities = grpc_client
        .get_capabilities(GetCapabilitiesRequest {
            instance_name: String::new(),
        })
        .await
        .expect("co-hosted port should answer REAPI GetCapabilities")
        .into_inner();
    assert!(
        capabilities.cache_capabilities.is_some(),
        "REAPI GetCapabilities over the co-hosted port should return cache capabilities"
    );

    shutdown_tx.send(true).expect("signal shutdown");
    let _ = server.await;
}

// Same as above but over TLS (reusing the public cert): both HTTPS and REAPI
// gRPC ride one TLS port, ALPN-negotiated (http/1.1 for HTTP, h2 for gRPC).
#[tokio::test]
async fn cohosted_listener_serves_http_and_grpc_over_tls() {
    use bazel_remote_apis::build::bazel::remote::execution::v2::{
        GetCapabilitiesRequest, capabilities_client::CapabilitiesClient,
    };

    let context = test_context(|_| {}).await;
    let state = context.state.clone();

    // Self-signed cert for "localhost", loaded through PublicTlsConfig so the
    // test exercises the real build_public_rustls_config path (ALPN + all).
    let cert = rcgen::generate_simple_self_signed(vec!["localhost".to_string()])
        .expect("generate self-signed cert");
    let cert_pem = cert.cert.pem();
    let key_pem = cert.signing_key.serialize_pem();
    let dir = tempfile::tempdir().expect("temp dir");
    let cert_path = dir.path().join("tls.crt");
    let key_path = dir.path().join("tls.key");
    std::fs::write(&cert_path, &cert_pem).expect("write cert");
    std::fs::write(&key_path, &key_pem).expect("write key");
    let public_tls = crate::config::PublicTlsConfig {
        cert_path,
        key_path,
    };
    let tls_config = crate::peer_tls::build_public_rustls_config(&public_tls)
        .await
        .expect("build public rustls config")
        .get_inner();

    // The production TLS serving path: rustls handshake in front of the
    // same per-connection hyper loop.
    let listener = tokio::net::TcpListener::bind(SocketAddr::from((Ipv4Addr::LOCALHOST, 0)))
        .await
        .expect("bind co-hosted TLS test listener");
    let addr = listener
        .local_addr()
        .expect("co-hosted TLS listener address");
    let (shutdown_tx, shutdown_rx) = watch::channel(false);
    let server = tokio::spawn(accelerated_file_serving::serve_public_tls(
        listener,
        cohosted_router(state.clone()),
        tls_config,
        shutdown_rx,
        configure_http_builder,
    ));

    // HTTPS cache surface answers on the co-hosted port.
    let http = reqwest::Client::builder()
        .add_root_certificate(
            reqwest::Certificate::from_pem(cert_pem.as_bytes()).expect("trust test cert"),
        )
        .resolve("localhost", addr)
        .build()
        .expect("build https client")
        .get(format!("https://localhost:{}/up", addr.port()))
        .send()
        .await
        .expect("co-hosted TLS port should answer HTTPS /up");
    assert_eq!(http.status(), reqwest::StatusCode::OK);

    // REAPI gRPC answers over TLS (ALPN h2) on the same port. Dial the IP and
    // pin the cert domain so the test never depends on localhost resolution.
    let client_tls = tonic::transport::ClientTlsConfig::new()
        .ca_certificate(tonic::transport::Certificate::from_pem(cert_pem.as_bytes()))
        .domain_name("localhost");
    let mut grpc_client = None;
    for _ in 0..50 {
        let endpoint = tonic::transport::Endpoint::from_shared(format!("https://{addr}"))
            .expect("valid gRPC endpoint")
            .tls_config(client_tls.clone())
            .expect("apply client tls");
        match endpoint.connect().await {
            Ok(channel) => {
                grpc_client = Some(CapabilitiesClient::new(channel));
                break;
            }
            Err(_) => tokio::time::sleep(Duration::from_millis(20)).await,
        }
    }
    let mut grpc_client =
        grpc_client.expect("co-hosted TLS port should accept gRPC (h2 over TLS) connections");
    let capabilities = grpc_client
        .get_capabilities(GetCapabilitiesRequest {
            instance_name: String::new(),
        })
        .await
        .expect("co-hosted TLS port should answer REAPI GetCapabilities")
        .into_inner();
    assert!(
        capabilities.cache_capabilities.is_some(),
        "REAPI GetCapabilities over the co-hosted TLS port should return cache capabilities"
    );

    shutdown_tx.send(true).expect("signal shutdown");
    let _ = server.await;
}

#[tokio::test]
async fn wait_for_shutdown_signal_returns_when_ctrl_c_resolves() {
    let (ctrl_c_tx, ctrl_c_rx) = oneshot::channel::<()>();
    let (_terminate_tx, terminate_rx) = oneshot::channel::<()>();

    let waiter = tokio::spawn(wait_for_shutdown_signal(
        async move {
            let _ = ctrl_c_rx.await;
        },
        async move {
            let _ = terminate_rx.await;
        },
    ));

    ctrl_c_tx.send(()).expect("ctrl-c sender should be open");

    timeout(Duration::from_secs(1), waiter)
        .await
        .expect("shutdown waiter should return after ctrl-c")
        .expect("shutdown waiter task should finish cleanly");
}

#[tokio::test]
async fn wait_for_shutdown_signal_returns_when_terminate_resolves() {
    let (_ctrl_c_tx, ctrl_c_rx) = oneshot::channel::<()>();
    let (terminate_tx, terminate_rx) = oneshot::channel::<()>();

    let waiter = tokio::spawn(wait_for_shutdown_signal(
        async move {
            let _ = ctrl_c_rx.await;
        },
        async move {
            let _ = terminate_rx.await;
        },
    ));

    terminate_tx
        .send(())
        .expect("terminate sender should be open");

    timeout(Duration::from_secs(1), waiter)
        .await
        .expect("shutdown waiter should return after terminate")
        .expect("shutdown waiter task should finish cleanly");
}

#[tokio::test]
async fn wait_for_inflight_drain_returns_when_requests_finish() {
    let context = test_context(|_| {}).await;
    let guard = context
        .state
        .start_http_request(crate::runtime::HttpTrafficClass::Public);
    let waiter = tokio::spawn(wait_for_inflight_drain(
        context.state.clone(),
        ShutdownBudget::new(Duration::from_millis(250)),
    ));

    tokio::time::sleep(Duration::from_millis(20)).await;
    drop(guard);

    assert!(
        waiter
            .await
            .expect("wait task should finish after request completion")
    );
}

#[tokio::test]
async fn wait_for_inflight_drain_times_out_when_requests_do_not_finish() {
    let context = test_context(|_| {}).await;
    let _guard = context.state.start_grpc_request();

    assert!(
        !wait_for_inflight_drain(
            context.state.clone(),
            ShutdownBudget::new(Duration::from_millis(25)),
        )
        .await
    );
}
