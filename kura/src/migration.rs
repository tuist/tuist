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

/// Where the retained walk continues on the current destination process. The
/// walk is newest-first by index key; records written after it started sort
/// before `after` and are covered by the feed from `Active::confirmed`.
#[derive(Default)]
struct Walk {
    after: Option<Vec<u8>>,
    complete: bool,
}

struct Active {
    target: Target,
    /// Identifies this migration across retries and rebinds; its bridge loop
    /// exits once the migration is aborted or replaced.
    id: u64,
    /// Identifies the preparation, retry or rebind that owns the walk. A
    /// superseded worker can neither save progress nor report a result.
    attempt: u64,
    deadline: Instant,
    confirmed: u64,
    /// Feed head through which a completed run verified every record and then
    /// the destination identity. Any write committed at or below it is proven.
    proven: u64,
    walk: Walk,
    /// Retained records verified since the walk last started from the top.
    walked: u64,
    /// Whether the current attempt moved the walk or the feed proof forward.
    advanced: bool,
    ready: bool,
    error: Option<String>,
}

impl Active {
    fn new(target: Target, attempt: u64, deadline: Instant, confirmed: u64) -> Self {
        Self {
            target,
            id: attempt,
            attempt,
            deadline,
            confirmed,
            proven: 0,
            walk: Walk::default(),
            walked: 0,
            advanced: false,
            ready: false,
            error: None,
        }
    }

    fn restart_walk(&mut self) {
        self.walk = Walk::default();
        self.walked = 0;
    }
}

#[derive(Default)]
pub struct MigrationState {
    armed: AtomicBool,
    active: Mutex<Option<Active>>,
    attempts: std::sync::atomic::AtomicU64,
    /// When an armed bridge last proved the feed through its head.
    last_proof: Mutex<Option<Instant>>,
    gate: tokio::sync::Mutex<()>,
    verification_gate: tokio::sync::Mutex<()>,
    #[cfg(test)]
    verifications: std::sync::atomic::AtomicU64,
    #[cfg(test)]
    verified_records: std::sync::atomic::AtomicU64,
    #[cfg(test)]
    deadline: Mutex<Option<Duration>>,
}

impl MigrationState {
    fn preparation_deadline(&self) -> Duration {
        #[cfg(test)]
        if let Some(deadline) = *self.deadline.lock().expect("migration deadline lock") {
            return deadline;
        }
        DEADLINE
    }

    fn next_attempt(&self) -> u64 {
        self.attempts.fetch_add(1, Ordering::Relaxed) + 1
    }

