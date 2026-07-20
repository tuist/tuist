
use super::*;
use tempfile::TempDir;

use crate::{
    config::{AcceleratedFileServingConfig, AcceleratedFileServingMode, Config},
    failpoints::{FailpointAction, FailpointName},
    io::IoController,
    memory::MemoryController,
    metrics::Metrics,
    replication::operation::ReplicationOperation,
    segment::{reference::SegmentReference, state::SegmentState},
};

const GIB: u64 = 1024 * 1024 * 1024;

#[test]
fn segment_ring_limits_fall_back_to_legacy_floor_without_disk_information() {
    let limits = resolve_segment_ring_limits(None, None);

    assert_eq!(limits, SegmentRingLimits::legacy_floor());
}

#[test]
fn segment_ring_limits_derive_from_disk_size_when_unconfigured() {
    // 50% of 100 GiB = 50 GiB = 100 segments, split 1:2:2.
    let limits = resolve_segment_ring_limits(None, Some(100 * GIB));

    assert_eq!(limits.desired_old_segments, 20);
    assert_eq!(limits.desired_current_segments, 40);
    assert_eq!(limits.desired_new_segments, 40);
    assert_eq!(limits.capacity_bytes(), 50 * GIB);
}

#[test]
fn segment_ring_limits_use_configured_capacity() {
    // 20 GiB = 40 segments.
    let limits = resolve_segment_ring_limits(Some(20 * GIB), Some(100 * GIB));

    assert_eq!(limits.desired_old_segments, 8);
    assert_eq!(limits.desired_current_segments, 16);
    assert_eq!(limits.desired_new_segments, 16);
}

#[test]
fn segment_ring_limits_cap_configured_capacity_below_disk_size() {
    // 80% of 10 GiB rounds down to 15 whole segments, regardless of the
    // configured 1 TiB.
    let limits = resolve_segment_ring_limits(Some(1024 * GIB), Some(10 * GIB));

    assert_eq!(limits.total_segments(), 15);
    assert!(limits.capacity_bytes() <= 10 * GIB * 80 / 100);
}

#[test]
fn segment_ring_limits_never_drop_below_legacy_floor() {
    let tiny_configured = resolve_segment_ring_limits(Some(1), Some(100 * GIB));
    assert_eq!(
        tiny_configured.total_segments(),
        SegmentRingLimits::legacy_floor().total_segments()
    );

    // 50% of 1 GiB = 512 MiB = 1 segment, floored to the legacy ring.
    let tiny_disk = resolve_segment_ring_limits(None, Some(GIB));
    assert_eq!(
        tiny_disk.total_segments(),
        SegmentRingLimits::legacy_floor().total_segments()
    );
}

#[test]
fn segment_ring_limits_use_configured_capacity_without_disk_information() {
    let limits = resolve_segment_ring_limits(Some(20 * GIB), None);

    assert_eq!(limits.total_segments(), 40);
}

fn temp_store() -> (TempDir, Config, Store) {
    temp_store_with(|_| {})
}

fn temp_store_with<F>(override_config: F) -> (TempDir, Config, Store)
where
    F: FnOnce(&mut Config),
{
    let temp_dir = tempfile::tempdir().expect("failed to create temp dir");
    let mut config = Config {
        port: 0,
        internal_port: 7443,
        tenant_id: "test-tenant".into(),
        region: "local".into(),
        tmp_dir: temp_dir.path().join("tmp"),
        data_dir: temp_dir.path().join("data"),
        tmp_dir_max_bytes: 8 * 1024 * 1024 * 1024,
        cas_capacity_bytes: None,
        node_url: "http://127.0.0.1:7443".into(),
        peer_gateway_url: None,
        peers: vec!["http://127.0.0.1:7443".into()],
        discovery_dns_name: None,
        global_discovery_dns_name: None,
        peer_tls: None,
        public_tls: None,
        https_port: 0,
        accelerated_file_serving: AcceleratedFileServingConfig {
            enabled: true,
            mode: AcceleratedFileServingMode::Splice,
            max_concurrent: 32,
            chunk_bytes: 1024 * 1024,
        },
        file_descriptor_pool_size: 32,
        file_descriptor_acquire_timeout_ms: 5_000,
        drain_completion_timeout_ms: 240_000,
        segment_handle_cache_size: 8,
        memory_soft_limit_bytes: 128 * 1024 * 1024,
        memory_hard_limit_bytes: 256 * 1024 * 1024,
        manifest_cache_max_bytes: 8 * 1024 * 1024,
        max_keyvalue_bytes: 512 * 1024,
        rocksdb_max_open_files: 256,
        rocksdb_max_background_jobs: 2,
        rocksdb_block_cache_bytes: 32 * 1024 * 1024,
        rocksdb_write_buffer_manager_bytes: 32 * 1024 * 1024,
        rocksdb_write_buffer_size_bytes: 8 * 1024 * 1024,
        rocksdb_max_write_buffer_number: 4,
        outbox_max_depth: 100_000,
        replication_bandwidth_limit_bytes_per_second: 0,
        replication_public_latency_target_ms: 100,
        multipart_upload_ttl_ms: 24 * 60 * 60 * 1000,
        multipart_janitor_interval_ms: 10 * 60 * 1000,
        bootstrap_timeout_ms: 30 * 60 * 1000,
        bootstrap_max_concurrent_peers: 8,
        analytics: None,
        usage: None,
        otlp_traces_endpoint: Some("http://127.0.0.1:4318/v1/traces".into()),
        otel_service_name: "kura-test".into(),
        otel_deployment_environment: "test".into(),
        sentry_dsn: None,
        geoip_refresh_interval_secs: 0,
        node_country_override: None,
        node_subdivision_override: None,
    };
    override_config(&mut config);
    std::fs::create_dir_all(config.tmp_dir.join("uploads"))
        .expect("failed to create upload temp dir");
    std::fs::create_dir_all(config.data_dir.join("rocksdb")).expect("failed to create rocksdb dir");
    std::fs::create_dir_all(config.data_dir.join("blobs")).expect("failed to create blobs dir");
    std::fs::create_dir_all(config.data_dir.join("segments"))
        .expect("failed to create segments dir");
    std::fs::create_dir_all(config.data_dir.join("multipart"))
        .expect("failed to create multipart dir");
    let io = IoController::new(
        Metrics::new(config.region.clone(), config.tenant_id.clone()),
        config.file_descriptor_pool_size,
        std::time::Duration::from_millis(config.file_descriptor_acquire_timeout_ms),
        vec![config.tmp_dir.clone(), config.data_dir.clone()],
    )
    .expect("failed to create io controller");
    let memory = MemoryController::new(
        io.metrics(),
        config.memory_soft_limit_bytes,
        config.memory_hard_limit_bytes,
    );
    let store = Store::open(&config, io, memory).expect("failed to open store");
    (temp_dir, config, store)
}

async fn read_manifest_bytes(store: &Store, manifest: &ArtifactManifest) -> Vec<u8> {
    store
        .read_artifact_bytes(manifest)
        .await
        .expect("artifact bytes should read")
}

#[tokio::test]
async fn concurrent_replicated_applies_of_same_key_write_once() {
    // Several peers replicating the same artifact concurrently (same key,
    // same version) must not each append their own copy to a segment. The
    // per-key apply lock serializes them: the first writer commits the
    // manifest and the rest re-read it and short-circuit to IgnoredStale. A
    // sleep failpoint between the durable append and the metadata commit
    // forces the writers to overlap, so without the lock every copy would be
    // appended (writer_count x on disk). This guards the store invariant
    // directly, independent of the bootstrap-level fetch gate.
    let (_temp_dir, config, store) = temp_store();
    store.failpoints().set_always(
        FailpointName::AfterArtifactBytesDurableBeforeMetadata,
        FailpointAction::Sleep(std::time::Duration::from_millis(150)),
    );

    let writer_count = 4_usize;
    let artifact_len = 128 * 1024_usize;
    let bytes = vec![9_u8; artifact_len];
    let version_ms = 100_u64;

    let mut sources = Vec::new();
    for index in 0..writer_count {
        let path = config.tmp_dir.join("uploads").join(format!("src-{index}"));
        std::fs::write(&path, &bytes).expect("source should write");
        sources.push(path);
    }

    let applies = sources.iter().map(|source_path| {
        store.apply_replicated_artifact_from_path(
            ArtifactProducer::Gradle,
            "ios",
            "artifact",
            "application/octet-stream",
            source_path,
            version_ms,
        )
    });
    let outcomes = futures_util::future::join_all(applies).await;

    let applied = outcomes
        .into_iter()
        .map(|outcome| outcome.expect("apply should succeed"))
        .filter(|outcome| outcome.applied())
        .count();
    assert_eq!(
        applied, 1,
        "exactly one concurrent same-key apply should write; the rest are stale"
    );

    let segments_bytes = crate::utils::directory_size_bytes(&config.data_dir.join("segments"));
    assert!(
        segments_bytes <= (artifact_len as u64) * 2,
        "segment store held {segments_bytes} bytes, expected ~{artifact_len} (one copy); \
             concurrent same-key applies amplified on-disk data"
    );
}

#[tokio::test]
async fn damped_persist_skips_identical_republish_of_a_fresh_entry() {
    let (_temp_dir, _config, store) = temp_store();
    let day = 24 * 60 * 60 * 1000;

    // Seed the entry with an aged version (a replicated apply preserves
    // the origin's version), so the first damped refresh applies.
    store
        .apply_replicated_inline_artifact_from_bytes(
            ArtifactProducer::Reapi,
            "ios",
            "action_cache/aa/10",
            "application/x-protobuf",
            b"graph",
            now_ms() - 2 * day,
        )
        .await
        .expect("seed should persist");

    let (refreshed, applied) = store
        .persist_inline_artifact_from_bytes_damped_and_enqueue(
            ArtifactProducer::Reapi,
            "ios",
            "action_cache/aa/10",
            "application/x-protobuf",
            b"graph",
            &[],
        )
        .await
        .expect("aged refresh should persist");
    assert!(applied, "an aged identical re-publish applies");

    let (damped, applied) = store
        .persist_inline_artifact_from_bytes_damped_and_enqueue(
            ArtifactProducer::Reapi,
            "ios",
            "action_cache/aa/10",
            "application/x-protobuf",
            b"graph",
            &[],
        )
        .await
        .expect("damped refresh should succeed");
    assert!(
        !applied,
        "an identical re-publish inside the window is damped"
    );
    assert_eq!(damped.version_ms, refreshed.version_ms);

    let (changed, applied) = store
        .persist_inline_artifact_from_bytes_damped_and_enqueue(
            ArtifactProducer::Reapi,
            "ios",
            "action_cache/aa/10",
            "application/x-protobuf",
            b"graph-v2",
            &[],
        )
        .await
        .expect("changed publish should persist");
    assert!(applied, "changed content always applies");
    assert!(changed.version_ms >= refreshed.version_ms);
}

