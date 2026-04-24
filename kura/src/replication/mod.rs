pub mod operation;
pub mod outbox_message;

use std::{
    collections::{BTreeMap, BTreeSet},
    net::IpAddr,
    path::Path,
    time::Duration,
};

use futures_util::StreamExt;
use reqwest::header::{CONTENT_TYPE, HeaderValue};
use serde::Deserialize;
use tokio::{io::AsyncWriteExt, time::sleep};
use tokio_util::io::ReaderStream;
use tracing::{Instrument, field, warn};

use crate::{
    artifact::manifest::ArtifactManifest,
    config::Config,
    constants::REPLICATION_RETRY_SECS,
    failpoints::FailpointName,
    state::SharedState,
    store::{ArtifactApplyOutcome, ManifestPage, NamespaceTombstonePage},
    telemetry::inject_current_trace_context,
    utils::{replication_target_label, temp_file_path, url_encode},
};

use self::{operation::ReplicationOperation, outbox_message::OutboxMessage};

const BOOTSTRAP_PAGE_LIMIT: usize = 256;

#[derive(Debug, Deserialize)]
struct PeerStatusPayload {
    region: String,
    tenant_id: String,
    node_url: String,
}

#[cfg(test)]
pub async fn enqueue_replication_for_artifact(state: &SharedState, manifest: &ArtifactManifest) {
    for peer in replication_targets(state).await {
        if let Err(error) = state.store.enqueue(OutboxMessage {
            target: peer.clone(),
            operation: ReplicationOperation::UpsertArtifact {
                producer: manifest.producer,
                namespace_id: manifest.namespace_id.clone(),
                key: manifest.key.clone(),
                content_type: manifest.content_type.clone(),
                artifact_id: manifest.artifact_id.clone(),
                version_ms: manifest.version_ms,
                inline: manifest.inline,
            },
        }) {
            warn!("failed to enqueue artifact replication for {peer}: {error}");
        }
    }
    state.notify.notify_one();
}

pub fn spawn_membership_task(state: SharedState) {
    tokio::spawn(async move {
        let mut initial_discovery_completed = false;
        loop {
            let mut members = BTreeSet::new();
            let mut peer_nodes = BTreeMap::new();
            for peer in discovery_targets(&state.config).await {
                match state
                    .client
                    .get(format!("{peer}/_internal/status"))
                    .send()
                    .await
                {
                    Ok(response) if response.status().is_success() => match response
                        .json::<PeerStatusPayload>()
                        .await
                    {
                        Ok(payload) => {
                            if payload.tenant_id != state.config.tenant_id
                                || payload.node_url == state.config.node_url
                            {
                                continue;
                            }
                            members.insert(payload.region.clone());
                            peer_nodes.insert(payload.node_url, payload.region);
                        }
                        Err(error) => warn!("failed to decode peer status from {peer}: {error}"),
                    },
                    Ok(response) => {
                        warn!("peer status check failed for {peer}: {}", response.status())
                    }
                    Err(error) => warn!("peer status request failed for {peer}: {error}"),
                }
            }

            *state.members.write().await = members;
            let (discovered_peers, lost_peers) = {
                let mut known_peers = state.peer_nodes.write().await;
                let lost_peers = known_peers
                    .keys()
                    .filter(|peer| !peer_nodes.contains_key(*peer))
                    .cloned()
                    .collect::<Vec<_>>();
                let discovered_peers = peer_nodes
                    .keys()
                    .filter(|peer| !known_peers.contains_key(*peer))
                    .cloned()
                    .collect::<Vec<_>>();
                *known_peers = peer_nodes;
                (discovered_peers, lost_peers)
            };
            if !lost_peers.is_empty() {
                state.forget_peers(&lost_peers).await;
            }
            if !initial_discovery_completed {
                state.mark_initial_discovery_completed().await;
                initial_discovery_completed = true;
            } else if !discovered_peers.is_empty() || !lost_peers.is_empty() {
                state.extend_readiness_settle_window().await;
            }
            state
                .metrics
                .update_discovered_peer_nodes(state.peer_nodes.read().await.len());
            for peer in discovered_peers {
                maybe_spawn_bootstrap_task(state.clone(), peer).await;
            }
            state.maybe_mark_serving().await;
            sleep(Duration::from_secs(2)).await;
        }
    });
}

