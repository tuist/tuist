use super::*;
use std::time::Duration;

const MIB: usize = 1024 * 1024;

fn managed_controller(floor_mib: u64, ceiling_mib: u64) -> MemoryController {
    let config = crate::config::Config::from_lookup_with_resources(
        |key| match key {
            "KURA_PORT" => Some("4500".into()),
            "KURA_INTERNAL_PORT" => Some("7443".into()),
            "KURA_TENANT_ID" => Some("test".into()),
            "KURA_REGION" | "KURA_OTEL_DEPLOYMENT_ENVIRONMENT" => Some("local".into()),
            "KURA_OTEL_SERVICE_NAME" => Some("response-admission-test".into()),
            "KURA_NODE_URL" => Some("http://127.0.0.1:7443".into()),
            "KURA_DATA_DIR" => Some("/tmp/unused-kura-response-test".into()),
            "KURA_TMP_DIR" => Some("/tmp/unused-kura-response-test-tmp".into()),
            "KURA_MEMORY_FLOOR_BYTES" => Some((floor_mib * MIB as u64).to_string()),
            "KURA_SNAPSHOT_CACHE_MAX_BYTES" => Some((64 * MIB).to_string()),
            "KURA_MANIFEST_CACHE_MAX_BYTES"
            | "KURA_METADATA_STORE_READ_CACHE_BYTES"
            | "KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES" => Some((32 * MIB).to_string()),
            _ => None,
        },
        crate::config::HostResources {
            file_descriptor_limit: 65536,
            memory_limit_bytes: ceiling_mib * MIB as u64,
            cpu_count: 8,
        },
    )
    .unwrap();
    MemoryController::with_anon_budget(
        Metrics::new("local".into(), "test".into()),
        config.memory_limit_bytes,
        config.memory_soft_limit_bytes,
        config.memory_hard_limit_bytes,
        config.anon_admission_budget_bytes(),
    )
}

#[tokio::test]
async fn response_queue_bounds_pending_bytes_on_managed_profiles() {
    for (floor, ceiling) in [(256, 768), (512, 3072), (1024, 4096)] {
        let controller = managed_controller(floor, ceiling);
        let held = fill(&controller);
        let pools = &controller.inner.pools;
        let serving = (controller.foreground_response_streaming_pool_bytes()
            + controller.elastic_foreground_response_streaming_pool_bytes())
        .min(pools.transient_capacity_bytes());
        assert_eq!(pools.response_stream_queue_bytes(), 2 * serving);
        // Large reservations hit the byte bound before the bookkeeping cap.
        let bytes = 2 * MIB;
        let capacity = (2 * serving / bytes).min(pools.response_stream_waiter_capacity());
        let mut waiting = Vec::new();
        for _ in 0..capacity {
            let mut request = Box::pin(controller.acquire_response_stream_memory(
                bytes,
                "bytestream",
                ResponseStreamAdmissionPatience::Blocking,
            ));
            assert!(futures_util::poll!(&mut request).is_pending());
            waiting.push(request);
        }
        assert!(matches!(
            controller
                .acquire_response_stream_memory(
                    bytes,
                    "bytestream",
                    ResponseStreamAdmissionPatience::Blocking
                )
                .await,
            Err(ResponseStreamAdmissionError::QueueFull)
        ));
        assert_eq!(controller.transient_reserved_bytes(), serving as u64);
        drop(waiting);
        assert_eq!(controller.response_stream_waiter_count(), 0);
        // Cancellation restores the whole pending-work budget, not just count slots.
        let queue = pools
            .try_acquire_response_stream_waiter(2 * serving)
            .unwrap();
        drop(queue);
        drop(held);
        assert_eq!(controller.transient_reserved_bytes(), 0);
    }
}

#[test]
fn response_retry_backoff_keeps_its_original_scale() {
    let controller = managed_controller(1024, 4096);
    assert_eq!(controller.inner.pools.response_stream_retry_backlog(), 152);
    controller
        .inner
        .response_stream_waiters
        .store(120, Ordering::Release);
    assert_eq!(controller.response_stream_retry_after_ceiling_seconds(), 9);
    controller
        .inner
        .response_stream_waiters
        .store(152, Ordering::Release);
    assert_eq!(controller.response_stream_retry_after_ceiling_seconds(), 10);
    controller
        .inner
        .response_stream_waiters
        .store(608, Ordering::Release);
    assert_eq!(controller.response_stream_retry_after_ceiling_seconds(), 10);
}

#[tokio::test(start_paused = true)]
async fn stalled_bytestream_readers_bound_overload_and_http_wait() {
    let controller = controller();
    let held = fill(&controller);
    let reserved = controller.transient_reserved_bytes();
    let mut reads = Vec::new();
    for _ in 0..17 {
        let mut read = Box::pin(controller.acquire_response_stream_memory(
            2 * MIB,
            "bytestream",
            ResponseStreamAdmissionPatience::Blocking,
        ));
        assert!(futures_util::poll!(&mut read).is_pending());
        reads.push(read);
    }
    let mut http = Box::pin(controller.acquire_response_stream_memory(
        2 * MIB,
        "http",
        ResponseStreamAdmissionPatience::Degradable,
    ));
    assert!(futures_util::poll!(&mut http).is_pending());
    // Additional work is shed immediately even though count slots remain.
    for _ in 0..64 {
        assert!(matches!(
            controller
                .acquire_response_stream_memory(
                    MIB,
                    "bytestream",
                    ResponseStreamAdmissionPatience::Blocking
                )
                .await,
            Err(ResponseStreamAdmissionError::QueueFull)
        ));
    }
    tokio::time::advance(Duration::from_millis(250)).await;
    assert!(matches!(
        http.await,
        Err(ResponseStreamAdmissionError::Timeout)
    ));
    // HTTP retains its bounded fallback while ByteStream is stalled.
    let degraded = controller
        .acquire_degraded_response_stream_memory(80 * 1024, "http")
        .await
        .unwrap();
    assert_eq!(controller.response_stream_waiter_count(), 17);
    drop(degraded);
    tokio::time::advance(Duration::from_secs(5)).await;
    for read in reads {
        assert!(matches!(
            read.await,
            Err(ResponseStreamAdmissionError::Timeout)
        ));
    }
    assert_eq!(controller.response_stream_waiter_count(), 0);
    assert_eq!(controller.transient_reserved_bytes(), reserved);
    drop(held);
    let recovered = controller
        .acquire_response_stream_memory(
            MIB,
            "bytestream",
            ResponseStreamAdmissionPatience::Blocking,
        )
        .await
        .unwrap();
    drop(recovered);
    assert_eq!(controller.transient_reserved_bytes(), 0);
}