#[tokio::test]
async fn expiry_sweep_deletes_only_stale_action_cache_entries() {
    let (_temp_dir, config, store) = temp_store();
    async fn write(
        store: &Store,
        config: &Config,
        key: &str,
        producer: ArtifactProducer,
        version_ms: u64,
    ) {
        let path = config.tmp_dir.join("uploads").join(key.replace('/', "-"));
        std::fs::write(&path, b"payload").expect("source should write");
        store
            .apply_replicated_artifact_from_path(
                producer,
                "ios",
                key,
                "application/octet-stream",
                &path,
                version_ms,
            )
            .await
            .expect("artifact should persist");
    }
    write(
        &store,
        &config,
        "action_cache/aa/10",
        ArtifactProducer::Reapi,
        1_000,
    )
    .await;
    write(
        &store,
        &config,
        "action_cache/bb/10",
        ArtifactProducer::Reapi,
        9_000,
    )
    .await;
    write(
        &store,
        &config,
        "blob/cc/10",
        ArtifactProducer::Reapi,
        1_000,
    )
    .await;
    write(&store, &config, "artifact", ArtifactProducer::Gradle, 1_000).await;

    let expired = store
        .expire_stale_action_cache_entries(5_000, 100)
        .expect("sweep should succeed");
    assert_eq!(expired, 1, "only the stale action-cache entry expires");

    let exists = |producer, key| {
        store
            .artifact_manifest_exists(producer, "ios", key)
            .expect("existence check should succeed")
    };
    assert!(!exists(ArtifactProducer::Reapi, "action_cache/aa/10"));
    assert!(exists(ArtifactProducer::Reapi, "action_cache/bb/10"));
    assert!(
        exists(ArtifactProducer::Reapi, "blob/cc/10"),
        "blobs are not the sweep's to delete, however old"
    );
    assert!(exists(ArtifactProducer::Gradle, "artifact"));
    assert!(
        store
            .action_cache_manifests("ios", 1_000)
            .expect("namespace scan should succeed")
            .iter()
            .all(|manifest| manifest.key != "action_cache/aa/10"),
        "the namespace index entry is deleted with the manifest"
    );

    // The per-sweep cap defers the remainder to the next sweep.
    write(
        &store,
        &config,
        "action_cache/dd/10",
        ArtifactProducer::Reapi,
        1_000,
    )
    .await;
    write(
        &store,
        &config,
        "action_cache/ee/10",
        ArtifactProducer::Reapi,
        1_000,
    )
    .await;
    assert_eq!(
        store
            .expire_stale_action_cache_entries(5_000, 1)
            .expect("capped sweep should succeed"),
        1
    );
    assert_eq!(
        store
            .expire_stale_action_cache_entries(5_000, 100)
            .expect("follow-up sweep should succeed"),
        1
    );
    assert_eq!(
        store
            .expire_stale_action_cache_entries(5_000, 100)
            .expect("idle sweep should succeed"),
        0
    );
}

#[tokio::test]
async fn action_cache_manifest_scan_keeps_only_the_newest_entries() {
    let (_temp_dir, config, store) = temp_store();
    async fn write(store: &Store, config: &Config, key: &str, version_ms: u64) {
        let path = config.tmp_dir.join("uploads").join(key.replace('/', "-"));
        std::fs::write(&path, b"payload").expect("source should write");
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
    write(&store, &config, "action_cache/aa/10", 1_000).await;
    write(&store, &config, "action_cache/bb/10", 3_000).await;
    write(&store, &config, "action_cache/cc/10", 2_000).await;

    let manifests = store
        .action_cache_manifests("ios", 2)
        .expect("scan should succeed");
    let mut keys: Vec<&str> = manifests.iter().map(|m| m.key.as_str()).collect();
    keys.sort_unstable();
    assert_eq!(
        keys,
        vec!["action_cache/bb/10", "action_cache/cc/10"],
        "the cap keeps the newest entries by write time"
    );
    assert_eq!(
        store
            .action_cache_manifests("ios", 10)
            .expect("scan should succeed")
            .len(),
        3
    );
}

#[tokio::test]
async fn action_cache_manifest_scan_sheds_mid_scan_at_twice_the_cap() {
    let (_temp_dir, config, store) = temp_store();
    let source = config.tmp_dir.join("uploads").join("payload");
    for version in 1..=5u64 {
        std::fs::write(&source, b"payload").expect("source should write");
        store
            .apply_replicated_artifact_from_path(
                ArtifactProducer::Reapi,
                "ios",
                &format!("action_cache/{version:064}/10"),
                "application/octet-stream",
                &source,
                version * 100,
            )
            .await
            .expect("artifact should persist");
    }
    // Five entries against a cap of two crosses the in-scan shed
    // threshold (2x cap) as well as the final truncation.
    let manifests = store
        .action_cache_manifests("ios", 2)
        .expect("scan should succeed");
    let mut versions: Vec<u64> = manifests.iter().map(|m| m.version_ms).collect();
    versions.sort_unstable();
    assert_eq!(versions, vec![400, 500], "newest two survive the shed");
}

#[tokio::test]
async fn action_cache_index_serves_entries_written_after_backfill() {
    let (_temp_dir, config, store) = temp_store();
    let source = config.tmp_dir.join("uploads").join("payload");
    std::fs::write(&source, b"payload").expect("source should write");
    store
        .apply_replicated_artifact_from_path(
            ArtifactProducer::Reapi,
            "ios",
            "action_cache/aa/10",
            "application/octet-stream",
            &source,
            1_000,
        )
        .await
        .expect("artifact should persist");
    // First scan backfills the index; later writes must land in it
    // through the persist path rather than re-scanning the namespace.
    assert_eq!(store.action_cache_manifests("ios", 10).unwrap().len(), 1);
    std::fs::write(&source, b"payload").expect("source should write");
    store
        .apply_replicated_artifact_from_path(
            ArtifactProducer::Reapi,
            "ios",
            "action_cache/bb/10",
            "application/octet-stream",
            &source,
            2_000,
        )
        .await
        .expect("artifact should persist");
    let manifests = store
        .action_cache_manifests("ios", 10)
        .expect("indexed scan should succeed");
    let mut keys: Vec<&str> = manifests.iter().map(|m| m.key.as_str()).collect();
    keys.sort_unstable();
    assert_eq!(keys, vec!["action_cache/aa/10", "action_cache/bb/10"]);
}

#[tokio::test]
async fn action_cache_index_replaces_the_row_on_overwrite() {
    let (_temp_dir, config, store) = temp_store();
    let source = config.tmp_dir.join("uploads").join("payload");
    std::fs::write(&source, b"payload").expect("source should write");
    store
        .apply_replicated_artifact_from_path(
            ArtifactProducer::Reapi,
            "ios",
            "action_cache/aa/10",
            "application/octet-stream",
            &source,
            1_000,
        )
        .await
        .expect("artifact should persist");
    // Backfill, then overwrite the same key at a newer version: the old
    // row must go, or capped indexed scans would double-count the key.
    assert_eq!(store.action_cache_manifests("ios", 10).unwrap().len(), 1);
    std::fs::write(&source, b"payload").expect("source should write");
    store
        .apply_replicated_artifact_from_path(
            ArtifactProducer::Reapi,
            "ios",
            "action_cache/aa/10",
            "application/octet-stream",
            &source,
            5_000,
        )
        .await
        .expect("overwrite should persist");
    let manifests = store
        .action_cache_manifests("ios", 10)
        .expect("indexed scan should succeed");
    assert_eq!(manifests.len(), 1, "one row per live key");
    assert_eq!(manifests[0].version_ms, 5_000);
}

#[tokio::test]
async fn action_cache_index_drops_rows_with_deleted_manifests() {
    let (_temp_dir, config, store) = temp_store();
    let source = config.tmp_dir.join("uploads").join("payload");
    for (hash, version) in [("aa", 1_000_u64), ("bb", 2_000)] {
        std::fs::write(&source, b"payload").expect("source should write");
        store
            .apply_replicated_artifact_from_path(
                ArtifactProducer::Reapi,
                "ios",
                &format!("action_cache/{hash}/10"),
                "application/octet-stream",
                &source,
                version,
            )
            .await
            .expect("artifact should persist");
    }
    assert_eq!(store.action_cache_manifests("ios", 10).unwrap().len(), 2);
    let expired = store
        .expire_stale_action_cache_entries(1_500, 10)
        .expect("expiry should succeed");
    assert_eq!(expired, 1);
    let manifests = store
        .action_cache_manifests("ios", 10)
        .expect("indexed scan should succeed");
    assert_eq!(manifests.len(), 1);
    assert_eq!(manifests[0].key, "action_cache/bb/10");
}

#[tokio::test]
async fn persist_reports_already_present_across_re_uploads() {
    // `already_present` must reflect presence, not the Applied/IgnoredStale
    // version outcome: a re-upload takes a newer version and still applies,
    // yet billing must see it as already present.
    let (_temp_dir, _config, store) = temp_store();

    let persisted = store
        .persist_artifact_from_bytes_and_enqueue(
            ArtifactProducer::Reapi,
            "ios",
            "blob/abc",
            "application/octet-stream",
            b"payload",
            &[],
        )
        .await
        .expect("first persist should succeed");
    assert!(
        !persisted.already_present,
        "first persist of a key should report the artifact as newly stored"
    );

    let re_persisted = store
        .persist_artifact_from_bytes_and_enqueue(
            ArtifactProducer::Reapi,
            "ios",
            "blob/abc",
            "application/octet-stream",
            b"payload",
            &[],
        )
        .await
        .expect("re-persist should succeed");
    assert!(
        re_persisted.already_present,
        "a re-upload of a stored key should report the artifact as already present"
    );
}

#[tokio::test]
async fn concurrent_persists_of_same_missing_key_report_one_not_present() {
    // `already_present` is evaluated under the per-artifact write lock, so
    // concurrent uploads of the same missing key must resolve to exactly one
    // "newly stored" — the signal billing uses to avoid double-charging the
    // losers of the race. The sleep failpoint holds the first writer between
    // its durable append and metadata commit so the others genuinely overlap.
    let (_temp_dir, _config, store) = temp_store();
    store.failpoints().set_always(
        FailpointName::AfterArtifactBytesDurableBeforeMetadata,
        FailpointAction::Sleep(std::time::Duration::from_millis(150)),
    );

    let persists = (0..4).map(|_| {
        store.persist_artifact_from_bytes_and_enqueue(
            ArtifactProducer::Reapi,
            "ios",
            "blob/raced",
            "application/octet-stream",
            b"payload",
            &[],
        )
    });
    let outcomes = futures_util::future::join_all(persists).await;

    let newly_stored = outcomes
        .into_iter()
        .map(|outcome| outcome.expect("persist should succeed"))
        .filter(|persisted| !persisted.already_present)
        .count();
    assert_eq!(
        newly_stored, 1,
        "exactly one concurrent persist of a missing key should report it as newly stored"
    );
}

#[tokio::test]
async fn persist_and_fetch_segment_backed_artifact_round_trip() {
    let (_temp_dir, _config, store) = temp_store();

    let manifest = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact-1",
            "application/octet-stream",
            b"hello",
        )
        .await
        .expect("failed to persist artifact");

    assert!(
        store
            .artifact_exists(ArtifactProducer::Xcode, "ios", "artifact-1")
            .await
            .expect("failed to check artifact existence")
    );

    let fetched = store
        .fetch_artifact(ArtifactProducer::Xcode, "ios", "artifact-1")
        .await
        .expect("failed to fetch artifact")
        .expect("artifact should exist");

    assert_eq!(fetched, manifest);
    assert!(manifest.is_segment_backed());
    assert_eq!(read_manifest_bytes(&store, &manifest).await, b"hello");
    assert_eq!(store.segment_handles.lock().await.len(), 1);
    let raw = store
        .db
        .get_cf(
            store.cf(ROCKSDB_CF_MANIFESTS),
            manifest.artifact_id.as_bytes(),
        )
        .expect("failed to read raw manifest bytes")
        .expect("manifest bytes should exist");
    assert_eq!(
        raw[0], 2,
        "segment-backed manifest should use compact record"
    );
}