pub fn spawn_outbox_task(state: SharedState) {
    tokio::spawn(async move {
        loop {
            let pause_outbox = state.memory.pause_outbox();
            state
                .metrics
                .update_background_work_paused("outbox", pause_outbox);
            if !pause_outbox && let Err(error) = process_outbox(&state).await {
                warn!("outbox processing failed: {error}");
            }

            tokio::select! {
                _ = state.notify.notified() => {},
                _ = sleep(Duration::from_secs(REPLICATION_RETRY_SECS)) => {},
            }
        }
    });
}

pub async fn replication_targets(state: &SharedState) -> Vec<String> {
    let mut targets = state.config.peers.iter().cloned().collect::<BTreeSet<_>>();
    targets.extend(state.peer_nodes.read().await.keys().cloned());
    targets.remove(&state.config.node_url);
    targets.into_iter().collect()
}

async fn maybe_spawn_bootstrap_task(state: SharedState, peer: String) {
    if !state.note_bootstrap_started(&peer).await {
        return;
    }

    tokio::spawn(async move {
        let started_at = std::time::Instant::now();
        let result = bootstrap_from_peer(&state, &peer).await;
        match result {
            Ok(stats) => {
                state.note_bootstrap_succeeded(&peer).await;
                state.metrics.record_bootstrap_run(
                    "ok",
                    started_at.elapsed(),
                    stats.tombstones_applied,
                    stats.artifacts_applied,
                );
                state.maybe_mark_serving().await;
            }
            Err(error) => {
                warn!("bootstrap from {peer} failed: {error}");
                state
                    .metrics
                    .record_bootstrap_run("error", started_at.elapsed(), 0, 0);
                state.note_bootstrap_failed(&peer).await;
            }
        }
    });
}

async fn bootstrap_from_peer(state: &SharedState, peer: &str) -> Result<BootstrapStats, String> {
    let tombstones_applied = bootstrap_namespace_tombstones_from_peer(state, peer).await?;
    let artifacts_applied = bootstrap_manifests_from_peer(state, peer).await?;
    Ok(BootstrapStats {
        tombstones_applied,
        artifacts_applied,
    })
}

async fn bootstrap_namespace_tombstones_from_peer(
    state: &SharedState,
    peer: &str,
) -> Result<u64, String> {
    let mut after = None;
    let mut applied = 0_u64;

    loop {
        let page = fetch_bootstrap_tombstones_page(state, peer, after.as_deref()).await?;
        for tombstone in &page.tombstones {
            let outcome = state
                .store
                .apply_replicated_namespace_delete(&tombstone.namespace_id, tombstone.version_ms)
                .await
                .inspect_err(|_| {
                    state.metrics.record_replication_apply(
                        "bootstrap",
                        "namespace_delete",
                        "error",
                    );
                })?;
            state.metrics.record_replication_apply(
                "bootstrap",
                "namespace_delete",
                outcome.as_str(),
            );
            if outcome.applied() {
                applied += 1;
            }
        }

        match page.next_after {
            Some(next_after) => after = Some(next_after),
            None => return Ok(applied),
        }
    }
}

async fn bootstrap_manifests_from_peer(state: &SharedState, peer: &str) -> Result<u64, String> {
    let mut after = None;
    let mut applied = 0_u64;

    loop {
        let page = fetch_bootstrap_manifests_page(state, peer, after.as_deref()).await?;
        state
            .store
            .hit_failpoint(FailpointName::AfterBootstrapManifestPageFetchBeforeApply)
            .await?;
        for manifest in &page.manifests {
            let outcome = state.store.artifact_apply_outcome(
                manifest.producer,
                &manifest.namespace_id,
                &manifest.key,
                manifest.version_ms,
            )?;
            if !outcome.applied() {
                state
                    .metrics
                    .record_replication_apply("bootstrap", "artifact", outcome.as_str());
                continue;
            }

            let outcome = bootstrap_artifact_from_peer(state, peer, manifest)
                .await
                .inspect_err(|_| {
                    state
                        .metrics
                        .record_replication_apply("bootstrap", "artifact", "error");
                })?;
            state
                .metrics
                .record_replication_apply("bootstrap", "artifact", outcome.as_str());
            if outcome.applied() {
                applied += 1;
            }
        }

        match page.next_after {
            Some(next_after) => after = Some(next_after),
            None => return Ok(applied),
        }
    }
}

