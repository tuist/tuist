use std::{
    collections::{BTreeMap, BTreeSet},
    net::{IpAddr, SocketAddr},
    path::Path,
    time::Duration,
};

use futures_util::stream::StreamExt;
use serde::Deserialize;
use tokio::{io::AsyncWriteExt, time::sleep};
use tracing::{Instrument, warn};

use crate::{config::Config, state::SharedState, sync::roles::PeerView};

// How much of a staged peer body may accumulate in the page cache before the
// writer drops what it has already written behind itself.
const PEER_BODY_CACHE_DROP_INTERVAL_BYTES: u64 = 8 * 1024 * 1024;

#[derive(Debug, Deserialize)]
struct PeerStatusPayload {
    region: String,
    tenant_id: String,
    node_url: String,
    /// Additive (design §2.4): an older peer reports none and is treated as
    /// serving.
    #[serde(default)]
    traffic_state: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
struct DiscoveryTarget {
    url: String,
    label: String,
    scope: DiscoveryScope,
    resolved: Option<ResolvedDiscoveryTarget>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
enum DiscoveryScope {
    Local,
    Global,
}

#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
struct ResolvedDiscoveryTarget {
    host: String,
    address: SocketAddr,
}

pub fn spawn_membership_task(state: SharedState) {
    spawn_supervised("membership", state, membership_task_loop);
}

pub(crate) fn spawn_supervised<F, Fut>(name: &'static str, state: SharedState, work: F)
where
    F: Fn(SharedState) -> Fut + Send + Sync + 'static,
    Fut: std::future::Future<Output = ()> + Send + 'static,
{
    tokio::spawn(
        async move {
            loop {
                let task_state = state.clone();
                let handle = tokio::spawn(work(task_state).in_current_span());
                match handle.await {
                    Ok(()) => return,
                    Err(error) if error.is_panic() => {
                        state
                            .metrics
                            .record_memory_action(&format!("background_panic_{name}"));
                        warn!("background task '{name}' panicked: {error:?}; respawning in 1s");
                        sleep(Duration::from_secs(1)).await;
                    }
                    Err(error) => {
                        warn!("background task '{name}' aborted: {error:?}");
                        return;
                    }
                }
            }
        }
        .in_current_span(),
    );
}

async fn membership_task_loop(state: SharedState) {
    loop {
        let mut members = BTreeSet::new();
        let mut peer_nodes = BTreeMap::new();
        let mut views: Vec<PeerView> = Vec::new();
        let targets = discovery_targets(&state.config, &state.dynamic_peers.load()).await;
        let mut peer_status_successes = 0_usize;
        let lookups = futures_util::future::join_all(targets.iter().map(|peer| {
            let client = match &peer.resolved {
                Some(resolved) => state
                    .peer_client_factory
                    .build_resolving(&resolved.host, resolved.address),
                None => Ok(state.client().as_ref().clone()),
            };
            let url = match peer.scope {
                DiscoveryScope::Local => format!("{}/_internal/status", peer.url),
                DiscoveryScope::Global => format!("{}/_internal/status?scope=global", peer.url),
            };
            let label = peer.label.clone();
            async move {
                let result = match client {
                    Ok(client) => client
                        .get(url)
                        .send()
                        .await
                        .map_err(|error| error.to_string()),
                    Err(error) => Err(error),
                };
                (label, result)
            }
        }))
        .await;
        for (peer, result) in lookups {
            match result {
                Ok(response) if response.status().is_success() => {
                    match response.json::<PeerStatusPayload>().await {
                        Ok(payload) => {
                            peer_status_successes += 1;
                            if payload.tenant_id != state.config.tenant_id
                                || is_self_or_own_gateway(
                                    &payload.node_url,
                                    &state.config.node_url,
                                    state.config.peer_gateway_url.as_deref(),
                                )
                            {
                                continue;
                            }
                            members.insert(payload.region.clone());
                            let traffic_state = payload.traffic_state.as_deref();
                            views.push(PeerView {
                                url: payload.node_url.clone(),
                                region: payload.region.clone(),
                                serving: traffic_state.is_none_or(|s| s == "serving"),
                                draining: traffic_state == Some("draining"),
                            });
                            peer_nodes.insert(payload.node_url, payload.region);
                        }
                        Err(error) => warn!("failed to decode peer status from {peer}: {error}"),
                    }
                }
                Ok(response) => {
                    warn!("peer status check failed for {peer}: {}", response.status())
                }
                Err(error) => warn!("peer status request failed for {peer}: {error}"),
            }
        }

        let discovery_observed = targets.is_empty() || peer_status_successes > 0;
        views.sort_by(|a, b| a.url.cmp(&b.url));
        views.dedup_by(|a, b| a.url == b.url);
        state.apply_peer_views(views);
        let membership_update = state
            .apply_membership_view(members, peer_nodes, discovery_observed)
            .await;
        state
            .metrics
            .update_discovered_peer_nodes(membership_update.known_peer_count);
        state.sync.evaluate(&state);
        state.maybe_mark_serving().await;
        sleep(Duration::from_secs(2)).await;
    }
}

pub(crate) async fn read_bounded_body(
    response: reqwest::Response,
    max_bytes: u64,
    label: &str,
) -> Result<Vec<u8>, String> {
    if let Some(content_length) = response.content_length()
        && content_length > max_bytes
    {
        return Err(format!(
            "{label} response body declared {content_length} bytes, exceeds limit of {max_bytes}"
        ));
    }
    let mut buffer = Vec::new();
    let mut total: u64 = 0;
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|error| format!("{label} body stream failed: {error}"))?;
        total = total.saturating_add(chunk.len() as u64);
        if total > max_bytes {
            return Err(format!(
                "{label} response body exceeded limit of {max_bytes} bytes"
            ));
        }
        buffer.extend_from_slice(&chunk);
    }
    Ok(buffer)
}

/// Streams a peer response body to a staging file under the caller's byte
/// reservation, applying replication bandwidth shaping and dropping the staged
/// page cache behind the writer under memory pressure. Used by the backfill
/// pass driver for both batch and per-artifact downloads.
pub(crate) async fn stream_response_to_temp(
    state: &SharedState,
    response: reqwest::Response,
    path: &Path,
    staging_limit: u64,
    bandwidth_shaped: bool,
) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| "peer staging path is missing a parent directory".to_string())?;
    state.io.create_dir_all(parent).await?;
    // The staged file must not exceed the caller's `peer_staging_budget`
    // reservation: an inconsistent peer serving a body larger than its manifest
    // advertised is rejected here instead of overrunning the budget.
    let mut destination = Some(state.io.create_file(path).await?);
    let outcome = async {
        let mut stream = response.bytes_stream();
        let mut total: u64 = 0;
        let mut advised_through: u64 = 0;
        while let Some(chunk) = stream.next().await {
            let chunk = chunk.map_err(|error| format!("failed to stream peer body: {error:?}"))?;
            total = total.saturating_add(chunk.len() as u64);
            if total > staging_limit {
                return Err(format!(
                    "peer body response exceeded reserved {staging_limit} bytes"
                ));
            }
            if bandwidth_shaped && let Some(limiter) = state.replication_bandwidth_limiter.as_ref()
            {
                limiter.acquire(chunk.len()).await;
            }
            destination
                .as_mut()
                .expect("peer staging destination remains open while streaming")
                .write_all(&chunk)
                .await
                .map_err(|error| format!("failed to persist peer body: {error}"))?;
            if total.saturating_sub(advised_through) >= PEER_BODY_CACHE_DROP_INTERVAL_BYTES {
                // Drop-behind follows the cache-reclaim serving mode (raw
                // charge / working set), while the park follows admission
                // (the pressure tier). They were one predicate when both
                // keyed on the raw charge; keeping them fused would stop
                // dropping staged page cache on exactly the charge-full warm
                // nodes the mode exists for, now that admission no longer
                // closes there.
                if state.memory.should_reclaim_file_cache() {
                    let file = destination
                        .take()
                        .expect("peer staging destination remains open while streaming");
                    destination = match state
                        .io
                        .sync_drop_cache_and_reopen_append(
                            file,
                            path,
                            advised_through,
                            total - advised_through,
                        )
                        .await
                    {
                        Ok(file) => Some(file),
                        Err(error) => {
                            state
                                .metrics
                                .record_memory_action("peer_body_file_cache_drop_failed");
                            warn!("failed to release peer body file cache: {error}");
                            return Err(error);
                        }
                    };
                    advised_through = total;
                }
                state.memory.wait_for_background_headroom().await;
            }
        }
        destination
            .as_mut()
            .expect("peer staging destination remains open while streaming")
            .flush()
            .await
            .map_err(|error| format!("failed to flush peer body: {error}"))?;
        Ok::<(), String>(())
    }
    .await;

    // Drop the handle before asynchronous best-effort cleanup. The caller's
    // owned guard is the cancellation-safe fallback when the watchdog drops
    // this future at an await point.
    drop(destination.take());
    if outcome.is_err() {
        state.io.remove_file_if_exists(path).await;
    }
    outcome
}

