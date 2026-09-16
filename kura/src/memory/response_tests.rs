use super::*;

fn controller() -> MemoryController {
    MemoryController::with_runtime_limit(
        Metrics::new("local".into(), "test".into()),
        128 * 1024 * 1024,
        64 * 1024 * 1024,
        96 * 1024 * 1024,
    )
}

fn fill(controller: &MemoryController) -> Vec<ResponseStreamMemoryPermit> {
    [
        controller.foreground_response_streaming_pool_bytes(),
        controller.elastic_foreground_response_streaming_pool_bytes(),
    ]
    .into_iter()
    .map(|bytes| {
        controller
            .try_acquire_response_stream_memory(bytes, "bytestream")
            .unwrap()
            .0
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
            .try_acquire_response_stream_waiter()
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