async fn bootstrap_artifact_from_peer(
    state: &SharedState,
    peer: &str,
    manifest: &ArtifactManifest,
) -> Result<ArtifactApplyOutcome, String> {
    let url = format!(
        "{peer}/_internal/bootstrap/artifacts/{}",
        url_encode(&manifest.artifact_id)
    );
    let response = state
        .client
        .get(&url)
        .send()
        .await
        .map_err(|error| format!("bootstrap artifact request failed: {error}"))?;
    if response.status() == reqwest::StatusCode::NOT_FOUND {
        return Ok(ArtifactApplyOutcome::IgnoredStale);
    }
    let response = response
        .error_for_status()
        .map_err(|error| format!("bootstrap artifact response failed: {error}"))?;

    if manifest.inline {
        let bytes = response
            .bytes()
            .await
            .map_err(|error| format!("failed to read bootstrap keyvalue body: {error}"))?;
        state
            .store
            .hit_failpoint(FailpointName::AfterBootstrapArtifactFetchBeforePersist)
            .await?;
        return state
            .store
            .apply_replicated_inline_artifact_from_bytes(
                manifest.producer,
                &manifest.namespace_id,
                &manifest.key,
                &manifest.content_type,
                bytes.as_ref(),
                manifest.version_ms,
            )
            .await;
    }

    let temp_path = temp_file_path(&state.config.tmp_dir.join("bootstrap"), "bootstrap");
    stream_response_to_temp(state, response, &temp_path).await?;
    state
        .store
        .hit_failpoint(FailpointName::AfterBootstrapArtifactFetchBeforePersist)
        .await?;
    state
        .store
        .apply_replicated_artifact_from_path(
            manifest.producer,
            &manifest.namespace_id,
            &manifest.key,
            &manifest.content_type,
            &temp_path,
            manifest.version_ms,
        )
        .await
}

async fn stream_response_to_temp(
    state: &SharedState,
    response: reqwest::Response,
    path: &Path,
) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| "bootstrap temp path is missing a parent directory".to_string())?;
    state.io.create_dir_all(parent).await?;
    let mut destination = state.io.create_file(path).await?;
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|error| format!("failed to stream bootstrap body: {error}"))?;
        destination
            .write_all(&chunk)
            .await
            .map_err(|error| format!("failed to persist bootstrap body: {error}"))?;
    }
    destination
        .flush()
        .await
        .map_err(|error| format!("failed to flush bootstrap body: {error}"))?;
    Ok(())
}

async fn fetch_bootstrap_manifests_page(
    state: &SharedState,
    peer: &str,
    after: Option<&str>,
) -> Result<ManifestPage, String> {
    let mut url = format!("{peer}/_internal/bootstrap/manifests?limit={BOOTSTRAP_PAGE_LIMIT}");
    if let Some(after) = after {
        url.push_str("&after=");
        url.push_str(&url_encode(after));
    }

    state
        .client
        .get(&url)
        .send()
        .await
        .map_err(|error| format!("bootstrap manifest request failed: {error}"))?
        .error_for_status()
        .map_err(|error| format!("bootstrap manifest response failed: {error}"))?
        .json::<ManifestPage>()
        .await
        .map_err(|error| format!("failed to decode bootstrap manifest page: {error}"))
}