/// Whether a discovered peer's advertised `node_url` should be skipped because
/// it is this node itself or this node's own peer gateway.
///
/// When global discovery is fronted by a public peer gateway (the account peer
/// LoadBalancer), every same-account peer advertises that one gateway URL for
/// global scope. A node must not adopt its own gateway as a distinct peer, or
/// same-region traffic would hairpin out through the public endpoint and back
/// instead of staying in-cluster. An external peer (which has no gateway of its
/// own) still adopts the gateway URL and replicates through it.
fn is_self_or_own_gateway(node_url: &str, own_node_url: &str, own_gateway: Option<&str>) -> bool {
    node_url == own_node_url || own_gateway == Some(node_url)
}

async fn discovery_targets(config: &Config, dynamic_peers: &[String]) -> Vec<DiscoveryTarget> {
    let mut targets = config
        .peers
        .iter()
        .chain(dynamic_peers.iter())
        .cloned()
        .map(|peer| DiscoveryTarget {
            label: peer.clone(),
            url: peer,
            scope: DiscoveryScope::Local,
            resolved: None,
        })
        .collect::<BTreeSet<_>>();

    let Ok(node_url) = reqwest::Url::parse(&config.node_url) else {
        return targets.into_iter().collect();
    };
    let Some(port) = node_url.port_or_known_default() else {
        return targets.into_iter().collect();
    };
    let scheme = node_url.scheme().to_owned();
    if let Some(dns_name) = &config.discovery_dns_name {
        discover_dns_targets(&mut targets, dns_name, port, &scheme, DiscoveryScope::Local).await;
    }
    if let Some(dns_name) = &config.global_discovery_dns_name {
        discover_dns_targets(
            &mut targets,
            dns_name,
            port,
            &scheme,
            DiscoveryScope::Global,
        )
        .await;
    }

    targets.into_iter().collect()
}

