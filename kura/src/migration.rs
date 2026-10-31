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
    /// Feed head through which a completed run verified every record and then
    /// the destination identity. Any write committed at or below it is proven.
    proven: u64,
    ready: bool,
    error: Option<String>,
}

#[derive(Default)]
pub struct MigrationState {
    armed: AtomicBool,
    active: Mutex<Option<Active>>,
    gate: tokio::sync::Mutex<()>,
    verification_gate: tokio::sync::Mutex<()>,
    #[cfg(test)]
    verifications: std::sync::atomic::AtomicU64,
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
                    proven: 0,
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
            let mut maintain = false;
            if let Some(active) = active.as_mut() {
                match result {
                    Ok(()) => {
                        active.ready = true;
                        maintain = true;
                    }
                    Err(error) => {
                        worker
                            .runtime
                            .migration
                            .armed
                            .store(false, Ordering::Release);
                        worker.store.sync_feed().forget_consumer(&consumer(&worker));
                        active.error = Some(error);
                    }
                }
            }
            drop(active);
            if maintain {
                maintain_bridge(std::sync::Arc::downgrade(&worker));
            }
        });
    }
    let active = migration.active.lock().expect("migration lock");
    // A concurrent reset may clear a failed attempt between the two locks.
    let Some(active) = active.as_ref() else {
        return Err(conflict("migration preparation was reset".into()));
    };
    if let Some(error) = &active.error {
        return Err(conflict(error.clone()));
    }
    if !active.ready && Instant::now() >= active.deadline {
        return Err(conflict("migration deadline expired".into()));
    }
    Ok(Json(
        serde_json::json!({"incarnation":state.runtime.connection_incarnation(),"target":active.target,"ready":active.ready}),
    ))
}

// Preparation has a fixed deadline. Once routing may have moved, keep the
// bridge and feed pin until the donor drains. A controller pause must not
// turn a healthy writer into an outage when that deadline elapses.
fn maintain_bridge(state: std::sync::Weak<crate::state::AppState>) {
    tokio::spawn(async move {
        let mut previous_error = None;
        loop {
            tokio::time::sleep(Duration::from_secs(1)).await;
            let Some(state) = state.upgrade() else { break };
            if state.runtime.is_draining() {
                state.store.sync_feed().forget_consumer(&consumer(&state));
                break;
            }
            // Forced, so an idle bridge still probes its destination and refreshes
            // the feed pin rather than relying on the last proven run.
            let error = acknowledge_with(&state, true).await.err();
            if error != previous_error
                && let Some(error) = &error
            {
                tracing::warn!(event.name="kura.migration.bridge_failed", %error,
                    "Migration acknowledgments remain closed until the destination can be verified");
            }
            previous_error = error;
        }
    });
}