#[tokio::test]
async fn mmap_artifact_bytes_is_opportunistic_under_memory_pressure() {
    let (_temp_dir, config, store) = temp_store();

    let manifest = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact-1",
            "application/octet-stream",
            b"hello",
        )
        .await
        .expect("failed to persist artifact");

    let mmap_bytes = store
        .try_mmap_artifact_bytes(&manifest)
        .await
        .expect("mmap lookup should not fail")
        .expect("normal memory pressure should permit mmap serving");
    assert_eq!(&mmap_bytes[..], b"hello");

    store.memory.observe(config.memory_soft_limit_bytes);
    let mmap_bytes = store
        .try_mmap_artifact_bytes(&manifest)
        .await
        .expect("mmap lookup should not fail");

    assert!(mmap_bytes.is_none());
}

#[tokio::test]
async fn mmap_artifact_bytes_maps_non_zero_segment_offsets() {
    let (_temp_dir, _config, store) = temp_store();

    let first = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact-first",
            "application/octet-stream",
            b"first-artifact-payload",
        )
        .await
        .expect("failed to persist first artifact");

    let second = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact-second",
            "application/octet-stream",
            b"second-artifact-payload",
        )
        .await
        .expect("failed to persist second artifact");

    assert_eq!(
        first.segment_id, second.segment_id,
        "both artifacts should share the same append-only segment"
    );
    assert!(
        second.segment_offset.unwrap_or(0) > first.segment_offset.unwrap_or(0),
        "second artifact should land at a non-zero offset within the segment"
    );

    let mmap_bytes = store
        .try_mmap_artifact_bytes(&second)
        .await
        .expect("mmap lookup should not fail")
        .expect("normal memory pressure should permit mmap serving");

    assert_eq!(&mmap_bytes[..], b"second-artifact-payload");
}

#[tokio::test]
async fn artifact_exists_cache_is_invalidated_by_namespace_delete() {
    let (_temp_dir, _config, store) = temp_store();

    store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact-1",
            "application/octet-stream",
            b"hello",
        )
        .await
        .expect("failed to persist artifact");

    assert!(
        store
            .artifact_exists(ArtifactProducer::Xcode, "ios", "artifact-1")
            .await
            .expect("failed to check artifact existence")
    );

    store
        .delete_namespace("ios")
        .await
        .expect("failed to delete namespace");

    assert!(
        !store
            .artifact_exists(ArtifactProducer::Xcode, "ios", "artifact-1")
            .await
            .expect("failed to re-check artifact existence")
    );
}

#[tokio::test]
async fn artifact_exists_cache_is_invalidated_by_replicated_namespace_delete() {
    let (_temp_dir, _config, store) = temp_store();

    store
        .apply_replicated_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact-1",
            "application/octet-stream",
            b"hello",
            100,
        )
        .await
        .expect("failed to apply replicated artifact");

    assert!(
        store
            .artifact_exists(ArtifactProducer::Xcode, "ios", "artifact-1")
            .await
            .expect("failed to check artifact existence")
    );

    assert!(
        store
            .apply_replicated_namespace_delete("ios", 200)
            .await
            .expect("failed to apply replicated namespace delete")
            .applied()
    );

    assert!(
        !store
            .artifact_exists(ArtifactProducer::Xcode, "ios", "artifact-1")
            .await
            .expect("failed to re-check artifact existence")
    );
}

#[test]
fn existence_cache_expires_entries_after_ttl() {
    let mut cache = ExistenceCache::new(8, Duration::from_millis(10));
    cache.insert("artifact-1".into());
    assert!(cache.contains("artifact-1"));
    std::thread::sleep(Duration::from_millis(20));
    assert!(!cache.contains("artifact-1"));
}

#[test]
fn existence_cache_evicts_least_recently_used() {
    let mut cache = ExistenceCache::new(3, Duration::from_secs(60));
    for id in ["a", "b", "c"] {
        cache.insert(id.into());
    }
    // Touch "a" so "b" becomes the least-recently-used entry.
    assert!(cache.contains("a"));
    cache.insert("d".into());

    assert!(!cache.contains("b"), "LRU entry should have been evicted");
    for id in ["a", "c", "d"] {
        assert!(cache.contains(id), "{id} should still be present");
    }
}

#[test]
fn existence_cache_bounds_size_and_mirrors_index_past_capacity() {
    let capacity = 64;
    let mut cache = ExistenceCache::new(capacity, Duration::from_secs(60));
    // Insert far past capacity: O(log n) eviction must keep the entry map
    // and its access-order mirror bounded and equal in size.
    for index in 0..capacity * 20 {
        cache.insert(format!("artifact-{index}"));
    }
    assert_eq!(cache.entries.len(), capacity);
    assert_eq!(
        cache.access.order.len(),
        cache.entries.len(),
        "access-order index must mirror the entry map exactly"
    );
    // The most recently inserted entry survives.
    assert!(cache.contains(&format!("artifact-{}", capacity * 20 - 1)));
}

#[tokio::test]
async fn persist_and_fetch_rocksdb_backed_keyvalue_round_trip() {
    let (_temp_dir, _config, store) = temp_store();

    let manifest = store
        .persist_inline_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact-1",
            "application/json",
            br#"{"hello":"world"}"#,
        )
        .await
        .expect("failed to persist artifact");

    assert!(!manifest.is_segment_backed());
    assert!(manifest.blob_path.is_none());
    assert!(manifest.segment_id.is_none());
    assert_eq!(
        store
            .inline_bytes(&manifest.artifact_id)
            .expect("failed to read inline bytes")
            .expect("inline bytes should exist"),
        br#"{"hello":"world"}"#
    );
    assert_eq!(
        store
            .fetch_inline_artifact_bytes(ArtifactProducer::Xcode, "ios", "artifact-1")
            .expect("failed to fetch inline artifact bytes")
            .expect("inline artifact bytes should exist"),
        br#"{"hello":"world"}"#
    );
    assert_eq!(
        read_manifest_bytes(&store, &manifest).await,
        br#"{"hello":"world"}"#
    );
    let raw = store
        .db
        .get_cf(
            store.cf(ROCKSDB_CF_MANIFESTS),
            manifest.artifact_id.as_bytes(),
        )
        .expect("failed to read raw manifest bytes")
        .expect("manifest bytes should exist");
    assert_eq!(
        raw[0], b'{',
        "keyvalue manifest should keep json encoding for now"
    );
}

#[tokio::test]
async fn manifest_index_rebuilds_from_rocksdb_on_restart() {
    let (_temp_dir, config, store) = temp_store();
    let manifest = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Module,
            "ios",
            "builds/hash-1/Module.framework",
            "application/octet-stream",
            b"module-bytes",
        )
        .await
        .expect("failed to persist artifact");

    drop(store);

    let reopened_metrics = Metrics::new(config.region.clone(), config.tenant_id.clone());
    let reopened_io = IoController::new(
        reopened_metrics,
        config.file_descriptor_pool_size,
        std::time::Duration::from_millis(config.file_descriptor_acquire_timeout_ms),
        vec![config.tmp_dir.clone(), config.data_dir.clone()],
    )
    .expect("failed to create reopened io controller");
    let reopened_memory = MemoryController::new(
        reopened_io.metrics(),
        config.memory_soft_limit_bytes,
        config.memory_hard_limit_bytes,
    );
    let reopened =
        Store::open(&config, reopened_io, reopened_memory).expect("failed to reopen store");

    let rebuilt = reopened
        .manifest(&manifest.artifact_id)
        .expect("manifest lookup should succeed")
        .expect("manifest should be present after rebuild");
    assert_eq!(rebuilt, manifest);
    assert_eq!(
        read_manifest_bytes(&reopened, &rebuilt).await,
        b"module-bytes"
    );
}