async fn discover_dns_targets(
    targets: &mut BTreeSet<DiscoveryTarget>,
    dns_name: &str,
    port: u16,
    scheme: &str,
    scope: DiscoveryScope,
) {
    match tokio::net::lookup_host((dns_name, port)).await {
        Ok(addresses) => {
            for address in addresses {
                if scheme == "https" {
                    let url = format!("{scheme}://{dns_name}:{port}");
                    targets.insert(DiscoveryTarget {
                        label: format!("{url}@{}", address.ip()),
                        url,
                        scope,
                        resolved: Some(ResolvedDiscoveryTarget {
                            host: dns_name.to_owned(),
                            address,
                        }),
                    });
                } else {
                    let url = format!("{scheme}://{}:{port}", format_ip_for_url(address.ip()));
                    targets.insert(DiscoveryTarget {
                        label: url.clone(),
                        url,
                        scope,
                        resolved: None,
                    });
                }
            }
        }
        Err(error) => warn!("dns discovery lookup failed for {dns_name}:{port}: {error}"),
    }
}

fn format_ip_for_url(ip: IpAddr) -> String {
    match ip {
        IpAddr::V4(ip) => ip.to_string(),
        IpAddr::V6(ip) => format!("[{ip}]"),
    }
}

#[cfg(test)]
mod tests {
    use axum::{Router, routing::get};
    use tokio::net::TcpListener;

    use super::*;
    use crate::test_support::test_context;

