
use super::*;
use crate::metrics::Metrics;
use axum::body::Body;
use tempfile::tempdir;

#[test]
fn artifact_ids_are_stable() {
    let a = artifact_storage_id(ArtifactProducer::Xcode, "tenant", "ios", "abc");
    let b = artifact_storage_id(ArtifactProducer::Xcode, "tenant", "ios", "abc");
    let c = artifact_storage_id(ArtifactProducer::Gradle, "tenant", "ios", "abc");

    assert_eq!(a, b);
    assert_ne!(a, c);
}

#[test]
fn artifact_ids_include_producer() {
    let mut hasher = Sha256::new();
    hasher.update(b"xcode");
    hasher.update([0]);
    hasher.update(b"tenant");
    hasher.update([0]);
    hasher.update(b"ios");
    hasher.update([0]);
    hasher.update(b"abc");

    assert_eq!(
        artifact_storage_id(ArtifactProducer::Xcode, "tenant", "ios", "abc"),
        hex::encode(hasher.finalize())
    );
}

#[test]
fn module_keys_include_category_hash_and_name() {
    assert_eq!(
        module_key("builds", "hash-1", "Module.framework"),
        "builds/hash-1/Module.framework"
    );
}

#[test]
fn route_keys_are_scoped() {
    assert_eq!(action_cache_key("cas-1"), "action_cache/cas-1");
    assert_eq!(blob_key("artifact-1"), "blob/artifact-1");
}

#[test]
fn url_encoding_is_query_safe() {
    assert_eq!(
        url_encode("builds/hash 1/Module.framework"),
        "builds%2Fhash%201%2FModule.framework"
    );
}

#[test]
fn replication_labels_strip_scheme_and_path() {
    assert_eq!(
        replication_target_label("https://kura.example.com/_internal/status"),
        "kura.example.com"
    );
}

#[test]
fn blob_paths_are_partitioned_by_hash_prefix() {
    let path = blob_path(Path::new("/data"), "abcdef1234567890abcdef1234567890");

    assert_eq!(
        path,
        PathBuf::from("/data/blobs/ab/cd/abcdef1234567890abcdef1234567890")
    );
}

#[test]
fn segment_paths_are_shared() {
    let path = segment_path(Path::new("/data"), "01962a2d-8f1f");

    assert_eq!(path, PathBuf::from("/data/segments/01962a2d-8f1f.seg"));
}

#[test]
fn segment_artifact_index_keys_include_segment_and_artifact() {
    assert_eq!(
        segment_artifact_index_key("segment-1", "artifact-1"),
        "segment-1\0artifact-1"
    );
    assert_eq!(segment_artifact_index_prefix("segment-1"), "segment-1\0");
}

#[tokio::test]
async fn read_request_to_temp_persists_request_body() {
    let directory = tempdir().expect("failed to create temp dir");
    let io = IoController::new(
        Metrics::new("eu-west".into(), "acme".into()),
        8,
        Duration::from_secs(1),
        vec![directory.path().to_path_buf()],
    )
    .expect("failed to create io controller");
    let request = Request::builder()
        .body(Body::from("hello"))
        .expect("failed to build request");

    let temp = read_request_to_temp(
        request,
        directory.path(),
        10,
        directory.path(),
        10,
        &io,
        None,
    )
    .await
    .expect("failed to read request to temp");

    assert_eq!(temp.size, 5);
    assert_eq!(
        std::fs::read_to_string(temp.path).expect("failed to read temp file"),
        "hello"
    );
}

#[tokio::test]
async fn read_request_to_temp_rejects_large_payloads() {
    let directory = tempdir().expect("failed to create temp dir");
    let io = IoController::new(
        Metrics::new("eu-west".into(), "acme".into()),
        8,
        Duration::from_secs(1),
        vec![directory.path().to_path_buf()],
    )
    .expect("failed to create io controller");
    let request = Request::builder()
        .body(Body::from("hello"))
        .expect("failed to build request");

    let error = read_request_to_temp(
        request,
        directory.path(),
        4,
        directory.path(),
        10,
        &io,
        None,
    )
    .await
    .expect_err("expected body reader to reject oversized request");

    assert_eq!(error, BodyReadError::TooLarge);
    assert!(
        std::fs::read_dir(directory.path())
            .expect("failed to list temp dir")
            .next()
            .is_none()
    );
}

#[tokio::test]
async fn read_request_to_temp_rejects_when_tmp_budget_is_exhausted() {
    let directory = tempdir().expect("failed to create temp dir");
    std::fs::write(directory.path().join("staged"), b"hello").expect("failed to seed tmp dir");
    let io = IoController::new(
        Metrics::new("eu-west".into(), "acme".into()),
        8,
        Duration::from_secs(1),
        vec![directory.path().to_path_buf()],
    )
    .expect("failed to create io controller");
    let request = Request::builder()
        .body(Body::from("world"))
        .expect("failed to build request");

    let error = read_request_to_temp(request, directory.path(), 5, directory.path(), 9, &io, None)
        .await
        .expect_err("expected body reader to reject exhausted tmp budget");

    assert!(matches!(error, BodyReadError::TmpDirFull(_)));
    assert_eq!(
        std::fs::read_to_string(directory.path().join("staged"))
            .expect("failed to read seeded file"),
        "hello"
    );
}

#[tokio::test]
async fn tmp_budget_caps_concurrent_reservations() {
    let budget = TmpBudget::new(100);
    let first = budget.reserve(60).await;
    let second = budget.reserve(40).await;
    assert_eq!(budget.reserved.load(Ordering::Acquire), 100);

    // A third reservation cannot fit until one of the held ones drops.
    let pending = tokio::spawn({
        let budget = budget.clone();
        async move { budget.reserve(40).await }
    });
    tokio::time::sleep(Duration::from_millis(20)).await;
    assert!(!pending.is_finished(), "reservation should wait for budget");

    drop(first);
    let third = pending.await.expect("pending reservation should resolve");
    assert!(budget.reserved.load(Ordering::Acquire) <= 100);
    drop(second);
    drop(third);
    assert_eq!(budget.reserved.load(Ordering::Acquire), 0);
}

#[tokio::test]
async fn tmp_budget_serializes_total_far_exceeding_capacity() {
    // Stage a total volume far larger than the budget through a tiny budget;
    // every reservation must eventually succeed (peak never exceeds budget),
    // proving bootstrap convergence is independent of total account size.
    let budget = TmpBudget::new(100);
    let mut total = 0_u64;
    for _ in 0..50 {
        let reservation = budget.reserve(80).await;
        assert!(budget.reserved.load(Ordering::Acquire) <= 100);
        total += 80;
        drop(reservation);
    }
    assert_eq!(total, 4000);
    assert_eq!(budget.reserved.load(Ordering::Acquire), 0);
}

#[tokio::test]
async fn tmp_budget_clamps_oversized_request_to_capacity() {
    let budget = TmpBudget::new(100);
    let reservation = budget.reserve(10_000).await;
    assert_eq!(budget.reserved.load(Ordering::Acquire), 100);
    drop(reservation);
    assert_eq!(budget.reserved.load(Ordering::Acquire), 0);
}
