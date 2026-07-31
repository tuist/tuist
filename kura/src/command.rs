//! Executes the inspection commands against a running node.

use crate::{
    cli::{
        CacheCommand, Command, ConnectArgs, GrantArgs, NamespaceCommand, NodeCommand,
        OutboxCommand, OutputFormat, PeerCommand, RuntimeCommand, UploadCommand,
    },
    control::{
        client::{self, Target},
        report::{PeerListReport, ReplicationReport, RuntimeReport, StoreReport, TrafficReport},
    },
};

pub async fn execute(command: Command) -> Result<(), String> {
    match command {
        // Handled by the caller, which owns the serving path.
        Command::Serve => Ok(()),
        Command::Runtime(RuntimeCommand::Inspect(args)) => {
            let report: RuntimeReport = fetch(&args, "/v1/runtime").await?;
            emit(&args, &report, render_runtime)
        }
        Command::Runtime(RuntimeCommand::Config(args)) => {
            // Forwarded as untyped JSON so that a node newer than this CLI can
            // add configuration fields without breaking the command.
            let target = Target::resolve(args.data_dir.as_deref())?;
            let config = client::get_json(&target, "/v1/config").await?;
            println!(
                "{}",
                serde_json::to_string_pretty(&config)
                    .map_err(|error| format!("failed to render configuration: {error}"))?
            );
            Ok(())
        }
        Command::Runtime(RuntimeCommand::Store(args)) => {
            let report: StoreReport = fetch(&args, "/v1/store").await?;
            emit(&args, &report, render_store)
        }
        Command::Node(NodeCommand::Status(args)) => {
            let report: TrafficReport = fetch(&args, "/v1/status").await?;
            emit(&args, &report, render_status)
        }
        Command::Peer(PeerCommand::List(args)) => {
            let report: PeerListReport = fetch(&args, "/v1/peers").await?;
            emit(&args, &report, render_peers)
        }
        Command::Outbox(OutboxCommand::Stats(args)) => {
            let report: ReplicationReport = fetch(&args, "/v1/outbox").await?;
            emit(&args, &report, render_outbox)
        }
        Command::Cache(CacheCommand::Trim {
            cache,
            target,
            connect,
            grant,
        }) => {
            let result = mutate(
                &connect,
                &grant,
                "POST",
                "/v1/cache/trim",
                Some(serde_json::json!({ "cache": cache.as_str(), "target": target })),
            )
            .await?;
            println!(
                "trimmed {} entries from the {} cache",
                result
                    .get("evicted")
                    .and_then(serde_json::Value::as_u64)
                    .unwrap_or(0),
                cache.as_str()
            );
            Ok(())
        }
        Command::Namespace(NamespaceCommand::Delete {
            namespace_id,
            connect,
            grant,
        }) => {
            let result = mutate(
                &connect,
                &grant,
                "DELETE",
                &format!("/v1/namespaces/{namespace_id}"),
                None,
            )
            .await?;
            println!(
                "deleted namespace {namespace_id}, replicating to {} target(s)",
                result
                    .get("replication_targets")
                    .and_then(serde_json::Value::as_u64)
                    .unwrap_or(0)
            );
            Ok(())
        }
        Command::Upload(UploadCommand::Abort {
            upload_id,
            connect,
            grant,
        }) => {
            mutate(
                &connect,
                &grant,
                "DELETE",
                &format!("/v1/uploads/{upload_id}"),
                None,
            )
            .await?;
            println!("aborted upload {upload_id} and released its staged parts");
            Ok(())
        }
    }
}

async fn mutate(
    connect: &ConnectArgs,
    grant: &GrantArgs,
    method: &str,
    path: &str,
    body: Option<serde_json::Value>,
) -> Result<serde_json::Value, String> {
    let target = Target::resolve(connect.data_dir.as_deref())?;
    client::mutate(&target, method, path, grant.grant.as_deref(), body).await
}

async fn fetch<T: serde::de::DeserializeOwned>(
    args: &ConnectArgs,
    path: &str,
) -> Result<T, String> {
    let target = Target::resolve(args.data_dir.as_deref())?;
    client::get(&target, path).await
}

fn emit<T, R>(args: &ConnectArgs, report: &T, render: R) -> Result<(), String>
where
    T: serde::Serialize,
    R: Fn(&T) -> String,
{
    match args.resolved_output() {
        OutputFormat::Json => {
            println!(
                "{}",
                serde_json::to_string_pretty(report)
                    .map_err(|error| format!("failed to render report: {error}"))?
            );
        }
        OutputFormat::Text => print!("{}", render(report)),
    }
    Ok(())
}

