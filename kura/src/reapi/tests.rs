use super::*;
use std::{convert::Infallible, time::Duration};

#[test]
fn actioncache_snapshot_index_encodes_full_and_delta_views() {
    let mut index = NamespaceSnapshotIndex::new();
    let shared = index.intern_node(vec![0xBB], [8; 32], 20);
    let a_root = index.intern_node(vec![0xAA, 0xAA], [7; 32], 10);
    let b_root = index.intern_node(vec![0xCC], [9; 32], 30);
    assert_eq!(index.intern_node(vec![0xBB], [8; 32], 20), shared, "dedup");
    index.entries.insert(
        [1; 32],
        SnapshotIndexEntry {
            version_ms: 100,
            nodes: vec![a_root, shared],
        },
    );
    index.entries.insert(
        [2; 32],
        SnapshotIndexEntry {
            version_ms: 200,
            nodes: vec![b_root, shared],
        },
    );

    let read_u32 = |bytes: &[u8], at: usize| {
        u32::from_le_bytes(bytes[at..at + 4].try_into().unwrap()) as usize
    };

    // Full view: both keys, watermark = newest version, node table deduped.
    let full = index.encode_body(0, SNAPSHOT_MIN_BUDGET_BYTES);
    assert_eq!(&full[..4], b"TSNP");
    assert_eq!(full[4], 2);
    assert_eq!(u64::from_le_bytes(full[5..13].try_into().unwrap()), 200);
    assert_eq!(read_u32(&full, 13), 3, "three unique nodes");

    // Delta view: only the key strictly newer than the cursor, with a
    // self-contained node table (root + the shared node).
    let delta = index.encode_body(150, SNAPSHOT_MIN_BUDGET_BYTES);
    assert_eq!(u64::from_le_bytes(delta[5..13].try_into().unwrap()), 200);
    let node_count = read_u32(&delta, 13);
    assert_eq!(node_count, 2);
    // Walk past the node table to the key section.
    let mut at = 17;
    for _ in 0..node_count {
        let len = delta[at] as usize;
        at += 1 + len + 32 + 8;
    }
    assert_eq!(read_u32(&delta, at), 1, "one delta key");
    assert_eq!(&delta[at + 4..at + 36], &[2u8; 32]);

    // The cursor is INCLUSIVE: millisecond versions are not unique, so a
    // write landing in an already-served millisecond must reappear on the
    // next delta rather than being skipped until the full refresh. The
    // boundary key is re-sent (merge is idempotent client-side).
    let boundary = index.encode_body(200, SNAPSHOT_MIN_BUDGET_BYTES);
    assert_eq!(u64::from_le_bytes(boundary[5..13].try_into().unwrap()), 200);
    let node_count = read_u32(&boundary, 13);
    assert_eq!(node_count, 2, "boundary key re-sent");

    // Nothing at or past the cursor: an empty delta echoes it.
    let empty = index.encode_body(300, SNAPSHOT_MIN_BUDGET_BYTES);
    assert_eq!(u64::from_le_bytes(empty[5..13].try_into().unwrap()), 300);
    let node_count = read_u32(&empty, 13);
    assert_eq!(node_count, 0);
}

#[test]
fn actioncache_snapshot_compressed_envelope_round_trips() {
    let mut index = NamespaceSnapshotIndex::new();
    let root = index.intern_node(vec![0xAA, 0xAA], [7; 32], 10);
    let shared = index.intern_node(vec![0xBB], [8; 32], 20);
    index.entries.insert(
        [1; 32],
        SnapshotIndexEntry {
            version_ms: 100,
            nodes: vec![root, shared],
        },
    );

    // The compressed wire is the TSNZ envelope: magic, version 1, the
    // uncompressed length, then the zstd stream that decodes to exactly
    // the uncompressed body the same view would have produced.
    let wire = index.encode(0);
    assert_eq!(&wire[..4], b"TSNZ");
    assert_eq!(wire[4], 1);
    let declared = u64::from_le_bytes(wire[5..13].try_into().unwrap()) as usize;
    let body = zstd::stream::decode_all(&wire[13..]).expect("zstd body should decode");
    assert_eq!(body.len(), declared, "declared length matches the body");
    assert_eq!(
        body,
        index.encode_body(0, SNAPSHOT_MIN_BUDGET_BYTES),
        "body equals the plain TSNP view"
    );
}

#[test]
fn actioncache_snapshot_index_compacts_stranded_nodes() {
    let mut index = NamespaceSnapshotIndex::new();
    // A churned namespace: interned nodes whose entries are gone.
    for stranded in 0..SNAPSHOT_COMPACT_MIN_GARBAGE as u64 {
        index.intern_node(stranded.to_le_bytes().to_vec(), [3; 32], stranded);
    }
    let live = index.intern_node(vec![0xAA], [7; 32], 10);
    index.entries.insert(
        [1; 32],
        SnapshotIndexEntry {
            version_ms: 100,
            nodes: vec![live],
        },
    );

    index.compact_nodes();

    assert_eq!(index.nodes.len(), 1, "stranded nodes swept");
    assert_eq!(index.node_index.len(), 1);
    let entry = index.entries.get(&[1; 32]).unwrap();
    assert_eq!(entry.nodes, vec![0], "entry remapped onto the new table");
    assert_eq!(index.nodes[0].llcas, vec![0xAA]);
    assert_eq!(index.node_index.get(&vec![0xAA]).copied(), Some(0));
    // The rebuilt table keeps serving: the full view carries the live key.
    let full = index.encode_body(0, SNAPSHOT_MIN_BUDGET_BYTES);
    assert_eq!(u64::from_le_bytes(full[5..13].try_into().unwrap()), 100);
}

/// Marks a cached index stale so the next serve kicks a reconcile
/// (serves return the cached view and reconcile in the background once
/// the freshness window lapses).
fn backdate_snapshot_index(service: &ReapiService, namespace_id: &str) {
    if let Some(index) = service
        .snapshot_cache
        .indexes
        .lock()
        .unwrap()
        .get_mut(namespace_id)
    {
        index.reconciled_at = Instant::now() - 2 * SNAPSHOT_RECONCILE_INTERVAL;
    }
}

/// Waits until the namespace's cached index satisfies `done` (background
/// reconciles land asynchronously after a stale serve).
async fn wait_for_snapshot_index<F>(service: &ReapiService, namespace_id: &str, done: F)
where
    F: Fn(&NamespaceSnapshotIndex) -> bool,
{
    for _ in 0..400 {
        {
            let indexes = service.snapshot_cache.indexes.lock().unwrap();
            if indexes.get(namespace_id).map(&done).unwrap_or(false) {
                return;
            }
        }
        tokio::time::sleep(std::time::Duration::from_millis(10)).await;
    }
    panic!("background reconcile did not reach the expected state");
}

#[tokio::test]
async fn snapshot_serve_cascade_deletes_stranded_entries_past_grace() {
    let context = test_context(|_| {}).await;
    let service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };
    let store = &context.state.store;
    let uploads = context.state.config.tmp_dir.join("uploads");
    std::fs::create_dir_all(&uploads).expect("uploads dir should create");

    async fn write_artifact(
        store: &crate::store::Store,
        uploads: &std::path::Path,
        key: &str,
        bytes: &[u8],
        version_ms: u64,
    ) {
        let path = uploads.join(key.replace('/', "-"));
        std::fs::write(&path, bytes).expect("source should write");
        store
            .apply_replicated_artifact_from_path(
                ArtifactProducer::Reapi,
                "ios",
                key,
                "application/octet-stream",
                &path,
                version_ms,
            )
            .await
            .expect("artifact should persist");
    }
    fn entry_bytes(llcas: &[u8], blob_hash: [u8; 32]) -> Vec<u8> {
        reapi::ActionResult {
            output_files: vec![reapi::OutputFile {
                path: hex::encode(llcas),
                digest: Some(reapi::Digest {
                    hash: hex::encode(blob_hash),
                    size_bytes: 7,
                }),
                ..Default::default()
            }],
            ..Default::default()
        }
        .encode_to_vec()
    }

    let now = crate::utils::now_ms();
    let old = now - 2 * SNAPSHOT_CASCADE_GRACE_MS;
    let evicted_blob = [0x11u8; 32];
    let live_blob = [0x22u8; 32];
    let evicted_blob_key = blob_key(&format!("{}/7", hex::encode(evicted_blob)));
    let live_blob_key = blob_key(&format!("{}/7", hex::encode(live_blob)));
    let stranded_key = format!("action_cache/{}/10", hex::encode([0x44u8; 32]));
    let young_key = format!("action_cache/{}/10", hex::encode([0x55u8; 32]));
    let live_key = format!("action_cache/{}/10", hex::encode([0x66u8; 32]));
    write_artifact(store, &uploads, &evicted_blob_key, b"payload", old).await;
    write_artifact(store, &uploads, &live_blob_key, b"payload", old).await;
    write_artifact(
        store,
        &uploads,
        &stranded_key,
        &entry_bytes(&[0xAB, 0xCD], evicted_blob),
        old,
    )
    .await;
    write_artifact(
        store,
        &uploads,
        &young_key,
        &entry_bytes(&[0xAB, 0xCD], evicted_blob),
        now,
    )
    .await;
    write_artifact(
        store,
        &uploads,
        &live_key,
        &entry_bytes(&[0xEE, 0xFF], live_blob),
        old,
    )
    .await;

    service
        .serve_actioncache_snapshot("ios", 0)
        .await
        .expect("first serve should succeed");
    assert_eq!(
        service.snapshot_cache.indexes.lock().unwrap()["ios"]
            .entries
            .len(),
        3,
        "all three entries advertised while their blobs exist"
    );

    // Evict the shared blob the way segment eviction would: manifest gone.
    let blob_manifest = store
        .manifest(&crate::utils::artifact_storage_id(
            ArtifactProducer::Reapi,
            "test-tenant",
            "ios",
            &evicted_blob_key,
        ))
        .expect("manifest read should succeed")
        .expect("blob manifest should exist");
    store
        .delete_artifact_metadata(&[blob_manifest])
        .expect("blob eviction should succeed");

    backdate_snapshot_index(&service, "ios");
    service
        .serve_actioncache_snapshot("ios", 0)
        .await
        .expect("second serve should succeed");
    wait_for_snapshot_index(&service, "ios", |index| index.entries.len() == 1).await;
    let exists = |key: &str| {
        store
            .artifact_manifest_exists(ArtifactProducer::Reapi, "ios", key)
            .expect("existence check should succeed")
    };
    assert!(
        !exists(&stranded_key),
        "the stranded entry past the grace window is cascade-deleted"
    );
    assert!(
        exists(&young_key),
        "a young stranded entry is kept — its blobs may still be mid-replication"
    );
    assert!(exists(&live_key));
}