    pub fn export_metrics(&self, metrics: &crate::metrics::Metrics) {
        let armed = self.armed.load(Ordering::Acquire);
        let (ready, walked) = self
            .active
            .lock()
            .expect("migration lock")
            .as_ref()
            .map_or((false, 0), |active| (active.ready, active.walked));
        let last_proof_age = self
            .last_proof
            .lock()
            .expect("migration proof lock")
            .filter(|_| armed)
            .map_or(Duration::ZERO, |proved| proved.elapsed());
        metrics.update_migration_bridge(armed, ready, last_proof_age, walked);
    }
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
    let mut start = None;
    {
        let mut active = migration.active.lock().expect("migration lock");
        let feed = state.store.sync_feed();
        match active.as_mut() {
            Some(active) if active.target != request.target => {
                return Err(conflict("another destination owns migration".into()));
            }
            // A retry continues a failed attempt that made progress. One that
            // made none keeps its failure, so a stuck move does not loop.
            Some(active)
                if active.error.is_some()
                    && active.advanced
                    && !migration.armed.load(Ordering::Acquire) =>
            {
                if !feed.enabled() {
                    return Err(conflict("replica feed is not active".into()));
                }
                // Writes since the saved feed position may be gone, so the
                // walk behind it no longer covers everything.
                if active.confirmed < feed.floor() {
                    active.restart_walk();
                    active.confirmed = feed.head();
                    active.proven = 0;
                }
                active.attempt = migration.next_attempt();
                active.deadline = Instant::now() + migration.preparation_deadline();
                active.advanced = false;
                active.error = None;
                feed.note_consumer(&consumer(&state), active.confirmed);
                start = Some((active.attempt, active.deadline));
            }
            Some(_) => {}
            None => {
                if !feed.enabled() {
                    return Err(conflict("replica feed is not active".into()));
                }
                let confirmed = feed.head();
                let created = Active::new(
                    request.target.clone(),
                    migration.next_attempt(),
                    Instant::now() + migration.preparation_deadline(),
                    confirmed,
                );
                start = Some((created.attempt, created.deadline));
                *active = Some(created);
                feed.note_consumer(&consumer(&state), confirmed);
            }
        }
    }
    if let Some((attempt, deadline)) = start {
        let worker = state.clone();
        tokio::spawn(async move {
            let result = tokio::time::timeout_at(deadline, prepare_inner(&worker, attempt))
                .await
                .unwrap_or_else(|_| Err("migration preparation expired".into()));
            let migration = &worker.runtime.migration;
            let mut active = migration.active.lock().expect("migration lock");
            let mut maintain = None;
            if let Some(active) = active.as_mut().filter(|active| active.attempt == attempt) {
                match result {
                    Ok(()) => {
                        active.ready = true;
                        maintain = Some(active.id);
                    }
                    Err(error) => {
                        migration.armed.store(false, Ordering::Release);
                        let feed = worker.store.sync_feed();
                        if active.advanced {
                            // Keeps the feed position for a retry without
                            // holding up a drain; trimming past it restarts.
                            feed.note_consumer_snapshot(&consumer(&worker), active.confirmed);
                        } else {
                            feed.forget_consumer(&consumer(&worker));
                        }
                        active.error = Some(error);
                    }
                }
            }
            drop(active);
            if let Some(id) = maintain {
                maintain_bridge(std::sync::Arc::downgrade(&worker), id);
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
    if !active.ready
        && !migration.armed.load(Ordering::Acquire)
        && Instant::now() >= active.deadline
    {
        return Err(conflict("migration deadline expired".into()));
    }
    Ok(Json(
        serde_json::json!({"incarnation":state.runtime.connection_incarnation(),"target":active.target,"ready":active.ready}),
    ))
}

// Preparation has a fixed deadline. Once routing may have moved, keep the
// bridge and feed pin until the donor drains. A controller pause must not
// turn a healthy writer into an outage when that deadline elapses.
fn maintain_bridge(state: std::sync::Weak<crate::state::AppState>, id: u64) {
    tokio::spawn(async move {
        let mut previous_error = None;
        loop {
            tokio::time::sleep(Duration::from_secs(1)).await;
            let Some(state) = state.upgrade() else { break };
            let current = state
                .runtime
                .migration
                .active
                .lock()
                .expect("migration lock")
                .as_ref()
                .is_some_and(|active| active.id == id);
            if !current {
                break;
            }
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

/// Clears the migration for exactly this target in any state: running,
/// failed, ready or armed. It disarms the bridge, discards resume progress and
/// releases the feed pin; the preparation, bridge loop and re-proof tasks see
/// their attempt gone and exit without writing state back.
///
/// The controller calls this only while the source was never demoted (no
/// `kura.tuist.dev/lvm-rebuild` annotation), so routing never moved through the
/// migration. Disarming then returns the source to ordinary asynchronous
/// replication, which is how it served before preparation. Never abort a
/// bridge that may protect a moved endpoint.
///
/// Disarming comes first, so an acknowledgment already waiting on the bridge
/// completes as an ordinary write instead of failing; the gate is then taken
/// so no acknowledgment run that started before the abort outlives it.
pub async fn abort(
    State(state): State<SharedState>,
    Json(request): Json<PrepareRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    if request.incarnation != state.runtime.connection_incarnation() {
        return Err(conflict("migration source changed".into()));
    }
    let migration = &state.runtime.migration;
    let feed = state.store.sync_feed();
    let aborted = {
        let mut active = migration.active.lock().expect("migration lock");
        match active.as_ref() {
            Some(current) if current.target != request.target => {
                return Err(conflict("another destination owns migration".into()));
            }
            Some(_) => {
                migration.armed.store(false, Ordering::Release);
                *active = None;
                *migration.last_proof.lock().expect("migration proof lock") = None;
                feed.forget_consumer(&consumer(&state));
                true
            }
            None => false,
        }
    };
    if aborted {
        let _gate = migration.gate.lock().await;
        // An acknowledgment that read the bridge before it was cleared may
        // have re-registered the pin; a newer preparation owns it otherwise.
        if migration.active.lock().expect("migration lock").is_none() {
            feed.forget_consumer(&consumer(&state));
        }
        tracing::warn!(
            event.name = "kura.migration.aborted",
            "Migration aborted; writes acknowledge without destination proof"
        );
    }
    Ok(Json(
        serde_json::json!({"incarnation": state.runtime.connection_incarnation(), "aborted": true}),
    ))
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

#[derive(Deserialize)]
pub struct RebindRequest {
    incarnation: String,
    target: Target,
    replacement: Target,
}

/// Moves an armed bridge to a restarted process of the same destination. The
/// bridge stays armed and reports ready only after re-proving every retained
/// record and the pinned feed on that process: proof never carries across
/// destination processes.
pub async fn rebind(
    State(state): State<SharedState>,
    Json(request): Json<RebindRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    if request.incarnation != state.runtime.connection_incarnation()
        || state.runtime.is_draining()
        || request.replacement.url != request.target.url
        || request.replacement.incarnation == request.target.incarnation
        || request.replacement.incarnation.is_empty()
        || request.replacement.incarnation.len() > 128
        || !state.peer_views.load().iter().any(|peer| {
            peer.url == request.replacement.url
                && peer.region == state.config.region
                && peer.serving
                && !peer.draining
        })
    {
        return Err(conflict(
            "migration source or destination is not qualified".into(),
        ));
    }
    let migration = &state.runtime.migration;
    let _gate = migration.gate.lock().await;
    if !migration.armed.load(Ordering::Acquire) {
        return Err(conflict("only an armed bridge can be rebound".into()));
    }
    let start = {
        let mut active = migration.active.lock().expect("migration lock");
        let active = active
            .as_mut()
            .ok_or_else(|| conflict("no migration".into()))?;
        if active.target == request.replacement {
            None
        } else if active.target != request.target {
            return Err(conflict("another destination owns migration".into()));
        } else {
            active.target = request.replacement.clone();
            active.attempt = migration.next_attempt();
            active.restart_walk();
            active.proven = 0;
            active.ready = false;
            active.error = None;
            Some(active.attempt)
        }
    };
    if let Some(attempt) = start {
        tracing::warn!(
            event.name = "kura.migration.destination_rebound",
            "Migration destination restarted; re-proving retained records on the new process"
        );
        reprove(std::sync::Arc::downgrade(&state), attempt);
    }
    let active = migration.active.lock().expect("migration lock");
    let active = active
        .as_ref()
        .ok_or_else(|| conflict("no migration".into()))?;
    Ok(Json(
        serde_json::json!({"incarnation":state.runtime.connection_incarnation(),"target":active.target,"ready":active.ready}),
    ))
}

// A rebound bridge has no deadline: it keeps refusing unproven writes, so
// retrying is never worse than giving up. Each retry continues the walk on the
// same process. A later rebind supersedes this one.
fn reprove(state: std::sync::Weak<crate::state::AppState>, attempt: u64) {
    tokio::spawn(async move {
        let mut previous_error = None;
        loop {
            let Some(state) = state.upgrade() else { break };
            if state.runtime.is_draining() {
                break;
            }
            let result = prove(&state, attempt).await;
            {
                let mut guard = state
                    .runtime
                    .migration
                    .active
                    .lock()
                    .expect("migration lock");
                let Some(active) = guard.as_mut().filter(|active| active.attempt == attempt) else {
                    break;
                };
                match result {
                    Ok(()) => {
                        active.ready = true;
                        break;
                    }
                    Err(error) => {
                        state.metrics.record_migration_reproof_failure();
                        if previous_error.as_ref() != Some(&error) {
                            tracing::warn!(event.name="kura.migration.reproof_failed", %error,
                                "Rebound migration destination is not ready until it holds every retained record");
                        }
                        previous_error = Some(error);
                    }
                }
            }
            drop(state);
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
    });
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
    let armed = state.runtime.migration.armed.load(Ordering::Acquire);
    if (!active.ready && !armed && Instant::now() >= active.deadline) || state.runtime.is_draining()
    {
        return Err("migration expired or draining".into());
    }
    if let Some(error) = &active.error {
        return Err(error.clone());
    }
    Ok(active.target.clone())
}

async fn prepare_inner(state: &SharedState, attempt: u64) -> Result<(), String> {
    // Public writes continue during the bounded retained walk. Once armed,
    // every successful mutation waits for verification, including requests that
    // entered before arming. The feed then closes the walk's live-write window.
    prove(state, attempt).await?;
    {
        let active = state
            .runtime
            .migration
            .active
            .lock()
            .expect("migration lock");
        if active
            .as_ref()
            .is_none_or(|active| active.attempt != attempt)
        {
            return Err(SUPERSEDED.into());
        }
        state.runtime.migration.armed.store(true, Ordering::Release);
    }
    acknowledge(state).await
}

const SUPERSEDED: &str = "migration attempt was superseded";

/// Verifies every retained record, then the pinned feed through its head, on
/// the current destination process. The walk resumes from the position the
/// last attempt on this process saved after each verified page.
async fn prove(state: &SharedState, attempt: u64) -> Result<(), String> {
    loop {
        let after = {
            let active = state
                .runtime
                .migration
                .active
                .lock()
                .expect("migration lock");
            let active = active
                .as_ref()
                .filter(|active| active.attempt == attempt)
                .ok_or(SUPERSEDED)?;
            if active.walk.complete {
                break;
            }
            active.walk.after.clone()
        };
        let target = target(state)?;
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
        let verified = records.len() as u64;
        verify_remote(state, &target, records).await?;
        let mut active = state
            .runtime
            .migration
            .active
            .lock()
            .expect("migration lock");
        let active = active
            .as_mut()
            .filter(|active| active.attempt == attempt && active.target == target)
            .ok_or(SUPERSEDED)?;
        active.walk = Walk {
            complete: page.next_after.is_none(),
            after: page.next_after,
        };
        active.walked += verified;
        active.advanced = true;
        state.metrics.record_migration_records_verified(verified);
    }
    acknowledge_inner(state, true).await
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
    let target = target(state)?;
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
            verify_remote(state, &target, Vec::new()).await?;
            let mut active = state
                .runtime
                .migration
                .active
                .lock()
                .expect("migration lock");
            let active = active.as_mut().ok_or("no migration")?;
            active.proven = active.proven.max(head);
            *state
                .runtime
                .migration
                .last_proof
                .lock()
                .expect("migration proof lock") = Some(Instant::now());
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
        verify_remote(state, &target, records).await?;
        // Trimming or a feed reset during I/O must not turn omitted rows into
        // proof. Verification never changes cache admission or capacity policy.
        if !feed.enabled() || confirmed < feed.floor() {
            return Err("migration feed history was lost".into());
        }
        {
            let mut active = state
                .runtime
                .migration
                .active
                .lock()
                .expect("migration lock");
            let active = active.as_mut().ok_or("no migration")?;
            active.confirmed = next;
            active.advanced = true;
        }
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

async fn verify_remote(
    state: &SharedState,
    destination: &Target,
    records: Vec<Record>,
) -> Result<(), String> {
    let target = destination;
    let request = VerifyRequest {
        incarnation: target.incarnation.clone(),
        records,
    };
    let deadline = Instant::now() + ACK_TIMEOUT;
    loop {
        // Rechecked on every retry, so an abort or rebind stops waiting here.
        if self::target(state)? != *target {
            return Err("migration destination changed".into());
        }
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
    for expected in &request.records {
        verify_record(&state, expected).await.map_err(conflict)?;
    }
    #[cfg(test)]
    state
        .runtime
        .migration
        .verified_records
        .fetch_add(request.records.len() as u64, Ordering::Relaxed);
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
        *source.state.runtime.migration.active.lock().unwrap() = Some(Active::new(
            target.clone(),
            0,
            Instant::now() - Duration::from_secs(1),
            0,
        ));
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
                error: Some("injected failure".into()),
                ..Active::new(target.clone(), 0, Instant::now() + DEADLINE, 0)
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

    async fn serve_at(state: SharedState, url: &str) -> tokio::task::JoinHandle<()> {
        state.store.run_backfill_index_build().unwrap();
        let address: std::net::SocketAddr = url.trim_start_matches("http://").parse().unwrap();
        let listener = tokio::net::TcpListener::bind(address).await.unwrap();
        tokio::spawn(async move {
            axum::serve(listener, crate::http::router(state))
                .await
                .unwrap();
        })
    }

    fn rebind_request(
        source: &SharedState,
        target: &Target,
        replacement: &Target,
    ) -> RebindRequest {
        RebindRequest {
            incarnation: source.runtime.connection_incarnation().to_owned(),
            target: target.clone(),
            replacement: replacement.clone(),
        }
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn an_armed_bridge_rebinds_to_a_restarted_destination_only_after_reproving_it() {
        let source = test_context(|_| {}).await;
        let destination = test_context(|_| {}).await;
        put(&source.state, "retained", 1000).await;
        put(&destination.state, "retained", 1000).await;
        let (url, server) = serve(destination.state.clone()).await;
        let target = activate(&source.state, url.clone(), &destination.state);
        wait_ready(&source.state, &target).await;
        put(&source.state, "acknowledged", 2000).await;
        put(&destination.state, "acknowledged", 2000).await;
        acknowledge(&source.state).await.unwrap();

        // The same pod comes back as a new process that lost one acknowledged
        // record. Its receipt cannot stand in for the previous process's.
        server.abort();
        let _ = server.await;
        let restarted = test_context(|_| {}).await;
        put(&restarted.state, "retained", 1000).await;
        let server = serve_at(restarted.state.clone(), &url).await;
        let replacement = Target {
            url: url.clone(),
            incarnation: restarted.state.runtime.connection_incarnation().to_owned(),
        };
        let elsewhere = Target {
            url: "http://127.0.0.1:1".into(),
            incarnation: replacement.incarnation.clone(),
        };
        assert!(
            rebind(
                State(source.state.clone()),
                Json(rebind_request(&source.state, &target, &elsewhere))
            )
            .await
            .is_err(),
            "a rebind cannot move the bridge to another destination"
        );
        for _ in 0..2 {
            let receipt = rebind(
                State(source.state.clone()),
                Json(rebind_request(&source.state, &target, &replacement)),
            )
            .await
            .unwrap();
            assert_eq!(receipt["target"]["incarnation"], replacement.incarnation);
            assert_eq!(receipt["ready"], false);
        }
        tokio::time::sleep(Duration::from_millis(300)).await;
        let receipt = prepare(
            State(source.state.clone()),
            Json(PrepareRequest {
                incarnation: source.state.runtime.connection_incarnation().to_owned(),
                target: replacement.clone(),
            }),
        )
        .await
        .unwrap();
        assert_eq!(receipt["ready"], false, "ready without the lost record");
        assert!(source.state.runtime.migration.armed.load(Ordering::Acquire));

        put(&restarted.state, "acknowledged", 2000).await;
        wait_ready(&source.state, &replacement).await;
        put(&source.state, "after-rebind", 3000).await;
        put(&restarted.state, "after-rebind", 3000).await;
        acknowledge(&source.state).await.unwrap();
        server.abort();
    }

    #[tokio::test]
    async fn only_an_armed_bridge_can_be_rebound() {
        let source = test_context(|_| {}).await;
        let destination = test_context(|_| {}).await;
        let target = activate(
            &source.state,
            "http://127.0.0.1:1".into(),
            &destination.state,
        );
        let replacement = Target {
            url: target.url.clone(),
            incarnation: "restarted".into(),
        };
        *source.state.runtime.migration.active.lock().unwrap() = Some(Active {
            error: Some("injected failure".into()),
            ..Active::new(target.clone(), 0, Instant::now() + DEADLINE, 0)
        });
        assert!(
            rebind(
                State(source.state.clone()),
                Json(rebind_request(&source.state, &target, &replacement))
            )
            .await
            .is_err(),
            "a failed unarmed preparation is reset, not rebound"
        );
    }

    fn prepare_request(source: &SharedState, target: &Target) -> PrepareRequest {
        PrepareRequest {
            incarnation: source.runtime.connection_incarnation().to_owned(),
            target: target.clone(),
        }
    }

    async fn wait_failed(source: &SharedState) -> String {
        tokio::time::timeout(Duration::from_secs(15), async {
            loop {
                let error = source
                    .runtime
                    .migration
                    .active
                    .lock()
                    .unwrap()
                    .as_ref()
                    .and_then(|active| active.error.clone());
                if let Some(error) = error {
                    return error;
                }
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .unwrap()
    }

    // Three walk pages, newest first; `missing` is left off the destination.
    async fn seed(source: &SharedState, destination: &SharedState, missing: &[u64]) {
        for i in 0..40 {
            put(source, &format!("record-{i:02}"), 1000 + i).await;
            if !missing.contains(&i) {
                put(destination, &format!("record-{i:02}"), 1000 + i).await;
            }
        }
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn a_retried_preparation_resumes_after_its_deadline_and_proves_interrupted_writes() {
        let source = test_context(|_| {}).await;
        let destination = test_context(|_| {}).await;
        // Record 15 sits on the second page of the newest-first walk.
        seed(&source.state, &destination.state, &[15]).await;
        let (url, server) = serve(destination.state.clone()).await;
        let target = activate(&source.state, url, &destination.state);
        *source.state.runtime.migration.deadline.lock().unwrap() = Some(Duration::from_secs(2));
        let records = &destination.state.runtime.migration.verified_records;
        let poll = || {
            prepare(
                State(source.state.clone()),
                Json(prepare_request(&source.state, &target)),
            )
        };

        assert_eq!(poll().await.unwrap()["ready"], false);
        let interrupted = wait_failed(&source.state).await;
        assert!(interrupted.contains("expired"), "{interrupted}");
        assert_eq!(records.load(Ordering::Relaxed), 16, "one page verified");

        // Written while no attempt runs, and newer than the saved position.
        put(&source.state, "interrupted", 5000).await;
        put(&destination.state, "record-15", 1015).await;
        assert_eq!(
            poll()
                .await
                .expect("a retry resumes a failed attempt that made progress")["ready"],
            false
        );
        let missing = wait_failed(&source.state).await;
        assert!(missing.contains("expired"), "{missing}");
        assert_eq!(
            records.load(Ordering::Relaxed),
            40,
            "the retry continued after the first page instead of restarting"
        );

        put(&destination.state, "interrupted", 5000).await;
        wait_ready(&source.state, &target).await;
        assert_eq!(
            records.load(Ordering::Relaxed),
            41,
            "the interrupted write was proven through the pinned feed"
        );
        server.abort();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn a_retry_after_feed_history_loss_restarts_the_walk() {
        let source = test_context(|_| {}).await;
        let destination = test_context(|_| {}).await;
        seed(&source.state, &destination.state, &[15]).await;
        let (url, server) = serve(destination.state.clone()).await;
        let target = activate(&source.state, url, &destination.state);
        *source.state.runtime.migration.deadline.lock().unwrap() = Some(Duration::from_secs(2));
        let records = &destination.state.runtime.migration.verified_records;
        let _ = prepare(
            State(source.state.clone()),
            Json(prepare_request(&source.state, &target)),
        )
        .await
        .expect("prepare accepted");
        wait_failed(&source.state).await;
        assert_eq!(records.load(Ordering::Relaxed), 16);

        // The write's feed row is trimmed before the retry, so the saved walk
        // position no longer covers it.
        put(&source.state, "interrupted", 5000).await;
        put(&destination.state, "interrupted", 5000).await;
        put(&destination.state, "record-15", 1015).await;
        let feed = source.state.store.sync_feed();
        feed.raise_floor(feed.head());
        wait_ready(&source.state, &target).await;
        assert_eq!(
            records.load(Ordering::Relaxed),
            16 + 41,
            "the retry walked every retained record again"
        );
        server.abort();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn a_stuck_attempt_keeps_failing_and_a_new_destination_restarts_from_zero() {
        let source = test_context(|_| {}).await;
        let destination = test_context(|_| {}).await;
        // The newest record opens the walk, so nothing can be verified.
        seed(&source.state, &destination.state, &[39, 15]).await;
        let (url, server) = serve(destination.state.clone()).await;
        let target = activate(&source.state, url, &destination.state);
        *source.state.runtime.migration.deadline.lock().unwrap() = Some(Duration::from_secs(1));
        let _ = prepare(
            State(source.state.clone()),
            Json(prepare_request(&source.state, &target)),
        )
        .await
        .expect("prepare accepted");
        wait_failed(&source.state).await;
        let calls = destination
            .state
            .runtime
            .migration
            .verifications
            .load(Ordering::Relaxed);
        for _ in 0..3 {
            assert!(
                prepare(
                    State(source.state.clone()),
                    Json(prepare_request(&source.state, &target)),
                )
                .await
                .is_err(),
                "an attempt that made no progress is not retried"
            );
        }
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert_eq!(
            destination
                .state
                .runtime
                .migration
                .verifications
                .load(Ordering::Relaxed),
            calls
        );

        // Reset discards the attempt; the next one verifies the first page and
        // stops at record 15, leaving resumable progress for this target.
        let _ = reset(
            State(source.state.clone()),
            Json(prepare_request(&source.state, &target)),
        )
        .await
        .expect("reset accepted");
        put(&destination.state, "record-39", 1039).await;
        let other = test_context(|_| {}).await;
        for i in 0..40 {
            put(&other.state, &format!("record-{i:02}"), 1000 + i).await;
        }
        let _ = prepare(
            State(source.state.clone()),
            Json(prepare_request(&source.state, &target)),
        )
        .await
        .expect("prepare accepted");
        wait_failed(&source.state).await;

        // Moving to another destination never carries that progress along.
        let (other_url, other_server) = serve(other.state.clone()).await;
        let replacement = Target {
            url: other_url.clone(),
            incarnation: other.state.runtime.connection_incarnation().to_owned(),
        };
        let mut peers = (**source.state.peer_views.load()).clone();
        peers.push(PeerView {
            url: other_url,
            topology: None,
            private_healthy: false,
            region: source.state.config.region.clone(),
            serving: true,
            draining: false,
        });
        source.state.peer_views.store(std::sync::Arc::new(peers));
        assert!(
            prepare(
                State(source.state.clone()),
                Json(prepare_request(&source.state, &replacement)),
            )
            .await
            .is_err(),
            "another destination waits for the failed attempt to be reset"
        );
        let _ = reset(
            State(source.state.clone()),
            Json(prepare_request(&source.state, &target)),
        )
        .await
        .expect("reset accepted");
        wait_ready(&source.state, &replacement).await;
        assert_eq!(
            other
                .state
                .runtime
                .migration
                .verified_records
                .load(Ordering::Relaxed),
            40,
            "the new destination is walked from the first record"
        );
        server.abort();
        other_server.abort();
    }

    fn metric(state: &SharedState, name: &str) -> Option<f64> {
        state
            .metrics
            .render()
            .lines()
            .find_map(|line| line.strip_prefix(name)?.strip_prefix(' ')?.parse().ok())
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn bridge_metrics_show_an_armed_bridge_that_cannot_reprove() {
        let source = test_context(|_| {}).await;
        let destination = test_context(|_| {}).await;
        seed(&source.state, &destination.state, &[]).await;
        let (url, server) = serve(destination.state.clone()).await;
        let target = activate(&source.state, url.clone(), &destination.state);
        source.state.sync_runtime_metrics().await;
        assert_eq!(
            metric(&source.state, "kura_migration_bridge_armed"),
            Some(0.0)
        );
        assert_eq!(
            metric(&source.state, "kura_migration_bridge_ready"),
            Some(0.0)
        );

        wait_ready(&source.state, &target).await;
        acknowledge(&source.state).await.unwrap();
        source.state.sync_runtime_metrics().await;
        assert_eq!(
            metric(&source.state, "kura_migration_bridge_armed"),
            Some(1.0)
        );
        assert_eq!(
            metric(&source.state, "kura_migration_bridge_ready"),
            Some(1.0)
        );
        assert_eq!(
            metric(
                &source.state,
                "kura_migration_preparation_records_verified_total_total"
            ),
            Some(40.0)
        );
        assert_eq!(
            metric(&source.state, "kura_migration_preparation_walk_records"),
            Some(40.0)
        );
        assert!(
            metric(
                &source.state,
                "kura_migration_bridge_last_proof_age_seconds"
            )
            .is_some_and(|age| age < 2.0)
        );

        // The destination restarts without the records: the bridge stays armed
        // but unready, and each failed re-proof is counted.
        server.abort();
        let _ = server.await;
        let restarted = test_context(|_| {}).await;
        let server = serve_at(restarted.state.clone(), &url).await;
        let replacement = Target {
            url,
            incarnation: restarted.state.runtime.connection_incarnation().to_owned(),
        };
        let _ = rebind(
            State(source.state.clone()),
            Json(rebind_request(&source.state, &target, &replacement)),
        )
        .await
        .expect("rebind accepted");
        tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                source.state.sync_runtime_metrics().await;
                if metric(&source.state, "kura_migration_reproof_failures_total_total")
                    .is_some_and(|failures| failures >= 1.0)
                {
                    break;
                }
                tokio::time::sleep(Duration::from_millis(50)).await;
            }
        })
        .await
        .expect("a failed re-proof is counted");
        assert_eq!(
            metric(&source.state, "kura_migration_bridge_armed"),
            Some(1.0)
        );
        assert_eq!(
            metric(&source.state, "kura_migration_bridge_ready"),
            Some(0.0)
        );
        server.abort();
    }

    fn abort_request(source: &SharedState, target: &Target) -> Json<PrepareRequest> {
        Json(prepare_request(source, target))
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn aborting_an_armed_bridge_releases_writes_without_destination_proof() {
        let source = test_context(|_| {}).await;
        let destination = test_context(|_| {}).await;
        let (url, server) = serve(destination.state.clone()).await;
        let target = activate(&source.state, url, &destination.state);
        wait_ready(&source.state, &target).await;
        put(&source.state, "unproven", 1000).await;
        let state = source.state.clone();
        let blocked = tokio::spawn(async move { acknowledge(&state).await });
        tokio::time::sleep(Duration::from_millis(100)).await;
        assert!(!blocked.is_finished(), "the bridge holds the write");

        let receipt = abort(
            State(source.state.clone()),
            abort_request(&source.state, &target),
        )
        .await
        .expect("abort accepted");
        assert_eq!(receipt["aborted"], true);
        assert_eq!(
            receipt["incarnation"],
            source.state.runtime.connection_incarnation()
        );
        tokio::time::timeout(Duration::from_secs(1), blocked)
            .await
            .expect("the waiting write is released promptly")
            .unwrap()
            .expect("the waiting write completes as an ordinary write");
        put(&source.state, "after-abort", 2000).await;
        acknowledge(&source.state).await.unwrap();

        // Nothing comes back: no bridge, no pin, no destination traffic.
        let calls = destination
            .state
            .runtime
            .migration
            .verifications
            .load(Ordering::Relaxed);
        tokio::time::sleep(Duration::from_millis(1500)).await;
        assert!(!source.state.runtime.migration.armed.load(Ordering::Acquire));
        assert!(
            source
                .state
                .runtime
                .migration
                .active
                .lock()
                .unwrap()
                .is_none()
        );
        assert!(
            source
                .state
                .store
                .sync_feed()
                .consumers()
                .iter()
                .all(|(name, _)| *name != consumer(&source.state))
        );
        assert_eq!(
            destination
                .state
                .runtime
                .migration
                .verifications
                .load(Ordering::Relaxed),
            calls
        );
        server.abort();
    }

    #[tokio::test]
    async fn abort_is_bound_to_the_source_and_target_and_idempotent() {
        let source = test_context(|_| {}).await;
        let destination = test_context(|_| {}).await;
        let target = activate(
            &source.state,
            "http://127.0.0.1:1".into(),
            &destination.state,
        );
        for _ in 0..2 {
            let receipt = abort(
                State(source.state.clone()),
                abort_request(&source.state, &target),
            )
            .await
            .expect("aborting nothing succeeds");
            assert_eq!(receipt["aborted"], true);
        }
        *source.state.runtime.migration.active.lock().unwrap() =
            Some(Active::new(target.clone(), 1, Instant::now() + DEADLINE, 0));
        let other = Target {
            url: target.url.clone(),
            incarnation: "another-process".into(),
        };
        let error = abort(
            State(source.state.clone()),
            abort_request(&source.state, &other),
        )
        .await
        .unwrap_err();
        assert_eq!(error.0, StatusCode::CONFLICT);
        let error = abort(
            State(source.state.clone()),
            Json(PrepareRequest {
                incarnation: "previous-process".into(),
                target: target.clone(),
            }),
        )
        .await
        .unwrap_err();
        assert_eq!(error.0, StatusCode::CONFLICT);
        assert!(
            source
                .state
                .runtime
                .migration
                .active
                .lock()
                .unwrap()
                .is_some()
        );
        let _ = abort(
            State(source.state.clone()),
            abort_request(&source.state, &target),
        )
        .await
        .expect("abort accepted");
        assert!(
            source
                .state
                .runtime
                .migration
                .active
                .lock()
                .unwrap()
                .is_none()
        );
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn abort_stops_a_running_preparation_and_the_next_one_starts_from_zero() {
        let source = test_context(|_| {}).await;
        let destination = test_context(|_| {}).await;
        seed(&source.state, &destination.state, &[15]).await;
        let (url, server) = serve(destination.state.clone()).await;
        let target = activate(&source.state, url, &destination.state);
        let migration = &destination.state.runtime.migration;
        let _ = prepare(
            State(source.state.clone()),
            Json(prepare_request(&source.state, &target)),
        )
        .await
        .expect("prepare accepted");
        // The first page verifies, then the walk retries the missing record.
        tokio::time::timeout(Duration::from_secs(5), async {
            while migration.verifications.load(Ordering::Relaxed) < 4 {
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .unwrap();
        assert_eq!(migration.verified_records.load(Ordering::Relaxed), 16);

        let _ = abort(
            State(source.state.clone()),
            abort_request(&source.state, &target),
        )
        .await
        .expect("abort accepted");
        tokio::time::sleep(Duration::from_millis(200)).await;
        let calls = migration.verifications.load(Ordering::Relaxed);
        tokio::time::sleep(Duration::from_millis(300)).await;
        assert_eq!(
            migration.verifications.load(Ordering::Relaxed),
            calls,
            "the aborted walk stopped"
        );
        assert!(
            source
                .state
                .runtime
                .migration
                .active
                .lock()
                .unwrap()
                .is_none()
        );

        put(&destination.state, "record-15", 1015).await;
        wait_ready(&source.state, &target).await;
        assert_eq!(
            migration.verified_records.load(Ordering::Relaxed),
            16 + 40,
            "the next preparation walked from the first record"
        );
        server.abort();
    }

    #[tokio::test]
    async fn ordinary_requests_need_no_feed_or_peer() {
        let source = test_context(|_| {}).await;
        acknowledge(&source.state).await.unwrap();
    }
}
