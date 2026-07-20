
use super::*;

#[test]
fn public_http_metrics_exclude_probes_internal_and_unmatched_routes() {
    assert!(records_public_http_metrics("/api/cache/cas/{id}"));
    assert!(!records_public_http_metrics("/up"));
    assert!(!records_public_http_metrics("/metrics"));
    assert!(!records_public_http_metrics("/_internal/status"));
    assert!(!records_public_http_metrics("/_unmatched"));
}

#[test]
fn render_includes_recorded_metrics() {
    let metrics = Metrics::new("eu-west".into(), "acme".into());
    metrics.record_http(
        "/up".into(),
        StatusCode::OK,
        Some("US".into()),
        Duration::from_millis(10),
    );
    metrics.record_http(
        "/api/cache/keyvalue".into(),
        StatusCode::INTERNAL_SERVER_ERROR,
        None,
        Duration::from_millis(20),
    );
    metrics.record_artifact_read(ArtifactProducer::Xcode, "ok", 5);
    metrics.record_artifact_write(ArtifactProducer::Module, "ok", 10);
    metrics.record_artifact_egress(
        ArtifactProducer::Module,
        "ok",
        10,
        Duration::from_millis(30),
    );
    metrics.record_segment_refresh(ArtifactProducer::Xcode, "ok", 5, Duration::from_millis(4));
    metrics.record_segment_eviction(ArtifactProducer::Xcode, "ok", 2);
    metrics.record_replication(
        "https://kura.example.com/internal",
        "upsert_artifact",
        "ok",
        Duration::from_millis(5),
    );
    metrics.record_replication_apply("replication", "artifact", "applied");
    metrics.record_replication_apply("bootstrap", "namespace_delete", "ignored_older");
    metrics.update_replication_bandwidth_limits(10_485_760, 5_242_880, 100);
    metrics.record_multipart_part("ok");
    metrics.record_file_descriptor_wait("ok", Duration::from_millis(1));
    metrics.record_file_operation("open_read", "ok", Duration::from_millis(2), 42);
    metrics.update_file_descriptor_pool(64, 3, 61, 1);
    metrics.update_http_inflight(2);
    metrics.update_public_http_inflight(1);
    metrics.update_public_request_latency_ewma(Duration::from_millis(42));
    metrics.observe_public_request_latency(
        "http",
        "/api/cache/cas/{id}",
        Duration::from_millis(12),
    );
    metrics.update_grpc_inflight(1);
    metrics.update_segment_handles_cached(2);
    metrics.update_segment_handle_cache_capacity(8);
    metrics.record_segment_handle_cache_lookup("hit");
    metrics.record_segment_handle_cache_lookup("miss");
    metrics.record_segment_handle_evictions("capacity", 1);
    metrics.update_manifest_index_entries(7);
    metrics.update_manifest_cache_bytes(1024);
    metrics.update_manifest_cache_capacity_bytes(2048);
    metrics.record_manifest_cache_lookup("hit");
    metrics.record_manifest_cache_admission("admitted");
    metrics.record_manifest_cache_evictions("capacity", 1);
    metrics.record_manifest_index_rebuild("ok", Duration::from_millis(3));
    metrics.update_outbox_messages(4);
    metrics.update_multipart_uploads(2);
    metrics.update_discovered_peer_nodes(3);
    metrics.update_bootstrap_peers(3, 2, 1);
    metrics.record_bootstrap_run("ok", Duration::from_millis(6), 2, 5);
    metrics.update_analytics_queue(1000, 2);
    metrics.record_analytics_event("xcode", "sent", 2);
    metrics.record_analytics_batch("xcode", "ok", Duration::from_millis(7));
    metrics.update_analytics_circuit_state("xcode", 1);
    metrics.record_analytics_circuit_transition("xcode", "closed", "open");
    metrics.update_segment_generation_count("old", 1);
    metrics.update_process_memory(1024, 2048);
    metrics.update_process_resident_breakdown(768, 256);
    metrics.update_jemalloc_stats(700, 900, 200);
    metrics.update_rocksdb_memory(256, 64, 4096, 512, 2048);
    metrics.update_memory_limits(4_096, 8_192);
    metrics.update_memory_pressure_state(1);
    metrics.record_memory_pressure_transition("normal", "constrained");
    metrics.update_background_work_paused("outbox", true);
    metrics.record_memory_action("manifest_cache_trim");
    metrics.update_runtime_state(1, true, false, true, true);
    metrics.record_writer_lock_acquire_failure();
    metrics.record_node_geo(&NodeLocation {
        country: Some("US".into()),
        subdivision: Some("US-VA".into()),
    });

    let rendered = metrics.render();

    assert!(rendered.contains("kura_http_requests_total"));
    assert!(rendered.contains("kura_http_client_requests_total"));
    assert!(rendered.contains("kura_http_exceptions_total"));
    assert!(
        rendered
            .lines()
            .filter(|line| line.starts_with("kura_http_request_duration_seconds"))
            .all(|line| !line.contains("route="))
    );
    assert!(
        rendered
            .lines()
            .filter(|line| line.starts_with("kura_http_requests_total"))
            .all(|line| !line.contains("client_country="))
    );
    assert!(
        rendered
            .lines()
            .filter(|line| line.starts_with("kura_http_requests_total"))
            .all(|line| !line.contains("method="))
    );
    assert!(rendered.contains("client_country=\"unknown\""));
    assert!(
        rendered
            .lines()
            .filter(|line| line.starts_with("kura_replication_request_duration_seconds"))
            .all(|line| !line.contains("target="))
    );
    assert!(rendered.contains("kura_artifact_reads_total"));
    assert!(rendered.contains("kura_artifact_write_bytes_total"));
    assert!(rendered.contains("kura_artifact_egress_completions_total"));
    assert!(rendered.contains("kura_artifact_egress_bytes_total"));
    assert!(rendered.contains("kura_artifact_egress_duration_seconds"));
    assert!(rendered.contains("kura_artifact_egress_throughput_bytes_per_second"));
    assert!(rendered.contains("kura_public_request_latency_seconds"));
    assert!(rendered.contains("transport=\"http\""));
    assert!(rendered.contains("kura_segment_refreshes_total"));
    assert!(rendered.contains("kura_segment_evicted_artifacts_total"));
    assert!(rendered.contains("kura_replication_requests_total"));
    assert!(rendered.contains("kura_replication_apply_results_total"));
    assert!(rendered.contains("source=\"replication\""));
    assert!(rendered.contains("source=\"bootstrap\""));
    assert!(rendered.contains("item_type=\"artifact\""));
    assert!(rendered.contains("item_type=\"namespace_delete\""));
    assert!(rendered.contains("outcome=\"applied\""));
    assert!(rendered.contains("outcome=\"ignored_older\""));
    assert!(rendered.contains("kura_multipart_parts_total"));
    assert!(rendered.contains("kura_node_info"));
    assert!(rendered.contains("kura_node_geo_info"));
    assert!(rendered.contains("kura_file_descriptor_wait_seconds"));
    assert!(rendered.contains("kura_file_operations_total"));
    assert!(rendered.contains("kura_file_descriptor_in_use"));
    assert!(rendered.contains("kura_http_inflight_requests"));
    assert!(rendered.contains("kura_public_http_inflight_requests"));
    assert!(rendered.contains("kura_grpc_inflight_requests"));
    assert!(rendered.contains("kura_segment_handles_cached"));
    assert!(rendered.contains("kura_segment_handle_cache_capacity"));
    assert!(rendered.contains("kura_segment_handle_cache_lookups_total"));
    assert!(rendered.contains("kura_segment_handle_evictions_total"));
    assert!(rendered.contains("kura_manifest_index_entries"));
    assert!(rendered.contains("kura_manifest_cache_bytes"));
    assert!(rendered.contains("kura_manifest_cache_capacity_bytes"));
    assert!(rendered.contains("kura_manifest_cache_lookups_total"));
    assert!(rendered.contains("kura_manifest_cache_admissions_total"));
    assert!(rendered.contains("kura_manifest_cache_evictions_total"));
    assert!(rendered.contains("kura_manifest_index_rebuilds_total"));
    assert!(rendered.contains("kura_outbox_messages"));
    assert!(rendered.contains("kura_multipart_uploads"));
    assert!(rendered.contains("kura_tmp_dir_bytes"));
    assert!(rendered.contains("kura_discovered_peer_nodes"));
    assert!(rendered.contains("kura_bootstrap_known_peers"));
    assert!(rendered.contains("kura_bootstrap_completed_peers"));
    assert!(rendered.contains("kura_bootstrap_inflight_peers"));
    assert!(rendered.contains("kura_bootstrap_runs_total"));
    assert!(rendered.contains("kura_bootstrap_duration_seconds"));
    assert!(rendered.contains("kura_bootstrap_applied_items_total"));
    assert!(rendered.contains("kura_replication_bandwidth_configured_limit_bytes_per_second"));
    assert!(rendered.contains("kura_replication_bandwidth_effective_limit_bytes_per_second"));
    assert!(rendered.contains("kura_replication_bandwidth_public_latency_target_ms"));
    assert!(rendered.contains("kura_public_request_latency_ewma_ms"));
    assert!(rendered.contains("kura_analytics_events_total"));
    assert!(rendered.contains("kura_analytics_batches_total"));
    assert!(rendered.contains("kura_analytics_batch_duration_seconds"));
    assert!(rendered.contains("kura_analytics_queue_depth"));
    assert!(rendered.contains("kura_analytics_queue_capacity"));
    assert!(rendered.contains("kura_analytics_circuit_state"));
    assert!(rendered.contains("kura_analytics_circuit_transitions_total"));
    assert!(rendered.contains("kura_segment_generation_count"));
    assert!(rendered.contains("kura_process_resident_memory_bytes"));
    assert!(rendered.contains("kura_process_resident_anon_bytes"));
    assert!(rendered.contains("kura_process_resident_file_bytes"));
    assert!(rendered.contains("kura_jemalloc_allocated_bytes"));
    assert!(rendered.contains("kura_jemalloc_resident_bytes"));
    assert!(rendered.contains("kura_jemalloc_retained_bytes"));
    assert!(rendered.contains("kura_rocksdb_block_cache_usage_bytes"));
    assert!(rendered.contains("kura_rocksdb_block_cache_pinned_usage_bytes"));
    assert!(rendered.contains("kura_rocksdb_block_cache_capacity_bytes"));
    assert!(rendered.contains("kura_rocksdb_write_buffer_usage_bytes"));
    assert!(rendered.contains("kura_rocksdb_write_buffer_capacity_bytes"));
    assert!(rendered.contains("kura_memory_pressure_state"));
    assert!(rendered.contains("kura_memory_pressure_transitions_total"));
    assert!(rendered.contains("kura_background_work_paused"));
    assert!(rendered.contains("kura_memory_actions_total"));
    assert!(rendered.contains("kura_traffic_state"));
    assert!(rendered.contains("kura_ready_state"));
    assert!(rendered.contains("kura_drain_state"));
    assert!(rendered.contains("kura_initial_discovery_completed"));
    assert!(rendered.contains("kura_writer_lock_owned"));
    assert!(rendered.contains("kura_writer_lock_acquire_failures_total"));
    assert!(rendered.contains("kura_mmap_partial_page_exemptions_total"));
    assert!(rendered.contains("kura_process_start_time_seconds"));
    assert!(rendered.contains("region=\"eu-west\""));
    assert!(rendered.contains("tenant_id=\"acme\""));
    assert!(rendered.contains("country=\"US\""));
    assert!(rendered.contains("subdivision=\"US-VA\""));
}