#[tokio::test]
async fn per_key_serve_gates_entries_with_evicted_outputs() {
    let context = test_context(|_| {}).await;
    let service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };
    let store = &context.state.store;
    let uploads = context.state.config.tmp_dir.join("uploads");
    std::fs::create_dir_all(&uploads).expect("uploads dir should create");

    async fn write_artifact(
        store: &crate::store::Store,
        uploads: &std::path::Path,
        key: &str,
        bytes: &[u8],
        version_ms: u64,
    ) {
        let path = uploads.join(key.replace('/', "-"));
        std::fs::write(&path, bytes).expect("source should write");
        store
            .apply_replicated_artifact_from_path(
                ArtifactProducer::Reapi,
                "ios",
                key,
                "application/octet-stream",
                &path,
                version_ms,
            )
            .await
            .expect("artifact should persist");
    }
    fn entry_bytes(blob_hash: [u8; 32]) -> Vec<u8> {
        reapi::ActionResult {
            output_files: vec![reapi::OutputFile {
                path: hex::encode([0xAB, 0xCD]),
                digest: Some(reapi::Digest {
                    hash: hex::encode(blob_hash),
                    size_bytes: 7,
                }),
                ..Default::default()
            }],
            ..Default::default()
        }
        .encode_to_vec()
    }
    fn get_request(action_hash: [u8; 32]) -> Request<reapi::GetActionResultRequest> {
        Request::new(reapi::GetActionResultRequest {
            instance_name: "ios".into(),
            action_digest: Some(reapi::Digest {
                hash: hex::encode(action_hash),
                size_bytes: 10,
            }),
            ..Default::default()
        })
    }

    let now = crate::utils::now_ms();
    let old = now - 2 * SNAPSHOT_CASCADE_GRACE_MS;
    let live_blob = [0x11u8; 32];
    let missing_blob = [0x22u8; 32];
    let live_blob_key = blob_key(&format!("{}/7", hex::encode(live_blob)));
    let live_action = [0x44u8; 32];
    let dead_action = [0x55u8; 32];
    let young_dead_action = [0x66u8; 32];
    let live_key = format!("action_cache/{}/10", hex::encode(live_action));
    let dead_key = format!("action_cache/{}/10", hex::encode(dead_action));
    let young_dead_key = format!("action_cache/{}/10", hex::encode(young_dead_action));
    write_artifact(store, &uploads, &live_blob_key, b"payload", old).await;
    write_artifact(store, &uploads, &live_key, &entry_bytes(live_blob), old).await;
    write_artifact(store, &uploads, &dead_key, &entry_bytes(missing_blob), old).await;
    write_artifact(
        store,
        &uploads,
        &young_dead_key,
        &entry_bytes(missing_blob),
        now,
    )
    .await;

    service
        .get_action_result(get_request(live_action))
        .await
        .expect("an entry with present outputs serves");

    let status = service
        .get_action_result(get_request(dead_action))
        .await
        .expect_err("an entry with evicted outputs must not serve");
    assert_eq!(status.code(), tonic::Code::NotFound);
    let exists = |key: &str| {
        store
            .artifact_manifest_exists(ArtifactProducer::Reapi, "ios", key)
            .expect("existence check should succeed")
    };
    assert!(
        !exists(&dead_key),
        "a dead entry past the grace window is deleted on serve"
    );

    let status = service
        .get_action_result(get_request(young_dead_action))
        .await
        .expect_err("a young dead entry must not serve either");
    assert_eq!(status.code(), tonic::Code::NotFound);
    assert!(
        exists(&young_dead_key),
        "a young dead entry is kept — its blobs may still be mid-replication"
    );
}

#[tokio::test]
async fn snapshot_index_build_survives_an_aborted_request() {
    let context = test_context(|_| {}).await;
    let service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };
    let store = &context.state.store;
    let uploads = context.state.config.tmp_dir.join("uploads");
    std::fs::create_dir_all(&uploads).expect("uploads dir should create");
    let blob_hash = [0x11u8; 32];
    let blob_key_name = blob_key(&format!("{}/7", hex::encode(blob_hash)));
    let entry_key = format!("action_cache/{}/10", hex::encode([0x44u8; 32]));
    let entry_bytes = reapi::ActionResult {
        output_files: vec![reapi::OutputFile {
            path: hex::encode([0xABu8, 0xCD]),
            digest: Some(reapi::Digest {
                hash: hex::encode(blob_hash),
                size_bytes: 7,
            }),
            ..Default::default()
        }],
        ..Default::default()
    }
    .encode_to_vec();
    for (key, bytes) in [
        (&blob_key_name, b"payload".to_vec()),
        (&entry_key, entry_bytes.clone()),
    ] {
        let path = uploads.join(key.replace('/', "-"));
        std::fs::write(&path, &bytes).expect("source should write");
        store
            .apply_replicated_artifact_from_path(
                ArtifactProducer::Reapi,
                "ios",
                key,
                "application/octet-stream",
                &path,
                100,
            )
            .await
            .expect("artifact should persist");
    }

    // Abort the request before the build completes: one poll starts the
    // detached build, then the request future is dropped — the build must
    // keep running and cache the index anyway. Dropping it with the
    // request meant every retry rebuilt from scratch, and a gateway
    // timeout made the snapshot permanently unservable.
    let mut serve = Box::pin(service.serve_actioncache_snapshot("ios", 0));
    let first = futures_util::future::poll_immediate(serve.as_mut()).await;
    assert!(first.is_none(), "the first poll leaves the build in flight");
    drop(serve);
    let mut cached = false;
    for _ in 0..400 {
        if service
            .snapshot_cache
            .indexes
            .lock()
            .unwrap()
            .contains_key("ios")
        {
            cached = true;
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(10)).await;
    }
    assert!(
        cached,
        "the detached build cached the index after the abort"
    );
    assert!(
        service.snapshot_cache.builds.lock().unwrap().is_empty(),
        "the finished build removed itself from the in-flight map"
    );
    let bytes = service
        .serve_actioncache_snapshot("ios", 0)
        .await
        .expect("the follow-up request serves from the cached index");
    assert_eq!(&bytes[..4], b"TSNZ");

    // A later publish must reach the next serve: every serve reconciles
    // afresh (a memoized index served forever is the production-staleness
    // failure this guards against).
    let late_key = format!("action_cache/{}/10", hex::encode([0x55u8; 32]));
    let late_path = uploads.join("late");
    std::fs::write(&late_path, &entry_bytes).expect("late entry should write");
    store
        .apply_replicated_artifact_from_path(
            ArtifactProducer::Reapi,
            "ios",
            &late_key,
            "application/octet-stream",
            &late_path,
            2_000,
        )
        .await
        .expect("late entry should persist");
    backdate_snapshot_index(&service, "ios");
    service
        .serve_actioncache_snapshot("ios", 0)
        .await
        .expect("the post-publish serve succeeds");
    wait_for_snapshot_index(&service, "ios", |index| {
        index.entries.len() == 2
            && index
                .entries
                .values()
                .any(|entry| entry.version_ms == 2_000)
    })
    .await;
}

