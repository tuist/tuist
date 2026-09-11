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
    state::SharedState,
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
        4,
        "the dropped rows and lifetime boundary are below the floor"
    );
    write_inline(store, "after-deactivation", b"e").await;
    assert_eq!(store.sync_feed().head(), 4, "off again: no rows");
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

// A-29a: an exhausted page reports the head, so a gap at the head — the
// seqs of allocations that were aborted before staging — neither pins the
// requester's cursor nor shows as lag (D-26).
#[tokio::test]
async fn an_exhausted_forward_page_reports_the_head_over_an_aborted_gap() {
    let context = test_context(|_| {}).await;
    let store = &context.state.store;
    let head = snapshot(&context).await;
    let incarnation = head.incarnation.clone();
    write_inline(store, "one", b"1").await;

    // Two allocations that never stage a row: the contiguous head passes
    // them, and no row will ever fill their seqs.
    let feed = store.sync_feed();
    drop((feed.allocate(), feed.allocate()));
    assert_eq!(feed.head(), 3, "the head passed the aborted seqs");

    let response = forward(&context, &format!("&after={incarnation}:1")).await;
    let page: SyncForwardPage = serde_json::from_value(body_json(response).await).expect("page");
    assert!(page.entries.is_empty(), "the gap holds no rows");
    assert_eq!(
        (page.next, page.head),
        (3, 3),
        "the scan reached the head, so the cursor may go there"
    );
    assert_eq!(
        page.head.saturating_sub(page.next),
        0,
        "no phantom lag remains"
    );

    // A page cut short by the limit still reports its last row: the scan
    // says nothing about what is above it.
    let response = forward(&context, &format!("&after={incarnation}:0&limit=1")).await;
    let page: SyncForwardPage = serde_json::from_value(body_json(response).await).expect("page");
    assert_eq!(page.entries.len(), 1);
    assert_eq!((page.next, page.head), (1, 3));

    // A row above the gap is served from the reported cursor as usual.
    write_inline(store, "two", b"2").await;
    let response = forward(&context, &format!("&after={incarnation}:3")).await;
    let page: SyncForwardPage = serde_json::from_value(body_json(response).await).expect("page");
    assert_eq!(page.entries.len(), 1);
    assert_eq!((page.next, page.head), (4, 4));
}