fn controller() -> MemoryController {
    MemoryController::with_runtime_limit(
        Metrics::new("local".into(), "test".into()),
        128 * 1024 * 1024,
        64 * 1024 * 1024,
        96 * 1024 * 1024,
    )
}

fn fill(controller: &MemoryController) -> Vec<ResponseStreamMemoryPermit> {
    let mut available = controller.inner.pools.transient_capacity_bytes();
    [
        controller.foreground_response_streaming_pool_bytes(),
        controller.elastic_foreground_response_streaming_pool_bytes(),
    ]
    .into_iter()
    .filter_map(|capacity| {
        let bytes = capacity.min(available);
        available -= bytes;
        (bytes > 0).then(|| {
            controller
                .try_acquire_response_stream_memory(bytes, "bytestream")
                .unwrap()
                .0
        })
    })
    .collect()
}

#[tokio::test]
async fn response_queue_preserves_fifo_and_cancelled_waiters_release_their_slots() {
    let controller = controller();
    let held = fill(&controller);
    let mut first = Box::pin(controller.acquire_response_stream_memory(
        1024 * 1024,
        "bytestream",
        ResponseStreamAdmissionPatience::Blocking,
    ));
    let mut second = Box::pin(controller.acquire_response_stream_memory(
        1024 * 1024,
        "bytestream",
        ResponseStreamAdmissionPatience::Blocking,
    ));
    assert!(futures_util::poll!(&mut first).is_pending());
    assert!(futures_util::poll!(&mut second).is_pending());
    assert_eq!(
        controller
            .inner
            .response_stream_waiters
            .load(Ordering::Acquire),
        2
    );
    drop(first);
    assert_eq!(
        controller
            .inner
            .response_stream_waiters
            .load(Ordering::Acquire),
        1
    );
    drop(held);
    let mut arrival = Box::pin(controller.acquire_response_stream_memory(
        1024 * 1024,
        "bytestream",
        ResponseStreamAdmissionPatience::Blocking,
    ));
    assert!(
        futures_util::poll!(&mut arrival).is_pending(),
        "new arrivals must not jump the FIFO turn"
    );
    let permit = second.await.unwrap();
    assert_eq!(permit.bytes, 1024 * 1024);
    drop(permit);
    drop(arrival.await.unwrap());
    assert_eq!(
        controller
            .inner
            .response_stream_waiters
            .load(Ordering::Acquire),
        0
    );
    assert_eq!(controller.transient_reserved_bytes(), 0);
}

#[tokio::test]
async fn response_queue_stays_bounded_and_cancellation_releases_every_slot() {
    let controller = controller();
    let held = fill(&controller);
    let capacity = controller.inner.pools.response_stream_waiter_capacity();
    assert_eq!(capacity, 32);
    let mut waiting = Vec::new();
    for _ in 0..capacity {
        let mut request = Box::pin(controller.acquire_response_stream_memory(
            1024 * 1024,
            "bytestream",
            ResponseStreamAdmissionPatience::Blocking,
        ));
        assert!(futures_util::poll!(&mut request).is_pending());
        waiting.push(request);
    }
    assert!(matches!(
        controller
            .acquire_response_stream_memory(
                1024 * 1024,
                "bytestream",
                ResponseStreamAdmissionPatience::Blocking
            )
            .await,
        Err(ResponseStreamAdmissionError::QueueFull)
    ));
    drop(waiting);
    assert_eq!(
        controller
            .inner
            .response_stream_waiters
            .load(Ordering::Acquire),
        0
    );
    assert!(
        controller
            .inner
            .pools
            .try_acquire_response_stream_waiter(1024 * 1024)
            .is_ok()
    );
    drop(held);
    assert_eq!(controller.transient_reserved_bytes(), 0);
}

#[tokio::test(start_paused = true)]
async fn response_queue_timeout_releases_slot_and_preserves_live_reservations() {
    let controller = controller();
    let held = fill(&controller);
    let reserved = controller.transient_reserved_bytes();
    assert!(matches!(
        controller
            .acquire_response_stream_memory(
                1024 * 1024,
                "bytestream",
                ResponseStreamAdmissionPatience::Blocking
            )
            .await,
        Err(ResponseStreamAdmissionError::Timeout)
    ));
    assert_eq!(
        controller
            .inner
            .response_stream_waiters
            .load(Ordering::Acquire),
        0
    );
    assert_eq!(controller.transient_reserved_bytes(), reserved);
    drop(held);
    assert_eq!(controller.transient_reserved_bytes(), 0);
}