// Scale validation for the bounded index build: a namespace more than
// twice the entry cap exercises the mid-scan shed, the cap, and the
// streaming loads end to end. Run manually (writes 220k artifacts):
//   /usr/bin/time -l cargo test --release -- --ignored snapshot_index_build_is_bounded
// and eyeball the max RSS — the serve must not add hundreds of MB.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "scale validation; run manually with --ignored"]
async fn snapshot_index_build_is_bounded_on_a_large_namespace() {
    let context = test_context(|_| {}).await;
    let service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };
    let store = &context.state.store;
    let uploads = context.state.config.tmp_dir.join("uploads");
    std::fs::create_dir_all(&uploads).expect("uploads dir should create");
    let blob_hash = [0x11u8; 32];
    let blob_key_name = blob_key(&format!("{}/7", hex::encode(blob_hash)));
    let blob_path = uploads.join("blob");
    std::fs::write(&blob_path, b"payload").expect("blob should write");
    store
        .apply_replicated_artifact_from_path(
            ArtifactProducer::Reapi,
            "ios",
            &blob_key_name,
            "application/octet-stream",
            &blob_path,
            1,
        )
        .await
        .expect("blob should persist");
    let entry_bytes = reapi::ActionResult {
        output_files: vec![reapi::OutputFile {
            path: hex::encode([0xABu8, 0xCD]),
            digest: Some(reapi::Digest {
                hash: hex::encode(blob_hash),
                size_bytes: 7,
            }),
            ..Default::default()
        }],
        ..Default::default()
    }
    .encode_to_vec();
    let entry_path = uploads.join("entry");
    const ENTRIES: u64 = 220_000;
    for version in 1..=ENTRIES {
        std::fs::write(&entry_path, &entry_bytes).expect("entry should write");
        let mut hash = [0u8; 32];
        hash[..8].copy_from_slice(&version.to_be_bytes());
        store
            .apply_replicated_artifact_from_path(
                ArtifactProducer::Reapi,
                "ios",
                &format!("action_cache/{}/10", hex::encode(hash)),
                "application/octet-stream",
                &entry_path,
                version,
            )
            .await
            .expect("entry should persist");
    }

    let bytes = service
        .serve_actioncache_snapshot("ios", 0)
        .await
        .expect("serve should succeed on the large namespace");
    assert_eq!(&bytes[..4], b"TSNZ");
    let indexes = service.snapshot_cache.indexes.lock().unwrap();
    let index = &indexes["ios"];
    assert_eq!(
        index.entries.len(),
        SNAPSHOT_INDEX_MAX_ENTRIES,
        "the index holds exactly the cap"
    );
    assert!(
        index
            .entries
            .values()
            .all(|entry| entry.version_ms > (ENTRIES - SNAPSHOT_INDEX_MAX_ENTRIES as u64)),
        "the cap kept the newest entries"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn snapshot_build_waits_for_pool_headroom_instead_of_declining() {
    let context = test_context(|_| {}).await;
    let service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };
    let store = &context.state.store;
    let uploads = context.state.config.tmp_dir.join("uploads");
    std::fs::create_dir_all(&uploads).expect("uploads dir should create");
    let entry_key = format!("action_cache/{}/10", hex::encode([0x44u8; 32]));
    let entry_path = uploads.join("entry");
    let entry_bytes = reapi::ActionResult {
        output_files: vec![reapi::OutputFile {
            path: hex::encode([0xABu8, 0xCD]),
            digest: Some(reapi::Digest {
                hash: hex::encode([0x11u8; 32]),
                size_bytes: 7,
            }),
            ..Default::default()
        }],
        ..Default::default()
    }
    .encode_to_vec();
    std::fs::write(&entry_path, &entry_bytes).expect("entry should write");
    store
        .apply_replicated_artifact_from_path(
            ArtifactProducer::Reapi,
            "ios",
            &entry_key,
            "application/octet-stream",
            &entry_path,
            100,
        )
        .await
        .expect("entry should persist");
    let blob_path = uploads.join("blob");
    std::fs::write(&blob_path, b"payload").expect("blob should write");
    store
        .apply_replicated_artifact_from_path(
            ArtifactProducer::Reapi,
            "ios",
            &blob_key(&format!("{}/7", hex::encode([0x11u8; 32]))),
            "application/octet-stream",
            &blob_path,
            100,
        )
        .await
        .expect("blob should persist");

    // Exhaust the pool: the old try-acquire declined the build here —
    // which, under the per-key load a stale snapshot causes, parked the
    // index stale indefinitely. The build must wait instead.
    let pool = context.state.memory.reapi_materialization_pool_bytes();
    let hog = context
        .state
        .memory
        .try_acquire_reapi_materialization(pool)
        .expect("pool should be acquirable when idle");
    let serve = tokio::spawn({
        let service = service.clone();
        async move { service.serve_actioncache_snapshot("ios", 0).await }
    });
    tokio::time::sleep(std::time::Duration::from_millis(200)).await;
    assert!(
        !serve.is_finished(),
        "the build waits for headroom rather than declining"
    );
    drop(hog);
    let bytes = tokio::time::timeout(std::time::Duration::from_secs(30), serve)
        .await
        .expect("build should complete once the pool frees")
        .expect("serve task should not panic")
        .expect("serve should succeed");
    assert_eq!(&bytes[..4], b"TSNZ");
}

#[tokio::test]
async fn snapshot_serve_returns_the_cached_full_view_while_the_index_is_out_for_reconcile() {
    let context = test_context(|_| {}).await;
    let service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };
    let store = &context.state.store;
    let uploads = context.state.config.tmp_dir.join("uploads");
    std::fs::create_dir_all(&uploads).expect("uploads dir should create");
    let entry_key = format!("action_cache/{}/10", hex::encode([0x44u8; 32]));
    let entry_path = uploads.join("entry");
    let entry_bytes = reapi::ActionResult {
        output_files: vec![reapi::OutputFile {
            path: hex::encode([0xABu8, 0xCD]),
            digest: Some(reapi::Digest {
                hash: hex::encode([0x11u8; 32]),
                size_bytes: 7,
            }),
            ..Default::default()
        }],
        ..Default::default()
    }
    .encode_to_vec();
    std::fs::write(&entry_path, &entry_bytes).expect("entry should write");
    store
        .apply_replicated_artifact_from_path(
            ArtifactProducer::Reapi,
            "ios",
            &entry_key,
            "application/octet-stream",
            &entry_path,
            100,
        )
        .await
        .expect("entry should persist");
    let blob_path = uploads.join("blob");
    std::fs::write(&blob_path, b"payload").expect("blob should write");
    store
        .apply_replicated_artifact_from_path(
            ArtifactProducer::Reapi,
            "ios",
            &blob_key(&format!("{}/7", hex::encode([0x11u8; 32]))),
            "application/octet-stream",
            &blob_path,
            100,
        )
        .await
        .expect("blob should persist");

    // A full serve builds the index and caches the full view.
    let first = service
        .serve_actioncache_snapshot("ios", 0)
        .await
        .expect("first serve builds the index");
    assert_eq!(&first[..4], b"TSNZ");
    assert!(
        service
            .snapshot_cache
            .served_full
            .lock()
            .unwrap()
            .contains_key("ios"),
        "the full view is cached for the rebuild window"
    );

    // Simulate a reconcile in flight: the index is OUT of the map. Exhaust
    // the pool so the serve's kicked rebuild cannot reinsert it before the
    // assertion.
    service.snapshot_cache.indexes.lock().unwrap().remove("ios");
    let pool = context.state.memory.reapi_materialization_pool_bytes();
    let _hog = context
        .state
        .memory
        .try_acquire_reapi_materialization(pool)
        .expect("pool should be acquirable when idle");

    // A full serve now finds no index but returns the cached full view
    // immediately, rather than shedding a cold client to UNAVAILABLE while
    // the rebuild runs. Before `served_full`, this fell to the cold path.
    let stale = tokio::time::timeout(
        std::time::Duration::from_secs(2),
        service.serve_actioncache_snapshot("ios", 0),
    )
    .await
    .expect("serve must not block on the stalled rebuild")
    .expect("serve returns the cached full view, not UNAVAILABLE");
    assert_eq!(stale, first, "serves the exact cached full view");
}

#[tokio::test(start_paused = true)]
async fn snapshot_cold_serve_sheds_to_unavailable_while_the_build_runs() {
    let context = test_context(|_| {}).await;
    let service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };
    // Stall the build at its memory permit: with no cached index the
    // serve must answer UNAVAILABLE within its bound instead of pinning
    // the request to the build — production builds ran for tens of
    // minutes and walked every client fetch into its deadline.
    let pool = context.state.memory.reapi_materialization_pool_bytes();
    let hog = context
        .state
        .memory
        .try_acquire_reapi_materialization(pool)
        .expect("pool should be acquirable when idle");
    let status = service
        .serve_actioncache_snapshot("ios", 0)
        .await
        .expect_err("cold serve should shed while the build is stuck");
    assert_eq!(status.code(), tonic::Code::Unavailable);
    // Once the pool frees the same build completes in the background and
    // the next fetch is served from the index it produced.
    drop(hog);
    let bytes = tokio::time::timeout(
        std::time::Duration::from_secs(120),
        service.serve_actioncache_snapshot("ios", 0),
    )
    .await
    .expect("serve should not hang once the pool frees")
    .expect("serve should succeed after the build completes");
    assert_eq!(&bytes[..4], b"TSNZ");
}

use tokio::net::TcpListener;
use tonic::body::Body as TonicBody;

use crate::{
    artifact::producer::ArtifactProducer,
    failpoints::{FailpointAction, FailpointName},
    test_support::{TestContext, test_context, test_context_with_extension},
};

// Serves the REAPI routes over a plaintext h2c listener for the tests
// below. axum::serve's auto builder speaks HTTP/2 prior knowledge, which
// is what the tonic clients connect with.
async fn serve_routes(
    listener: TcpListener,
    state: SharedState,
    shutdown: impl std::future::Future<Output = ()> + Send + 'static,
) {
    let _ = axum::serve(listener, routes(state).into_make_service())
        .with_graceful_shutdown(shutdown)
        .await;
}