#[tokio::test]
async fn manifests_page_returns_results_in_artifact_id_order() {
    let (_temp_dir, _config, store) = temp_store();

    let first = store
        .persist_inline_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "action-a",
            "application/json",
            br#"{"a":1}"#,
        )
        .await
        .expect("failed to persist first artifact");
    let second = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Gradle,
            "ios",
            "artifact-b",
            "application/octet-stream",
            b"gradle",
        )
        .await
        .expect("failed to persist second artifact");

    let first_page = store
        .manifests_page_scoped(None, None, 1)
        .expect("failed to load first manifest page");
    assert_eq!(first_page.manifests.len(), 1);
    assert!(
        first_page.manifests[0].artifact_id == first.artifact_id
            || first_page.manifests[0].artifact_id == second.artifact_id
    );
    assert_eq!(
        first_page.next_after,
        Some(first_page.manifests[0].artifact_id.clone())
    );

    let second_page = store
        .manifests_page_scoped(first_page.next_after.as_deref(), None, 1)
        .expect("failed to load second manifest page");
    assert_eq!(second_page.manifests.len(), 1);
    assert_ne!(
        second_page.manifests[0].artifact_id,
        first_page.manifests[0].artifact_id
    );
    assert!(
        second_page.manifests[0].artifact_id == first.artifact_id
            || second_page.manifests[0].artifact_id == second.artifact_id
    );
}

async fn apply_inline(store: &Store, key: &str, version_ms: u64, bytes: &[u8]) {
    store
        .apply_replicated_inline_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            key,
            "application/octet-stream",
            bytes,
            version_ms,
        )
        .await
        .expect("failed to apply replicated inline artifact");
}

#[tokio::test]
async fn manifests_digest_partitions_keyspace_and_matches_identical_stores() {
    let (_temp_dir_a, _config_a, store_a) = temp_store();
    let (_temp_dir_b, _config_b, store_b) = temp_store();

    // Same replicated artifacts (identical id + version_ms) on both stores,
    // mirroring how a peer holds the same version of a replicated artifact.
    for key in ["alpha", "beta", "gamma", "delta", "epsilon"] {
        apply_inline(&store_a, key, 100, b"payload").await;
        apply_inline(&store_b, key, 100, b"payload").await;
    }

    let digest_a = store_a.manifests_digest(3).expect("digest a");
    let digest_b = store_b.manifests_digest(3).expect("digest b");

    assert_eq!(
        digest_a, digest_b,
        "identical content must yield identical digests across nodes"
    );
    assert_eq!(
        digest_a.iter().map(|bucket| bucket.count).sum::<u64>(),
        5,
        "bucket counts must sum to the total manifest count"
    );
    for bucket in &digest_a {
        assert_eq!(bucket.prefix.len(), 3, "prefix_len must be honored");
    }
    let mut prefixes: Vec<&str> = digest_a.iter().map(|b| b.prefix.as_str()).collect();
    let sorted = {
        let mut copy = prefixes.clone();
        copy.sort_unstable();
        copy
    };
    assert_eq!(prefixes, sorted, "buckets must be emitted in sorted order");
    prefixes.dedup();
    assert_eq!(prefixes.len(), digest_a.len(), "bucket prefixes are unique");
}

#[tokio::test]
async fn manifests_digest_flips_only_the_changed_bucket_on_version_bump() {
    let (_temp_dir, _config, store) = temp_store();
    for key in ["alpha", "beta", "gamma", "delta"] {
        apply_inline(&store, key, 100, b"payload").await;
    }

    let before = store.manifests_digest(3).expect("digest before");

    // Locate the artifact_id (hence bucket prefix) for "alpha".
    let manifests = store
        .manifests_page_scoped(None, None, 256)
        .expect("list manifests")
        .manifests;
    let alpha_id = manifests
        .iter()
        .find(|m| m.key == "alpha")
        .expect("alpha manifest")
        .artifact_id
        .clone();
    let alpha_prefix: String = alpha_id.chars().take(3).collect();

    // A version bump on the same key keeps the id (and bucket) but must flip
    // the bucket's hash so the peer detects the newer version.
    apply_inline(&store, "alpha", 200, b"payload-v2").await;
    let after = store.manifests_digest(3).expect("digest after");

    for bucket_before in &before {
        let bucket_after = after
            .iter()
            .find(|b| b.prefix == bucket_before.prefix)
            .expect("bucket present after");
        if bucket_before.prefix == alpha_prefix {
            assert_eq!(
                bucket_before.count, bucket_after.count,
                "a version bump must not change the bucket count"
            );
            assert_ne!(
                bucket_before.hash, bucket_after.hash,
                "a version bump must flip the bucket hash"
            );
        } else {
            assert_eq!(
                bucket_before, bucket_after,
                "unrelated buckets must be untouched"
            );
        }
    }
}

#[tokio::test]
async fn manifests_page_scoped_restricts_to_prefix() {
    let (_temp_dir, _config, store) = temp_store();
    for key in ["alpha", "beta", "gamma", "delta", "epsilon", "zeta"] {
        apply_inline(&store, key, 100, b"payload").await;
    }

    let all = store
        .manifests_page_scoped(None, None, 256)
        .expect("list all")
        .manifests;
    let target_prefix: String = all[0].artifact_id.chars().take(2).collect();
    let expected: Vec<String> = all
        .iter()
        .filter(|m| m.artifact_id.starts_with(&target_prefix))
        .map(|m| m.artifact_id.clone())
        .collect();

    let scoped = store
        .manifests_page_scoped(None, Some(&target_prefix), 256)
        .expect("scoped walk")
        .manifests;
    let scoped_ids: Vec<String> = scoped.iter().map(|m| m.artifact_id.clone()).collect();

    assert_eq!(
        scoped_ids, expected,
        "scoped walk must return exactly the artifacts in the prefix range"
    );
    assert!(
        scoped
            .iter()
            .all(|m| m.artifact_id.starts_with(&target_prefix)),
        "scoped walk must not leak artifacts outside the prefix"
    );
}

#[tokio::test]
async fn namespace_tombstones_page_returns_written_tombstones() {
    let (_temp_dir, _config, store) = temp_store();

    store
        .apply_replicated_namespace_delete("ios", 100)
        .await
        .expect("failed to apply first tombstone");
    store
        .apply_replicated_namespace_delete("android", 200)
        .await
        .expect("failed to apply second tombstone");

    let page = store
        .namespace_tombstones_page(None, 8)
        .expect("failed to load tombstone page");
    assert_eq!(page.tombstones.len(), 2);
    assert_eq!(page.tombstones[0].namespace_id, "android");
    assert_eq!(page.tombstones[0].version_ms, 200);
    assert_eq!(page.tombstones[1].namespace_id, "ios");
    assert_eq!(page.tombstones[1].version_ms, 100);
    assert_eq!(page.next_after, None);
}

#[tokio::test]
async fn manifest_cache_stays_within_configured_byte_budget() {
    let (_temp_dir, _config, store) = temp_store_with(|config| {
        config.manifest_cache_max_bytes = 256;
    });

    let first = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Gradle,
            "ios",
            "artifact-1",
            "application/octet-stream",
            b"first",
        )
        .await
        .expect("failed to persist first artifact");
    let second = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Gradle,
            "ios",
            "artifact-2",
            "application/octet-stream",
            b"second",
        )
        .await
        .expect("failed to persist second artifact");

    {
        let cache = store
            .manifest_cache
            .lock()
            .expect("manifest cache lock poisoned");
        assert!(
            cache.total_bytes() <= 256,
            "manifest cache should stay within its configured byte budget"
        );
        assert!(
            cache.len() < 2,
            "manifest cache should evict once it cannot hold every manifest"
        );
    }

    store.trim_manifest_cache_to(0, "test");
    let reloaded = store
        .manifest(&first.artifact_id)
        .expect("manifest lookup should succeed")
        .expect("first manifest should reload from RocksDB");
    assert_eq!(reloaded.artifact_id, first.artifact_id);
    let reloaded = store
        .manifest(&second.artifact_id)
        .expect("manifest lookup should succeed")
        .expect("second manifest should reload from RocksDB");
    assert_eq!(reloaded.artifact_id, second.artifact_id);
}

#[tokio::test]
async fn segment_handle_cache_evicts_least_recently_used_handles_when_full() {
    let (_temp_dir, _config, store) = temp_store_with(|config| {
        config.segment_handle_cache_size = 1;
    });

    let xcode = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact-1",
            "application/octet-stream",
            b"xcode",
        )
        .await
        .expect("failed to persist xcode artifact");
    let gradle = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Gradle,
            "android",
            "artifact-2",
            "application/octet-stream",
            b"gradle",
        )
        .await
        .expect("failed to persist gradle artifact");

    let _ = read_manifest_bytes(&store, &xcode).await;
    {
        let cache = store.segment_handles.lock().await;
        assert_eq!(cache.len(), 1);
        assert!(
            cache.entries.contains_key(&segment_handle_cache_key(
                xcode
                    .segment_id
                    .as_deref()
                    .expect("xcode manifest should have a segment id")
            ))
        );
    }

    let _ = read_manifest_bytes(&store, &gradle).await;
    {
        let cache = store.segment_handles.lock().await;
        assert_eq!(cache.len(), 1);
        assert!(
            cache.entries.contains_key(&segment_handle_cache_key(
                gradle
                    .segment_id
                    .as_deref()
                    .expect("gradle manifest should have a segment id")
            ))
        );
        if xcode.segment_id != gradle.segment_id {
            assert!(
                !cache.entries.contains_key(&segment_handle_cache_key(
                    xcode
                        .segment_id
                        .as_deref()
                        .expect("xcode manifest should have a segment id")
                ))
            );
        }
    }
}

#[tokio::test]
async fn blob_handle_cache_is_bounded_and_dropped_before_namespace_delete() {
    let (_temp_dir, config, store) = temp_store_with(|config| {
        config.segment_handle_cache_size = 1;
    });
    let blob_path = config.data_dir.join("blobs").join("legacy-blob");
    std::fs::write(&blob_path, b"legacy-blob-payload").expect("failed to write blob");
    let blob_path_string = blob_path.to_string_lossy().into_owned();
    let artifact_id = artifact_storage_id(
        ArtifactProducer::Module,
        &config.tenant_id,
        "ios",
        "legacy-key",
    );
    let manifest = ArtifactManifest {
        artifact_id: artifact_id.clone(),
        producer: ArtifactProducer::Module,
        namespace_id: "ios".to_owned(),
        key: "legacy-key".to_owned(),
        content_type: "application/octet-stream".to_owned(),
        inline: false,
        blob_path: Some(blob_path_string.clone()),
        segment_id: None,
        segment_offset: None,
        size: b"legacy-blob-payload".len() as u64,
        version_ms: 100,
        created_at_ms: 100,
    };

    store
        .db
        .put_cf(
            store.cf(ROCKSDB_CF_MANIFESTS),
            artifact_id.as_bytes(),
            encode_manifest_record(&manifest).expect("manifest should encode"),
        )
        .expect("failed to persist manifest");
    store
        .db
        .put_cf(
            store.cf(ROCKSDB_CF_NAMESPACE_ARTIFACTS),
            namespace_artifact_index_key("ios", &artifact_id).as_bytes(),
            [],
        )
        .expect("failed to persist namespace index");

    assert_eq!(
        read_manifest_bytes(&store, &manifest).await,
        b"legacy-blob-payload"
    );
    {
        let cache = store.segment_handles.lock().await;
        assert_eq!(cache.len(), 1);
        assert!(
            cache
                .entries
                .contains_key(&blob_handle_cache_key(&blob_path_string))
        );
    }

    store
        .delete_namespace("ios")
        .await
        .expect("failed to delete namespace");

    {
        let cache = store.segment_handles.lock().await;
        assert!(
            !cache
                .entries
                .contains_key(&blob_handle_cache_key(&blob_path_string))
        );
    }
    assert!(!blob_path.exists());
}

