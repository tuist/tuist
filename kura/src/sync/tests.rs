//! Ring A of `docs/replication-test-plan.md`: the store and endpoint rules
//! behind the arrival feed, the region watermarks and the ascending read.
//! Test names carry the plan's `A-n` tags.

use std::{collections::HashMap, time::Duration};

use axum::{
    body::{Body, to_bytes},
    http::{Request, StatusCode},
};
use serde_json::Value;
use tower::ServiceExt;

use crate::{
    artifact::producer::ArtifactProducer,
    http::{SyncForwardGone, SyncForwardHead, SyncForwardPage, internal_router},
    store::{ApplyProvenance, Store},
    sync::feed::{SyncFeedKind, SyncPosition},
    test_support::{TestContext, test_context},
    utils::{BackfillRecordKind, artifact_storage_id, now_ms},
};

async fn body_json(response: axum::response::Response) -> Value {
    let bytes = to_bytes(response.into_body(), usize::MAX)
        .await
        .expect("body should read");
    serde_json::from_slice(&bytes).expect("body should be json")
}

async fn write_inline(store: &Store, key: &str, body: &[u8]) -> String {
    store
        .persist_inline_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            key,
            "application/octet-stream",
            body,
        )
        .await
        .expect("inline write should persist");
    artifact_storage_id(ArtifactProducer::Xcode, "test-tenant", "ios", key)
}

async fn forward(context: &TestContext, query: &str) -> axum::response::Response {
    internal_router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri(format!(
                    "/_internal/sync/forward?peer=http://sibling:7443&region=local{query}"
                ))
                .body(Body::empty())
                .expect("request should build"),
        )
        .await
        .expect("route should respond")
}

async fn snapshot(context: &TestContext) -> SyncForwardHead {
    let response = forward(context, "").await;
    assert_eq!(response.status(), StatusCode::OK);
    serde_json::from_value(body_json(response).await).expect("head shape")
}

// A-1, A-2, A-6: rows for client writes and cross-region applies only,
// and only while a sibling has asked.
#[tokio::test]
async fn feed_rows_follow_the_echo_rule_and_the_activation() {
    let context = test_context(|_| {}).await;
    let store = &context.state.store;

    write_inline(store, "before-activation", b"a").await;
    assert_eq!(store.sync_feed().head(), 0, "no sibling asked, so no rows");
    assert!(!store.sync_feed().enabled());

    let head = snapshot(&context).await;
    assert!(store.sync_feed().enabled());
    assert_eq!(head.head, 0);

    let client_id = write_inline(store, "client-write", b"b").await;
    store
        .apply_replicated_inline_artifact_from_bytes_with(
            ApplyProvenance {
                origin_region: Some("eu"),
                sync_feed_row: true,
            },
            ArtifactProducer::Xcode,
            "ios",
            "from-region",
            "application/octet-stream",
            b"c",
            now_ms(),
            None,
            None,
        )
        .await
        .expect("region apply should persist");
    store
        .apply_replicated_inline_artifact_from_bytes_with(
            ApplyProvenance {
                origin_region: Some("local"),
                sync_feed_row: false,
            },
            ArtifactProducer::Xcode,
            "ios",
            "from-sibling",
            "application/octet-stream",
            b"d",
            now_ms(),
            None,
            None,
        )
        .await
        .expect("sibling apply should persist");
    // A no-op apply (older version than the stored one) writes no row.
    let outcome = store
        .apply_replicated_inline_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "client-write",
            "application/octet-stream",
            b"stale",
            1,
            None,
            None,
        )
        .await
        .expect("stale apply should resolve");
    assert!(!outcome.applied());
    store
        .delete_namespace("android")
        .await
        .expect("namespace delete should persist");

    let rows = store.sync_feed_page(0, 100).expect("page should read");
    let described: Vec<(SyncFeedKind, &str)> = rows
        .iter()
        .map(|row| (row.kind, row.record_id.as_str()))
        .collect();
    assert_eq!(
        described,
        vec![
            (
                SyncFeedKind::Record(BackfillRecordKind::InlineArtifact),
                client_id.as_str()
            ),
            (
                SyncFeedKind::Record(BackfillRecordKind::InlineArtifact),
                artifact_storage_id(ArtifactProducer::Xcode, "test-tenant", "ios", "from-region")
                    .as_str()
            ),
            (
                SyncFeedKind::Record(BackfillRecordKind::NamespaceTombstone),
                "android"
            ),
        ]
    );
    assert_eq!(rows[0].seq, 1);
    assert_eq!(rows[0].size, Some(1));
    assert!(rows[0].arrived_at_ms > 0);
    assert_eq!(store.sync_feed().head(), 3);

    store
        .sync_feed_deactivate()
        .await
        .expect("deactivation should succeed");
    assert!(store.sync_feed_page(0, 100).expect("page").is_empty());
    assert_eq!(
        store.sync_feed().floor(),
        3,
        "the dropped rows are below the floor"
    );
    write_inline(store, "after-deactivation", b"e").await;
    assert_eq!(store.sync_feed().head(), 3, "off again: no rows");
}

