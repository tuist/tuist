//! Integration tests for `once-cas` that exercise the public API
//! across `Cas` lifetimes - i.e. open, write, drop, reopen, read.
//!
//! Each test allocates its own `TempDir`, so the suite is parallel-safe
//! under `cargo test`'s default parallel execution.

use once_cas::{ActionResult, Cas, Digest};
use tempfile::TempDir;

fn open_in(tmp: &TempDir) -> Cas {
    Cas::open(tmp.path())
}

#[tokio::test]
async fn blobs_survive_dropping_and_reopening_the_cas() {
    let tmp = TempDir::new().unwrap();
    let payload = b"persistent payload";
    let digest = {
        let cas = open_in(&tmp);
        cas.put_blob(payload).await.unwrap()
    };
    // Drop and reopen - same root.
    let cas = open_in(&tmp);
    assert_eq!(cas.get_blob(&digest).await.unwrap(), payload);
}

#[tokio::test]
async fn action_results_survive_reopen() {
    let tmp = TempDir::new().unwrap();
    let key = Digest::of_bytes(b"persisted");
    let stored = {
        let cas = open_in(&tmp);
        let stdout = cas.put_blob(b"out").await.unwrap();
        let result = ActionResult {
            exit_code: 0,
            stdout: Some(stdout),
            stderr: Some(stdout),
            outputs: std::collections::BTreeMap::new(),
        };
        cas.put_action_result(&key, &result).await.unwrap();
        result
    };
    let cas = open_in(&tmp);
    assert_eq!(cas.get_action_result(&key).await.unwrap(), Some(stored));
}

#[tokio::test]
async fn forget_action_persists_across_reopen() {
    let tmp = TempDir::new().unwrap();
    let key = Digest::of_bytes(b"to-forget");
    {
        let cas = open_in(&tmp);
        let stdout = cas.put_blob(b"x").await.unwrap();
        cas.put_action_result(
            &key,
            &ActionResult {
                exit_code: 0,
                stdout: Some(stdout),
                stderr: Some(stdout),
                outputs: std::collections::BTreeMap::new(),
            },
        )
        .await
        .unwrap();
        assert!(cas.forget_action(&key).await.unwrap());
    }
    let cas = open_in(&tmp);
    assert_eq!(cas.get_action_result(&key).await.unwrap(), None);
}

#[tokio::test]
async fn put_stream_then_reopen_observes_blob() {
    let tmp = TempDir::new().unwrap();
    let payload: Vec<u8> = (0..200_000u32).map(|i| (i & 0xff) as u8).collect();
    let digest = {
        let cas = open_in(&tmp);
        cas.put_stream(payload.as_slice()).await.unwrap()
    };
    let cas = open_in(&tmp);
    assert_eq!(cas.get_blob(&digest).await.unwrap(), payload);
}

#[tokio::test]
async fn stats_aggregates_across_reopens() {
    let tmp = TempDir::new().unwrap();
    {
        let cas = open_in(&tmp);
        cas.put_blob(b"one").await.unwrap();
    }
    {
        let cas = open_in(&tmp);
        cas.put_blob(b"two").await.unwrap();
    }
    let cas = open_in(&tmp);
    let s = cas.stats().await.unwrap();
    assert_eq!(s.blob_count, 2);
}

#[tokio::test]
async fn isolated_cas_instances_do_not_share_state() {
    // Two separate roots produce two independent caches; this test
    // exists so that a future regression that introduces a global
    // (process-wide cache, static map, etc.) is loud.
    let tmp_a = TempDir::new().unwrap();
    let tmp_b = TempDir::new().unwrap();
    let cas_a = open_in(&tmp_a);
    let cas_b = open_in(&tmp_b);
    let d = cas_a.put_blob(b"only in A").await.unwrap();
    assert!(matches!(
        cas_b.get_blob(&d).await,
        Err(once_cas::Error::BlobNotFound(_))
    ));
}
