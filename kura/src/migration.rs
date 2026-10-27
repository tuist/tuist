//! Temporary, destination-bound write acknowledgments for legacy storage moves.
//! This is not a serving grant: ordinary admission stays authoritative. A feed
//! cursor selects work, but only verified destination content completes it.
use std::{
    sync::{
        Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};

use axum::{Json, extract::State, http::StatusCode};
use serde::{Deserialize, Serialize};
use tokio::time::Instant;

use crate::{
    handover::{Record, record, verify_record},
    state::SharedState,
    sync::feed::SyncFeedKind,
};

const PAGE: usize = 16;
const DEADLINE: Duration = Duration::from_secs(20 * 60);
const ACK_TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct Target {
    pub url: String,
    pub incarnation: String,
}

struct Active {
    target: Target,
    deadline: Instant,
    confirmed: u64,
    ready: bool,
    error: Option<String>,
}

#[derive(Default)]
pub struct MigrationState {
    armed: AtomicBool,
    active: Mutex<Option<Active>>,
    gate: tokio::sync::Mutex<()>,
    verification_gate: tokio::sync::Mutex<()>,
}

#[derive(Deserialize)]
pub struct PrepareRequest {
    incarnation: String,
    target: Target,
}

#[derive(Serialize, Deserialize)]
pub struct VerifyRequest {
    incarnation: String,
    records: Vec<Record>,
}

fn conflict(error: String) -> (StatusCode, String) {
    (StatusCode::CONFLICT, error)
}

pub async fn prepare(
    State(state): State<SharedState>,
    Json(request): Json<PrepareRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    if request.incarnation != state.runtime.connection_incarnation()
        || !state.store.backfill_index_built()
        || state.runtime.authority.enabled()
        || state.runtime.is_draining()
        || !state.peer_views.load().iter().any(|peer| {
            peer.url == request.target.url
                && peer.region == state.config.region
                && peer.serving
                && !peer.draining
        })
        || request.target.incarnation.is_empty()
        || request.target.incarnation.len() > 128
    {
        return Err(conflict(
            "migration source or destination is not qualified".into(),
        ));
    }
    let migration = &state.runtime.migration;
    let mut start = false;
    {
        let mut active = migration.active.lock().expect("migration lock");
        match active.as_ref() {
            Some(active) if active.target != request.target => {
                return Err(conflict("another destination owns migration".into()));
            }
            Some(_) => {}
            None => {
                if !state.store.sync_feed().enabled() {
                    return Err(conflict("replica feed is not active".into()));
                }
                let confirmed = state.store.sync_feed().head();
                *active = Some(Active {
                    target: request.target.clone(),
                    deadline: Instant::now() + DEADLINE,
                    confirmed,
                    ready: false,
                    error: None,
                });
                state
                    .store
                    .sync_feed()
                    .note_consumer(&consumer(&state), confirmed);
                start = true;
            }
        }
    }
    if start {
        let worker = state.clone();
        tokio::spawn(async move {
            let result = tokio::time::timeout(DEADLINE, prepare_inner(&worker))
                .await
                .unwrap_or_else(|_| Err("migration preparation expired".into()));
            let mut active = worker
                .runtime
                .migration
                .active
                .lock()
                .expect("migration lock");
            if let Some(active) = active.as_mut() {
                match result {
                    Ok(()) => active.ready = true,
                    Err(error) => {
                        worker
                            .runtime
                            .migration
                            .armed
                            .store(false, Ordering::Release);
                        active.error = Some(error);
                    }
                }
            }
        });
    }
    let active = migration.active.lock().expect("migration lock");
    let active = active.as_ref().expect("migration started");
    if let Some(error) = &active.error {
        return Err(conflict(error.clone()));
    }
    if Instant::now() >= active.deadline {
        return Err(conflict("migration deadline expired".into()));
    }
    Ok(Json(
        serde_json::json!({"incarnation":state.runtime.connection_incarnation(),"target":active.target,"ready":active.ready}),
    ))
}

fn consumer(state: &SharedState) -> String {
    format!("migration:{}", state.runtime.connection_incarnation())
}

fn target(state: &SharedState) -> Result<Target, String> {
    let active = state
        .runtime
        .migration
        .active
        .lock()
        .expect("migration lock");
    let active = active.as_ref().ok_or("no migration")?;
    if Instant::now() >= active.deadline || state.runtime.is_draining() {
        return Err("migration expired or draining".into());
    }
    if let Some(error) = &active.error {
        return Err(error.clone());
    }
    Ok(active.target.clone())
}

async fn prepare_inner(state: &SharedState) -> Result<(), String> {
    // Public writes continue during the bounded retained walk. Once armed,
    // every successful mutation waits for verification, including requests that
    // entered before arming. The feed then closes the walk's live-write window.
    let mut after = None;
    loop {
        target(state)?;
        state.store.sync_feed().refresh_consumer(&consumer(state));
        let page = state.store.backfill_index_page(after.as_deref(), PAGE)?;
        let mut records = Vec::new();
        for row in page.entries {
            if let Some(descriptor) =
                record(state, row.kind, &row.record_id, row.version_ms).await?
            {
                records.push(descriptor);
            }
        }
        verify_remote(state, records).await?;
        match page.next_after {
            Some(next) => after = Some(next),
            None => break,
        }
    }
    acknowledge_inner(state).await?;
    state.runtime.migration.armed.store(true, Ordering::Release);
    acknowledge(state).await
}

/// Also called for an already-running request: checking after its handler
/// completes is what includes writes admitted before migration was armed.
pub async fn acknowledge(state: &SharedState) -> Result<(), String> {
    if !state.runtime.migration.armed.load(Ordering::Acquire) {
        return Ok(());
    }
    let result = tokio::time::timeout(ACK_TIMEOUT, acknowledge_inner(state))
        .await
        .map_err(|_| "migration acknowledgment timed out".to_owned())?;
    // A failed preparation never authorizes routing to move. Restore ordinary
    // asynchronous acknowledgments when that preparation has been disarmed.
    if !state.runtime.migration.armed.load(Ordering::Acquire) {
        return Ok(());
    }
    result
}

async fn acknowledge_inner(state: &SharedState) -> Result<(), String> {
    let _gate = state.runtime.migration.gate.lock().await;
    target(state)?;
    let feed = state.store.sync_feed();
    feed.settle().await;
    let head = feed.head();
    loop {
        let confirmed = state
            .runtime
            .migration
            .active
            .lock()
            .expect("migration lock")
            .as_ref()
            .ok_or("no migration")?
            .confirmed;
        if !feed.enabled() || confirmed < feed.floor() {
            return Err("migration feed history was lost".into());
        }
        if confirmed >= head {
            return verify_remote(state, Vec::new()).await;
        }
        let rows = state.store.sync_feed_page_to(confirmed, PAGE, head)?;
        let next = if rows.len() < PAGE {
            head
        } else {
            rows.last().expect("full page").seq
        };
        let mut records = Vec::new();
        for row in rows {
            if let SyncFeedKind::Record(kind) = row.kind
                && let Some(descriptor) =
                    record(state, kind, &row.record_id, row.version_ms).await?
            {
                records.push(descriptor);
            }
        }
        verify_remote(state, records).await?;
        // Trimming or a feed reset during I/O must not turn omitted rows into
        // proof. Verification never changes cache admission or capacity policy.
        if !feed.enabled() || confirmed < feed.floor() {
            return Err("migration feed history was lost".into());
        }
        state
            .runtime
            .migration
            .active
            .lock()
            .expect("migration lock")
            .as_mut()
            .ok_or("no migration")?
            .confirmed = next;
        feed.note_consumer(&consumer(state), next);
    }
}

async fn verify_remote(state: &SharedState, records: Vec<Record>) -> Result<(), String> {
    let target = target(state)?;
    let request = VerifyRequest {
        incarnation: target.incarnation.clone(),
        records,
    };
    let deadline = Instant::now() + ACK_TIMEOUT;
    loop {
        let response = state
            .peer_request(
                reqwest::Method::POST,
                &target.url,
                &format!("{}/_internal/migration/verify", target.url),
            )?
            .timeout(ACK_TIMEOUT)
            .json(&request)
            .send()
            .await
            .map_err(|e| format!("migration verification: {e}"))?;
        let status = response.status();
        let body =
            crate::replication::read_bounded_body(response, 4096, "migration receipt").await?;
        if status.is_success() {
            let receipt: serde_json::Value =
                serde_json::from_slice(&body).map_err(|e| e.to_string())?;
            if receipt.get("incarnation").and_then(|v| v.as_str())
                == Some(target.incarnation.as_str())
                && receipt.get("verified").and_then(|v| v.as_bool()) == Some(true)
            {
                return Ok(());
            }
            return Err("invalid migration receipt".into());
        }
        if status != StatusCode::CONFLICT || Instant::now() >= deadline {
            return Err(format!("migration verification returned {status}"));
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
}

pub async fn verify(
    State(state): State<SharedState>,
    Json(request): Json<VerifyRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    if request.incarnation != state.runtime.connection_incarnation()
        || request.records.len() > PAGE
        || state.runtime.is_draining()
    {
        return Err(conflict(
            "migration destination changed or batch invalid".into(),
        ));
    }
    let _gate = state
        .runtime
        .migration
        .verification_gate
        .try_lock()
        .map_err(|_| conflict("destination verification busy".into()))?;
    for expected in request.records {
        verify_record(&state, &expected).await.map_err(conflict)?;
    }
    Ok(Json(
        serde_json::json!({"incarnation":state.runtime.connection_incarnation(),"verified":true}),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        artifact::producer::ArtifactProducer, sync::roles::PeerView, test_support::test_context,
    };

    async fn serve(state: SharedState) -> (String, tokio::task::JoinHandle<()>) {
        state.store.run_backfill_index_build().unwrap();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let task = tokio::spawn(async move {
            axum::serve(listener, crate::http::router(state))
                .await
                .unwrap();
        });
        (url, task)
    }

    fn activate(source: &SharedState, url: String, destination: &SharedState) -> Target {
        source.store.run_backfill_index_build().unwrap();
        source.store.sync_feed().set_enabled(true);
        let target = Target {
            url,
            incarnation: destination.runtime.connection_incarnation().to_owned(),
        };
        source.peer_views.store(std::sync::Arc::new(vec![PeerView {
            url: target.url.clone(),
            topology: None,
            private_healthy: false,
            region: source.config.region.clone(),
            serving: true,
            draining: false,
        }]));
        target
    }

    async fn put(state: &SharedState, key: &str, version: u64) {
        state
            .store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                key,
                "text/plain",
                b"retained",
                version,
                None,
                None,
            )
            .await
            .unwrap();
    }

    async fn wait_ready(source: &SharedState, target: &Target) {
        tokio::time::timeout(Duration::from_secs(3), async {
            loop {
                let receipt = prepare(
                    State(source.clone()),
                    Json(PrepareRequest {
                        incarnation: source.runtime.connection_incarnation().to_owned(),
                        target: target.clone(),
                    }),
                )
                .await
                .unwrap();
                if receipt["ready"] == true {
                    break;
                }
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn missing_retained_bytes_are_not_proven_by_a_feed_cursor() {
        let source = test_context(|_| {}).await;
        let destination = test_context(|_| {}).await;
        put(&source.state, "retained", 1000).await;
        source.state.store.run_backfill_index_build().unwrap();
        let row = source
            .state
            .store
            .backfill_index_page(None, 16)
            .unwrap()
            .entries
            .remove(0);
        let expected = record(&source.state, row.kind, &row.record_id, row.version_ms)
            .await
            .unwrap()
            .unwrap();
        destination.state.store.sync_feed().raise_floor(100_000);
        let request = VerifyRequest {
            incarnation: destination
                .state
                .runtime
                .connection_incarnation()
                .to_owned(),
            records: vec![expected.clone()],
        };
        assert!(
            verify(State(destination.state.clone()), Json(request))
                .await
                .is_err()
        );
        put(&destination.state, "retained", 1000).await;
        let receipt = verify(
            State(destination.state.clone()),
            Json(VerifyRequest {
                incarnation: destination
                    .state
                    .runtime
                    .connection_incarnation()
                    .to_owned(),
                records: vec![expected],
            }),
        )
        .await
        .unwrap();
        assert_eq!(receipt["verified"], true);
    }

    #[tokio::test]
    async fn write_entering_before_arming_waits_for_destination_bytes() {
        let source = test_context(|_| {}).await;
        let destination = test_context(|_| {}).await;
        let (url, server) = serve(destination.state.clone()).await;
        let target = activate(&source.state, url, &destination.state);
        // Admission occurred before preparation; publication happens afterwards.
        wait_ready(&source.state, &target).await;
        put(&source.state, "in-flight", 1000).await;
        let source_state = source.state.clone();
        let ack = tokio::spawn(async move { acknowledge(&source_state).await });
        tokio::time::sleep(Duration::from_millis(100)).await;
        assert!(
            !ack.is_finished(),
            "acknowledged a write absent from the target"
        );
        put(&destination.state, "in-flight", 1000).await;
        ack.await.unwrap().unwrap();
        assert_eq!(
            source
                .state
                .runtime
                .migration
                .active
                .lock()
                .unwrap()
                .as_ref()
                .unwrap()
                .confirmed,
            source.state.store.sync_feed().head()
        );
        server.abort();
    }

    #[tokio::test]
    async fn empty_verification_rejects_a_restarted_destination() {
        let target = test_context(|_| {}).await;
        let err = verify(
            State(target.state.clone()),
            Json(VerifyRequest {
                incarnation: "previous-process".into(),
                records: vec![],
            }),
        )
        .await
        .unwrap_err();
        assert_eq!(err.0, StatusCode::CONFLICT);
    }

    #[tokio::test]
    async fn armed_migration_refuses_feed_loss_and_destination_substitution() {
        let source = test_context(|_| {}).await;
        let destination = test_context(|_| {}).await;
        let (url, server) = serve(destination.state.clone()).await;
        let mut target = activate(&source.state, url, &destination.state);
        wait_ready(&source.state, &target).await;
        source.state.store.sync_feed().raise_floor(1);
        assert!(
            acknowledge(&source.state)
                .await
                .unwrap_err()
                .contains("history was lost")
        );
        target.incarnation = "replacement".into();
        assert!(
            prepare(
                State(source.state.clone()),
                Json(PrepareRequest {
                    incarnation: source.state.runtime.connection_incarnation().to_owned(),
                    target
                })
            )
            .await
            .is_err()
        );
        server.abort();
    }

    #[tokio::test]
    async fn concurrent_acknowledgments_do_not_skip_a_missing_record() {
        let source = test_context(|_| {}).await;
        let destination = test_context(|_| {}).await;
        let (url, server) = serve(destination.state.clone()).await;
        let target = activate(&source.state, url, &destination.state);
        wait_ready(&source.state, &target).await;
        put(&source.state, "one", 1000).await;
        put(&source.state, "two", 1001).await;
        put(&destination.state, "two", 1001).await;
        let mut acks = Vec::new();
        for _ in 0..4 {
            let state = source.state.clone();
            acks.push(tokio::spawn(async move { acknowledge(&state).await }));
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
        assert!(acks.iter().all(|ack| !ack.is_finished()));
        put(&destination.state, "one", 1000).await;
        for ack in acks {
            ack.await.unwrap().unwrap();
        }
        server.abort();
    }

    #[tokio::test]
    async fn ordinary_requests_need_no_feed_or_peer() {
        let source = test_context(|_| {}).await;
        acknowledge(&source.state).await.unwrap();
    }
}