#[tokio::test]
async fn grpc_request_accounting_layer_keeps_guard_until_response_body_drops() {
    let context = test_context(|_| {}).await;
    let layer = GrpcRequestAccountingLayer {
        state: context.state.clone(),
    };
    let mut service = layer.layer(tower::service_fn(
        |_request: http::Request<TonicBody>| async {
            Ok::<_, Infallible>(http::Response::new(TonicBody::empty()))
        },
    ));

    let response = service
        .call(http::Request::new(TonicBody::empty()))
        .await
        .expect("accounting layer should pass through service response");

    assert_eq!(context.state.runtime.grpc_inflight(), 1);
    assert_eq!(context.state.runtime.public_inflight(), 1);

    drop(response);

    assert_eq!(context.state.runtime.grpc_inflight(), 0);
    assert_eq!(context.state.runtime.public_inflight(), 0);
}

// Regression test for the missing flush in the ByteStream `write` handler. The
// handler streams chunks into a temp file with `write_all` and then persists it by
// re-opening the path on a separate descriptor (stat + copy into a segment).
// `tokio::fs::File` buffers writes and flushes lazily, so without an explicit flush
// the persist read races the flush and intermittently fails with
// "appended N bytes, expected M" — which silently broke remote caching of every
// action that uploads many blobs concurrently (notably cargo build scripts' directory
// outputs, e.g. librocksdb-sys). This drives the real gRPC handler with many
// concurrent multi-chunk uploads and asserts each persists and reads back intact.
#[tokio::test]
async fn bytestream_writes_persist_completely_under_concurrency() {
    use bazel_remote_apis::google::bytestream::byte_stream_client::ByteStreamClient;

    let context = test_context(|_| {}).await;
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind test listener");
    let addr = listener.local_addr().expect("listener addr");
    let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
    let server_state = context.state.clone();
    let server = tokio::spawn(async move {
        serve_routes(listener, server_state, async move {
            let _ = shutdown_rx.await;
        })
        .await
    });

    let endpoint = format!("http://{addr}");
    let mut channel = None;
    for _ in 0..50 {
        match tonic::transport::Endpoint::from_shared(endpoint.clone())
            .expect("valid endpoint")
            .connect()
            .await
        {
            Ok(connected) => {
                channel = Some(connected);
                break;
            }
            Err(_) => tokio::time::sleep(Duration::from_millis(20)).await,
        }
    }
    let channel = channel.expect("gRPC server should accept connections");

    let concurrency = 24u32;
    let chunk_size = 32 * 1024;
    let mut writers = Vec::new();
    for index in 0..concurrency {
        let mut client = ByteStreamClient::new(channel.clone());
        writers.push(tokio::spawn(async move {
            // Per-blob-distinct, multi-chunk content so each upload spans many
            // `write_all` calls (leaving buffered bytes for the flush to race).
            let blob: Vec<u8> = (0..384 * 1024u32)
                .map(|byte| byte.wrapping_mul(31).wrapping_add(index) as u8)
                .collect();
            let hash = hex::encode(Sha256::digest(&blob));
            let resource = format!("uploads/upload-{index}/blobs/{hash}/{}", blob.len());
            let mut requests = Vec::new();
            let mut offset = 0usize;
            while offset < blob.len() {
                let end = (offset + chunk_size).min(blob.len());
                requests.push(bytestream::WriteRequest {
                    resource_name: if offset == 0 {
                        resource.clone()
                    } else {
                        String::new()
                    },
                    write_offset: offset as i64,
                    finish_write: end == blob.len(),
                    data: blob[offset..end].to_vec(),
                });
                offset = end;
            }
            let committed = client
                .write(tokio_stream::iter(requests))
                .await
                .expect("concurrent ByteStream write should persist")
                .into_inner()
                .committed_size;
            assert_eq!(committed as usize, blob.len());
            (hash, blob)
        }));
    }

    let mut reader = ByteStreamClient::new(channel.clone());
    for writer in writers {
        let (hash, blob) = writer.await.expect("write task should not panic");
        let mut stream = reader
            .read(bytestream::ReadRequest {
                resource_name: format!("blobs/{hash}/{}", blob.len()),
                read_offset: 0,
                read_limit: 0,
            })
            .await
            .expect("blob should be readable back")
            .into_inner();
        let mut roundtrip = Vec::new();
        while let Some(chunk) = stream.message().await.expect("read chunk") {
            roundtrip.extend_from_slice(&chunk.data);
        }
        assert_eq!(roundtrip, blob, "persisted blob must match the upload");
    }

    let _ = shutdown_tx.send(());
    let _ = server.await;
}

// Regression: a CAS blob uploaded via the ByteStream `Write` interface must be reported
// present by `FindMissingBlobs`. ByteStream Write/Read once keyed blobs as "{hash}/{size}"
// while FindMissingBlobs/BatchUpdateBlobs/BatchReadBlobs use blob_key() = "blob/{hash}/{size}",
// so ByteStream-uploaded blobs were invisible to FindMissingBlobs and REAPI clients (e.g.
// Bazel) re-executed the action that produced them. Drives the real gRPC handlers end to end.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn bytestream_uploaded_blob_is_visible_to_find_missing_blobs() {
    use bazel_remote_apis::google::bytestream::byte_stream_client::ByteStreamClient;
    use reapi::content_addressable_storage_client::ContentAddressableStorageClient;

    let context = test_context(|_| {}).await;
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind test listener");
    let addr = listener.local_addr().expect("listener addr");
    let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
    let server_state = context.state.clone();
    let server = tokio::spawn(async move {
        serve_routes(listener, server_state, async move {
            let _ = shutdown_rx.await;
        })
        .await
    });

    let endpoint = format!("http://{addr}");
    let mut channel = None;
    for _ in 0..50 {
        match tonic::transport::Endpoint::from_shared(endpoint.clone())
            .expect("valid endpoint")
            .connect()
            .await
        {
            Ok(connected) => {
                channel = Some(connected);
                break;
            }
            Err(_) => tokio::time::sleep(Duration::from_millis(20)).await,
        }
    }
    let channel = channel.expect("gRPC server should accept connections");

    let blob = b"kura reapi bytestream blob-key regression payload".to_vec();
    let hash = hex::encode(Sha256::digest(&blob));
    let len = blob.len();

    // Upload via the ByteStream Write interface, exactly as a REAPI client does for CAS.
    let committed = ByteStreamClient::new(channel.clone())
        .write(tokio_stream::iter(vec![bytestream::WriteRequest {
            resource_name: format!("uploads/regression/blobs/{hash}/{len}"),
            write_offset: 0,
            finish_write: true,
            data: blob.clone(),
        }]))
        .await
        .expect("ByteStream write should succeed")
        .into_inner()
        .committed_size;
    assert_eq!(committed as usize, len);

    // FindMissingBlobs must report it PRESENT — it shares blob_key()'s namespace with Write.
    let missing = ContentAddressableStorageClient::new(channel.clone())
        .find_missing_blobs(reapi::FindMissingBlobsRequest {
            instance_name: String::new(),
            blob_digests: vec![reapi::Digest {
                hash: hash.clone(),
                size_bytes: len as i64,
            }],
            digest_function: 0,
        })
        .await
        .expect("find_missing_blobs should succeed")
        .into_inner()
        .missing_blob_digests;
    assert!(
        missing.is_empty(),
        "a ByteStream-uploaded blob must be visible to FindMissingBlobs; got {} missing",
        missing.len()
    );

    let _ = shutdown_tx.send(());
    let _ = server.await;
}

#[test]
fn parses_read_resource_names_with_and_without_instance_names() {
    assert_eq!(
        parse_read_resource_name("blobs/abc/10").expect("resource should parse"),
        BlobResource {
            namespace_id: "default".into(),
            hash: "abc".into(),
            size_bytes: 10,
            key: "blob/abc/10".into(),
        }
    );
    assert_eq!(
        parse_read_resource_name("bazel/cache/blobs/abc/10")
            .expect("instance-scoped resource should parse"),
        BlobResource {
            namespace_id: "bazel/cache".into(),
            hash: "abc".into(),
            size_bytes: 10,
            key: "blob/abc/10".into(),
        }
    );
}

#[test]
fn parses_write_resource_names_with_upload_prefix() {
    assert_eq!(
        parse_write_resource_name("buck/cache/uploads/uuid-1/blobs/abc/10")
            .expect("write resource should parse"),
        BlobResource {
            namespace_id: "buck/cache".into(),
            hash: "abc".into(),
            size_bytes: 10,
            key: "blob/abc/10".into(),
        }
    );
}

#[test]
fn rejects_write_resources_without_upload_prefix() {
    let error = parse_write_resource_name("blobs/abc/10")
        .expect_err("write resources should require uploads prefix");
    assert_eq!(error.code(), tonic::Code::InvalidArgument);
}

fn grpc_spec() -> GrpcExtensionSpec<'static> {
    GrpcExtensionSpec {
        route: "reapi.capabilities.get",
        operation: "capabilities.read",
        namespace_id: Some("ios"),
        producer: Some("reapi"),
        artifact_key: None,
        artifact_hash: None,
    }
}