/// Only a completed, failed preparation can be reset. An armed bridge may
/// already protect a moved endpoint and must never be cleared by this API.
pub async fn reset(
    State(state): State<SharedState>,
    Json(request): Json<PrepareRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    if request.incarnation != state.runtime.connection_incarnation() {
        return Err(conflict("migration source changed".into()));
    }
    let migration = &state.runtime.migration;
    let _gate = migration.gate.lock().await;
    let mut active = migration.active.lock().expect("migration lock");
    if let Some(current) = active.as_ref()
        && (current.target != request.target
            || current.ready
            || current.error.is_none()
            || migration.armed.load(Ordering::Acquire))
    {
        return Err(conflict(
            "only a failed, unarmed preparation can be reset".into(),
        ));
    }
    *active = None;
    state.store.sync_feed().forget_consumer(&consumer(&state));
    Ok(Json(
        serde_json::json!({"incarnation": state.runtime.connection_incarnation(), "reset": true}),
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
    if (!active.ready && Instant::now() >= active.deadline) || state.runtime.is_draining() {
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
    acknowledge_inner(state, true).await?;
    state.runtime.migration.armed.store(true, Ordering::Release);
    acknowledge(state).await
}

/// Also called for an already-running request: checking after its handler
/// completes is what includes writes admitted before migration was armed.
pub async fn acknowledge(state: &SharedState) -> Result<(), String> {
    acknowledge_with(state, false).await
}

async fn acknowledge_with(state: &SharedState, force: bool) -> Result<(), String> {
    if !state.runtime.migration.armed.load(Ordering::Acquire) {
        return Ok(());
    }
    let result = tokio::time::timeout(ACK_TIMEOUT, acknowledge_inner(state, force))
        .await
        .map_err(|_| "migration acknowledgment timed out".to_owned())?;
    // A failed preparation never authorizes routing to move. Restore ordinary
    // asynchronous acknowledgments when that preparation has been disarmed.
    if !state.runtime.migration.armed.load(Ordering::Acquire) {
        return Ok(());
    }
    result
}

/// Group commit: completions queue on one gate, and a run that took its head
/// after a write committed proves that write, so waiters behind it return
/// without another destination round trip. `force` always runs, for arming
/// and for the bridge loop that probes an idle destination.
async fn acknowledge_inner(state: &SharedState, force: bool) -> Result<(), String> {
    let feed = state.store.sync_feed();
    feed.settle().await;
    let committed = feed.head();
    let _gate = state.runtime.migration.gate.lock().await;
    target(state)?;
    if !force && active_field(state, |active| active.proven)? >= committed {
        return Ok(());
    }
    feed.settle().await;
    let head = feed.head();
    loop {
        let confirmed = active_field(state, |active| active.confirmed)?;
        if !feed.enabled() || confirmed < feed.floor() {
            return Err("migration feed history was lost".into());
        }
        feed.note_consumer(&consumer(state), confirmed);
        if confirmed >= head {
            verify_remote(state, Vec::new()).await?;
            let mut active = state
                .runtime
                .migration
                .active
                .lock()
                .expect("migration lock");
            let active = active.as_mut().ok_or("no migration")?;
            active.proven = active.proven.max(head);
            return Ok(());
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

fn active_field(state: &SharedState, field: impl FnOnce(&Active) -> u64) -> Result<u64, String> {
    let active = state
        .runtime
        .migration
        .active
        .lock()
        .expect("migration lock");
    Ok(field(active.as_ref().ok_or("no migration")?))
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
    #[cfg(test)]
    state
        .runtime
        .migration
        .verifications
        .fetch_add(1, Ordering::Relaxed);
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
        // A completing write is past everything proven so far, so its feed rows
        // must still be verifiable.
        put(&source.state, "after-arming", 3000).await;
        let feed = source.state.store.sync_feed();
        feed.raise_floor(feed.head());
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
    async fn a_paused_controller_does_not_expire_a_healthy_bridge_or_its_feed_pin() {
        let source = test_context(|_| {}).await;
        let destination = test_context(|_| {}).await;
        let (url, server) = serve(destination.state.clone()).await;
        let target = activate(&source.state, url, &destination.state);
        wait_ready(&source.state, &target).await;
        source
            .state
            .runtime
            .migration
            .active
            .lock()
            .unwrap()
            .as_mut()
            .unwrap()
            .deadline = Instant::now() - Duration::from_secs(1);
        source.state.store.sync_feed().clear_consumers();
        tokio::time::timeout(Duration::from_secs(3), async {
            while source.state.store.sync_feed().consumers().is_empty() {
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .unwrap();
        acknowledge(&source.state).await.unwrap();
        let receipt = prepare(
            State(source.state.clone()),
            Json(PrepareRequest {
                incarnation: source.state.runtime.connection_incarnation().to_owned(),
                target: target.clone(),
            }),
        )
        .await
        .unwrap();
        assert_eq!(receipt["ready"], true);
        assert!(
            reset(
                State(source.state.clone()),
                Json(PrepareRequest {
                    incarnation: source.state.runtime.connection_incarnation().to_owned(),
                    target,
                })
            )
            .await
            .is_err(),
            "reset must never remove an armed bridge"
        );
        server.abort();
    }

    #[tokio::test]
    async fn failed_unarmed_preparation_can_be_reset_without_restarting_the_writer() {
        let source = test_context(|_| {}).await;
        let destination = test_context(|_| {}).await;
        let (url, server) = serve(destination.state.clone()).await;
        let target = activate(&source.state, url, &destination.state);
        *source.state.runtime.migration.active.lock().unwrap() = Some(Active {
            target: target.clone(),
            deadline: Instant::now() - Duration::from_secs(1),
            confirmed: 0,
            proven: 0,
            ready: false,
            error: None,
        });
        let request = || PrepareRequest {
            incarnation: source.state.runtime.connection_incarnation().to_owned(),
            target: target.clone(),
        };
        assert!(
            reset(State(source.state.clone()), Json(request()))
                .await
                .is_err(),
            "cannot reset while a preparation worker might still be running"
        );
        source
            .state
            .runtime
            .migration
            .active
            .lock()
            .unwrap()
            .as_mut()
            .unwrap()
            .error = Some("injected failure".into());
        assert!(
            reset(
                State(source.state.clone()),
                Json(PrepareRequest {
                    incarnation: "previous-process".into(),
                    target: target.clone(),
                })
            )
            .await
            .is_err()
        );
        let receipt = reset(State(source.state.clone()), Json(request()))
            .await
            .unwrap();
        assert_eq!(receipt["reset"], true);
        acknowledge(&source.state).await.unwrap();
        wait_ready(&source.state, &target).await;
        server.abort();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn concurrent_acknowledgments_share_one_destination_verification() {
        let source = test_context(|_| {}).await;
        let destination = test_context(|_| {}).await;
        let (url, server) = serve(destination.state.clone()).await;
        let target = activate(&source.state, url, &destination.state);
        wait_ready(&source.state, &target).await;
        for (i, key) in ["a", "b", "c", "d", "e", "f", "g", "h"].iter().enumerate() {
            put(&source.state, key, 2000 + i as u64).await;
            put(&destination.state, key, 2000 + i as u64).await;
        }
        let verifications = &destination.state.runtime.migration.verifications;
        let before = verifications.load(Ordering::Relaxed);
        let acks: Vec<_> = (0..16)
            .map(|_| {
                let state = source.state.clone();
                tokio::spawn(async move { acknowledge(&state).await })
            })
            .collect();
        for ack in acks {
            ack.await.unwrap().unwrap();
        }
        // One run verifies the eight writes and the destination's identity; the
        // background bridge loop may add one more. Serialized acknowledgments
        // made a round trip each.
        let calls = verifications.load(Ordering::Relaxed) - before;
        assert!(
            calls <= 4,
            "16 waiting writes made {calls} destination calls"
        );
        server.abort();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn polling_a_failed_preparation_while_it_is_reset_never_panics() {
        let source = test_context(|_| {}).await;
        let destination = test_context(|_| {}).await;
        let target = activate(
            &source.state,
            "https://destination.invalid".into(),
            &destination.state,
        );
        let request = || PrepareRequest {
            incarnation: source.state.runtime.connection_incarnation().to_owned(),
            target: target.clone(),
        };
        for _ in 0..2_000 {
            *source.state.runtime.migration.active.lock().unwrap() = Some(Active {
                target: target.clone(),
                deadline: Instant::now() + DEADLINE,
                confirmed: 0,
                proven: 0,
                ready: false,
                error: Some("injected failure".into()),
            });
            let polled = tokio::spawn(prepare(State(source.state.clone()), Json(request())));
            let cleared = tokio::spawn(reset(State(source.state.clone()), Json(request())));
            // Either order is legitimate: a reset that wins lets the poll start a
            // fresh attempt, which this unreachable destination then fails.
            assert!(
                !polled.await.is_err_and(|e| e.is_panic()),
                "prepare panicked while a reset cleared its attempt"
            );
            assert!(!cleared.await.is_err_and(|e| e.is_panic()));
        }
    }

    #[tokio::test]
    async fn ordinary_requests_need_no_feed_or_peer() {
        let source = test_context(|_| {}).await;
        acknowledge(&source.state).await.unwrap();
    }
}