#[tokio::test]
async fn fetch_artifact_refreshes_old_segment_backed_artifacts() {
    let (_temp_dir, _config, store) = temp_store();

    let manifest = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact-1",
            "application/octet-stream",
            b"hello",
        )
        .await
        .expect("failed to persist artifact");
    let original_segment_id = manifest
        .segment_id
        .clone()
        .expect("segment-backed artifact should have a segment id");
    store
        .save_segment_state(&SegmentState {
            old: vec![SegmentReference::new(original_segment_id.clone(), 1)],
            current: Vec::new(),
            new: vec![SegmentReference::new("fresh-segment".into(), 2)],
        })
        .expect("failed to seed segment state");

    let fetched = store
        .fetch_artifact(ArtifactProducer::Xcode, "ios", "artifact-1")
        .await
        .expect("failed to fetch artifact")
        .expect("artifact should still exist");

    assert_ne!(fetched.segment_id, Some(original_segment_id));
    assert_eq!(read_manifest_bytes(&store, &fetched).await, b"hello");
    assert_eq!(
        store
            .manifest(&fetched.artifact_id)
            .expect("failed to load manifest")
            .expect("refreshed manifest should still exist"),
        fetched
    );
    assert_eq!(store.segment_handles.lock().await.len(), 2);
}

#[tokio::test]
async fn serving_defers_old_segment_promotion_off_the_read_path() {
    let (_temp_dir, _config, store) = temp_store();

    let manifest = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact-1",
            "application/octet-stream",
            b"hello",
        )
        .await
        .expect("failed to persist artifact");
    let original_segment_id = manifest
        .segment_id
        .clone()
        .expect("segment-backed artifact should have a segment id");
    store
        .save_segment_state(&SegmentState {
            old: vec![SegmentReference::new(original_segment_id.clone(), 1)],
            current: Vec::new(),
            new: vec![SegmentReference::new("fresh-segment".into(), 2)],
        })
        .expect("failed to seed segment state");

    // The serving path answers straight from the Old segment (no inline
    // refresh) and queues the artifact for background promotion.
    let served = store
        .fetch_artifact_for_serving(ArtifactProducer::Xcode, "ios", "artifact-1")
        .await
        .expect("failed to fetch artifact for serving")
        .expect("artifact should still exist");
    assert_eq!(served.segment_id, Some(original_segment_id.clone()));
    assert_eq!(read_manifest_bytes(&store, &served).await, b"hello");
    {
        let queue = store.promotion_queue.lock().expect("queue lock");
        assert_eq!(queue.order.len(), 1);
        assert!(queue.pending.contains(&served.artifact_id));
    }

    // A second read of the same artifact does not enqueue it twice.
    store
        .fetch_artifact_for_serving(ArtifactProducer::Xcode, "ios", "artifact-1")
        .await
        .expect("failed to fetch artifact for serving")
        .expect("artifact should still exist");
    assert_eq!(
        store
            .promotion_queue
            .lock()
            .expect("queue lock")
            .order
            .len(),
        1
    );

    // Applying the queued promotion rewrites the artifact into the current
    // segment, exactly like the refresh the read path used to run inline.
    store
        .promote_artifact(&served.artifact_id)
        .await
        .expect("promotion should succeed");
    let promoted = store
        .manifest(&served.artifact_id)
        .expect("failed to load manifest")
        .expect("promoted manifest should exist");
    assert_ne!(promoted.segment_id, Some(original_segment_id));
    assert_eq!(read_manifest_bytes(&store, &promoted).await, b"hello");
}

#[tokio::test]
async fn tolerant_read_reresolves_when_a_concurrent_promotion_evicted_the_old_segment() {
    let (_temp_dir, _config, store) = temp_store();

    // Persist, then promote so the live manifest points at a new segment,
    // then evict the original segment out from under the pre-promotion
    // manifest -- the exact race a background promotion opens against a
    // serving read that already captured the old manifest.
    let stale = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact-1",
            "application/octet-stream",
            b"hello",
        )
        .await
        .expect("failed to persist artifact");
    let old_segment = stale
        .segment_id
        .clone()
        .expect("segment-backed artifact should have a segment id");
    store
        .save_segment_state(&SegmentState {
            old: vec![SegmentReference::new(old_segment.clone(), 1)],
            current: Vec::new(),
            new: vec![SegmentReference::new("fresh-segment".into(), 2)],
        })
        .expect("failed to seed segment state");
    store
        .promote_artifact(&stale.artifact_id)
        .await
        .expect("promotion should succeed");
    assert_ne!(
        store
            .manifest(&stale.artifact_id)
            .expect("lookup")
            .expect("manifest")
            .segment_id,
        stale.segment_id,
        "promotion should have relocated the artifact"
    );
    store
        .evict_segment(&old_segment)
        .await
        .expect("eviction should succeed");

    // The pre-promotion manifest can no longer be read directly...
    assert!(store.read_artifact_bytes(&stale).await.is_err());
    // ...but the tolerant read re-resolves to the promoted location.
    assert_eq!(
        store
            .read_artifact_bytes_tolerating_promotion(&stale)
            .await
            .expect("tolerant read should succeed"),
        Some(b"hello".to_vec())
    );
}

#[tokio::test]
async fn tolerant_read_reports_a_miss_when_the_artifact_was_actually_evicted() {
    let (_temp_dir, _config, store) = temp_store();

    let stale = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact-1",
            "application/octet-stream",
            b"hello",
        )
        .await
        .expect("failed to persist artifact");
    let old_segment = stale
        .segment_id
        .clone()
        .expect("segment-backed artifact should have a segment id");
    // Evict while the artifact still lives in the old segment (not promoted)
    // so its manifest is deleted and the file unlinked: a genuine miss.
    store
        .save_segment_state(&SegmentState {
            old: vec![SegmentReference::new(old_segment.clone(), 1)],
            current: Vec::new(),
            new: vec![SegmentReference::new("fresh-segment".into(), 2)],
        })
        .expect("failed to seed segment state");
    store
        .evict_segment(&old_segment)
        .await
        .expect("eviction should succeed");

    assert_eq!(
        store
            .read_artifact_bytes_tolerating_promotion(&stale)
            .await
            .expect("tolerant read should not error on a miss"),
        None
    );
}

async fn drain_reader(mut reader: ArtifactReader) -> Vec<u8> {
    use tokio::io::AsyncReadExt;
    let mut bytes = Vec::new();
    reader
        .read_to_end(&mut bytes)
        .await
        .expect("reader should drain");
    bytes
}

#[tokio::test]
async fn tolerant_reader_reresolves_when_a_concurrent_promotion_evicted_the_old_segment() {
    let (_temp_dir, _config, store) = temp_store();

    let stale = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact-1",
            "application/octet-stream",
            b"hello",
        )
        .await
        .expect("failed to persist artifact");
    let old_segment = stale
        .segment_id
        .clone()
        .expect("segment-backed artifact should have a segment id");
    store
        .save_segment_state(&SegmentState {
            old: vec![SegmentReference::new(old_segment.clone(), 1)],
            current: Vec::new(),
            new: vec![SegmentReference::new("fresh-segment".into(), 2)],
        })
        .expect("failed to seed segment state");
    store
        .promote_artifact(&stale.artifact_id)
        .await
        .expect("promotion should succeed");
    store
        .evict_segment(&old_segment)
        .await
        .expect("eviction should succeed");

    // The stale manifest can no longer be opened directly...
    assert!(store.open_artifact_reader(&stale).await.is_err());
    // ...but the tolerant open re-resolves to the promoted location and
    // hands back the manifest the bytes actually come from.
    let (fresh, reader) = store
        .open_artifact_reader_range_tolerating_promotion(&stale, 0, None)
        .await
        .expect("tolerant open should succeed")
        .expect("artifact should still be served");
    assert_ne!(fresh.segment_id, stale.segment_id);
    assert_eq!(drain_reader(reader).await, b"hello");
}

#[tokio::test]
async fn tolerant_reader_reports_a_miss_when_the_artifact_was_actually_evicted() {
    let (_temp_dir, _config, store) = temp_store();

    let stale = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact-1",
            "application/octet-stream",
            b"hello",
        )
        .await
        .expect("failed to persist artifact");
    let old_segment = stale
        .segment_id
        .clone()
        .expect("segment-backed artifact should have a segment id");
    store
        .save_segment_state(&SegmentState {
            old: vec![SegmentReference::new(old_segment.clone(), 1)],
            current: Vec::new(),
            new: vec![SegmentReference::new("fresh-segment".into(), 2)],
        })
        .expect("failed to seed segment state");
    store
        .evict_segment(&old_segment)
        .await
        .expect("eviction should succeed");

    assert!(
        store
            .open_artifact_reader_range_tolerating_promotion(&stale, 0, None)
            .await
            .expect("tolerant open should not error on a miss")
            .is_none()
    );
}

#[tokio::test]
async fn promotion_worker_drains_reads_queued_from_old_segments() {
    let (_temp_dir, _config, store) = temp_store();
    let store = Arc::new(store);

    let manifest = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact-1",
            "application/octet-stream",
            b"hello",
        )
        .await
        .expect("failed to persist artifact");
    let original_segment_id = manifest
        .segment_id
        .clone()
        .expect("segment-backed artifact should have a segment id");
    store
        .save_segment_state(&SegmentState {
            old: vec![SegmentReference::new(original_segment_id.clone(), 1)],
            current: Vec::new(),
            new: vec![SegmentReference::new("fresh-segment".into(), 2)],
        })
        .expect("failed to seed segment state");

    let worker_store = Arc::clone(&store);
    tokio::spawn(async move { worker_store.run_promotion_worker().await });

    store
        .fetch_artifact_for_serving(ArtifactProducer::Xcode, "ios", "artifact-1")
        .await
        .expect("failed to fetch artifact for serving")
        .expect("artifact should still exist");

    let promoted = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let manifest = store
                .manifest(&manifest.artifact_id)
                .expect("failed to load manifest")
                .expect("manifest should exist");
            if manifest.segment_id != Some(original_segment_id.clone()) {
                return manifest;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    .expect("worker should promote the artifact");
    assert_eq!(read_manifest_bytes(&store, &promoted).await, b"hello");
}