fn metadata_with(pairs: &[(&'static str, &'static str)]) -> tonic::metadata::MetadataMap {
    let mut metadata = tonic::metadata::MetadataMap::new();
    for (key, value) in pairs {
        metadata.insert(*key, tonic::metadata::MetadataValue::from_static(value));
    }
    metadata
}

#[test]
fn grpc_context_reads_tenant_from_kura_header() {
    let metadata = metadata_with(&[("x-kura-tenant-id", "acme")]);
    let ctx = grpc_extension_context("acme", &grpc_spec(), &metadata, None);
    assert_eq!(ctx.tenant_id.as_deref(), Some("acme"));
    assert_eq!(ctx.namespace_id.as_deref(), Some("ios"));
}

#[test]
fn grpc_context_reads_tenant_from_tuist_account_handle_alias() {
    let metadata = metadata_with(&[("x-tuist-account-handle", "acme")]);
    let ctx = grpc_extension_context("acme", &grpc_spec(), &metadata, None);
    assert_eq!(ctx.tenant_id.as_deref(), Some("acme"));
}

#[test]
fn grpc_context_without_tenant_header_leaves_tenant_unset() {
    let metadata = tonic::metadata::MetadataMap::new();
    let ctx = grpc_extension_context("acme", &grpc_spec(), &metadata, None);
    assert_eq!(ctx.tenant_id, None);
    assert_eq!(ctx.namespace_id.as_deref(), Some("ios"));
}

// Minimal policy: any token authenticates; only namespace "ios" is authorized.
// Used to prove that GetCapabilities and ByteStream Write reach the extension
// with the request's project namespace (instance_name / resource_name), not
// the account scope they previously fell back to.
const NAMESPACE_POLICY_SCRIPT: &str = r#"
function authenticate(ctx)
  return { principal = { id = "test", kind = "subject" }, ttl_seconds = 60 }
end

function authorize(ctx, principal)
  if ctx.namespace_id == "ios" then
    return { allow = true, ttl_seconds = 60 }
  end
  return { deny = { status = 403, message = "forbidden namespace" }, ttl_seconds = 1 }
end
"#;

async fn namespace_policy_extension() -> crate::extension::SharedExtension {
    let dir = tempfile::tempdir().expect("create policy temp dir");
    let script_path = dir.path().join("policy.lua");
    tokio::fs::write(&script_path, NAMESPACE_POLICY_SCRIPT)
        .await
        .expect("write policy script");
    crate::extension::ExtensionEngine::from_script_for_test(
        script_path,
        crate::metrics::Metrics::new("test".into(), "tenant".into()),
    )
    .await
    .expect("build policy extension")
}

#[tokio::test]
async fn get_capabilities_authorizes_against_instance_namespace() {
    let extension = namespace_policy_extension().await;
    let context = test_context_with_extension(|_| {}, Some(extension)).await;
    let service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };

    service
        .get_capabilities(Request::new(reapi::GetCapabilitiesRequest {
            instance_name: "ios".into(),
        }))
        .await
        .expect("capabilities for a granted instance_name should be allowed");

    let denied = service
        .get_capabilities(Request::new(reapi::GetCapabilitiesRequest {
            instance_name: "forbidden".into(),
        }))
        .await
        .expect_err("capabilities for a non-granted instance_name should be denied");
    assert_eq!(denied.code(), tonic::Code::PermissionDenied);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn bytestream_write_authorizes_against_resource_namespace() {
    use bazel_remote_apis::google::bytestream::byte_stream_client::ByteStreamClient;

    let extension = namespace_policy_extension().await;
    let context = test_context_with_extension(|_| {}, Some(extension)).await;
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind test listener");
    let addr = listener.local_addr().expect("listener addr");
    let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
    let server_state = context.state.clone();
    let server = tokio::spawn(async move {
        serve_routes(listener, server_state, async move {
            let _ = shutdown_rx.await;
        })
        .await
    });

    let endpoint = format!("http://{addr}");
    let mut channel = None;
    for _ in 0..50 {
        match tonic::transport::Endpoint::from_shared(endpoint.clone())
            .expect("valid endpoint")
            .connect()
            .await
        {
            Ok(connected) => {
                channel = Some(connected);
                break;
            }
            Err(_) => tokio::time::sleep(Duration::from_millis(20)).await,
        }
    }
    let channel = channel.expect("gRPC server should accept connections");

    let blob = b"kura reapi project-scoped write payload".to_vec();
    let hash = hex::encode(Sha256::digest(&blob));
    let len = blob.len();

    // Granted namespace ("ios", from the resource_name prefix) authorizes and persists.
    let committed = ByteStreamClient::new(channel.clone())
        .write(tokio_stream::iter(vec![bytestream::WriteRequest {
            resource_name: format!("ios/uploads/write-1/blobs/{hash}/{len}"),
            write_offset: 0,
            finish_write: true,
            data: blob.clone(),
        }]))
        .await
        .expect("write to a granted namespace should be allowed")
        .into_inner()
        .committed_size;
    assert_eq!(committed as usize, len);

    // Non-granted namespace ("forbidden") is rejected before the blob is persisted.
    let denied = ByteStreamClient::new(channel.clone())
        .write(tokio_stream::iter(vec![bytestream::WriteRequest {
            resource_name: format!("forbidden/uploads/write-2/blobs/{hash}/{len}"),
            write_offset: 0,
            finish_write: true,
            data: blob.clone(),
        }]))
        .await
        .expect_err("write to a non-granted namespace should be denied");
    assert_eq!(denied.code(), tonic::Code::PermissionDenied);

    let _ = shutdown_tx.send(());
    let _ = server.await;
}

#[tokio::test]
async fn action_cache_reads_emit_keyvalue_metrics() {
    let context = test_context(|_| {}).await;
    let service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };
    let action_result = reapi::ActionResult::default();
    let bytes = action_result.encode_to_vec();
    let digest = reapi::Digest {
        hash: hex::encode(Sha256::digest(&bytes)),
        size_bytes: bytes.len() as i64,
    };
    let key = action_cache_key(&digest_key(&digest).expect("digest key should build"));

    context
        .state
        .store
        .persist_inline_artifact_from_bytes(
            ArtifactProducer::Reapi,
            DEFAULT_INSTANCE_NAME,
            &key,
            "application/x-protobuf",
            &bytes,
        )
        .await
        .expect("action result should persist");

    service
        .get_action_result(Request::new(reapi::GetActionResultRequest {
            instance_name: DEFAULT_INSTANCE_NAME.into(),
            action_digest: Some(digest),
            digest_function: reapi::digest_function::Value::Sha256 as i32,
            ..Default::default()
        }))
        .await
        .expect("action result should load");

    let rendered = context.state.metrics.render();
    assert!(rendered.contains("kura_artifact_reads_total"));
    assert!(rendered.contains("producer=\"reapi\""));
    assert!(rendered.contains("result=\"ok\""));
}

#[tokio::test]
async fn cas_batch_reads_emit_module_metrics() {
    let context = test_context(|_| {}).await;
    let service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };
    let bytes = b"blob-bytes";
    let digest = reapi::Digest {
        hash: hex::encode(Sha256::digest(bytes)),
        size_bytes: bytes.len() as i64,
    };
    let key = blob_key(&digest_key(&digest).expect("digest key should build"));

    context
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Reapi,
            DEFAULT_INSTANCE_NAME,
            &key,
            "application/octet-stream",
            bytes,
        )
        .await
        .expect("cas blob should persist");

    let response = service
        .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
            instance_name: DEFAULT_INSTANCE_NAME.into(),
            digests: vec![digest],
            digest_function: reapi::digest_function::Value::Sha256 as i32,
            ..Default::default()
        }))
        .await
        .expect("batch read should succeed");

    assert_eq!(response.get_ref().responses.len(), 1);
    assert_eq!(response.get_ref().responses[0].data, bytes);

    let rendered = context.state.metrics.render();
    assert!(rendered.contains("kura_artifact_reads_total"));
    assert!(rendered.contains("producer=\"reapi\""));
    assert!(rendered.contains("result=\"ok\""));
}

#[tokio::test]
async fn cas_batch_reads_mark_oversized_blobs_resource_exhausted_without_spending_budget() {
    let context = test_context(|config| {
        config.memory_soft_limit_bytes = 32 * 1024 * 1024;
        config.memory_hard_limit_bytes = 64 * 1024 * 1024;
    })
    .await;
    let service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };
    let oversized_bytes = vec![b'x'; 9 * 1024 * 1024];
    let small_bytes = b"small-bytes";
    let oversized_digest = reapi::Digest {
        hash: hex::encode(Sha256::digest(&oversized_bytes)),
        size_bytes: oversized_bytes.len() as i64,
    };
    let small_digest = reapi::Digest {
        hash: hex::encode(Sha256::digest(small_bytes)),
        size_bytes: small_bytes.len() as i64,
    };
    let oversized_key = blob_key(&digest_key(&oversized_digest).expect("digest key should build"));
    let small_key = blob_key(&digest_key(&small_digest).expect("digest key should build"));

    context
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Reapi,
            DEFAULT_INSTANCE_NAME,
            &oversized_key,
            "application/octet-stream",
            &oversized_bytes,
        )
        .await
        .expect("oversized cas blob should persist");
    context
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Reapi,
            DEFAULT_INSTANCE_NAME,
            &small_key,
            "application/octet-stream",
            small_bytes,
        )
        .await
        .expect("small cas blob should persist");

    let response = service
        .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
            instance_name: DEFAULT_INSTANCE_NAME.into(),
            digests: vec![oversized_digest, small_digest],
            digest_function: reapi::digest_function::Value::Sha256 as i32,
            ..Default::default()
        }))
        .await
        .expect("batch read should succeed");

    assert_eq!(response.get_ref().responses.len(), 2);
    assert_eq!(
        response.get_ref().responses[0]
            .status
            .as_ref()
            .map(|status| status.code),
        Some(tonic::Code::ResourceExhausted as i32)
    );
    assert!(response.get_ref().responses[0].data.is_empty());
    assert_eq!(
        response.get_ref().responses[1]
            .status
            .as_ref()
            .map(|status| status.code),
        Some(0)
    );
    assert_eq!(response.get_ref().responses[1].data, small_bytes);
}

