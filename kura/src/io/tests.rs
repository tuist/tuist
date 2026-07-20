use tempfile::tempdir;
use tokio::{sync::oneshot, time::timeout};

use super::*;

#[tokio::test]
async fn controller_blocks_when_all_permits_are_checked_out() {
    let metrics = Metrics::new("eu-west".into(), "acme".into());
    let directory = tempdir().expect("failed to create temp dir");
    let controller = IoController::new(
        metrics,
        1,
        Duration::from_secs(1),
        vec![directory.path().to_path_buf()],
    )
    .expect("controller should initialize");
    let first = controller
        .acquire("test")
        .await
        .expect("first permit should be acquired");

    let controller_clone = controller.clone();
    let (started_tx, started_rx) = oneshot::channel();
    let mut waiter = tokio::spawn(async move {
        started_tx
            .send(())
            .expect("started signal should be delivered");
        controller_clone.acquire("test").await
    });

    let _ = started_rx.await;
    assert!(
        timeout(Duration::from_millis(50), &mut waiter)
            .await
            .is_err(),
        "second checkout should wait while the only permit is held"
    );

    drop(first);

    waiter
        .await
        .expect("waiter task should complete")
        .expect("second permit should acquire after release");
}

#[tokio::test]
async fn rejects_paths_outside_allowed_roots() {
    let metrics = Metrics::new("eu-west".into(), "acme".into());
    let allowed_root = tempdir().expect("failed to create allowed root");
    let outside_root = tempdir().expect("failed to create outside root");
    let controller = IoController::new(
        metrics,
        1,
        Duration::from_secs(1),
        vec![allowed_root.path().to_path_buf()],
    )
    .expect("controller should initialize");

    let error = match controller
        .create_file(&outside_root.path().join("escape"))
        .await
    {
        Ok(_) => panic!("path outside the allowed roots should be rejected"),
        Err(error) => error,
    };

    assert!(error.contains("outside configured storage roots"));
}

#[tokio::test]
async fn rejects_paths_with_parent_traversal_components() {
    let metrics = Metrics::new("eu-west".into(), "acme".into());
    let allowed_root = tempdir().expect("failed to create allowed root");
    let controller = IoController::new(
        metrics,
        1,
        Duration::from_secs(1),
        vec![allowed_root.path().to_path_buf()],
    )
    .expect("controller should initialize");

    let error = match controller
        .create_file(&allowed_root.path().join("nested").join("..").join("escape"))
        .await
    {
        Ok(_) => panic!("path traversal should be rejected"),
        Err(error) => error,
    };

    assert!(error.contains("parent traversal component"));
}