#[tokio::test]
async fn evict_segment_removes_segment_backed_manifests() {
    let (_temp_dir, _config, store) = temp_store();

    let manifest = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Gradle,
            "android",
            "artifact-1",
            "application/octet-stream",
            b"hello",
        )
        .await
        .expect("failed to persist artifact");
    let segment_id = manifest
        .segment_id
        .clone()
        .expect("segment-backed artifact should have a segment id");
    let segment_path = store.segment_path(&segment_id);

    store
        .evict_segment(&segment_id)
        .await
        .expect("failed to evict segment");

    assert!(
        store
            .fetch_artifact(ArtifactProducer::Gradle, "android", "artifact-1")
            .await
            .expect("failed to fetch artifact")
            .is_none()
    );
    assert!(
        store
            .manifest(&manifest.artifact_id)
            .expect("failed to load manifest")
            .is_none()
    );
    assert!(!segment_path.exists());
    assert_eq!(store.segment_handles.lock().await.len(), 0);
}

#[tokio::test]
async fn delete_namespace_removes_keyvalue_payloads() {
    let (_temp_dir, _config, store) = temp_store();

    let manifest = store
        .persist_inline_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "android",
            "gradle-1",
            "application/json",
            br#"{"gradle":"cache"}"#,
        )
        .await
        .expect("failed to persist artifact");

    store
        .delete_namespace("android")
        .await
        .expect("failed to delete namespace");

    assert!(
        store
            .fetch_artifact(ArtifactProducer::Xcode, "android", "gradle-1")
            .await
            .expect("failed to fetch artifact")
            .is_none()
    );
    assert!(
        store
            .inline_bytes(&manifest.artifact_id)
            .expect("failed to read inline bytes")
            .is_none()
    );
}

#[tokio::test]
async fn replicated_namespace_tombstones_reject_stale_upserts() {
    let (_temp_dir, _config, store) = temp_store();

    assert!(
        store
            .apply_replicated_namespace_delete("ios", 200)
            .await
            .expect("namespace delete should apply")
            .applied()
    );

    assert_eq!(
        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact-1",
                "application/octet-stream",
                b"stale",
                100,
            )
            .await
            .expect("stale artifact should be ignored"),
        ArtifactApplyOutcome::IgnoredTombstone
    );
    assert!(
        !store
            .artifact_version_is_current(ArtifactProducer::Gradle, "ios", "artifact-1", 100)
            .expect("version check should succeed")
    );
    assert!(
        store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact-1")
            .await
            .expect("artifact fetch should succeed")
            .is_none()
    );
}

#[tokio::test]
async fn replicated_namespace_delete_only_removes_older_artifacts() {
    let (_temp_dir, _config, store) = temp_store();

    assert!(
        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact-old",
                "application/octet-stream",
                b"old",
                100,
            )
            .await
            .expect("old artifact should apply")
            .applied()
    );
    assert!(
        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact-new",
                "application/octet-stream",
                b"new",
                300,
            )
            .await
            .expect("new artifact should apply")
            .applied()
    );

    assert!(
        store
            .apply_replicated_namespace_delete("ios", 200)
            .await
            .expect("namespace delete should apply")
            .applied()
    );

    assert!(
        store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact-old")
            .await
            .expect("old artifact fetch should succeed")
            .is_none()
    );
    let remaining = store
        .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact-new")
        .await
        .expect("new artifact fetch should succeed")
        .expect("newer artifact should remain");
    assert_eq!(remaining.version_ms, 300);
    assert_eq!(read_manifest_bytes(&store, &remaining).await, b"new");
}

#[tokio::test]
async fn newer_replicated_upserts_win_over_older_ones() {
    let (_temp_dir, _config, store) = temp_store();

    assert!(
        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"v1",
                100,
            )
            .await
            .expect("initial artifact should apply")
            .applied()
    );
    assert!(
        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"v2",
                200,
            )
            .await
            .expect("newer artifact should apply")
            .applied()
    );
    assert_eq!(
        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"stale",
                150,
            )
            .await
            .expect("stale artifact should resolve cleanly"),
        ArtifactApplyOutcome::IgnoredStale
    );

    let manifest = store
        .fetch_artifact(ArtifactProducer::Xcode, "ios", "artifact")
        .await
        .expect("artifact fetch should succeed")
        .expect("artifact should remain");
    assert_eq!(manifest.version_ms, 200);
    assert_eq!(read_manifest_bytes(&store, &manifest).await, b"v2");
}

#[tokio::test]
async fn multipart_upload_round_trip() {
    let (_temp_dir, config, store) = temp_store();
    let upload_id = store
        .start_multipart_upload("acme", "ios", "builds", "hash-1", "Module.framework")
        .expect("failed to start upload");

    let part_1 = config.tmp_dir.join("part-1");
    let part_2 = config.tmp_dir.join("part-2");
    std::fs::write(&part_1, b"part-one-").expect("failed to write part 1");
    std::fs::write(&part_2, b"part-two").expect("failed to write part 2");

    store
        .add_multipart_part(&upload_id, 1, &part_1, 9)
        .await
        .expect("failed to store part 1");
    store
        .add_multipart_part(&upload_id, 2, &part_2, 8)
        .await
        .expect("failed to store part 2");

    let manifest = store
        .complete_multipart_upload(&upload_id, &[1, 2])
        .await
        .expect("failed to complete upload");

    assert_eq!(
        read_manifest_bytes(&store, &manifest).await,
        b"part-one-part-two"
    );
    assert!(
        store
            .multipart_upload(&upload_id)
            .expect("failed to load multipart upload")
            .is_none()
    );
}

#[tokio::test]
async fn concurrent_multipart_part_writes_do_not_lose_updates() {
    let (_temp_dir, config, store) = temp_store();
    let upload_id = store
        .start_multipart_upload("acme", "ios", "builds", "hash-1", "Module.framework")
        .expect("failed to start upload");
    let store = Arc::new(store);

    let mut handles = Vec::new();
    for part_number in 1u32..=8 {
        let part_path = config.tmp_dir.join(format!("part-{part_number}"));
        std::fs::write(&part_path, format!("part-{part_number}")).expect("write part");
        let store = store.clone();
        let upload_id = upload_id.clone();
        handles.push(tokio::spawn(async move {
            store
                .add_multipart_part(&upload_id, part_number, &part_path, 6)
                .await
                .expect("part should persist");
        }));
    }
    for handle in handles {
        handle.await.expect("part task should complete");
    }

    let upload = store
        .multipart_upload(&upload_id)
        .expect("failed to load multipart upload")
        .expect("upload should exist");
    assert_eq!(upload.parts.len(), 8, "all 8 parts should be persisted");
    for part_number in 1u32..=8 {
        assert!(
            upload.parts.contains_key(&part_number),
            "missing part {part_number}"
        );
    }
}

#[test]
fn multipart_size_validation_accounts_for_replaced_parts() {
    let mut parts = BTreeMap::new();
    parts.insert(
        1,
        MultipartPart {
            path: "part-1".into(),
            size: 10,
        },
    );
    parts.insert(
        2,
        MultipartPart {
            path: "part-2".into(),
            size: 5,
        },
    );

    assert_eq!(next_total_size(&parts, 1, 8), 13);
    assert_eq!(
        validate_total_size(101, 100),
        Err(MultipartError::TotalSizeExceeded)
    );
    assert_eq!(validate_total_size(100, 100), Ok(()));
}

#[test]
fn outbox_queue_round_trip() {
    let (_temp_dir, _config, store) = temp_store();

    store
        .enqueue(OutboxMessage {
            target: "http://peer".into(),
            operation: ReplicationOperation::DeleteNamespace {
                namespace_id: "ios".into(),
                version_ms: 123,
            },
        })
        .expect("failed to enqueue outbox message");

    let messages = store
        .outbox_messages()
        .expect("failed to read outbox messages");
    assert_eq!(messages.len(), 1);

    let (key, message) = &messages[0];
    assert_eq!(
        *message,
        OutboxMessage {
            target: "http://peer".into(),
            operation: ReplicationOperation::DeleteNamespace {
                namespace_id: "ios".into(),
                version_ms: 123,
            },
        }
    );

    store
        .delete_outbox_message(key)
        .expect("failed to delete outbox message");
    assert!(
        store
            .outbox_messages()
            .expect("failed to read outbox messages")
            .is_empty()
    );
}

#[test]
fn outbox_drains_metadata_before_earlier_bulk_messages() {
    let (_temp_dir, _config, store) = temp_store();

    // Bulk first (earlier timestamp), metadata second: the metadata-lane
    // key must still sort first so an inline action-cache entry is not
    // parked behind a segment-blob backlog.
    store
        .enqueue(OutboxMessage {
            target: "http://peer".into(),
            operation: ReplicationOperation::UpsertArtifact {
                producer: ArtifactProducer::Reapi,
                namespace_id: "ios".into(),
                key: "blob/aabb".into(),
                content_type: "application/octet-stream".into(),
                artifact_id: "blob-artifact".into(),
                inline: false,
                version_ms: 1,
            },
        })
        .expect("failed to enqueue bulk message");
    store
        .enqueue(OutboxMessage {
            target: "http://peer".into(),
            operation: ReplicationOperation::UpsertArtifact {
                producer: ArtifactProducer::Reapi,
                namespace_id: "ios".into(),
                key: "action_cache/ccdd".into(),
                content_type: "application/x-protobuf".into(),
                artifact_id: "entry-artifact".into(),
                inline: true,
                version_ms: 2,
            },
        })
        .expect("failed to enqueue metadata message");

    let messages = store
        .outbox_messages()
        .expect("failed to read outbox messages");
    let keys: Vec<&str> = messages
        .iter()
        .map(|(key, _)| std::str::from_utf8(key).expect("outbox key should be utf-8"))
        .collect();
    assert!(
        keys[0].starts_with("0-") && keys[1].starts_with(OUTBOX_BULK_LANE_PREFIX),
        "expected metadata lane before bulk lane, got {keys:?}"
    );
    let (_, first) = &messages[0];
    assert!(!first.operation.is_bulk());
    // Legacy unprefixed keys (zero-padded timestamps) drain between the
    // lanes across a rolling upgrade.
    let legacy = format!("{:020}-legacy", crate::utils::now_ms());
    assert!(keys[0] < legacy.as_str() && legacy.as_str() < keys[1]);
}