fn section(output: &mut String, title: &str) {
    output.push_str(&format!("\n{title}\n"));
}

fn field(output: &mut String, label: &str, value: impl std::fmt::Display) {
    output.push_str(&format!("  {label:<38}{value}\n"));
}

fn list(output: &mut String, label: &str, values: &[String]) {
    if values.is_empty() {
        field(output, label, "(none)");
        return;
    }
    field(output, label, values.len());
    for value in values {
        output.push_str(&format!("    {value}\n"));
    }
}

fn render_status(report: &TrafficReport) -> String {
    let mut output = String::new();
    section(&mut output, "traffic");
    field(&mut output, "state", &report.state);
    field(&mut output, "ready", report.ready);
    field(&mut output, "serving", report.serving);
    field(&mut output, "draining", report.draining);
    field(&mut output, "writer lock owned", report.writer_lock_owned);
    field(&mut output, "http inflight", report.http_inflight);
    field(
        &mut output,
        "public http inflight",
        report.public_http_inflight,
    );
    field(&mut output, "grpc inflight", report.grpc_inflight);
    match report.public_request_latency_ewma_ms {
        Some(latency) => field(&mut output, "public latency ewma", format!("{latency}ms")),
        None => field(&mut output, "public latency ewma", "(no recent requests)"),
    }
    if !report.reasons.is_empty() {
        list(&mut output, "not ready because", &report.reasons);
    }
    output
}

fn render_store(report: &StoreReport) -> String {
    let mut output = String::new();
    section(&mut output, "store");
    field(&mut output, "outbox messages", report.outbox_messages);
    field(&mut output, "multipart uploads", report.multipart_uploads);
    field(
        &mut output,
        "promotion queue depth",
        report.promotion_queue_depth,
    );
    field(&mut output, "segment fsyncs", report.segment_fsync_count);
    for count in &report.segment_counts {
        field(
            &mut output,
            &format!("segments ({})", count.generation),
            count.segments,
        );
    }
    section(&mut output, "rocksdb");
    field(
        &mut output,
        "block cache",
        format!(
            "{} / {}",
            bytes(report.rocksdb_block_cache_usage_bytes),
            bytes(report.rocksdb_block_cache_capacity_bytes)
        ),
    );
    field(
        &mut output,
        "block cache pinned",
        bytes(report.rocksdb_block_cache_pinned_usage_bytes),
    );
    field(
        &mut output,
        "write buffer",
        format!(
            "{} / {}",
            bytes(report.rocksdb_write_buffer_usage_bytes),
            bytes(report.rocksdb_write_buffer_capacity_bytes)
        ),
    );
    output
}

fn render_peers(report: &PeerListReport) -> String {
    let mut output = String::new();
    section(&mut output, "peers");
    if report.peers.is_empty() {
        output.push_str("  (none known)\n");
        return output;
    }
    for peer in &report.peers {
        output.push_str(&format!("  {}\n", peer.url));
        field(&mut output, "  source", &peer.source);
        field(
            &mut output,
            "  bootstrapped",
            if peer.bootstrap_inflight {
                "in progress".to_string()
            } else {
                peer.bootstrapped.to_string()
            },
        );
        if peer.consecutive_replication_failures > 0 {
            field(
                &mut output,
                "  replication failures",
                peer.consecutive_replication_failures,
            );
            if let Some(retry) = peer.retry_in_ms {
                field(&mut output, "  retry in", format!("{retry}ms"));
            }
        }
    }
    output
}

fn render_outbox(report: &ReplicationReport) -> String {
    let mut output = String::new();
    section(&mut output, "outbox");
    field(
        &mut output,
        "depth",
        format!("{} / {}", report.outbox_depth, report.outbox_max_depth),
    );
    field(
        &mut output,
        "configured bandwidth limit",
        throughput(report.configured_bandwidth_limit_bytes_per_second),
    );
    match report.effective_bandwidth_limit_bytes_per_second {
        Some(limit) => field(&mut output, "effective bandwidth limit", throughput(limit)),
        None => field(&mut output, "effective bandwidth limit", "(unlimited)"),
    }
    field(
        &mut output,
        "public latency target",
        format!("{}ms", report.public_latency_target_ms),
    );

    section(&mut output, "replication backoff");
    if report.backoff.is_empty() {
        output.push_str("  (no targets backed off)\n");
    }
    for entry in &report.backoff {
        output.push_str(&format!(
            "  {} failures={} retry_in={}ms\n",
            entry.target, entry.consecutive_failures, entry.retry_in_ms
        ));
    }
    output
}