    #[test]
    fn skips_self_and_own_gateway_but_adopts_other_peers() {
        let own = "https://kura-eu-0.kura-eu-headless.kura.svc.cluster.local:7443";
        let gateway = "https://peer.tuist-eu-1.kura.tuist.dev:7443";

        // Our own in-cluster URL and our own gateway are both skipped.
        assert!(is_self_or_own_gateway(own, own, Some(gateway)));
        assert!(is_self_or_own_gateway(gateway, own, Some(gateway)));

        // A different peer (another instance, or a self-hosted node) is adopted.
        assert!(!is_self_or_own_gateway(
            "https://kura-eu-1.kura-eu-headless.kura.svc.cluster.local:7443",
            own,
            Some(gateway),
        ));

        // With no gateway of our own, an external node adopting the managed
        // gateway URL must not skip it.
        assert!(!is_self_or_own_gateway(gateway, own, None));
    }

    async fn spawn_server(app: Router) -> (String, tokio::task::JoinHandle<()>) {
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("failed to bind test listener");
        let address = listener
            .local_addr()
            .expect("failed to read listener address");
        let handle = tokio::spawn(async move {
            axum::serve(listener, app)
                .await
                .expect("test server should run");
        });
        (format!("http://{address}"), handle)
    }

    #[tokio::test]
    async fn peer_body_larger_than_its_reservation_is_rejected_mid_stream() {
        // The guard the backfill pass relies on: an inconsistent peer streams
        // a chunked body larger than the manifest it listed, so the receiver
        // has reserved less than the peer sends. The staged file is capped at
        // the reservation and the transfer fails there, instead of overrunning
        // the staging budget and the tmp-dir ceiling. Both call sites derive
        // the reservation from the peer's declared size
        // (`spool_batch_response`, `apply_individual_response`), so a
        // regression here surfaces as ENOSPC rather than a failed pass.
        let chunk = vec![7_u8; 16 * 1024];
        let app = Router::new().route(
            "/body",
            get({
                let chunk = chunk.clone();
                move || {
                    let chunk = chunk.clone();
                    async move {
                        let stream = futures_util::stream::iter(0..8).then(move |_| {
                            let chunk = chunk.clone();
                            async move { Ok::<_, std::io::Error>(chunk) }
                        });
                        axum::body::Body::from_stream(stream)
                    }
                }
            }),
        );
        let (peer_url, _server) = spawn_server(app).await;

        let ctx = test_context(|_config| {}).await;
        let reserved = 32 * 1024_u64;
        let response = reqwest::get(format!("{peer_url}/body"))
            .await
            .expect("peer body request should succeed");
        let path = ctx.state.config.tmp_dir.join("backfill").join("overrun");

        let error = stream_response_to_temp(&ctx.state, response, &path, reserved, true)
            .await
            .expect_err("a body larger than the reservation must be rejected");
        assert!(
            error.contains("exceeded reserved"),
            "expected a reservation-overflow rejection, got: {error}"
        );

        assert!(
            tokio::fs::metadata(&path).await.is_err(),
            "the partial staging file must be removed, not left charging the tmp budget"
        );
    }

    #[tokio::test]
    async fn discover_targets_keeps_dns_names_for_https_peers() {
        let ctx = test_context(|config| {
            config.node_url = "https://kura-us.kura.internal:7443".into();
            config.peers = vec!["https://seed.kura.internal:7443".into()];
            config.discovery_dns_name = Some("localhost".into());
            config.global_discovery_dns_name = Some("localhost".into());
        })
        .await;

        let targets = discovery_targets(&ctx.state.config, &ctx.state.dynamic_peers.load()).await;

        assert!(targets.iter().any(|target| {
            target.url == "https://seed.kura.internal:7443" && target.resolved.is_none()
        }));
        assert!(targets.iter().any(|target| {
            target.url == "https://localhost:7443"
                && target.scope == DiscoveryScope::Local
                && target.resolved.is_some()
        }));
        assert!(targets.iter().any(|target| {
            target.url == "https://localhost:7443"
                && target.scope == DiscoveryScope::Global
                && target.resolved.is_some()
        }));
        assert!(!targets.iter().any(|target| {
            target.url.starts_with("https://127.") || target.url.starts_with("https://[::1]")
        }));
    }
}