async fn fetch_bootstrap_tombstones_page(
    state: &SharedState,
    peer: &str,
    after: Option<&str>,
) -> Result<NamespaceTombstonePage, String> {
    let mut url =
        format!("{peer}/_internal/bootstrap/namespace_tombstones?limit={BOOTSTRAP_PAGE_LIMIT}");
    if let Some(after) = after {
        url.push_str("&after=");
        url.push_str(&url_encode(after));
    }

    state
        .client
        .get(&url)
        .send()
        .await
        .map_err(|error| format!("bootstrap tombstone request failed: {error}"))?
        .error_for_status()
        .map_err(|error| format!("bootstrap tombstone response failed: {error}"))?
        .json::<NamespaceTombstonePage>()
        .await
        .map_err(|error| format!("failed to decode bootstrap tombstone page: {error}"))
}

async fn discovery_targets(config: &Config) -> Vec<String> {
    let mut targets = config.peers.iter().cloned().collect::<BTreeSet<_>>();
    let Some(dns_name) = &config.discovery_dns_name else {
        return targets.into_iter().collect();
    };

    let Ok(node_url) = reqwest::Url::parse(&config.node_url) else {
        return targets.into_iter().collect();
    };
    let Some(port) = node_url.port_or_known_default() else {
        return targets.into_iter().collect();
    };
    let scheme = node_url.scheme().to_owned();
    if scheme == "https" {
        targets.insert(format!("{scheme}://{dns_name}:{port}"));
        return targets.into_iter().collect();
    }

    match tokio::net::lookup_host((dns_name.as_str(), port)).await {
        Ok(addresses) => {
            for address in addresses {
                targets.insert(format!(
                    "{scheme}://{}:{port}",
                    format_ip_for_url(address.ip())
                ));
            }
        }
        Err(error) => warn!("dns discovery lookup failed for {dns_name}:{port}: {error}"),
    }

    targets.into_iter().collect()
}

fn format_ip_for_url(ip: IpAddr) -> String {
    match ip {
        IpAddr::V4(ip) => ip.to_string(),
        IpAddr::V6(ip) => format!("[{ip}]"),
    }
}

struct BootstrapStats {
    tombstones_applied: u64,
    artifacts_applied: u64,
}

pub async fn process_outbox(state: &SharedState) -> Result<(), String> {
    let mut after = None::<Vec<u8>>;
    while let Some((message_key, message)) = state.store.next_outbox_message(after.as_deref())? {
        let started_at = std::time::Instant::now();
        let operation_name = message.operation.name();
        let result = replicate_message(state, &message).await;

        match result {
            Ok(()) => {
                match state
                    .store
                    .hit_failpoint(FailpointName::BeforeDeleteOutboxMessageAfterSuccess)
                    .await
                {
                    Ok(()) => {
                        state.metrics.record_replication(
                            &message.target,
                            operation_name,
                            "ok",
                            started_at.elapsed(),
                        );
                        state.store.delete_outbox_message(&message_key)?;
                    }
                    Err(error) => {
                        state.metrics.record_replication(
                            &message.target,
                            operation_name,
                            "error",
                            started_at.elapsed(),
                        );
                        warn!("replication to {} failed: {error}", message.target);
                    }
                }
            }
            Err(error) => {
                state.metrics.record_replication(
                    &message.target,
                    operation_name,
                    "error",
                    started_at.elapsed(),
                );
                warn!("replication to {} failed: {error}", message.target);
            }
        }
        after = Some(message_key);
    }

    Ok(())
}