// A-23: the origin rides the manifest on both codecs.
#[tokio::test]
async fn origin_region_is_stamped_on_client_writes_and_carried_on_applies() {
    let context = test_context(|_| {}).await;
    let store = &context.state.store;
    let inline_id = write_inline(store, "inline", b"x").await;
    let segment = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Gradle,
            "android",
            "segment",
            "application/octet-stream",
            b"a body large enough to live in a segment",
        )
        .await
        .expect("segment write should persist");
    assert_eq!(
        store
            .manifest(&inline_id)
            .expect("read")
            .expect("present")
            .origin_region
            .as_deref(),
        Some("local")
    );
    assert_eq!(segment.origin_region.as_deref(), Some("local"));
    assert_eq!(
        store
            .manifest(&segment.artifact_id)
            .expect("read")
            .expect("present")
            .origin_region
            .as_deref(),
        Some("local"),
        "the segment record codec carries the trailing origin"
    );

    store
        .apply_replicated_inline_artifact_from_bytes_with(
            ApplyProvenance {
                origin_region: Some("eu"),
                sync_feed_row: true,
            },
            ArtifactProducer::Xcode,
            "ios",
            "carried",
            "application/octet-stream",
            b"y",
            now_ms(),
            None,
            None,
        )
        .await
        .expect("apply");
    let carried = artifact_storage_id(ArtifactProducer::Xcode, "test-tenant", "ios", "carried");
    assert_eq!(
        store
            .manifest(&carried)
            .expect("read")
            .expect("present")
            .origin_region
            .as_deref(),
        Some("eu")
    );
    store
        .apply_replicated_inline_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "pushed-by-old-peer",
            "application/octet-stream",
            b"z",
            now_ms(),
            None,
            None,
        )
        .await
        .expect("apply");
    let pushed = artifact_storage_id(
        ArtifactProducer::Xcode,
        "test-tenant",
        "ios",
        "pushed-by-old-peer",
    );
    assert_eq!(
        store
            .manifest(&pushed)
            .expect("read")
            .expect("present")
            .origin_region,
        None,
        "an old peer forwards no origin"
    );
}

// A-3: seq and incarnation across a reopen and across an empty volume.
#[tokio::test]
async fn seq_and_incarnation_survive_a_reopen_and_a_rebuild_mints_a_new_one() {
    let shared = tempfile::tempdir().expect("temp dir");
    let dirs = (shared.path().join("data"), shared.path().join("tmp"));
    let (incarnation, head) = {
        let dirs = dirs.clone();
        let context = test_context(move |config| {
            config.data_dir = dirs.0;
            config.tmp_dir = dirs.1;
        })
        .await;
        snapshot(&context).await;
        write_inline(&context.state.store, "one", b"1").await;
        write_inline(&context.state.store, "two", b"2").await;
        (
            context.state.store.sync_feed().incarnation(),
            context.state.store.sync_feed().head(),
        )
    };
    assert_eq!(head, 2);
    let reopened = test_context(move |config| {
        config.data_dir = dirs.0;
        config.tmp_dir = dirs.1;
    })
    .await;
    let feed = reopened.state.store.sync_feed();
    assert_eq!(feed.incarnation(), incarnation);
    assert_eq!(feed.head(), 2, "the tail on disk is the head");
    assert!(feed.enabled(), "activation survives a restart");
    write_inline(&reopened.state.store, "three", b"3").await;
    assert_eq!(feed.head(), 3, "seq resumes above the persisted tail");

    let fresh = test_context(|_| {}).await;
    assert_ne!(fresh.state.store.sync_feed().incarnation(), incarnation);
}