fn render_runtime(report: &RuntimeReport) -> String {
    let mut output = String::new();

    section(&mut output, "node");
    field(&mut output, "version", &report.node.version);
    field(&mut output, "pid", report.node.pid);
    field(
        &mut output,
        "uptime",
        format_duration(report.node.uptime_seconds),
    );
    field(&mut output, "node url", &report.node.node_url);
    field(&mut output, "region", &report.node.region);
    field(&mut output, "tenant", &report.node.tenant_id);
    field(
        &mut output,
        "ports",
        format!(
            "public={} internal={}",
            report.node.port, report.node.internal_port
        ),
    );
    field(&mut output, "peer tls", report.node.peer_tls_enabled);
    field(&mut output, "public tls", report.node.public_tls_enabled);
    field(&mut output, "extension", report.node.extension_enabled);
    field(&mut output, "analytics", report.node.analytics_enabled);
    field(
        &mut output,
        "usage metering",
        report.node.usage_metering_enabled,
    );
    field(&mut output, "geoip", report.node.geoip_loaded);

    output.push_str(&render_status(&report.traffic));

    section(&mut output, "membership");
    field(&mut output, "generation", report.membership.generation);
    field(
        &mut output,
        "initial discovery completed",
        report.membership.initial_discovery_completed,
    );
    field(
        &mut output,
        "peer view pending",
        report.membership.peer_view_pending,
    );
    field(
        &mut output,
        "bootstrap epoch",
        report.membership.bootstrap_epoch,
    );
    field(
        &mut output,
        "local data available at join",
        report.membership.local_data_available_at_join,
    );
    list(
        &mut output,
        "configured peers",
        &report.membership.configured_peers,
    );
    list(
        &mut output,
        "control-plane peers",
        &report.membership.dynamic_peers,
    );
    list(&mut output, "known peers", &report.membership.known_peers);
    list(
        &mut output,
        "bootstrapped peers",
        &report.membership.bootstrapped_peers,
    );
    list(
        &mut output,
        "bootstrap inflight peers",
        &report.membership.bootstrap_inflight_peers,
    );
    list(
        &mut output,
        "discovered-only peers",
        &report.membership.discovered_only_peers,
    );

    output.push_str(&render_outbox(&report.replication));

    section(&mut output, "memory");
    field(&mut output, "pressure", &report.memory.pressure);
    field(
        &mut output,
        "container accounting",
        report.memory.uses_container_accounting,
    );
    field(
        &mut output,
        "observation sequence",
        report.memory.observation_sequence,
    );
    field(
        &mut output,
        "runtime limit",
        bytes(report.memory.runtime_limit_bytes),
    );
    field(
        &mut output,
        "hard limit",
        bytes(report.memory.hard_limit_bytes),
    );
    field(
        &mut output,
        "transient",
        format!(
            "{} / {}",
            bytes(report.memory.transient_reserved_bytes),
            bytes(report.memory.transient_capacity_bytes)
        ),
    );
    field(
        &mut output,
        "mmap serving pool",
        bytes(report.memory.mmap_serving_pool_bytes as u64),
    );
    field(
        &mut output,
        "response streaming pool",
        bytes(report.memory.response_streaming_pool_bytes as u64),
    );
    field(
        &mut output,
        "foreground streaming pool",
        bytes(report.memory.foreground_response_streaming_pool_bytes as u64),
    );
    field(
        &mut output,
        "elastic foreground pool",
        bytes(
            report
                .memory
                .elastic_foreground_response_streaming_pool_bytes as u64,
        ),
    );
    field(
        &mut output,
        "degraded stream slots",
        report.memory.degraded_response_stream_slots,
    );
    field(
        &mut output,
        "reapi response budget",
        bytes(report.memory.reapi_response_budget_bytes as u64),
    );
    field(
        &mut output,
        "reapi materialization limit",
        bytes(report.memory.reapi_materialization_limit_bytes as u64),
    );
    field(
        &mut output,
        "manifest cache target",
        bytes(report.memory.manifest_cache_target_bytes as u64),
    );
    field(
        &mut output,
        "snapshot cache target",
        bytes(report.memory.snapshot_cache_target_bytes as u64),
    );
    field(
        &mut output,
        "bootstrap staging budget",
        bytes(report.memory.bootstrap_staging_budget_bytes),
    );
    field(
        &mut output,
        "background admission allowed",
        report.memory.background_admission_allowed,
    );
    field(&mut output, "outbox paused", report.memory.outbox_paused);
    field(
        &mut output,
        "segment refresh allowed",
        report.memory.segment_refresh_allowed,
    );
    field(
        &mut output,
        "manifest cache admission allowed",
        report.memory.manifest_cache_admission_allowed,
    );

    section(&mut output, "pools");
    field(
        &mut output,
        "bootstrap peer permits",
        report.pools.bootstrap_peer_permits_available,
    );
    field(
        &mut output,
        "bootstrap artifact permits",
        report.pools.bootstrap_artifact_permits_available,
    );
    field(
        &mut output,
        "tmp staging",
        format!(
            "{} / {}",
            bytes(report.pools.tmp_staging_reserved_bytes),
            bytes(report.pools.tmp_staging_capacity_bytes)
        ),
    );
    field(
        &mut output,
        "bootstrap staging",
        format!(
            "{} / {}",
            bytes(report.pools.bootstrap_staging_reserved_bytes),
            bytes(report.pools.bootstrap_staging_capacity_bytes)
        ),
    );

    output.push_str(&render_store(&report.store));
    output
}