#[tokio::test]
async fn concurrent_cas_batch_reads_respect_shared_materialization_pool() {
    let context = test_context(|config| {
        config.memory_soft_limit_bytes = 64 * 1024 * 1024;
        config.memory_hard_limit_bytes = 128 * 1024 * 1024;
    })
    .await;
    let first_service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };
    let second_service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };
    let third_service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };
    let bytes = vec![b'b'; 16 * 1024 * 1024];
    let digest = reapi::Digest {
        hash: hex::encode(Sha256::digest(&bytes)),
        size_bytes: bytes.len() as i64,
    };
    let key = blob_key(&digest_key(&digest).expect("digest key should build"));
    context
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Reapi,
            DEFAULT_INSTANCE_NAME,
            &key,
            "application/octet-stream",
            &bytes,
        )
        .await
        .expect("cas blob should persist");
    context.state.store.failpoints().set_always(
        FailpointName::AfterReadArtifactBytesBeforeReturn,
        FailpointAction::Sleep(Duration::from_millis(250)),
    );

    let first = tokio::spawn({
        let digest = digest.clone();
        async move {
            first_service
                .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                    instance_name: DEFAULT_INSTANCE_NAME.into(),
                    digests: vec![digest],
                    digest_function: reapi::digest_function::Value::Sha256 as i32,
                    ..Default::default()
                }))
                .await
        }
    });
    let second = tokio::spawn({
        let digest = digest.clone();
        async move {
            second_service
                .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                    instance_name: DEFAULT_INSTANCE_NAME.into(),
                    digests: vec![digest],
                    digest_function: reapi::digest_function::Value::Sha256 as i32,
                    ..Default::default()
                }))
                .await
        }
    });

    tokio::time::sleep(Duration::from_millis(50)).await;

    let third = third_service
        .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
            instance_name: DEFAULT_INSTANCE_NAME.into(),
            digests: vec![digest.clone()],
            digest_function: reapi::digest_function::Value::Sha256 as i32,
            ..Default::default()
        }))
        .await
        .expect("third request should get a per-digest response");

    context
        .state
        .store
        .failpoints()
        .clear(FailpointName::AfterReadArtifactBytesBeforeReturn);

    assert_eq!(
        third.get_ref().responses[0]
            .status
            .as_ref()
            .map(|status| status.code),
        Some(tonic::Code::ResourceExhausted as i32)
    );

    for handle in [first, second] {
        let response = handle
            .await
            .expect("concurrent read task should join")
            .expect("concurrent read should succeed");
        assert_eq!(
            response.get_ref().responses[0]
                .status
                .as_ref()
                .map(|status| status.code),
            Some(0)
        );
        assert_eq!(response.get_ref().responses[0].data, bytes);
    }
}

#[tokio::test]
async fn cas_batch_reads_shed_under_critical_memory_pressure() {
    let context = test_context(|_| {}).await;
    let service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };
    let bytes = b"blob-bytes";
    let digest = reapi::Digest {
        hash: hex::encode(Sha256::digest(bytes)),
        size_bytes: bytes.len() as i64,
    };
    let key = blob_key(&digest_key(&digest).expect("digest key should build"));

    context
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Reapi,
            DEFAULT_INSTANCE_NAME,
            &key,
            "application/octet-stream",
            bytes,
        )
        .await
        .expect("cas blob should persist");
    context
        .state
        .memory
        .observe(context.state.config.memory_hard_limit_bytes);

    let response = service
        .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
            instance_name: DEFAULT_INSTANCE_NAME.into(),
            digests: vec![digest],
            digest_function: reapi::digest_function::Value::Sha256 as i32,
            ..Default::default()
        }))
        .await
        .expect("batch read should return per-digest status");

    assert_eq!(
        response.get_ref().responses[0]
            .status
            .as_ref()
            .map(|status| status.code),
        Some(tonic::Code::ResourceExhausted as i32)
    );
}

#[tokio::test]
async fn action_cache_inline_reads_reject_when_inline_expansion_exceeds_budget() {
    let context = test_context(|config| {
        config.memory_soft_limit_bytes = 32 * 1024 * 1024;
        config.memory_hard_limit_bytes = 64 * 1024 * 1024;
    })
    .await;
    let service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };
    let stdout_bytes = vec![b's'; 9 * 1024 * 1024];
    let stdout_digest = reapi::Digest {
        hash: hex::encode(Sha256::digest(&stdout_bytes)),
        size_bytes: stdout_bytes.len() as i64,
    };
    let stdout_key = blob_key(&digest_key(&stdout_digest).expect("digest key should build"));
    context
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Reapi,
            DEFAULT_INSTANCE_NAME,
            &stdout_key,
            "application/octet-stream",
            &stdout_bytes,
        )
        .await
        .expect("stdout blob should persist");

    let action_result = reapi::ActionResult {
        stdout_digest: Some(stdout_digest),
        ..Default::default()
    };
    let action_bytes = action_result.encode_to_vec();
    let action_digest = reapi::Digest {
        hash: hex::encode(Sha256::digest(&action_bytes)),
        size_bytes: action_bytes.len() as i64,
    };
    let action_key =
        action_cache_key(&digest_key(&action_digest).expect("digest key should build"));
    context
        .state
        .store
        .persist_inline_artifact_from_bytes(
            ArtifactProducer::Reapi,
            DEFAULT_INSTANCE_NAME,
            &action_key,
            "application/x-protobuf",
            &action_bytes,
        )
        .await
        .expect("action result should persist");

    let error = service
        .get_action_result(Request::new(reapi::GetActionResultRequest {
            instance_name: DEFAULT_INSTANCE_NAME.into(),
            action_digest: Some(action_digest),
            inline_stdout: true,
            digest_function: reapi::digest_function::Value::Sha256 as i32,
            ..Default::default()
        }))
        .await
        .expect_err("inline expansion should respect the materialization budget");

    assert_eq!(error.code(), tonic::Code::ResourceExhausted);
}

async fn persist_output_file_blob(context: &TestContext, bytes: &[u8]) -> reapi::Digest {
    let digest = reapi::Digest {
        hash: hex::encode(Sha256::digest(bytes)),
        size_bytes: bytes.len() as i64,
    };
    let key = blob_key(&digest_key(&digest).expect("digest key should build"));
    context
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Reapi,
            DEFAULT_INSTANCE_NAME,
            &key,
            "application/octet-stream",
            bytes,
        )
        .await
        .expect("output blob should persist");
    digest
}

async fn persist_action_result_with_outputs(
    context: &TestContext,
    output_files: Vec<reapi::OutputFile>,
) -> reapi::Digest {
    let action_result = reapi::ActionResult {
        output_files,
        ..Default::default()
    };
    let action_bytes = action_result.encode_to_vec();
    let action_digest = reapi::Digest {
        hash: hex::encode(Sha256::digest(&action_bytes)),
        size_bytes: action_bytes.len() as i64,
    };
    let action_key =
        action_cache_key(&digest_key(&action_digest).expect("digest key should build"));
    context
        .state
        .store
        .persist_inline_artifact_from_bytes(
            ArtifactProducer::Reapi,
            DEFAULT_INSTANCE_NAME,
            &action_key,
            "application/x-protobuf",
            &action_bytes,
        )
        .await
        .expect("action result should persist");
    action_digest
}

#[tokio::test]
async fn action_cache_wildcard_inlines_every_output_file() {
    let context = test_context(|_| {}).await;
    let service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };
    let first_bytes = b"first output".to_vec();
    let second_bytes = b"second output".to_vec();
    let first_digest = persist_output_file_blob(&context, &first_bytes).await;
    let second_digest = persist_output_file_blob(&context, &second_bytes).await;
    let action_digest = persist_action_result_with_outputs(
        &context,
        vec![
            reapi::OutputFile {
                path: "aaaa".into(),
                digest: Some(first_digest),
                ..Default::default()
            },
            reapi::OutputFile {
                path: "bbbb".into(),
                digest: Some(second_digest),
                ..Default::default()
            },
        ],
    )
    .await;

    let response = service
        .get_action_result(Request::new(reapi::GetActionResultRequest {
            instance_name: DEFAULT_INSTANCE_NAME.into(),
            action_digest: Some(action_digest),
            inline_output_files: vec!["*".into()],
            digest_function: reapi::digest_function::Value::Sha256 as i32,
            ..Default::default()
        }))
        .await
        .expect("wildcard inline should succeed");

    let output_files = &response.get_ref().output_files;
    assert_eq!(output_files[0].contents, first_bytes);
    assert_eq!(output_files[1].contents, second_bytes);
}