// A-4: trimming below the consumer cursor, in batches, with a floor.
#[tokio::test]
async fn feed_trims_below_the_lowest_consumer_cursor_in_batches() {
    let context = test_context(|_| {}).await;
    let store = &context.state.store;
    snapshot(&context).await;
    for index in 0..1_100 {
        write_inline(store, &format!("key-{index}"), b"v").await;
    }
    assert_eq!(store.sync_feed().head(), 1_100);

    // The snapshot registered the sibling at the head it saw; that pin is
    // what keeps its backward-pass window intact, so release it here.
    store.sync_feed().forget_consumer("http://sibling:7443");
    store.sync_feed().note_consumer("a", 1_050);
    store.sync_feed().note_consumer("b", 500);
    store.sync_feed_trim_below_consumers().await.expect("trim");
    assert_eq!(
        store.sync_feed().floor(),
        0,
        "500 rows is below the trim batch"
    );
    store.sync_feed().note_consumer("b", 1_040);
    store.sync_feed_trim_below_consumers().await.expect("trim");
    assert_eq!(
        store.sync_feed().floor(),
        1_040,
        "the lowest live cursor decides"
    );
    let rows = store.sync_feed_page(0, 10).expect("page");
    assert_eq!(rows[0].seq, 1_041, "rows at or below the floor are gone");
}

// A-5: the cap drops oldest and never refuses a write.
#[tokio::test]
async fn feed_cap_drops_the_oldest_rows_instead_of_blocking() {
    let context = test_context(|config| config.sync_feed_max_rows = 10).await;
    let store = &context.state.store;
    snapshot(&context).await;
    for index in 0..15 {
        write_inline(store, &format!("key-{index}"), b"v").await;
    }
    assert_eq!(store.sync_feed().head(), 15);
    assert_eq!(store.sync_feed().floor(), 5);
    assert_eq!(store.sync_feed().dropped_total(), 5);
    let rows = store.sync_feed_page(0, 100).expect("page");
    assert_eq!(rows.first().map(|row| row.seq), Some(6));
    assert_eq!(rows.len(), 10);
    assert!(
        context
            .state
            .metrics
            .render()
            .contains("kura_sync_forward_index_dropped_total_total 5"),
        "the drop counter is exported"
    );
}

// A-7: the four cases of the forward endpoint.
#[tokio::test]
async fn forward_endpoint_answers_head_entries_and_gone() {
    let context = test_context(|config| config.sync_feed_max_rows = 4).await;
    let store = &context.state.store;

    let mismatched = internal_router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri("/_internal/sync/forward?peer=http://x:1&region=elsewhere")
                .body(Body::empty())
                .expect("request"),
        )
        .await
        .expect("route");
    assert_eq!(mismatched.status(), StatusCode::BAD_REQUEST);

    let head = snapshot(&context).await;
    assert_eq!(head.head, 0);
    assert_eq!(head.floor, 0);
    assert!(head.watermarks.is_empty());
    let incarnation = head.incarnation.clone();

    write_inline(store, "one", b"1").await;
    write_inline(store, "two", b"2").await;
    let response = forward(&context, &format!("&after={incarnation}:0&limit=1")).await;
    assert_eq!(response.status(), StatusCode::OK);
    let page: SyncForwardPage = serde_json::from_value(body_json(response).await).expect("page");
    assert_eq!(page.entries.len(), 1);
    assert_eq!((page.next, page.head), (1, 2));
    assert_eq!(page.entries[0].kind, "inline_artifact");
    let response = forward(&context, &format!("&after={incarnation}:1")).await;
    let page: SyncForwardPage = serde_json::from_value(body_json(response).await).expect("page");
    assert_eq!(page.entries.len(), 1);
    assert_eq!(page.next, 2);
    let response = forward(&context, &format!("&after={incarnation}:2")).await;
    let page: SyncForwardPage = serde_json::from_value(body_json(response).await).expect("page");
    assert!(
        page.entries.is_empty(),
        "caught up without a wait returns at once"
    );

    let response = forward(&context, &format!("&after={incarnation}:9")).await;
    assert_eq!(response.status(), StatusCode::GONE);
    let gone: SyncForwardGone = serde_json::from_value(body_json(response).await).expect("gone");
    assert_eq!(gone.error, "ahead");

    let response = forward(&context, "&after=00000000000000ff:1").await;
    assert_eq!(response.status(), StatusCode::GONE);
    let gone: SyncForwardGone = serde_json::from_value(body_json(response).await).expect("gone");
    assert_eq!(gone.error, "incarnation");

    for index in 0..6 {
        write_inline(store, &format!("cap-{index}"), b"v").await;
    }
    let response = forward(&context, &format!("&after={incarnation}:2")).await;
    assert_eq!(response.status(), StatusCode::GONE);
    let gone: SyncForwardGone = serde_json::from_value(body_json(response).await).expect("gone");
    assert_eq!(gone.error, "floor");
    assert_eq!(gone.floor, 4);
    assert_eq!(gone.head, 8);
}

