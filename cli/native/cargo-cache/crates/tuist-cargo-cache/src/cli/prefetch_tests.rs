use super::cargo_tests::managed_target_config;
use super::*;

#[test]
fn prefetch_accepts_a_read_capable_remote() {
    let directory = tempfile::tempdir().unwrap();
    let mut config = managed_target_config(directory.path());
    config.remote.url = Some("https://cache.example.test".into());
    config.remote.mode = tuist_cargo_cache_core::RemoteCacheMode::ReadOnly;

    assert!(validate_prefetch_config(&config).is_ok());
}