#[tokio::test]
async fn reactivation_rejects_a_cursor_from_the_previous_feed_lifetime() {
    let context = test_context(|_| {}).await;
    let first = snapshot(&context).await;
    write_inline(&context.state.store, "before-disable", b"1").await;
    let caught_up = forward(&context, &format!("&after={}:0", first.incarnation)).await;
    let caught_up: SyncForwardPage =
        serde_json::from_value(body_json(caught_up).await).expect("page");

    context
        .state
        .store
        .sync_feed_deactivate()
        .await
        .expect("deactivate");
    write_inline(&context.state.store, "while-disabled", b"2").await;
    let second = snapshot(&context).await;
    assert!(
        second.floor > caught_up.next,
        "lifetime boundary raises the floor"
    );

    let stale = forward(
        &context,
        &format!("&after={}:{}", first.incarnation, caught_up.next),
    )
    .await;
    assert_eq!(stale.status(), StatusCode::GONE);
    let gone: SyncForwardGone = serde_json::from_value(body_json(stale).await).expect("gone");
    assert_eq!(gone.error, "floor");
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
    let apply = |key: &str, version_ms: u64, origin: Option<&str>| {
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
    assert!(
        page.next_after.is_some(),
        "the cursor moves whenever the scan did, caught up or not (D-14)"
    );
    let cursor = page.next_after.expect("cursor");
    let page = store
        .backfill_index_page_ascending(base, Some(&cursor), 10, now_ms(), Some("local"))
        .expect("page");
    assert!(
        page.entries.is_empty() && page.next_after.is_none(),
        "nothing scanned: caught up"
    );
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

// A-28b: a write this node generates takes its version from the feed
// ticket's stamp, so versions order like seqs; an explicit version — a
// replicated apply, or a delete carrying the origin's — is never rewritten.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn server_generated_versions_come_from_the_feed_ticket() {
    let context = test_context(|_| {}).await;
    let store = &context.state.store;
    snapshot(&context).await;

    let mut writes = tokio::task::JoinSet::new();
    for index in 0..16 {
        let store = store.clone();
        writes.spawn(async move {
            store
                .persist_inline_artifact_from_bytes(
                    ArtifactProducer::Xcode,
                    "ios",
                    &format!("concurrent-{index}"),
                    "application/octet-stream",
                    b"v",
                )
                .await
                .expect("write should persist")
        });
    }
    let mut versions = HashMap::new();
    while let Some(manifest) = writes.join_next().await {
        let manifest = manifest.expect("write task");
        versions.insert(manifest.artifact_id.clone(), manifest.version_ms);
    }

    let rows = store.sync_feed_page(0, 100).expect("page");
    assert_eq!(rows.len(), 16, "one row per write");
    for row in &rows {
        assert_eq!(
            row.version_ms, row.arrived_at_ms,
            "the row's version is the stamp its seq was allocated at"
        );
        assert_eq!(
            versions.get(&row.record_id),
            Some(&row.version_ms),
            "the manifest carries the same version as its row"
        );
    }
    let ordered: Vec<u64> = rows.iter().map(|row| row.version_ms).collect();
    let mut sorted = ordered.clone();
    sorted.sort_unstable();
    assert_eq!(
        ordered, sorted,
        "concurrent writes are versioned in seq order"
    );

    // An explicit version rides through untouched, and so does its row.
    let base = now_ms() - 60_000;
    store
        .apply_replicated_inline_artifact_from_bytes_with(
            ApplyProvenance {
                origin_region: Some("eu"),
                sync_feed_row: true,
            },
            ArtifactProducer::Xcode,
            "ios",
            "from-eu",
            "application/octet-stream",
            b"v",
            base,
            None,
            None,
        )
        .await
        .expect("apply");
    let applied = artifact_storage_id(ArtifactProducer::Xcode, "test-tenant", "ios", "from-eu");
    assert_eq!(
        store
            .manifest(&applied)
            .expect("read")
            .expect("present")
            .version_ms,
        base,
        "a replicated apply keeps the origin's stamp"
    );
    let row = store
        .sync_feed_page(0, 100)
        .expect("page")
        .into_iter()
        .find(|row| row.record_id == applied)
        .expect("the cross-region apply earned a row");
    assert_eq!(row.version_ms, base);
    assert!(
        row.arrived_at_ms > row.version_ms,
        "its arrival is now, its version is the origin's"
    );

    // Tombstones follow the same split: local stamped, replicated kept.
    let local = store.delete_namespace("ios").await.expect("delete");
    let tombstone = store
        .sync_feed_page(0, 100)
        .expect("page")
        .into_iter()
        .find(|row| row.kind == SyncFeedKind::Record(BackfillRecordKind::NamespaceTombstone))
        .expect("the delete earned a row");
    assert_eq!(
        (tombstone.version_ms, tombstone.arrived_at_ms),
        (local, local),
        "a local delete is stamped from its ticket"
    );
    store
        .apply_replicated_namespace_delete("android", local + 5)
        .await
        .expect("replicated delete");
    let replicated = store
        .sync_feed_page(0, 100)
        .expect("page")
        .into_iter()
        .rfind(|row| row.kind == SyncFeedKind::Record(BackfillRecordKind::NamespaceTombstone))
        .expect("row");
    assert_eq!(replicated.version_ms, local + 5);
}

async fn ascending(context: &TestContext, query: &str) -> Value {
    let response = internal_router(context.state.clone())
        .oneshot(
            Request::builder()
                .uri(format!(
                    "/_internal/backfill/entries?order=asc&origin_region=local&limit=10{query}"
                ))
                .body(Body::empty())
                .expect("request"),
        )
        .await
        .expect("route");
    assert_eq!(response.status(), StatusCode::OK);
    body_json(response).await
}

fn listed_versions(page: &Value) -> Vec<u64> {
    page["entries"]
        .as_array()
        .expect("entries")
        .iter()
        .map(|entry| entry["version_ms"].as_u64().expect("version"))
        .collect()
}

// A-28c: the ascending listing stops at the coordinator's bound, so an
// entry a replica link could still deliver below it is withheld — and the
// cursor the requester was given earlier still reaches it once it is not.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn the_ascending_listing_stops_at_the_replica_link_frontier() {
    let context = test_context(|config| config.replication_pull = true).await;
    let store = &context.state.store;
    let base = now_ms() - 60_000;
    for (key, version_ms) in [("early", base + 10), ("late", base + 20)] {
        store
            .apply_replicated_inline_artifact_from_bytes_with(
                ApplyProvenance {
                    origin_region: Some("local"),
                    sync_feed_row: true,
                },
                ArtifactProducer::Xcode,
                "ios",
                key,
                "application/octet-stream",
                b"v",
                version_ms,
                None,
                None,
            )
            .await
            .expect("apply");
    }
    store.run_backfill_index_build().expect("index build");

    let sibling = "http://127.0.0.1:1";
    context
        .state
        .apply_peer_views(vec![crate::sync::roles::PeerView {
            url: sibling.to_owned(),
            region: "local".to_owned(),
            serving: true,
            draining: false,
            pulling: true,
            knows_me: true,
        }]);
    context.state.sync.evaluate(&context.state);

    // The link has yet to report: nothing may be listed at all, because
    // anything it has not delivered could sort below what we would show.
    assert_eq!(context.state.sync.listing_bound(&context.state), 0);
    let page = ascending(&context, &format!("&from_version_ms={base}")).await;
    assert!(listed_versions(&page).is_empty(), "held: {page}");

    context
        .state
        .sync
        .set_replica_link_frontier(sibling, base + 20);
    assert_eq!(
        context.state.sync.listing_bound(&context.state),
        base + 19,
        "the bound is exclusive of the frontier"
    );
    let page = ascending(&context, &format!("&from_version_ms={base}")).await;
    assert_eq!(
        listed_versions(&page),
        vec![base + 10],
        "the entry at the frontier is withheld"
    );
    let cursor = page["next_after"].as_str().expect("cursor").to_owned();

    context
        .state
        .sync
        .set_replica_link_frontier(sibling, now_ms());
    let page = ascending(
        &context,
        &format!(
            "&from_version_ms={base}&after={}",
            crate::utils::url_encode(&cursor)
        ),
    )
    .await;
    assert_eq!(
        listed_versions(&page),
        vec![base + 20],
        "the cursor from the bounded page still reaches the withheld entry"
    );
}