async fn replicate_message(state: &SharedState, message: &OutboxMessage) -> Result<(), String> {
    match &message.operation {
        ReplicationOperation::UpsertArtifact {
            producer,
            namespace_id,
            key,
            content_type,
            artifact_id,
            version_ms,
            inline,
        } => {
            let manifest = match state.store.manifest(artifact_id)? {
                Some(manifest) => manifest,
                None => return Ok(()),
            };

            let file = state
                .store
                .open_artifact_reader(&manifest)
                .await
                .map_err(|error| {
                    format!("failed to open local artifact for replication: {error}")
                })?;

            let url = format!(
                "{}/_internal/replicate/artifact?producer={}&inline={}&namespace_id={}&key={}&content_type={}&version_ms={}",
                message.target,
                producer.as_str(),
                inline,
                url_encode(namespace_id),
                url_encode(key),
                url_encode(content_type),
                version_ms,
            );
            let body = reqwest::Body::wrap_stream(ReaderStream::new(file));
            let request_span = tracing::info_span!(
                "replication.request",
                otel.name = "PUT /_internal/replicate/artifact",
                otel.kind = "client",
                kura.operation = "upsert_artifact",
                http.request.method = "PUT",
                url.full = %url,
                peer.service = %replication_target_label(&message.target),
                http.response.status_code = field::Empty,
                otel.status_code = field::Empty,
            );
            let response_span = request_span.clone();

            async {
                let mut headers = reqwest::header::HeaderMap::new();
                inject_current_trace_context(&mut headers);
                headers.insert(
                    CONTENT_TYPE,
                    HeaderValue::from_static("application/octet-stream"),
                );

                let response = state
                    .client
                    .put(&url)
                    .headers(headers)
                    .body(body)
                    .send()
                    .await
                    .map_err(|error| format!("artifact replication request failed: {error}"))?;
                response_span.record("http.response.status_code", response.status().as_u16());
                if response.status().is_server_error() {
                    response_span.record("otel.status_code", "ERROR");
                }
                response
                    .error_for_status()
                    .map(|_| ())
                    .map_err(|error| format!("artifact replication response failed: {error}"))
            }
            .instrument(request_span)
            .await
        }
        ReplicationOperation::DeleteNamespace {
            namespace_id,
            version_ms,
        } => {
            let url = format!(
                "{}/_internal/replicate/namespace?namespace_id={}&version_ms={}",
                message.target,
                url_encode(namespace_id),
                version_ms,
            );
            let request_span = tracing::info_span!(
                "replication.request",
                otel.name = "DELETE /_internal/replicate/namespace",
                otel.kind = "client",
                kura.operation = "delete_namespace",
                http.request.method = "DELETE",
                url.full = %url,
                peer.service = %replication_target_label(&message.target),
                http.response.status_code = field::Empty,
                otel.status_code = field::Empty,
            );
            let response_span = request_span.clone();

            async {
                let mut headers = reqwest::header::HeaderMap::new();
                inject_current_trace_context(&mut headers);
                let response = state
                    .client
                    .delete(&url)
                    .headers(headers)
                    .send()
                    .await
                    .map_err(|error| format!("namespace replication request failed: {error}"))?;
                response_span.record("http.response.status_code", response.status().as_u16());
                if response.status().is_server_error() {
                    response_span.record("otel.status_code", "ERROR");
                }
                response
                    .error_for_status()
                    .map(|_| ())
                    .map_err(|error| format!("namespace replication response failed: {error}"))
            }
            .instrument(request_span)
            .await
        }
    }
}

#[cfg(test)]
mod tests {
    use axum::{Json, Router, extract::Path as AxumPath, http::StatusCode, routing::get};
    use tokio::net::TcpListener;

    use super::*;
    use crate::{
        artifact::producer::ArtifactProducer,
        failpoints::{FailpointAction, FailpointName},
        http::router,
        test_support::test_context,
        utils::artifact_storage_id,
    };

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

    fn bootstrap_test_manifest(
        producer: ArtifactProducer,
        inline: bool,
        namespace_id: &str,
        key: &str,
        content_type: &str,
        size: u64,
        version_ms: u64,
    ) -> ArtifactManifest {
        ArtifactManifest {
            artifact_id: artifact_storage_id(producer, "test-tenant", namespace_id, key),
            producer,
            namespace_id: namespace_id.to_owned(),
            key: key.to_owned(),
            content_type: content_type.to_owned(),
            inline,
            blob_path: None,
            segment_id: None,
            segment_offset: None,
            size,
            version_ms,
            created_at_ms: version_ms,
        }
    }

