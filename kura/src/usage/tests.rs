
use super::*;

fn test_config(window_secs: u64, max_buckets: usize) -> UsageConfig {
    UsageConfig {
        control_plane_url: "http://localhost:0".to_owned(),
        client_id: "kura".to_owned(),
        client_secret: "secret".to_owned(),
        window_secs,
        flush_interval_ms: 1_000,
        delivery_interval_ms: 1_000,
        batch_size: 100,
        max_buckets,
        outbox_max_depth: 100,
    }
}

fn test_usage(window_secs: u64, max_buckets: usize) -> Usage {
    let metrics = Metrics::new("test-region".to_owned(), "test-tenant".to_owned());
    Usage::from_config(
        Some(&test_config(window_secs, max_buckets)),
        "http://node-1.kura.local",
        metrics,
    )
    .expect("usage config valid")
    .expect("usage enabled when config present")
}

fn bucket_key(tenant: &str, namespace: &str, window_start: u64) -> UsageBucketKey {
    UsageBucketKey {
        tenant_id: tenant.to_owned(),
        namespace_id: namespace.to_owned(),
        window_start_unix_seconds: window_start,
        traffic_plane: "public",
        direction: "egress",
        operation: "download",
        protocol: "http",
        artifact_kind: "xcframework",
    }
}

#[test]
fn from_config_returns_none_when_unconfigured() {
    let metrics = Metrics::new("region".into(), "tenant".into());
    let usage = Usage::from_config(None, "http://node.kura.local", metrics).unwrap();
    assert!(usage.is_none());
}

#[test]
fn usage_node_id_uses_host_when_url_is_parseable() {
    assert_eq!(
        usage_node_id("http://node-1.kura.local"),
        "node-1.kura.local"
    );
    assert_eq!(
        usage_node_id("https://node-2.kura.local:8443/path"),
        "node-2.kura.local"
    );
}

#[test]
fn usage_node_id_falls_back_to_raw_string_for_unparseable_url() {
    assert_eq!(usage_node_id("not a url"), "not a url");
}

#[test]
fn record_accumulates_bytes_and_request_count_into_existing_bucket() {
    let usage = test_usage(60, 100);

    usage.record_public_download("acme", "ios", "xcframework", 100);
    usage.record_public_download("acme", "ios", "xcframework", 250);
    usage.record_public_download("acme", "ios", "xcframework", 50);

    let buckets = usage.inner.buckets.lock().unwrap();
    assert_eq!(buckets.len(), 1);
    let bucket = buckets.values().next().unwrap();
    assert_eq!(bucket.bytes, 400);
    assert_eq!(bucket.request_count, 3);
}

#[test]
fn record_keeps_separate_buckets_per_tenant_namespace() {
    let usage = test_usage(60, 100);

    usage.record_public_download("acme", "ios", "xcframework", 100);
    usage.record_public_download("acme", "android", "xcframework", 200);
    usage.record_public_upload("acme", "ios", "xcframework", 300);

    let buckets = usage.inner.buckets.lock().unwrap();
    assert_eq!(buckets.len(), 3);
}

#[test]
fn record_rejects_new_keys_once_max_buckets_reached() {
    let usage = test_usage(60, 2);

    usage.record_public_download("acme", "ios", "xcframework", 1);
    usage.record_public_download("acme", "android", "xcframework", 1);
    // Third unique key — rejected.
    usage.record_public_download("globex", "ios", "xcframework", 1);
    // Existing keys still accumulate.
    usage.record_public_download("acme", "ios", "xcframework", 9);

    let buckets = usage.inner.buckets.lock().unwrap();
    assert_eq!(buckets.len(), 2);
    let key = bucket_key(
        "acme",
        "ios",
        buckets.keys().next().unwrap().window_start_unix_seconds,
    );
    let acme_ios = buckets.get(&key).unwrap();
    assert_eq!(acme_ios.bytes, 10);
    assert!(!buckets.keys().any(|k| k.tenant_id == "globex"));
}

#[test]
fn record_uses_saturating_add_on_overflow() {
    let usage = test_usage(60, 100);

    usage.record_public_download("acme", "ios", "xcframework", u64::MAX - 5);
    usage.record_public_download("acme", "ios", "xcframework", 100);

    let buckets = usage.inner.buckets.lock().unwrap();
    let bucket = buckets.values().next().unwrap();
    assert_eq!(bucket.bytes, u64::MAX);
    assert_eq!(bucket.request_count, 2);
}

#[test]
fn closed_rollups_only_returns_buckets_for_past_windows() {
    let usage = test_usage(60, 100);
    let now = unix_seconds();
    let current_window = now - (now % 60);
    let past_window = current_window - 60;

    {
        let mut buckets = usage.inner.buckets.lock().unwrap();
        buckets.insert(
            bucket_key("acme", "ios", past_window),
            UsageBucket {
                bytes: 1_000,
                request_count: 5,
            },
        );
        buckets.insert(
            bucket_key("acme", "android", current_window),
            UsageBucket {
                bytes: 2_000,
                request_count: 7,
            },
        );
    }

    let rollups = usage.closed_rollups();
    assert_eq!(rollups.len(), 1);
    let (_, rollup) = &rollups[0];
    assert_eq!(rollup.namespace_id, "ios");
    assert_eq!(rollup.bytes, 1_000);
    assert_eq!(rollup.request_count, 5);
    assert_eq!(rollup.window_start_unix_seconds, past_window);
    assert_eq!(rollup.window_seconds, 60);
    assert_eq!(rollup.region, "test-region");
    assert_eq!(rollup.node_id, "node-1.kura.local");
}

#[test]
fn closed_rollups_event_id_is_deterministic() {
    let usage = test_usage(60, 100);
    let past_window = (unix_seconds() / 60 - 1) * 60;
    let key = bucket_key("acme", "ios", past_window);

    {
        let mut buckets = usage.inner.buckets.lock().unwrap();
        buckets.insert(
            key.clone(),
            UsageBucket {
                bytes: 10,
                request_count: 1,
            },
        );
    }

    let first = usage.closed_rollups();
    let second = usage.closed_rollups();

    assert_eq!(first.len(), 1);
    assert_eq!(second.len(), 1);
    assert_eq!(first[0].1.event_id, second[0].1.event_id);
    let expected =
        format!("node-1.kura.local:{past_window}:acme:ios:public:egress:download:http:xcframework");
    assert_eq!(first[0].1.event_id, expected);
}

#[test]
fn remove_buckets_drops_only_the_specified_keys() {
    let usage = test_usage(60, 100);
    let now = unix_seconds();
    let past_window = now - (now % 60) - 60;

    let acme_key = bucket_key("acme", "ios", past_window);
    let globex_key = bucket_key("globex", "ios", past_window);

    {
        let mut buckets = usage.inner.buckets.lock().unwrap();
        buckets.insert(
            acme_key.clone(),
            UsageBucket {
                bytes: 1,
                request_count: 1,
            },
        );
        buckets.insert(
            globex_key.clone(),
            UsageBucket {
                bytes: 1,
                request_count: 1,
            },
        );
    }

    usage.remove_buckets(std::slice::from_ref(&acme_key));

    let buckets = usage.inner.buckets.lock().unwrap();
    assert!(!buckets.contains_key(&acme_key));
    assert!(buckets.contains_key(&globex_key));
}
