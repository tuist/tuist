use super::*;

#[test]
fn pressure_uses_hysteresis_before_recovering() {
    let metrics = Metrics::new("eu-west".into(), "tenant".into());
    let controller = MemoryController::new(metrics, 100, 200);

    assert_eq!(controller.observe(150), MemoryPressure::Constrained);
    assert_eq!(controller.observe(95), MemoryPressure::Constrained);
    assert_eq!(controller.observe(90), MemoryPressure::Normal);
    assert_eq!(controller.observe(220), MemoryPressure::Critical);
    assert_eq!(controller.observe(185), MemoryPressure::Critical);
    assert_eq!(controller.observe(180), MemoryPressure::Constrained);
}

#[test]
fn reapi_response_budget_shrinks_with_memory_pressure() {
    let metrics = Metrics::new("eu-west".into(), "tenant".into());
    let controller = MemoryController::new(metrics, 128 * 1024 * 1024, 256 * 1024 * 1024);

    assert_eq!(controller.reapi_response_budget_bytes(), 32 * 1024 * 1024);

    controller.observe(128 * 1024 * 1024);
    assert_eq!(controller.reapi_response_budget_bytes(), 16 * 1024 * 1024);

    controller.observe(256 * 1024 * 1024);
    assert_eq!(controller.reapi_response_budget_bytes(), 0);
}

#[test]
fn reapi_materialization_pool_is_clamped_from_memory_headroom() {
    let metrics = Metrics::new("eu-west".into(), "tenant".into());
    let small = MemoryController::new(metrics.clone(), 24 * 1024 * 1024, 48 * 1024 * 1024);
    let medium = MemoryController::new(metrics.clone(), 128 * 1024 * 1024, 256 * 1024 * 1024);
    let large = MemoryController::new(metrics, 8 * 1024 * 1024 * 1024, 9 * 1024 * 1024 * 1024);

    assert_eq!(small.reapi_materialization_pool_bytes(), 12 * 1024 * 1024);
    assert_eq!(medium.reapi_materialization_pool_bytes(), 64 * 1024 * 1024);
    assert_eq!(large.reapi_materialization_pool_bytes(), 128 * 1024 * 1024);
}

#[test]
fn mmap_serving_pool_is_bounded_by_memory_headroom() {
    let metrics = Metrics::new("eu-west".into(), "tenant".into());
    let small = MemoryController::new(metrics.clone(), 128 * 1024 * 1024, 192 * 1024 * 1024);
    let medium = MemoryController::new(metrics.clone(), 512 * 1024 * 1024, 768 * 1024 * 1024);
    let large = MemoryController::new(metrics, 2 * 1024 * 1024 * 1024, 4 * 1024 * 1024 * 1024);

    assert_eq!(small.mmap_serving_pool_bytes(), 64 * 1024 * 1024);
    assert_eq!(medium.mmap_serving_pool_bytes(), 256 * 1024 * 1024);
    assert_eq!(large.mmap_serving_pool_bytes(), 512 * 1024 * 1024);
}

#[test]
fn mmap_serving_permits_are_non_blocking_and_pressure_sensitive() {
    let metrics = Metrics::new("eu-west".into(), "tenant".into());
    let controller = MemoryController::new(metrics, 128 * 1024 * 1024, 256 * 1024 * 1024);

    let permit = controller
        .try_acquire_mmap_serving(64 * 1024 * 1024)
        .expect("permit should be available");
    assert!(
        controller
            .try_acquire_mmap_serving(65 * 1024 * 1024)
            .is_none()
    );

    drop(permit);
    controller.observe(128 * 1024 * 1024);
    assert!(controller.try_acquire_mmap_serving(1).is_none());
}