// A-8: a long-poll wakes on the next commit and returns at the deadline.
#[tokio::test]
async fn forward_endpoint_long_polls_until_a_commit_lands() {
    let context = test_context(|_| {}).await;
    let head = snapshot(&context).await;
    let incarnation = head.incarnation.clone();

    let started = std::time::Instant::now();
    let idle = forward(&context, &format!("&after={incarnation}:0&wait=1")).await;
    let page: SyncForwardPage = serde_json::from_value(body_json(idle).await).expect("page");
    assert!(page.entries.is_empty());
    assert!(
        started.elapsed() >= Duration::from_millis(900),
        "held for the wait"
    );

    let writer = context.state.clone();
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_millis(200)).await;
        write_inline(&writer.store, "late", b"1").await;
    });
    let started = std::time::Instant::now();
    let woken = forward(&context, &format!("&after={incarnation}:0&wait=10")).await;
    let page: SyncForwardPage = serde_json::from_value(body_json(woken).await).expect("page");
    assert_eq!(page.entries.len(), 1);
    assert!(
        started.elapsed() < Duration::from_secs(5),
        "woke well before the wait"
    );
}

// A-11, A-12: watermarks merge by max and travel as feed rows.
#[tokio::test]
async fn region_watermarks_merge_by_max_and_ride_the_feed() {
    let context = test_context(|_| {}).await;
    let store = &context.state.store;
    snapshot(&context).await;
    assert!(
        store
            .advance_sync_watermark("eu", 100)
            .await
            .expect("advance")
    );
    assert!(
        !store
            .advance_sync_watermark("eu", 90)
            .await
            .expect("advance")
    );
    assert!(
        store
            .advance_sync_watermark("ap", 50)
            .await
            .expect("advance")
    );
    assert_eq!(store.sync_watermark("eu").expect("read"), Some(100));
    assert_eq!(
        store.sync_watermarks().expect("read"),
        [("ap".to_string(), 50), ("eu".to_string(), 100)]
            .into_iter()
            .collect()
    );
    let rows = store.sync_feed_page(0, 10).expect("page");
    assert_eq!(rows.len(), 2, "only the advances that moved earned a row");
    assert_eq!(rows[0].kind, SyncFeedKind::Watermark);
    assert_eq!(
        (rows[0].record_id.as_str(), rows[0].version_ms),
        ("eu", 100)
    );
    let head = snapshot(&context).await;
    assert_eq!(head.watermarks.get("eu"), Some(&100));

    // Cursor persistence, the other half of the sibling's position.
    let position = SyncPosition {
        incarnation: 7,
        seq: 42,
    };
    store
        .write_sync_cursor("http://peer", position)
        .expect("write");
    assert_eq!(
        store.sync_cursor("http://peer").expect("read"),
        Some(position)
    );
    store.clear_sync_cursor("http://peer").expect("clear");
    assert_eq!(store.sync_cursor("http://peer").expect("read"), None);
}

