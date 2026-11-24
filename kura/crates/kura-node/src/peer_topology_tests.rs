//! Peer topology as the node applies it: private-origin routing through `AppState`. The topology
//! type and its validation are tested in kura-core.
use kura_core::peer_topology::PeerTopology;

fn topology(provider: &str, network: &str) -> PeerTopology {
    PeerTopology {
        provider: provider.into(),
        private_network: Some(network.into()),
        private_url: Some("https://private.example:7443".into()),
        canonical_networks: Vec::new(),
    }
}

#[tokio::test]
async fn approved_remote_vpc_is_not_a_preferred_private_donor() {
    let mut own = topology("vultr", "ord");
    own.canonical_networks.push("scl".into());
    let mut remote = topology("vultr", "scl");
    remote.canonical_networks.push("ord".into());
    let ctx =
        crate::test_support::test_context(|config| config.peer_topology = Some(own.clone())).await;
    let canonical = "https://public.example:7443";
    ctx.state
        .apply_peer_views(vec![crate::sync::roles::PeerView {
            private_healthy: true,
            url: canonical.into(),
            region: "scl".into(),
            topology: Some(remote),
            serving: true,
            draining: false,
        }]);
    assert!(!ctx.state.prefers_peer(canonical));
    let request = ctx
        .state
        .peer_request(
            reqwest::Method::GET,
            canonical,
            &format!("{canonical}/_internal/backfill/bodies"),
        )
        .unwrap()
        .build()
        .unwrap();
    assert_eq!(
        request.url().as_str(),
        format!("{canonical}/_internal/backfill/bodies")
    );
}

#[tokio::test]
async fn every_peer_request_uses_private_origin_and_keeps_canonical_identity() {
    let own = topology("ovh", "vrack-1");
    let ctx = crate::test_support::test_context(|config| {
        config.peer_topology = Some(own.clone());
    })
    .await;
    let canonical = "https://public.example:7443";
    let view = crate::sync::roles::PeerView {
        private_healthy: true,
        url: canonical.into(),
        region: "remote".into(),
        topology: Some(own),
        serving: true,
        draining: false,
    };
    ctx.state.apply_peer_views(vec![view.clone()]);
    for path in [
        "/_internal/sync/forward?after=123",
        "/_internal/backfill/entries?order=asc",
        "/_internal/backfill/bodies",
        "/_internal/backfill/artifacts/key",
    ] {
        let request = ctx
            .state
            .peer_request(
                reqwest::Method::GET,
                canonical,
                &format!("{canonical}{path}"),
            )
            .unwrap()
            .build()
            .unwrap();
        assert_eq!(
            request.url().as_str(),
            format!("https://private.example:7443{path}")
        );
    }
    assert_eq!(ctx.state.peer_views.load()[0].url, canonical);
    let mut remote = view;
    remote.topology.as_mut().unwrap().provider = "vultr".into();
    ctx.state.apply_peer_views(vec![remote]);
    let request = ctx
        .state
        .peer_request(
            reqwest::Method::GET,
            canonical,
            &format!("{canonical}/_internal/status"),
        )
        .unwrap()
        .build()
        .unwrap();
    assert_eq!(request.url().host_str(), Some("public.example"));
    ctx.state.apply_peer_views(vec![]);
    assert!(
        ctx.state
            .peer_request(
                reqwest::Method::GET,
                canonical,
                &format!("{canonical}/_internal/status")
            )
            .is_err(),
        "membership removal must not race a public fallback"
    );
}

#[tokio::test]
async fn unreachable_private_endpoint_never_retries_the_public_listener() {
    use std::sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    };
    let hits = Arc::new(AtomicUsize::new(0));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let count = hits.clone();
    let server = tokio::spawn(async move {
        loop {
            let (stream, _) = listener.accept().await.unwrap();
            count.fetch_add(1, Ordering::Relaxed);
            drop(stream);
        }
    });
    let private = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let private_address = private.local_addr().unwrap();
    drop(private);
    let mut own = topology("ovh", "vrack-1");
    own.private_url = Some(format!("https://{private_address}"));
    let ctx =
        crate::test_support::test_context(|config| config.peer_topology = Some(own.clone())).await;
    // The advertised public endpoint is syntactically HTTPS; the listener
    // counts accepted TCP connections as well as HTTP so even a TLS retry
    // cannot be mistaken for no fallback.
    let canonical = format!("https://{address}");
    ctx.state
        .apply_peer_views(vec![crate::sync::roles::PeerView {
            private_healthy: true,
            url: canonical.clone(),
            region: "remote".into(),
            topology: Some(own),
            serving: true,
            draining: false,
        }]);
    assert!(
        ctx.state
            .peer_request(reqwest::Method::GET, &canonical, &format!("{canonical}/"))
            .unwrap()
            .send()
            .await
            .is_err()
    );
    assert_eq!(hits.load(Ordering::Relaxed), 0);
    server.abort();
}