#[tokio::test]
async fn action_cache_wildcard_inline_degrades_to_partial_when_budget_is_exceeded() {
    let context = test_context(|config| {
        config.memory_soft_limit_bytes = 32 * 1024 * 1024;
        config.memory_hard_limit_bytes = 64 * 1024 * 1024;
    })
    .await;
    let service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };
    // Larger than the response budget under this memory config (the same
    // sizing the explicit-inline rejection test relies on), listed FIRST
    // to prove a rejected file does not stop later ones from inlining.
    let large_bytes = vec![b'x'; 9 * 1024 * 1024];
    let small_bytes = b"small output".to_vec();
    let large_digest = persist_output_file_blob(&context, &large_bytes).await;
    let small_digest = persist_output_file_blob(&context, &small_bytes).await;
    let action_digest = persist_action_result_with_outputs(
        &context,
        vec![
            reapi::OutputFile {
                path: "large".into(),
                digest: Some(large_digest),
                ..Default::default()
            },
            reapi::OutputFile {
                path: "small".into(),
                digest: Some(small_digest),
                ..Default::default()
            },
        ],
    )
    .await;

    let response = service
        .get_action_result(Request::new(reapi::GetActionResultRequest {
            instance_name: DEFAULT_INSTANCE_NAME.into(),
            action_digest: Some(action_digest),
            inline_output_files: vec!["*".into()],
            digest_function: reapi::digest_function::Value::Sha256 as i32,
            ..Default::default()
        }))
        .await
        .expect("wildcard inline should degrade to partial, not fail");

    let output_files = &response.get_ref().output_files;
    assert!(output_files[0].contents.is_empty());
    assert_eq!(output_files[1].contents, small_bytes);
}

#[tokio::test]
async fn wildcard_inline_keeps_the_hard_budget_error_for_an_explicitly_listed_path() {
    let context = test_context(|config| {
        config.memory_soft_limit_bytes = 32 * 1024 * 1024;
        config.memory_hard_limit_bytes = 64 * 1024 * 1024;
    })
    .await;
    let service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };
    // Larger than the response budget; listed BOTH via "*" and explicitly.
    // The explicit listing must keep the hard error even though "*" would
    // otherwise let it degrade to partial.
    let large_bytes = vec![b'x'; 9 * 1024 * 1024];
    let large_digest = persist_output_file_blob(&context, &large_bytes).await;
    let action_digest = persist_action_result_with_outputs(
        &context,
        vec![reapi::OutputFile {
            path: "required".into(),
            digest: Some(large_digest),
            ..Default::default()
        }],
    )
    .await;

    let error = service
        .get_action_result(Request::new(reapi::GetActionResultRequest {
            instance_name: DEFAULT_INSTANCE_NAME.into(),
            action_digest: Some(action_digest),
            inline_output_files: vec!["*".into(), "required".into()],
            digest_function: reapi::digest_function::Value::Sha256 as i32,
            ..Default::default()
        }))
        .await
        .expect_err("an explicitly listed over-budget file must fail the lookup");

    assert_eq!(error.code(), tonic::Code::ResourceExhausted);
}

#[tokio::test]
async fn draining_rejects_new_grpc_requests() {
    let context = test_context(|_| {}).await;
    let service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };
    context.state.enter_draining();

    let error = service
        .get_capabilities(Request::new(reapi::GetCapabilitiesRequest::default()))
        .await
        .expect_err("draining nodes should reject new gRPC requests");

    assert_eq!(error.code(), tonic::Code::Unavailable);
    assert!(error.message().contains("draining"));
}

#[test]
fn usage_tenant_id_prefers_metadata_header_and_falls_back_to_node_tenant() {
    let mut metadata = tonic::metadata::MetadataMap::new();
    assert_eq!(usage_tenant_id(&metadata, "node-tenant"), "node-tenant");

    metadata.insert("x-tuist-account-handle", "  acme  ".parse().unwrap());
    assert_eq!(usage_tenant_id(&metadata, "node-tenant"), "acme");

    let mut kura_metadata = tonic::metadata::MetadataMap::new();
    kura_metadata.insert("x-kura-tenant-id", "globex".parse().unwrap());
    assert_eq!(usage_tenant_id(&kura_metadata, "node-tenant"), "globex");
}

// Authorization and billing must resolve the tenant from a duplicated header
// identically; otherwise a client could be authorized as one account and
// billed to another. Both go through `tenant_id_from_metadata`, which takes
// the first value of a repeated key.
#[test]
fn tenant_id_from_metadata_takes_first_value_of_a_repeated_header() {
    let mut metadata = tonic::metadata::MetadataMap::new();
    metadata.append("x-tuist-account-handle", "acme".parse().unwrap());
    metadata.append("x-tuist-account-handle", "globex".parse().unwrap());

    // The authorization path (grpc_extension_context) and the billing path
    // (usage_tenant_id) read the same value.
    assert_eq!(tenant_id_from_metadata(&metadata).as_deref(), Some("acme"));
    assert_eq!(usage_tenant_id(&metadata, "node-tenant"), "acme");

    let spec = GrpcExtensionSpec {
        route: "reapi.bytestream.read",
        operation: "artifact.read",
        namespace_id: Some("ios"),
        producer: Some("reapi"),
        artifact_key: None,
        artifact_hash: None,
    };
    let context = grpc_extension_context("acme", &spec, &metadata, None);
    assert_eq!(context.tenant_id.as_deref(), Some("acme"));
}

fn test_usage_config() -> crate::config::UsageConfig {
    crate::config::UsageConfig {
        control_plane_url: "http://localhost:0".to_owned(),
        client_id: "kura".to_owned(),
        client_secret: "secret".to_owned(),
        window_secs: 60,
        flush_interval_ms: 1_000,
        delivery_interval_ms: 1_000,
        batch_size: 100,
        max_buckets: 100,
        outbox_max_depth: 100,
    }
}

// The CAS batch handlers carry the bulk of small-blob REAPI traffic; both
// must land in the usage rollups tagged protocol="grpc"/artifact_kind="reapi"
// and attributed to the tenant declared via the account-handle metadata
// header (the gRPC analog of the HTTP tenant_id query param). A batch RPC of N
// blobs counts as ONE request (not N), and re-uploading an already-present
// blob is not billed a second time — matching the HTTP upload path.
#[tokio::test]
async fn cas_batch_transfers_record_grpc_usage_events() {
    let context = test_context(|config| {
        config.usage = Some(test_usage_config());
    })
    .await;
    let service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };

    let blob_a = b"reapi-cas-blob-a".to_vec();
    let blob_b = b"reapi-cas-blob-bb".to_vec();
    let total_bytes = (blob_a.len() + blob_b.len()) as u64;
    let build_update = || {
        let mut update = Request::new(reapi::BatchUpdateBlobsRequest {
            instance_name: "ios".into(),
            requests: vec![
                reapi::batch_update_blobs_request::Request {
                    digest: Some(reapi::Digest {
                        hash: hex::encode(Sha256::digest(&blob_a)),
                        size_bytes: blob_a.len() as i64,
                    }),
                    data: blob_a.clone(),
                    ..Default::default()
                },
                reapi::batch_update_blobs_request::Request {
                    digest: Some(reapi::Digest {
                        hash: hex::encode(Sha256::digest(&blob_b)),
                        size_bytes: blob_b.len() as i64,
                    }),
                    data: blob_b.clone(),
                    ..Default::default()
                },
            ],
            ..Default::default()
        });
        update
            .metadata_mut()
            .insert("x-tuist-account-handle", "acme".parse().unwrap());
        update
    };

    // First upload stores both blobs; the second finds both already present
    // (IgnoredStale) and must not bill them again.
    service
        .batch_update_blobs(build_update())
        .await
        .expect("batch update should succeed");
    service
        .batch_update_blobs(build_update())
        .await
        .expect("repeat batch update should succeed");

    let mut read = Request::new(reapi::BatchReadBlobsRequest {
        instance_name: "ios".into(),
        digests: vec![
            reapi::Digest {
                hash: hex::encode(Sha256::digest(&blob_a)),
                size_bytes: blob_a.len() as i64,
            },
            reapi::Digest {
                hash: hex::encode(Sha256::digest(&blob_b)),
                size_bytes: blob_b.len() as i64,
            },
        ],
        digest_function: reapi::digest_function::Value::Sha256 as i32,
        ..Default::default()
    });
    read.metadata_mut()
        .insert("x-tuist-account-handle", "acme".parse().unwrap());
    service
        .batch_read_blobs(read)
        .await
        .expect("batch read should succeed");

    let rollups = context
        .state
        .usage
        .as_ref()
        .expect("usage should be enabled")
        .current_rollups_for_tests();

    let upload = rollups
        .iter()
        .find(|rollup| rollup.operation == "upload")
        .expect("batch_update_blobs should record an upload rollup");
    assert_eq!(upload.tenant_id, "acme");
    assert_eq!(upload.namespace_id, "ios");
    assert_eq!(upload.traffic_plane, "public");
    assert_eq!(upload.direction, "ingress");
    assert_eq!(upload.protocol, "grpc");
    assert_eq!(upload.artifact_kind, "reapi");
    // Two blobs stored across two RPCs, but only the first RPC stored new
    // bytes and each batch RPC books one request: request_count == 1, and the
    // stale re-upload added nothing.
    assert_eq!(upload.bytes, total_bytes);
    assert_eq!(upload.request_count, 1);

    let download = rollups
        .iter()
        .find(|rollup| rollup.operation == "download")
        .expect("batch_read_blobs should record a download rollup");
    assert_eq!(download.tenant_id, "acme");
    assert_eq!(download.namespace_id, "ios");
    assert_eq!(download.traffic_plane, "public");
    assert_eq!(download.direction, "egress");
    assert_eq!(download.protocol, "grpc");
    assert_eq!(download.artifact_kind, "reapi");
    // One batch read of two blobs is one request carrying both blobs' bytes.
    assert_eq!(download.bytes, total_bytes);
    assert_eq!(download.request_count, 1);
}