#[test]
fn snapshot_reports_outbox_depth_without_loading_messages() {
    let (_temp_dir, _config, store) = temp_store();

    store
        .enqueue(OutboxMessage {
            target: "http://peer-a".into(),
            operation: ReplicationOperation::DeleteNamespace {
                namespace_id: "ios".into(),
                version_ms: 123,
            },
        })
        .expect("failed to enqueue first outbox message");
    store
        .enqueue(OutboxMessage {
            target: "http://peer-b".into(),
            operation: ReplicationOperation::DeleteNamespace {
                namespace_id: "android".into(),
                version_ms: 456,
            },
        })
        .expect("failed to enqueue second outbox message");

    assert_eq!(
        store
            .outbox_message_count()
            .expect("outbox count should load"),
        2
    );

    let snapshot = store.snapshot().expect("snapshot should load");
    assert_eq!(snapshot.outbox_messages, 2);
    assert_eq!(
        snapshot.rocksdb_block_cache_capacity_bytes,
        _config.rocksdb_block_cache_bytes as u64
    );
    assert_eq!(
        snapshot.rocksdb_write_buffer_capacity_bytes,
        _config.rocksdb_write_buffer_manager_bytes as u64
    );
}

#[tokio::test]
async fn local_write_enqueues_replication_targets_in_same_store_operation() {
    let (_temp_dir, _config, store) = temp_store();
    let targets = vec!["http://peer-a".to_string(), "http://peer-b".to_string()];

    let manifest = store
        .persist_inline_artifact_from_bytes_and_enqueue(
            ArtifactProducer::Xcode,
            "ios",
            "cas-1",
            "application/json",
            br#"{"ok":true}"#,
            &targets,
        )
        .await
        .expect("artifact should persist");

    let queued = store
        .outbox_messages()
        .expect("outbox messages should load")
        .into_iter()
        .map(|(_, message)| message)
        .collect::<Vec<_>>();

    assert_eq!(queued.len(), 2);
    assert_eq!(queued[0].target, "http://peer-a");
    assert_eq!(queued[1].target, "http://peer-b");
    for message in queued {
        assert_eq!(
            message.operation,
            ReplicationOperation::UpsertArtifact {
                producer: ArtifactProducer::Xcode,
                namespace_id: "ios".into(),
                key: "cas-1".into(),
                content_type: "application/json".into(),
                artifact_id: manifest.artifact_id.clone(),
                version_ms: manifest.version_ms,
                inline: true,
            }
        );
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn concurrent_artifact_writes_batch_segment_fsyncs() {
    let (_temp_dir, config, store) = temp_store();
    let store = Arc::new(store);

    // Slow every segment fsync so all writers reach the durability barrier
    // within one window. With one fsync per write under the global segment
    // write lock these serialize (one fsync each); group commit must
    // coalesce them into far fewer.
    store.failpoints().set_always(
        FailpointName::BeforeSegmentFsync,
        FailpointAction::Sleep(std::time::Duration::from_millis(50)),
    );

    let writers = 16u64;
    let mut handles = Vec::new();
    for i in 0..writers {
        let store = store.clone();
        let path = config.tmp_dir.join(format!("artifact-{i}"));
        std::fs::write(&path, format!("artifact-body-{i}")).expect("write artifact body");
        handles.push(tokio::spawn(async move {
            store
                .persist_artifact_from_path_and_enqueue(
                    ArtifactProducer::Xcode,
                    "ns",
                    &format!("key-{i}"),
                    "application/octet-stream",
                    &path,
                    &[],
                )
                .await
                .expect("artifact should persist");
        }));
    }
    for handle in handles {
        handle.await.expect("writer task should complete");
    }

    let fsyncs = store
        .segment_fsync_count
        .load(std::sync::atomic::Ordering::Relaxed);
    assert!(
        fsyncs <= 4,
        "expected concurrent writes to batch segment fsyncs (<=4) but observed {fsyncs} \
             for {writers} writers — every write is fsyncing under the global segment write lock"
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn concurrent_replicated_artifact_applies_batch_segment_fsyncs() {
    let (_temp_dir, _config, store) = temp_store();
    let store = Arc::new(store);

    // A fresh node bootstrapping an account applies inbound artifacts
    // concurrently (BOOTSTRAP_ARTIFACT_FETCH_CONCURRENCY at a time). Inbound
    // applies share the foreground write's segment-append + durability path
    // (`persist_artifact_from_path_with_version`), so group commit must
    // coalesce their fsyncs too — otherwise the parallel bootstrap fetch just
    // re-serializes one fsync per inbound write and gains nothing. Slow every
    // fsync so all appliers reach the durability barrier within one window.
    store.failpoints().set_always(
        FailpointName::BeforeSegmentFsync,
        FailpointAction::Sleep(std::time::Duration::from_millis(50)),
    );

    let appliers = 16u64;
    let mut handles = Vec::new();
    for i in 0..appliers {
        let store = store.clone();
        handles.push(tokio::spawn(async move {
            store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Xcode,
                    "ns",
                    &format!("key-{i}"),
                    "application/octet-stream",
                    format!("artifact-body-{i}").as_bytes(),
                    1_000 + i,
                )
                .await
                .expect("replicated artifact should apply");
        }));
    }
    for handle in handles {
        handle.await.expect("applier task should complete");
    }

    let fsyncs = store
        .segment_fsync_count
        .load(std::sync::atomic::Ordering::Relaxed);
    assert!(
        fsyncs <= 4,
        "expected concurrent replicated applies to batch segment fsyncs (<=4) but observed \
             {fsyncs} for {appliers} appliers — inbound bootstrap writes are fsyncing per write \
             under the global segment write lock"
    );
}

#[tokio::test]
async fn local_namespace_delete_enqueues_replication_targets_in_same_store_operation() {
    let (_temp_dir, _config, store) = temp_store();
    let targets = vec!["http://peer-a".to_string(), "http://peer-b".to_string()];

    store
        .persist_inline_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "cas-1",
            "application/json",
            br#"{"ok":true}"#,
        )
        .await
        .expect("artifact should persist");

    let version_ms = store
        .delete_namespace_and_enqueue("ios", &targets)
        .await
        .expect("namespace delete should succeed");

    let queued = store
        .outbox_messages()
        .expect("outbox messages should load")
        .into_iter()
        .map(|(_, message)| message)
        .collect::<Vec<_>>();

    assert_eq!(queued.len(), 2);
    for message in queued {
        assert_eq!(
            message.operation,
            ReplicationOperation::DeleteNamespace {
                namespace_id: "ios".into(),
                version_ms,
            }
        );
    }
}

#[tokio::test]
async fn segment_backed_write_remains_visible_after_post_commit_error_and_restart() {
    let (_temp_dir, config, store) = temp_store();
    store.failpoints().set_once(
        FailpointName::AfterMetadataCommitBeforeReturn,
        FailpointAction::Error("post-commit failure".into()),
    );

    let error = store
        .persist_artifact_from_bytes_and_enqueue(
            ArtifactProducer::Xcode,
            "ios",
            "artifact",
            "application/octet-stream",
            b"segment-bytes",
            &["http://peer-a".to_string()],
        )
        .await
        .expect_err("write should fail after the durable commit");
    assert!(error.contains("post-commit failure"));

    drop(store);

    let reopened_metrics = Metrics::new(config.region.clone(), config.tenant_id.clone());
    let reopened_io = IoController::new(
        reopened_metrics,
        config.file_descriptor_pool_size,
        std::time::Duration::from_millis(config.file_descriptor_acquire_timeout_ms),
        vec![config.tmp_dir.clone(), config.data_dir.clone()],
    )
    .expect("failed to create reopened io controller");
    let reopened_memory = MemoryController::new(
        reopened_io.metrics(),
        config.memory_soft_limit_bytes,
        config.memory_hard_limit_bytes,
    );
    let reopened =
        Store::open(&config, reopened_io, reopened_memory).expect("failed to reopen store");

    let manifest = reopened
        .fetch_artifact(ArtifactProducer::Xcode, "ios", "artifact")
        .await
        .expect("artifact fetch should succeed")
        .expect("artifact should remain visible after restart");
    assert_eq!(
        read_manifest_bytes(&reopened, &manifest).await,
        b"segment-bytes"
    );
    assert_eq!(
        reopened
            .outbox_message_count()
            .expect("outbox count should load"),
        1
    );
}

#[tokio::test]
async fn keyvalue_write_remains_visible_after_post_commit_error_and_restart() {
    let (_temp_dir, config, store) = temp_store();
    store.failpoints().set_once(
        FailpointName::AfterMetadataCommitBeforeReturn,
        FailpointAction::Error("post-commit failure".into()),
    );

    let error = store
        .persist_inline_artifact_from_bytes_and_enqueue(
            ArtifactProducer::Xcode,
            "ios",
            "cas-1",
            "application/json",
            br#"{"value":"ok"}"#,
            &["http://peer-a".to_string()],
        )
        .await
        .expect_err("write should fail after the durable commit");
    assert!(error.contains("post-commit failure"));

    drop(store);

    let reopened_metrics = Metrics::new(config.region.clone(), config.tenant_id.clone());
    let reopened_io = IoController::new(
        reopened_metrics,
        config.file_descriptor_pool_size,
        std::time::Duration::from_millis(config.file_descriptor_acquire_timeout_ms),
        vec![config.tmp_dir.clone(), config.data_dir.clone()],
    )
    .expect("failed to create reopened io controller");
    let reopened_memory = MemoryController::new(
        reopened_io.metrics(),
        config.memory_soft_limit_bytes,
        config.memory_hard_limit_bytes,
    );
    let reopened =
        Store::open(&config, reopened_io, reopened_memory).expect("failed to reopen store");

    let manifest = reopened
        .fetch_artifact(ArtifactProducer::Xcode, "ios", "cas-1")
        .await
        .expect("artifact fetch should succeed")
        .expect("keyvalue should remain visible after restart");
    assert_eq!(
        read_manifest_bytes(&reopened, &manifest).await,
        br#"{"value":"ok"}"#
    );
    assert_eq!(
        reopened
            .outbox_message_count()
            .expect("outbox count should load"),
        1
    );
}

#[tokio::test]
async fn duplicate_replicated_upserts_and_deletes_are_idempotent() {
    let (_temp_dir, _config, store) = temp_store();

    assert_eq!(
        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact",
                "application/octet-stream",
                b"payload",
                100,
            )
            .await
            .expect("first artifact apply should succeed"),
        ArtifactApplyOutcome::Applied
    );
    assert_eq!(
        store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact",
                "application/octet-stream",
                b"payload",
                100,
            )
            .await
            .expect("duplicate artifact apply should succeed"),
        ArtifactApplyOutcome::IgnoredStale
    );
    assert_eq!(
        store
            .apply_replicated_namespace_delete("ios", 150)
            .await
            .expect("first delete should succeed"),
        NamespaceDeleteOutcome::Applied
    );
    assert_eq!(
        store
            .apply_replicated_namespace_delete("ios", 150)
            .await
            .expect("duplicate delete should succeed"),
        NamespaceDeleteOutcome::IgnoredOlder
    );
    assert!(
        store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
            .await
            .expect("artifact fetch should succeed")
            .is_none()
    );
}