    #[tokio::test]
    async fn enqueue_replication_skips_current_node() {
        let ctx = test_context(|config| {
            config.node_url = "http://127.0.0.1:4100".into();
            config.peers = vec![
                "http://127.0.0.1:4100".into(),
                "http://127.0.0.1:4101".into(),
            ];
        })
        .await;
        let manifest = ctx
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "namespace",
                "artifact",
                "application/octet-stream",
                b"hello",
            )
            .await
            .expect("artifact should persist");

        enqueue_replication_for_artifact(&ctx.state, &manifest).await;

        let queued = ctx
            .state
            .store
            .outbox_messages()
            .expect("outbox should load");
        assert_eq!(queued.len(), 1);
        assert_eq!(queued[0].1.target, "http://127.0.0.1:4101");
    }

    #[tokio::test]
    async fn discover_targets_keeps_dns_names_for_https_peers() {
        let ctx = test_context(|config| {
            config.node_url = "https://kura-us.kura.internal:7443".into();
            config.peers = vec!["https://seed.kura.internal:7443".into()];
            config.discovery_dns_name = Some("kura-ring.kura.internal".into());
        })
        .await;

        let targets: Vec<String> = discovery_targets(&ctx.state.config).await;

        assert!(targets.contains(&"https://seed.kura.internal:7443".to_string()));
        assert!(targets.contains(&"https://kura-ring.kura.internal:7443".to_string()));
        assert!(!targets.iter().any(|target: &String| {
            target.starts_with("https://127.") || target.starts_with("https://[::1]")
        }));
    }

    #[tokio::test]
    async fn process_outbox_replicates_artifacts_and_namespace_deletes() {
        let remote = test_context(|_| {}).await;
        let (remote_url, _server) = spawn_server(router(remote.state.clone())).await;

        let local = test_context(|_| {}).await;
        local
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact",
                "application/octet-stream",
                b"payload",
            )
            .await
            .expect("artifact should persist");

        local
            .state
            .store
            .enqueue(OutboxMessage {
                target: remote_url.clone(),
                operation: ReplicationOperation::UpsertArtifact {
                    producer: ArtifactProducer::Gradle,
                    namespace_id: "ios".into(),
                    key: "artifact".into(),
                    content_type: "application/octet-stream".into(),
                    artifact_id: local
                        .state
                        .store
                        .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
                        .await
                        .expect("artifact fetch should succeed")
                        .expect("artifact should exist")
                        .artifact_id,
                    version_ms: local
                        .state
                        .store
                        .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
                        .await
                        .expect("artifact fetch should succeed")
                        .expect("artifact should exist")
                        .version_ms,
                    inline: false,
                },
            })
            .expect("upsert should enqueue");

        local
            .state
            .store
            .enqueue(OutboxMessage {
                target: remote_url,
                operation: ReplicationOperation::DeleteNamespace {
                    namespace_id: "android".into(),
                    version_ms: 123,
                },
            })
            .expect("delete should enqueue");

        process_outbox(&local.state)
            .await
            .expect("outbox processing should succeed");

        let replicated = remote
            .state
            .store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
            .await
            .expect("artifact fetch should succeed")
            .expect("replicated artifact should exist");
        let mut reader = remote
            .state
            .store
            .open_artifact_reader(&replicated)
            .await
            .expect("replicated artifact reader should open");
        let mut bytes = Vec::new();
        use tokio::io::AsyncReadExt;
        reader
            .read_to_end(&mut bytes)
            .await
            .expect("replicated bytes should read");
        assert_eq!(bytes, b"payload");

        let queued = local
            .state
            .store
            .outbox_messages()
            .expect("outbox should load");
        assert!(
            queued.is_empty(),
            "successful replication should clear outbox"
        );
    }

    #[tokio::test]
    async fn process_outbox_retries_after_success_before_outbox_delete() {
        let remote = test_context(|_| {}).await;
        let (remote_url, _server) = spawn_server(router(remote.state.clone())).await;
        let local = test_context(|_| {}).await;

        let manifest = local
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact",
                "application/octet-stream",
                b"payload",
            )
            .await
            .expect("artifact should persist");

        local
            .state
            .store
            .enqueue(OutboxMessage {
                target: remote_url,
                operation: ReplicationOperation::UpsertArtifact {
                    producer: ArtifactProducer::Gradle,
                    namespace_id: "ios".into(),
                    key: "artifact".into(),
                    content_type: "application/octet-stream".into(),
                    artifact_id: manifest.artifact_id.clone(),
                    version_ms: manifest.version_ms,
                    inline: false,
                },
            })
            .expect("outbox message should enqueue");

        local.state.store.failpoints().set_once(
            FailpointName::BeforeDeleteOutboxMessageAfterSuccess,
            FailpointAction::Error("delete interrupted".into()),
        );

        process_outbox(&local.state)
            .await
            .expect("outbox processing should complete");

        assert_eq!(
            local
                .state
                .store
                .outbox_message_count()
                .expect("outbox count should load"),
            1
        );

        process_outbox(&local.state)
            .await
            .expect("outbox retry should complete");

        assert_eq!(
            local
                .state
                .store
                .outbox_message_count()
                .expect("outbox count should load"),
            0
        );
        let replicated = remote
            .state
            .store
            .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
            .await
            .expect("artifact fetch should succeed")
            .expect("replicated artifact should exist");
        let mut reader = remote
            .state
            .store
            .open_artifact_reader(&replicated)
            .await
            .expect("artifact reader should open");
        let mut bytes = Vec::new();
        use tokio::io::AsyncReadExt;
        reader
            .read_to_end(&mut bytes)
            .await
            .expect("artifact bytes should read");
        assert_eq!(bytes, b"payload");
    }

    #[tokio::test]
    async fn bootstrap_respects_local_newer_winner() {
        let remote = test_context(|_| {}).await;
        let remote_manifest = remote
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"remote-v1",
            )
            .await
            .expect("remote artifact should persist");
        let (remote_url, _server) = spawn_server(router(remote.state.clone())).await;

        let local = test_context(|_| {}).await;
        local
            .state
            .store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "artifact",
                "application/octet-stream",
                b"local-v2",
                remote_manifest.version_ms + 100,
            )
            .await
            .expect("local newer artifact should apply");

        let outcome = bootstrap_artifact_from_peer(&local.state, &remote_url, &remote_manifest)
            .await
            .expect("bootstrap should complete");
        assert_eq!(outcome, ArtifactApplyOutcome::IgnoredStale);

        let manifest = local
            .state
            .store
            .fetch_artifact(ArtifactProducer::Xcode, "ios", "artifact")
            .await
            .expect("artifact fetch should succeed")
            .expect("artifact should remain");
        let mut reader = local
            .state
            .store
            .open_artifact_reader(&manifest)
            .await
            .expect("artifact reader should open");
        let mut bytes = Vec::new();
        use tokio::io::AsyncReadExt;
        reader
            .read_to_end(&mut bytes)
            .await
            .expect("artifact bytes should read");
        assert_eq!(bytes, b"local-v2");
    }

    #[tokio::test]
    async fn bootstrap_tombstones_prevent_stale_manifest_resurrection() {
        let stale_manifest = bootstrap_test_manifest(
            ArtifactProducer::Xcode,
            true,
            "ios",
            "cas-1",
            "application/json",
            br#"{"value":"stale"}"#.len() as u64,
            100,
        );
        let tombstones = NamespaceTombstonePage {
            tombstones: vec![crate::store::NamespaceTombstoneRecord {
                namespace_id: "ios".into(),
                version_ms: 200,
            }],
            next_after: None,
        };
        let manifests = ManifestPage {
            manifests: vec![stale_manifest.clone()],
            next_after: None,
        };
        let artifact_payload = br#"{"value":"stale"}"#.to_vec();
        let app = Router::new()
            .route(
                "/_internal/bootstrap/namespace_tombstones",
                get({
                    let tombstones = tombstones.clone();
                    move || {
                        let tombstones = tombstones.clone();
                        async move { Json(tombstones) }
                    }
                }),
            )
            .route(
                "/_internal/bootstrap/manifests",
                get({
                    let manifests = manifests.clone();
                    move || {
                        let manifests = manifests.clone();
                        async move { Json(manifests) }
                    }
                }),
            )
            .route(
                "/_internal/bootstrap/artifacts/{artifact_id}",
                get(move |AxumPath(_artifact_id): AxumPath<String>| {
                    let artifact_payload = artifact_payload.clone();
                    async move { (StatusCode::OK, artifact_payload) }
                }),
            );
        let (remote_url, _server) = spawn_server(app).await;
        let local = test_context(|_| {}).await;

        let stats = bootstrap_from_peer(&local.state, &remote_url)
            .await
            .expect("bootstrap should complete");
        assert_eq!(stats.tombstones_applied, 1);
        assert_eq!(stats.artifacts_applied, 0);
        assert!(
            local
                .state
                .store
                .fetch_artifact(ArtifactProducer::Xcode, "ios", "cas-1")
                .await
                .expect("artifact fetch should succeed")
                .is_none()
        );
    }

    #[tokio::test]
    async fn bootstrap_stale_manifest_then_tombstone_converges_to_delete() {
        let stale_manifest = bootstrap_test_manifest(
            ArtifactProducer::Xcode,
            true,
            "ios",
            "cas-1",
            "application/json",
            br#"{"value":"stale"}"#.len() as u64,
            100,
        );
        let tombstones = NamespaceTombstonePage {
            tombstones: vec![crate::store::NamespaceTombstoneRecord {
                namespace_id: "ios".into(),
                version_ms: 200,
            }],
            next_after: None,
        };
        let artifact_payload = br#"{"value":"stale"}"#.to_vec();
        let app = Router::new()
            .route(
                "/_internal/bootstrap/namespace_tombstones",
                get({
                    let tombstones = tombstones.clone();
                    move || {
                        let tombstones = tombstones.clone();
                        async move { Json(tombstones) }
                    }
                }),
            )
            .route(
                "/_internal/bootstrap/artifacts/{artifact_id}",
                get(move |AxumPath(_artifact_id): AxumPath<String>| {
                    let artifact_payload = artifact_payload.clone();
                    async move { (StatusCode::OK, artifact_payload) }
                }),
            );
        let (remote_url, _server) = spawn_server(app).await;
        let local = test_context(|_| {}).await;

        let outcome = bootstrap_artifact_from_peer(&local.state, &remote_url, &stale_manifest)
            .await
            .expect("artifact bootstrap should complete");
        assert_eq!(outcome, ArtifactApplyOutcome::Applied);
        assert!(
            local
                .state
                .store
                .fetch_artifact(ArtifactProducer::Xcode, "ios", "cas-1")
                .await
                .expect("artifact fetch should succeed")
                .is_some()
        );

        let applied = bootstrap_namespace_tombstones_from_peer(&local.state, &remote_url)
            .await
            .expect("tombstone bootstrap should complete");
        assert_eq!(applied, 1);
        assert!(
            local
                .state
                .store
                .fetch_artifact(ArtifactProducer::Xcode, "ios", "cas-1")
                .await
                .expect("artifact fetch should succeed")
                .is_none()
        );
    }

    #[tokio::test]
    async fn bootstrap_fetch_failpoint_prevents_partial_visibility() {
        let remote = test_context(|_| {}).await;
        let remote_manifest = remote
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "artifact",
                "application/octet-stream",
                b"payload",
            )
            .await
            .expect("remote artifact should persist");
        let (remote_url, _server) = spawn_server(router(remote.state.clone())).await;
        let local = test_context(|_| {}).await;
        local.state.store.failpoints().set_once(
            FailpointName::AfterBootstrapArtifactFetchBeforePersist,
            FailpointAction::Error("bootstrap interrupted".into()),
        );

        let error = bootstrap_artifact_from_peer(&local.state, &remote_url, &remote_manifest)
            .await
            .expect_err("bootstrap should fail before persist");
        assert!(error.contains("bootstrap interrupted"));
        assert!(
            local
                .state
                .store
                .fetch_artifact(ArtifactProducer::Gradle, "ios", "artifact")
                .await
                .expect("artifact fetch should succeed")
                .is_none()
        );
    }
}