// A-13: the ascending read filters by origin, pages by full key and stops
// at the settle guard; `now` rides every page.
#[tokio::test]
async fn ascending_index_read_filters_pages_and_settles() {
    let context = test_context(|_| {}).await;
    let store = &context.state.store;
    let base = now_ms() - 10_000;
    let mut apply = |key: &str, version_ms: u64, origin: Option<&str>| {
        let store = store.clone();
        let key = key.to_owned();
        let origin = origin.map(str::to_owned);
        async move {
            store
                .apply_replicated_inline_artifact_from_bytes_with(
                    ApplyProvenance {
                        origin_region: origin.as_deref(),
                        sync_feed_row: true,
                    },
                    ArtifactProducer::Xcode,
                    "ios",
                    &key,
                    "application/octet-stream",
                    b"v",
                    version_ms,
                    None,
                    None,
                )
                .await
                .expect("apply");
        }
    };
    apply("eu-1", base + 1, Some("eu")).await;
    apply("local-1", base + 1, Some("local")).await;
    apply("unknown-1", base + 2, None).await;
    apply("eu-2", base + 2, Some("eu")).await;
    apply("local-2", base + 3, Some("local")).await;
    apply("young", now_ms() + 1_000, Some("local")).await;

    let page = store
        .backfill_index_page_ascending(base, None, 2, now_ms(), Some("local"))
        .expect("page");
    assert_eq!(
        page.entries
            .iter()
            .map(|row| row.version_ms)
            .collect::<Vec<_>>(),
        vec![base + 1, base + 2],
        "own origin and unknown origin are listed, foreign rows skipped"
    );
    let next = page.next_after.expect("more to come");
    let page = store
        .backfill_index_page_ascending(base, Some(&next), 10, now_ms(), Some("local"))
        .expect("page");
    assert_eq!(
        page.entries
            .iter()
            .map(|row| row.version_ms)
            .collect::<Vec<_>>(),
        vec![base + 3],
        "the young row sits above the settle guard"
    );
    assert!(page.next_after.is_none(), "caught up");
    let unfiltered = store
        .backfill_index_page_ascending(base, None, 10, now_ms(), None)
        .expect("page");
    assert_eq!(unfiltered.entries.len(), 5);

    store
        .run_backfill_index_build()
        .expect("index build should run");
    let response = internal_router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri(format!(
                    "/_internal/backfill/entries?order=asc&from_version_ms={}&origin_region=eu&limit=10",
                    base
                ))
                .body(Body::empty())
                .expect("request"),
        )
        .await
        .expect("route");
    assert_eq!(response.status(), StatusCode::OK);
    let body = body_json(response).await;
    let versions: Vec<u64> = body["entries"]
        .as_array()
        .expect("entries")
        .iter()
        .map(|entry| entry["version_ms"].as_u64().expect("version"))
        .collect();
    assert_eq!(versions, vec![base + 1, base + 2, base + 2]);
    assert!(
        body["now"].as_u64().is_some(),
        "the page carries the serving clock"
    );

    let rejected = internal_router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri("/_internal/backfill/entries?origin_region=eu")
                .body(Body::empty())
                .expect("request"),
        )
        .await
        .expect("route");
    assert_eq!(
        rejected.status(),
        StatusCode::BAD_REQUEST,
        "the filter needs order=asc"
    );

    let params: HashMap<String, String> = HashMap::new();
    assert!(params.is_empty());
}

// The status probe advertises what the role rule needs.
#[tokio::test]
async fn status_advertises_traffic_state_pulling_and_incarnation() {
    let context = test_context(|config| config.replication_pull = true).await;
    let response = internal_router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri("/_internal/status")
                .body(Body::empty())
                .expect("request"),
        )
        .await
        .expect("route");
    let body = body_json(response).await;
    assert_eq!(body["pulling"], true);
    assert_eq!(body["traffic_state"], "joining");
    assert_eq!(
        body["incarnation"].as_str().map(str::len),
        Some(16),
        "incarnation is a 16-hex-digit id"
    );
    assert!(context.state.set_replication_pull(false));
    assert!(!context.state.replication_pull());
}