// A-28d: with no feed and no links — a region of one — the bound is the
// settle window, exactly as before D-24.
#[tokio::test]
async fn without_a_feed_the_bound_is_the_settle_window() {
    let context = test_context(|_| {}).await;
    assert!(!context.state.store.sync_feed().enabled());
    let settle = context.state.config.sync_region_settle_ms;
    let bound = context.state.sync.listing_bound(&context.state);
    let expected = now_ms() - settle;
    assert!(
        bound <= expected && expected - bound < 1_000,
        "bound {bound} should sit a settle window ({settle} ms) behind {expected}"
    );

    let store = &context.state.store;
    write_inline(store, "young", b"v").await;
    store.run_backfill_index_build().expect("index build");
    let page = ascending(&context, "&from_version_ms=0").await;
    assert!(
        listed_versions(&page).is_empty(),
        "a write inside the settle window is not listed yet: {page}"
    );
}

// The status probe advertises what the role rule needs.
#[tokio::test]
async fn status_advertises_traffic_state_pulling_and_incarnation() {
    let context = test_context(|config| config.replication_pull = true).await;
    let _ = snapshot(&context).await;
    assert!(context.state.store.sync_feed().enabled());
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
    assert!(
        context.state.store.sync_feed().enabled(),
        "rollback can leave a feed active for an older sibling until its stale window expires"
    );
}

// A-25 (design §11.2): a pulling peer whose advertised membership view does
// not name this node cannot dial back, so pull reaches it in neither
// direction and push stays its only leg.
#[tokio::test]
async fn a_pulling_peer_that_cannot_dial_back_stays_a_push_target() {
    let context = test_context(|config| {
        config.replication_pull = true;
        config.node_url = "http://runner:7443".into();
        config.peers = vec!["http://selfhosted:7443".into()];
    })
    .await;
    let state = &context.state;
    let view = |url: &str, knows_me: bool| crate::sync::roles::PeerView {
        url: url.into(),
        region: "local".into(),
        serving: true,
        draining: false,
        pulling: true,
        knows_me,
    };

    state.apply_peer_views(vec![view("http://selfhosted:7443", false)]);
    let targets = state.rebuild_replication_targets().await;
    assert_eq!(
        *targets,
        vec!["http://selfhosted:7443".to_string()],
        "a pulling peer that does not name us is still pushed to"
    );

    // The same peer while unreachable: the stickiness of D-20 never applied
    // to it, so it does not drift off the push targets during its absence.
    state.apply_peer_views(vec![]);
    let targets = state.rebuild_replication_targets().await;
    assert_eq!(
        *targets,
        vec!["http://selfhosted:7443".to_string()],
        "an absent peer that never knew us keeps its push leg"
    );

    // Its view now names us: it can dial back, and pull replaces push.
    state.apply_peer_views(vec![view("http://selfhosted:7443", true)]);
    let targets = state.rebuild_replication_targets().await;
    assert!(
        targets.is_empty(),
        "a pulling peer that names us leaves the push targets, got {targets:?}"
    );

    // And now D-20 applies: it keeps its exemption across an absence.
    state.apply_peer_views(vec![]);
    let targets = state.rebuild_replication_targets().await;
    assert!(
        targets.is_empty(),
        "a peer that pulled and knew us stays off push while unreachable, got {targets:?}"
    );
}