// The ActionCache methods move real bytes too: UpdateActionResult uploads an
// encoded action result, and GetActionResult returns it plus any inlined
// stdout/stderr/output-file blobs. Both must land in the grpc/reapi usage
// rollups like the ByteStream/CAS handlers, with the download counting the
// inlined blob bytes as egress.
#[tokio::test]
async fn action_cache_transfers_record_grpc_usage_events() {
    let context = test_context(|config| {
        config.usage = Some(test_usage_config());
    })
    .await;
    let service = ReapiService {
        snapshot_cache: Default::default(),
        state: context.state.clone(),
    };

    let stdout_bytes = b"action stdout".to_vec();
    let stdout_digest = reapi::Digest {
        hash: hex::encode(Sha256::digest(&stdout_bytes)),
        size_bytes: stdout_bytes.len() as i64,
    };
    let stdout_key = blob_key(&digest_key(&stdout_digest).expect("digest key should build"));
    context
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Reapi,
            "ios",
            &stdout_key,
            "application/octet-stream",
            &stdout_bytes,
        )
        .await
        .expect("stdout blob should persist");

    let action_result = reapi::ActionResult {
        stdout_digest: Some(stdout_digest),
        ..Default::default()
    };
    let encoded_bytes = action_result.encode_to_vec().len() as u64;
    let action_digest = reapi::Digest {
        hash: hex::encode(Sha256::digest(b"action")),
        size_bytes: "action".len() as i64,
    };

    let mut update = Request::new(reapi::UpdateActionResultRequest {
        instance_name: "ios".into(),
        action_digest: Some(action_digest.clone()),
        action_result: Some(action_result),
        digest_function: reapi::digest_function::Value::Sha256 as i32,
        ..Default::default()
    });
    update
        .metadata_mut()
        .insert("x-tuist-account-handle", "acme".parse().unwrap());
    service
        .update_action_result(update)
        .await
        .expect("update action result should succeed");

    let mut get = Request::new(reapi::GetActionResultRequest {
        instance_name: "ios".into(),
        action_digest: Some(action_digest),
        inline_stdout: true,
        digest_function: reapi::digest_function::Value::Sha256 as i32,
        ..Default::default()
    });
    get.metadata_mut()
        .insert("x-tuist-account-handle", "acme".parse().unwrap());
    let fetched = service
        .get_action_result(get)
        .await
        .expect("get action result should succeed");
    assert_eq!(
        fetched.get_ref().stdout_raw,
        stdout_bytes,
        "stdout should be inlined into the response"
    );

    let rollups = context
        .state
        .usage
        .as_ref()
        .expect("usage should be enabled")
        .current_rollups_for_tests();

    let upload = rollups
        .iter()
        .find(|rollup| rollup.operation == "upload")
        .expect("update_action_result should record an upload rollup");
    assert_eq!(upload.tenant_id, "acme");
    assert_eq!(upload.namespace_id, "ios");
    assert_eq!(upload.direction, "ingress");
    assert_eq!(upload.protocol, "grpc");
    assert_eq!(upload.artifact_kind, "reapi");
    assert_eq!(upload.bytes, encoded_bytes);
    assert_eq!(upload.request_count, 1);

    let download = rollups
        .iter()
        .find(|rollup| rollup.operation == "download")
        .expect("get_action_result should record a download rollup");
    assert_eq!(download.tenant_id, "acme");
    assert_eq!(download.namespace_id, "ios");
    assert_eq!(download.direction, "egress");
    assert_eq!(download.protocol, "grpc");
    assert_eq!(download.artifact_kind, "reapi");
    // The download egress is the stored action result plus the inlined
    // stdout blob it carried out.
    assert_eq!(download.bytes, encoded_bytes + stdout_bytes.len() as u64);
    assert_eq!(download.request_count, 1);
}

// Drives the real ByteStream gRPC handlers (the large-artifact read/write
// path) end to end and asserts each emits a grpc/reapi usage rollup, so the
// primary bandwidth carriers are no longer invisible to kura_usage_events.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn bytestream_transfers_record_grpc_usage_events() {
    use bazel_remote_apis::google::bytestream::byte_stream_client::ByteStreamClient;

    let context = test_context(|config| {
        config.usage = Some(test_usage_config());
    })
    .await;
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind test listener");
    let addr = listener.local_addr().expect("listener addr");
    let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
    let server_state = context.state.clone();
    let server = tokio::spawn(async move {
        serve_routes(listener, server_state, async move {
            let _ = shutdown_rx.await;
        })
        .await
    });

    let endpoint = format!("http://{addr}");
    let mut channel = None;
    for _ in 0..50 {
        match tonic::transport::Endpoint::from_shared(endpoint.clone())
            .expect("valid endpoint")
            .connect()
            .await
        {
            Ok(connected) => {
                channel = Some(connected);
                break;
            }
            Err(_) => tokio::time::sleep(Duration::from_millis(20)).await,
        }
    }
    let channel = channel.expect("gRPC server should accept connections");

    let blob: Vec<u8> = (0..200_000u32).map(|byte| byte as u8).collect();
    let hash = hex::encode(Sha256::digest(&blob));
    let resource = format!("ios/uploads/upload-1/blobs/{hash}/{}", blob.len());

    let chunk_size = 64 * 1024;
    let build_write = || {
        let mut requests = Vec::new();
        let mut offset = 0usize;
        while offset < blob.len() {
            let end = (offset + chunk_size).min(blob.len());
            requests.push(bytestream::WriteRequest {
                resource_name: if offset == 0 {
                    resource.clone()
                } else {
                    String::new()
                },
                write_offset: offset as i64,
                finish_write: end == blob.len(),
                data: blob[offset..end].to_vec(),
            });
            offset = end;
        }
        let mut write_request = Request::new(tokio_stream::iter(requests));
        write_request
            .metadata_mut()
            .insert("x-tuist-account-handle", "acme".parse().unwrap());
        write_request
    };

    let mut client = ByteStreamClient::new(channel.clone());
    let committed = client
        .write(build_write())
        .await
        .expect("bytestream write should persist")
        .into_inner()
        .committed_size;
    assert_eq!(committed as usize, blob.len());

    // A second write of the same blob is already present and must not be
    // billed again (parity with the HTTP upload path).
    client
        .write(build_write())
        .await
        .expect("repeat bytestream write should succeed");

    let mut read_request = Request::new(bytestream::ReadRequest {
        resource_name: format!("ios/blobs/{hash}/{}", blob.len()),
        read_offset: 0,
        read_limit: 0,
    });
    read_request
        .metadata_mut()
        .insert("x-tuist-account-handle", "acme".parse().unwrap());
    let mut stream = client
        .read(read_request)
        .await
        .expect("blob should read back")
        .into_inner();
    let mut roundtrip = Vec::new();
    while let Some(chunk) = stream.message().await.expect("read chunk") {
        roundtrip.extend_from_slice(&chunk.data);
    }
    assert_eq!(roundtrip, blob);

    let _ = shutdown_tx.send(());
    let _ = server.await;

    let rollups = context
        .state
        .usage
        .as_ref()
        .expect("usage should be enabled")
        .current_rollups_for_tests();

    let upload = rollups
        .iter()
        .find(|rollup| rollup.operation == "upload")
        .expect("bytestream write should record an upload rollup");
    assert_eq!(upload.tenant_id, "acme");
    assert_eq!(upload.namespace_id, "ios");
    assert_eq!(upload.protocol, "grpc");
    assert_eq!(upload.artifact_kind, "reapi");
    assert_eq!(upload.direction, "ingress");
    // Two writes of the same blob, but the second was already present: exactly
    // one request and one blob's worth of bytes are billed.
    assert_eq!(upload.bytes, blob.len() as u64);
    assert_eq!(upload.request_count, 1);

    let download = rollups
        .iter()
        .find(|rollup| rollup.operation == "download")
        .expect("bytestream read should record a download rollup");
    assert_eq!(download.tenant_id, "acme");
    assert_eq!(download.namespace_id, "ios");
    assert_eq!(download.protocol, "grpc");
    assert_eq!(download.artifact_kind, "reapi");
    assert_eq!(download.direction, "egress");
    assert_eq!(download.bytes, blob.len() as u64);
    assert_eq!(download.request_count, 1);
}