fn bytes(value: u64) -> String {
    const UNITS: [&str; 5] = ["B", "KiB", "MiB", "GiB", "TiB"];
    let mut scaled = value as f64;
    let mut unit = 0;
    while scaled >= 1024.0 && unit < UNITS.len() - 1 {
        scaled /= 1024.0;
        unit += 1;
    }
    if unit == 0 {
        format!("{value} B")
    } else {
        format!("{scaled:.1} {}", UNITS[unit])
    }
}

fn throughput(value: u64) -> String {
    if value == 0 {
        return "(unlimited)".to_string();
    }
    format!("{}/s", bytes(value))
}

fn format_duration(seconds: u64) -> String {
    let days = seconds / 86_400;
    let hours = (seconds % 86_400) / 3_600;
    let minutes = (seconds % 3_600) / 60;
    if days > 0 {
        format!("{days}d {hours}h {minutes}m")
    } else if hours > 0 {
        format!("{hours}h {minutes}m")
    } else {
        format!("{minutes}m {}s", seconds % 60)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bytes_scale_to_readable_units() {
        assert_eq!(bytes(512), "512 B");
        assert_eq!(bytes(1024), "1.0 KiB");
        assert_eq!(bytes(1024 * 1024 * 3), "3.0 MiB");
        assert_eq!(bytes(1024 * 1024 * 1024 * 2), "2.0 GiB");
    }

    #[test]
    fn zero_bandwidth_limit_reads_as_unlimited() {
        assert_eq!(throughput(0), "(unlimited)");
        assert_eq!(throughput(1024), "1.0 KiB/s");
    }

    #[test]
    fn durations_drop_units_that_are_zero() {
        assert_eq!(format_duration(45), "0m 45s");
        assert_eq!(format_duration(3_700), "1h 1m");
        assert_eq!(format_duration(90_100), "1d 1h 1m");
    }

    #[test]
    fn peer_rendering_surfaces_backoff_only_when_failing() {
        let healthy = PeerListReport {
            peers: vec![crate::control::report::PeerEntry {
                url: "http://peer-a:7443".into(),
                source: "configured".into(),
                bootstrapped: true,
                bootstrap_inflight: false,
                consecutive_replication_failures: 0,
                retry_in_ms: None,
            }],
        };
        let rendered = render_peers(&healthy);
        assert!(rendered.contains("http://peer-a:7443"), "{rendered}");
        assert!(!rendered.contains("replication failures"), "{rendered}");

        let failing = PeerListReport {
            peers: vec![crate::control::report::PeerEntry {
                url: "http://peer-b:7443".into(),
                source: "control-plane".into(),
                bootstrapped: false,
                bootstrap_inflight: false,
                consecutive_replication_failures: 4,
                retry_in_ms: Some(16_000),
            }],
        };
        let rendered = render_peers(&failing);
        assert!(rendered.contains("replication failures"), "{rendered}");
        assert!(rendered.contains("16000ms"), "{rendered}");
    }

    #[test]
    fn empty_peer_list_is_stated_rather_than_blank() {
        let rendered = render_peers(&PeerListReport { peers: Vec::new() });
        assert!(rendered.contains("(none known)"), "{rendered}");
    }
}