// A-25: the status probe advertises the membership view the rule above reads.
#[tokio::test]
async fn status_advertises_the_membership_view_node_urls() {
    let context = test_context(|config| config.replication_pull = true).await;
    let status = |state: SharedState| async move {
        let response = internal_router(state)
            .oneshot(
                Request::builder()
                    .uri("/_internal/status")
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("route");
        body_json(response).await
    };

    let body = status(context.state.clone()).await;
    assert_eq!(
        body["peers"].as_array().map(Vec::len),
        Some(0),
        "a node with no view advertises an empty list, never a missing field"
    );

    context
        .state
        .apply_peer_views(vec![crate::sync::roles::PeerView {
            url: "http://sibling:7443".into(),
            region: "local".into(),
            serving: true,
            draining: false,
            pulling: true,
            knows_me: true,
        }]);
    let body = status(context.state.clone()).await;
    assert_eq!(body["peers"][0], "http://sibling:7443");
}

// D-20: a pulling peer that stops answering stays off the push targets
// until it comes back saying otherwise.
#[tokio::test]
async fn a_pulling_peer_stays_off_push_while_unreachable() {
    let context = test_context(|config| {
        config.replication_pull = true;
        config.peers = vec!["http://sibling:7443".into(), "http://old:7443".into()];
    })
    .await;
    let state = &context.state;
    let view = |url: &str, pulling: bool| crate::sync::roles::PeerView {
        url: url.into(),
        region: "local".into(),
        serving: true,
        draining: false,
        pulling,
        knows_me: true,
    };
    state.apply_peer_views(vec![
        view("http://sibling:7443", true),
        view("http://old:7443", false),
    ]);
    let targets = state.rebuild_replication_targets().await;
    assert_eq!(
        *targets,
        vec!["http://old:7443".to_string()],
        "the pulling sibling is not pushed to"
    );

    // The sibling stops answering: it leaves the view but keeps its flag.
    state.apply_peer_views(vec![view("http://old:7443", false)]);
    let targets = state.rebuild_replication_targets().await;
    assert_eq!(
        *targets,
        vec!["http://old:7443".to_string()],
        "still not pushed to while unreachable"
    );

    // It comes back rolled back to a binary that does not pull.
    state.apply_peer_views(vec![
        view("http://sibling:7443", false),
        view("http://old:7443", false),
    ]);
    let mut targets = (*state.rebuild_replication_targets().await).clone();
    targets.sort();
    assert_eq!(
        targets,
        vec![
            "http://old:7443".to_string(),
            "http://sibling:7443".to_string()
        ]
    );
}

// A-26: the serving aggregate follows the membership view unless pinned.
#[tokio::test]
async fn the_peer_serving_aggregate_follows_the_membership_view() {
    use crate::sync::roles::PeerView;
    let view = |index: usize| PeerView {
        url: format!("http://peer-{index}.kura.internal:7443"),
        region: "local".to_owned(),
        serving: true,
        draining: false,
        pulling: false,
        knows_me: true,
    };
    let derived = test_context(|config| {
        config.sync_peer_bodies_slots_per_peer = 2;
        config.sync_peer_serving_max_inflight = None;
    })
    .await;
    assert_eq!(derived.state.backfill_bodies_peer_slots.max_inflight(), 8);
    derived.state.apply_peer_views((0..3).map(view).collect());
    assert_eq!(
        derived.state.backfill_bodies_peer_slots.max_inflight(),
        8,
        "three peers holding two slots each sit under the floor"
    );
    derived.state.apply_peer_views((0..6).map(view).collect());
    assert_eq!(derived.state.backfill_bodies_peer_slots.max_inflight(), 12);
    derived.state.apply_peer_views(Vec::new());
    assert_eq!(derived.state.backfill_bodies_peer_slots.max_inflight(), 8);

    let pinned = test_context(|config| {
        config.sync_peer_bodies_slots_per_peer = 1;
        config.sync_peer_serving_max_inflight = Some(3);
    })
    .await;
    pinned.state.apply_peer_views((0..20).map(view).collect());
    assert_eq!(pinned.state.backfill_bodies_peer_slots.max_inflight(), 3);
}
