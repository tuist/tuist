
use std::time::Duration;

use tempfile::tempdir;
use tokio::time::timeout;

use super::*;

#[test]
fn data_dir_lock_rejects_second_owner() {
    let temp_dir = tempdir().expect("failed to create temp dir");
    let first = DataDirLock::acquire(temp_dir.path()).expect("first lock should succeed");
    let second = DataDirLock::acquire(temp_dir.path());
    assert!(second.is_err(), "second lock acquisition should fail");
    assert_eq!(
        first.path(),
        temp_dir.path().join(DATA_DIR_LOCK_FILE).as_path()
    );
}

#[tokio::test]
async fn inflight_change_notification_resolves_on_request_completion() {
    let runtime = RuntimeState::new();
    let metrics = Metrics::new("region".into(), "tenant".into());
    let guard = runtime.start_http_request(&metrics, HttpTrafficClass::Public);

    let notified = runtime.inflight_changed();
    drop(guard);

    timeout(Duration::from_secs(1), notified)
        .await
        .expect("request completion should wake inflight waiters");
}

#[test]
fn public_http_inflight_excludes_background_http_requests() {
    let runtime = RuntimeState::new();
    let metrics = Metrics::new("region".into(), "tenant".into());

    let background = runtime.start_http_request(&metrics, HttpTrafficClass::Background);
    assert_eq!(runtime.http_inflight(), 1);
    assert_eq!(runtime.public_http_inflight(), 0);

    let public = runtime.start_http_request(&metrics, HttpTrafficClass::Public);
    assert_eq!(runtime.http_inflight(), 2);
    assert_eq!(runtime.public_http_inflight(), 1);
    assert_eq!(runtime.public_inflight(), 1);

    drop(public);
    assert_eq!(runtime.http_inflight(), 1);
    assert_eq!(runtime.public_http_inflight(), 0);

    drop(background);
    assert_eq!(runtime.http_inflight(), 0);
    assert_eq!(runtime.public_http_inflight(), 0);
}

#[test]
fn public_latency_pressure_divisor_tracks_recent_request_latency() {
    let runtime = RuntimeState::new();
    let metrics = Metrics::new("region".into(), "tenant".into());

    assert_eq!(runtime.public_latency_pressure_divisor(100), 1);

    runtime.record_public_request_latency(
        &metrics,
        "http",
        "/api/cache/cas/{id}",
        Duration::from_millis(250),
    );

    assert_eq!(
        runtime.public_request_latency_ewma(),
        Some(Duration::from_millis(250))
    );
    assert_eq!(runtime.public_latency_pressure_divisor(100), 3);
    assert_eq!(runtime.public_latency_pressure_divisor(0), 1);
}
