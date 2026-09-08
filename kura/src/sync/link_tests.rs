//! Ring A, end to end in one process: two or three nodes on real internal
//! listeners, membership views set by hand, the coordinator opening the
//! links the roles ask for. Covers A-9, A-10, A-14 and the shape of B-1.

use std::{sync::Arc, time::Duration};

use tokio::net::TcpListener;

use crate::{
    artifact::producer::ArtifactProducer,
    http::internal_router,
    state::SharedState,
    sync::{
        coordinator::{LinkKind, LinkPhase},
        roles::PeerView,
    },
    test_support::{TestContext, test_context},
    utils::artifact_storage_id,
};

struct Node {
    context: TestContext,
    url: String,
    region: &'static str,
    _server: tokio::task::JoinHandle<()>,
}

impl Node {
    fn state(&self) -> &SharedState {
        &self.context.state
    }

    fn view(&self) -> PeerView {
        PeerView {
            url: self.url.clone(),
            region: self.region.to_owned(),
            serving: true,
            draining: false,
            pulling: true,
        }
    }

    /// What the membership loop would have stored: the other nodes' status.
    fn see(&self, peers: &[&Node]) {
        let views: Vec<PeerView> = peers.iter().map(|peer| peer.view()).collect();
        self.state().peer_views.store(Arc::new(views));
        self.state().sync.evaluate(self.state());
    }

    async fn write(&self, key: &str, body: &[u8]) -> String {
        self.state()
            .store
            .persist_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                key,
                "application/octet-stream",
                body,
            )
            .await
            .expect("write should persist");
        artifact_storage_id(ArtifactProducer::Xcode, "test-tenant", "ios", key)
    }

    fn has(&self, artifact_id: &str) -> bool {
        self.state()
            .store
            .manifest(artifact_id)
            .expect("manifest read")
            .is_some()
    }

    async fn wait_for(&self, artifact_id: &str) {
        for _ in 0..600 {
            if self.has(artifact_id) {
                return;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        panic!("{} never received {artifact_id}", self.url);
    }
}

async fn node(region: &'static str, tune: impl FnOnce(&mut crate::config::Config)) -> Node {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind test listener");
    let url = format!("http://{}", listener.local_addr().expect("address"));
    let node_url = url.clone();
    let context = test_context(move |config| {
        config.node_url = node_url;
        config.region = region.to_owned();
        config.replication_pull = true;
        config.sync_long_poll_secs = 1;
        config.sync_region_settle_ms = 100;
        config.peers = Vec::new();
        tune(config);
    })
    .await;
    context
        .state
        .store
        .run_backfill_index_build()
        .expect("index build");
    let app = internal_router(context.state.clone());
    let server = tokio::spawn(async move {
        axum::serve(listener, app).await.expect("test server");
    });
    Node {
        context,
        url,
        region,
        _server: server,
    }
}

// A-9 (the cursor advances page by page), B-1 (write on one replica, read
// on the other), and the bootstrap: records written before the link opened
// arrive through the backward pass, records after it through the feed.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn siblings_converge_through_the_backward_pass_and_the_feed() {
    let a = node("local", |_| {}).await;
    let b = node("local", |_| {}).await;
    let before = a.write("before-link", b"1").await;

    a.see(&[&b]);
    b.see(&[&a]);
    b.wait_for(&before).await;

    let after = a.write("after-link", b"2").await;
    b.wait_for(&after).await;
    let reverse = b.write("from-b", b"3").await;
    a.wait_for(&reverse).await;

    for node in [&a, &b] {
        let links = node.state().sync.link_statuses();
        assert_eq!(links.len(), 1, "{}: one replica link", node.url);
        assert_eq!(links[0].kind, LinkKind::Replica);
        assert!(links[0].settled, "{}: bootstrap settled", node.url);
        assert_eq!(links[0].phase, LinkPhase::Forward);
        assert!(
            node.state().sync.bootstrap_settled(true),
            "{}: readiness term holds",
            node.url
        );
        assert!(
            node.state().store.sync_feed().enabled(),
            "{}: the sibling asked, so the feed is on",
            node.url
        );
        assert!(
            node.state().replication_targets().is_empty(),
            "{}: a pulling sibling is not pushed to",
            node.url
        );
    }
    // The echo rule end to end: b's copy of a's write earned no row on b.
    let b_rows = b.state().store.sync_feed_page(0, 100).expect("page");
    assert_eq!(
        b_rows
            .iter()
            .map(|row| row.record_id.as_str())
            .collect::<Vec<_>>(),
        vec![reverse.as_str()],
        "only b's own write is in b's feed"
    );
}

// A-10: a sibling that fell off the feed re-bootstraps and misses nothing.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_sibling_that_fell_off_the_feed_rebootstraps_completely() {
    let a = node("local", |config| config.sync_feed_max_rows = 8).await;
    let b = node("local", |_| {}).await;
    a.see(&[&b]);
    b.see(&[&a]);
    let warm = a.write("warm", b"w").await;
    b.wait_for(&warm).await;

    // b loses sight of a: its link closes, its cursor stays persisted.
    b.see(&[]);
    assert!(b.state().sync.link_statuses().is_empty());
    let mut ids = Vec::new();
    for index in 0..20 {
        ids.push(a.write(&format!("while-away-{index}"), b"x").await);
    }
    assert!(
        a.state().store.sync_feed().floor() > 0,
        "the cap dropped the oldest rows while b was away"
    );

    b.see(&[&a]);
    for id in &ids {
        b.wait_for(id).await;
    }
    let metrics = b.state().metrics.render();
    assert!(
        metrics.contains("kura_sync_forward_fell_behind_total_total{reason=\"floor\"} 1"),
        "b recorded the 410: {metrics}"
    );
    let late = a.write("after-recovery", b"y").await;
    b.wait_for(&late).await;
}

// B-5 in one process: two regions of one, both gateways, converge through
// the ascending region read; the watermark follows the origin's records.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn regions_of_one_converge_through_the_ascending_read() {
    let us = node("us", |_| {}).await;
    let eu = node("eu", |_| {}).await;
    let early = eu.write("eu-early", b"e").await;

    us.see(&[&eu]);
    eu.see(&[&us]);
    assert!(us.state().sync.own_gateway());
    assert!(eu.state().sync.own_gateway());
    us.wait_for(&early).await;

    let late = eu.write("eu-late", b"l").await;
    us.wait_for(&late).await;
    let from_us = us.write("us-write", b"u").await;
    eu.wait_for(&from_us).await;

    let links = us.state().sync.link_statuses();
    assert_eq!(links.len(), 1);
    assert_eq!(links[0].kind, LinkKind::Region);
    assert_eq!(links[0].region, "eu");
    assert!(links[0].settled);
    let late_version = us
        .state()
        .store
        .manifest(&late)
        .expect("read")
        .expect("present")
        .version_ms;
    // The forward read advanced eu's watermark to the newest eu record it
    // consumed; a us record never moves it.
    for _ in 0..100 {
        if us.state().store.sync_watermark("eu").expect("read") >= Some(late_version) {
            break;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    assert!(us.state().store.sync_watermark("eu").expect("read") >= Some(late_version));
    assert_eq!(
        us.state()
            .store
            .manifest(&late)
            .expect("read")
            .expect("present")
            .origin_region
            .as_deref(),
        Some("eu"),
        "the origin travels with the body"
    );
    // Records that arrived cross-region earn feed rows on the receiver.
    assert!(
        us.state().store.sync_feed().head() == 0,
        "no sibling asked, so no rows yet"
    );
}