#[tokio::test]
async fn reordered_delivery_converges_to_the_same_winner() {
    let (_temp_dir_a, _config_a, first) = temp_store();
    let (_temp_dir_b, _config_b, second) = temp_store();

    first
        .apply_replicated_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact",
            "application/octet-stream",
            b"v1",
            100,
        )
        .await
        .expect("initial write should succeed");
    first
        .apply_replicated_namespace_delete("ios", 150)
        .await
        .expect("delete should succeed");
    first
        .apply_replicated_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact",
            "application/octet-stream",
            b"v1",
            100,
        )
        .await
        .expect("duplicate stale write should succeed");
    first
        .apply_replicated_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact",
            "application/octet-stream",
            b"v2",
            200,
        )
        .await
        .expect("newer write should succeed");

    second
        .apply_replicated_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact",
            "application/octet-stream",
            b"v2",
            200,
        )
        .await
        .expect("newer write should succeed");
    second
        .apply_replicated_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact",
            "application/octet-stream",
            b"v1",
            100,
        )
        .await
        .expect("older duplicate write should succeed");
    second
        .apply_replicated_namespace_delete("ios", 150)
        .await
        .expect("delete should succeed");
    second
        .apply_replicated_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact",
            "application/octet-stream",
            b"v1",
            100,
        )
        .await
        .expect("older duplicate write should succeed");

    let first_manifest = first
        .fetch_artifact(ArtifactProducer::Xcode, "ios", "artifact")
        .await
        .expect("first fetch should succeed")
        .expect("artifact should remain");
    let second_manifest = second
        .fetch_artifact(ArtifactProducer::Xcode, "ios", "artifact")
        .await
        .expect("second fetch should succeed")
        .expect("artifact should remain");

    assert_eq!(first_manifest.version_ms, 200);
    assert_eq!(second_manifest.version_ms, 200);
    assert_eq!(read_manifest_bytes(&first, &first_manifest).await, b"v2");
    assert_eq!(read_manifest_bytes(&second, &second_manifest).await, b"v2");
}

#[test]
fn segment_rotation_requires_margin_for_oversized_artifacts() {
    assert_eq!(
        segment_rotation_required_bytes(0),
        MAX_SEGMENT_BYTES * SEGMENT_FREE_SPACE_MARGIN
    );
    assert_eq!(
        segment_rotation_required_bytes(MAX_SEGMENT_BYTES),
        MAX_SEGMENT_BYTES * SEGMENT_FREE_SPACE_MARGIN
    );
    assert_eq!(
        segment_rotation_required_bytes(3 * MAX_SEGMENT_BYTES),
        3 * MAX_SEGMENT_BYTES * SEGMENT_FREE_SPACE_MARGIN
    );
}

#[tokio::test]
async fn sweep_orphaned_segments_returns_zero_without_segments_dir() {
    let (_temp_dir, _config, store) = temp_store();

    let swept = store
        .sweep_orphaned_segments()
        .await
        .expect("sweep should succeed");

    assert_eq!(swept, 0);
}

#[tokio::test]
async fn sweep_orphaned_segments_removes_stray_files_and_keeps_live_segments() {
    let (_temp_dir, config, store) = temp_store();
    let manifest = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact",
            "application/octet-stream",
            b"payload",
        )
        .await
        .expect("artifact should persist");
    let stray_path = config.data_dir.join("segments").join("stray.seg");
    std::fs::write(&stray_path, b"junk").expect("stray segment should be written");

    let swept = store
        .sweep_orphaned_segments()
        .await
        .expect("sweep should succeed");

    assert_eq!(swept, 1);
    assert!(!stray_path.exists());
    let bytes = store
        .read_artifact_bytes(&manifest)
        .await
        .expect("live artifact should remain readable");
    assert_eq!(bytes, b"payload");
}

#[tokio::test]
async fn sweep_orphaned_segments_reclaims_crash_window_segment_and_metadata() {
    let (_temp_dir, _config, store) = temp_store();
    let manifest = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact",
            "application/octet-stream",
            b"payload",
        )
        .await
        .expect("artifact should persist");
    let segment_id = manifest
        .segment_id
        .clone()
        .expect("artifact should be segment-backed");
    let segment_file = store.segment_path(&segment_id);
    assert!(segment_file.exists());

    // Simulate the crash window: rotation saved the ring state without
    // the evicted segment, but the process died before the unlink.
    let mut state = store
        .load_segment_state_from_db()
        .expect("state should load");
    assert!(state.remove_segment(&segment_id));
    store.save_segment_state(&state).expect("state should save");

    let swept = store
        .sweep_orphaned_segments()
        .await
        .expect("sweep should succeed");

    assert_eq!(swept, 1);
    assert!(!segment_file.exists());
    assert!(
        store
            .manifest(&manifest.artifact_id)
            .expect("manifest lookup should succeed")
            .is_none()
    );
}

#[tokio::test]
async fn segment_generation_tracks_saved_state() {
    let (_temp_dir, _config, store) = temp_store();

    store
        .save_segment_state(&SegmentState {
            old: vec![SegmentReference::new("aged".into(), 1)],
            current: vec![SegmentReference::new("settled".into(), 2)],
            new: vec![SegmentReference::new("fresh".into(), 3)],
        })
        .expect("state should save");

    assert_eq!(
        store.segment_generation("aged").expect("lookup"),
        Some(SegmentGeneration::Old)
    );
    assert_eq!(
        store.segment_generation("settled").expect("lookup"),
        Some(SegmentGeneration::Current)
    );
    assert_eq!(
        store.segment_generation("fresh").expect("lookup"),
        Some(SegmentGeneration::New)
    );
    assert_eq!(store.segment_generation("missing").expect("lookup"), None);
}

#[tokio::test]
async fn evicting_a_segment_updates_the_cached_generation() {
    let (_temp_dir, _config, store) = temp_store();
    let manifest = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact",
            "application/octet-stream",
            b"payload",
        )
        .await
        .expect("artifact should persist");
    let segment_id = manifest
        .segment_id
        .clone()
        .expect("artifact should be segment-backed");
    assert_eq!(
        store.segment_generation(&segment_id).expect("lookup"),
        Some(SegmentGeneration::New)
    );

    store
        .evict_segment(&segment_id)
        .await
        .expect("eviction should succeed");

    assert_eq!(store.segment_generation(&segment_id).expect("lookup"), None);
}

#[tokio::test]
async fn segment_state_snapshot_survives_reopen() {
    let (_temp_dir, config, store) = temp_store();
    let manifest = store
        .persist_artifact_from_bytes(
            ArtifactProducer::Xcode,
            "ios",
            "artifact",
            "application/octet-stream",
            b"payload",
        )
        .await
        .expect("artifact should persist");
    let segment_id = manifest
        .segment_id
        .clone()
        .expect("artifact should be segment-backed");
    drop(store);

    let io = IoController::new(
        Metrics::new(config.region.clone(), config.tenant_id.clone()),
        config.file_descriptor_pool_size,
        std::time::Duration::from_millis(config.file_descriptor_acquire_timeout_ms),
        vec![config.tmp_dir.clone(), config.data_dir.clone()],
    )
    .expect("io controller should build");
    let memory = MemoryController::new(
        io.metrics(),
        config.memory_soft_limit_bytes,
        config.memory_hard_limit_bytes,
    );
    let reopened = Store::open(&config, io, memory).expect("store should reopen");

    assert_eq!(
        reopened.segment_generation(&segment_id).expect("lookup"),
        Some(SegmentGeneration::New)
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn concurrent_state_mutations_do_not_lose_updates() {
    let (_temp_dir, _config, store) = temp_store();
    let store = Arc::new(store);

    let mut tasks = Vec::new();
    for index in 0..16u64 {
        let store = store.clone();
        tasks.push(tokio::spawn(async move {
            store
                .mutate_segment_state(|state| {
                    state.push_new(
                        SegmentReference::new(format!("segment-{index}"), index),
                        16,
                        16,
                        16,
                    )
                })
                .await
                .expect("mutation should succeed");
        }));
    }
    for task in tasks {
        task.await.expect("mutation task should finish");
    }

    for index in 0..16u64 {
        assert!(
            store
                .segment_generation(&format!("segment-{index}"))
                .expect("lookup")
                .is_some(),
            "segment-{index} should survive concurrent mutations"
        );
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn concurrent_evictions_do_not_lose_state_updates() {
    let (_temp_dir, _config, store) = temp_store();
    let store = Arc::new(store);
    let segments: Vec<SegmentReference> = (0..16)
        .map(|index| SegmentReference::new(format!("segment-{index}"), index as u64))
        .collect();
    store
        .save_segment_state(&SegmentState {
            old: segments.clone(),
            current: Vec::new(),
            new: Vec::new(),
        })
        .expect("state should save");

    let mut tasks = Vec::new();
    for segment in &segments {
        let store = store.clone();
        let segment_id = segment.segment_id.clone();
        tasks.push(tokio::spawn(async move {
            store
                .evict_segment(&segment_id)
                .await
                .expect("eviction should succeed");
        }));
    }
    for task in tasks {
        task.await.expect("eviction task should finish");
    }

    for segment in &segments {
        assert_eq!(
            store
                .segment_generation(&segment.segment_id)
                .expect("lookup"),
            None,
            "{} should be gone after concurrent evictions",
            segment.segment_id
        );
    }
}
