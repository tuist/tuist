//! Named, retained-corpus handover verification. A feed cursor alone can skip
//! capacity-rejected data, so every retained body and metadata record is checked.
use crate::{
    backfill::{
        pass::{
            BackfillPassOutcome, BackfillPassTuning, PassSource, run_backfill_pass_with_tuning,
        },
        window::BackfillWindow,
    },
    http::BackfillBodyManifestMeta,
    serving_authority::Holder,
    state::SharedState,
    store::manifest_version_ms,
    utils::BackfillRecordKind,
};
use axum::{Json, extract::State, http::StatusCode};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{sync::atomic::Ordering, time::Duration};
use tokio_util::sync::CancellationToken;
use tracing::Instrument;

const MAX_BATCH_RECORDS: usize = 32;
const MAX_BATCH_BODY_BYTES: u64 = 8 * 1024 * 1024;
const MAX_BATCH_METADATA_BYTES: usize = 64 * 1024;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct Intent {
    pub id: String,
    pub destination: Holder,
    pub destination_url: String,
    pub source_url: String,
    pub deadline_ms: u64,
}

// A preparation report is a scheduling hint, never a retained-data receipt.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct Preparation {
    pub intent: Intent,
    pub source: Holder,
    pub epoch: u64,
    pub complete: bool,
    pub error: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct Receipt {
    pub id: String,
    pub source: Holder,
    pub destination: Holder,
    pub incarnation: u64,
    pub head: u64,
    pub frontier_ms: u64,
    pub records: u64,
    pub digest: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Record {
    kind: String,
    id: String,
    version: u64,
    size: u64,
    digest: String,
}

#[derive(Clone, Deserialize, Serialize)]
pub struct VerifyRequest {
    #[serde(default)]
    begin: bool,
    intent: Intent,
    source: Holder,
    record: Option<Record>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    records: Vec<Record>,
    receipt: Option<Receipt>,
}

fn verification_context(request: &VerifyRequest) -> String {
    if request.begin {
        "begin".into()
    } else if let Some(record) = &request.record {
        record_context(record)
    } else if !request.records.is_empty() {
        format!("batch records={}", request.records.len())
    } else {
        "receipt".into()
    }
}

fn record_context(record: &Record) -> String {
    format!(
        "record kind={} id={:?} version={} size={}",
        bounded_detail(&record.kind),
        bounded_detail(&record.id),
        record.version,
        record.size
    )
}

fn bounded_detail(detail: &str) -> String {
    detail.chars().take(1024).collect()
}

async fn record(
    state: &SharedState,
    kind: BackfillRecordKind,
    id: &str,
    version: u64,
) -> Result<Option<Record>, String> {
    if kind == BackfillRecordKind::NamespaceTombstone {
        return match state.store.namespace_tombstone_version(id)? {
            Some(current) if current == version => Ok(Some(Record {
                kind: kind.as_str().into(),
                id: id.into(),
                version,
                size: 0,
                digest: format!("{current:016x}"),
            })),
            _ => Ok(None),
        };
    }
    // The commit hold freezes RocksDB, while a pre-hold writer may still be
    // updating its manifest cache. Verify the frozen authoritative row.
    let Some(manifest) = state.store.manifest_from_db(id)? else {
        return Ok(None);
    };
    if manifest_version_ms(&manifest) != version {
        return Ok(None);
    }
    let meta = BackfillBodyManifestMeta::from_manifest(&manifest).to_wire_bytes()?;
    let mut digest = Sha256::new();
    digest.update((meta.len() as u64).to_be_bytes());
    digest.update(meta);
    let Some((opened, mut reader)) = state
        .store
        .open_artifact_reader_range_tolerating_promotion(&manifest, 0, None)
        .await?
    else {
        return Err("retained body disappeared".into());
    };
    if manifest_version_ms(&opened) != version {
        return Err("retained record changed during verification".into());
    }
    let mut bytes = 0u64;
    loop {
        let chunk = reader
            .read_bytes_chunk(64 * 1024)
            .await
            .map_err(|e| e.to_string())?;
        if chunk.is_empty() {
            break;
        }
        bytes += chunk.len() as u64;
        digest.update(&chunk);
    }
    if bytes != manifest.size {
        return Err("retained body length mismatch".into());
    }
    Ok(Some(Record {
        kind: kind.as_str().into(),
        id: id.into(),
        version,
        size: bytes,
        digest: format!("{:x}", digest.finalize()),
    }))
}

pub async fn verify(
    State(state): State<SharedState>,
    Json(request): Json<VerifyRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    if request.begin {
        // A source's per-request timeout can be shorter than retained repair.
        // Keep the serialized preparation alive across caller cancellation;
        // the named intent/deadline and runtime drain still bound its work.
        tokio::spawn(verify_response(state, request).in_current_span())
            .await
            .map_err(|error| {
                tracing::error!(%error, "Retained-corpus preparation task failed");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "retained corpus preparation task failed".into(),
                )
            })?
    } else {
        verify_response(state, request).await
    }
}

async fn verify_response(
    state: SharedState,
    request: VerifyRequest,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let context = verification_context(&request);
    let id = bounded_detail(&request.intent.id);
    verify_inner(&state, request)
        .await
        .map(Json)
        .map_err(|error| {
            let reason = bounded_detail(&error);
            tracing::warn!(
                event.name = "kura.handover.verification_rejected",
                %id,
                %context,
                %reason,
                "Retained-corpus verification rejected"
            );
            (StatusCode::CONFLICT, reason)
        })
}

async fn verify_inner(
    state: &SharedState,
    request: VerifyRequest,
) -> Result<serde_json::Value, String> {
    if request.records.len() > MAX_BATCH_RECORDS
        || (!request.records.is_empty()
            && (request.begin || request.record.is_some() || request.receipt.is_some()))
    {
        return Err("invalid retained record batch".into());
    }
    let authority = &state.runtime.authority;
    require_current_destination(state, &request)?;
    if request.begin {
        let receipt = request.receipt.as_ref().ok_or("missing source position")?;
        let _preparation = authority
            .handover_preparation
            .try_lock()
            .map_err(|_| "retained corpus reconciliation in progress")?;
        let cursor = state
            .store
            .sync_cursor(&request.intent.source_url)?
            .ok_or("missing source cursor")?;
        if cursor.incarnation != receipt.incarnation || cursor.seq < receipt.head {
            return Err("source feed not yet applied".into());
        }
        let already_held = {
            let hold = state
                .store
                .handover_hold
                .lock()
                .map_err(|_| "handover hold poisoned")?;
            if hold.as_ref().is_some_and(|id| id != &request.intent.id) {
                return Err("another handover owns the retained corpus".into());
            }
            hold.is_some()
        };
        if !already_held {
            loop {
                require_current_destination(state, &request)?;
                let before = state
                    .store
                    .handover_eviction_generation
                    .load(Ordering::Acquire);
                reconcile_retained_corpus(state, &request, None).await?;
                let mut hold = state
                    .store
                    .handover_hold
                    .lock()
                    .map_err(|_| "handover hold poisoned")?;
                // Share the eviction commit lock: a removal cannot slip between
                // this comparison and freezing the destination. Never release a
                // hold to repair a failed verification; finish repair first.
                require_current_destination(state, &request)?;
                let after = state
                    .store
                    .handover_eviction_generation
                    .load(Ordering::Acquire);
                if before != after {
                    tracing::info!(event.name="kura.handover.repair_revisit", id=%request.intent.id,
                        eviction_commits=after.wrapping_sub(before),
                        "Revisiting retained corpus after repair eviction");
                    continue;
                }
                *hold = Some(request.intent.id.clone());
                break;
            }
        }
        // An idempotent begin still has to belong to the current intent.
        require_current_destination(state, &request)?;
        return Ok(
            serde_json::json!({"destination": authority.identity(), "max_batch_records": MAX_BATCH_RECORDS}),
        );
    }
    if state
        .store
        .handover_hold
        .lock()
        .map_err(|_| "handover hold poisoned")?
        .as_deref()
        != Some(request.intent.id.as_str())
    {
        return Err("retained corpus not held".into());
    }
    if request.record.is_some() || !request.records.is_empty() {
        let records = request.record.into_iter().chain(request.records);
        let mut count = 0;
        for expected in records {
            verify_record(state, &expected)
                .await
                .map_err(|error| format!("{}; {error}", record_context(&expected)))?;
            count += 1;
        }
        return Ok(
            serde_json::json!({"destination": authority.identity(), "verified_records": count}),
        );
    }
    let receipt = request.receipt.ok_or("missing receipt")?;
    if receipt.id != request.intent.id
        || receipt.source != request.source
        || receipt.destination != request.intent.destination
    {
        return Err("receipt binding mismatch".into());
    }
    let cursor = state
        .store
        .sync_cursor(&request.intent.source_url)?
        .ok_or("missing source cursor")?;
    if cursor.incarnation != receipt.incarnation || cursor.seq < receipt.head {
        return Err("source feed not durably applied through barrier".into());
    }
    // Each backfill body is already durable when a forward cursor advances;
    // syncing this receipt also persists the cursor before acknowledgment.
    state
        .store
        .persist_handover_receipt(&serde_json::to_vec(&receipt).map_err(|e| e.to_string())?)
        .await?;
    *authority.barrier.lock().map_err(|_| "barrier poisoned")? = Some(receipt.clone());
    Ok(serde_json::json!({"receipt": receipt}))
}

fn require_current_destination(state: &SharedState, request: &VerifyRequest) -> Result<(), String> {
    if state.runtime.is_draining() {
        return Err("handover destination draining".into());
    }
    let authority = &state.runtime.authority;
    let grant = authority.intent().ok_or("no handover intent")?;
    if grant.phase != "Quiescing"
        || grant.holder != request.source
        || grant.handover.as_ref() != Some(&request.intent)
        || request.intent.destination != *authority.identity()
        || crate::utils::now_ms() >= request.intent.deadline_ms
    {
        return Err("handover identity, phase or deadline mismatch".into());
    }
    Ok(())
}

async fn reconcile_retained_corpus(
    state: &SharedState,
    request: &VerifyRequest,
    preparation_epoch: Option<u64>,
) -> Result<(), String> {
    // A feed cursor covers arrivals, not everything the source still retains:
    // bootstrap is horizon bounded and local eviction can remove older rows.
    // Reuse the bounded replication pipeline before freezing the destination.
    // Keep store capacity/version/tombstone rules, but not the ordinary
    // age-based selection policy: even old records belong to this barrier.
    // Full verification, never pass completion, authorizes the transfer.
    let mut tuning = BackfillPassTuning::from_config(&state.config);
    tuning.source = PassSource::RetainedIndex;
    tuning.feed_rows = false;
    tuning.bandwidth_shaped = preparation_epoch.is_some();
    let cancel = CancellationToken::new();
    let pass = run_backfill_pass_with_tuning(
        state,
        &request.intent.source_url,
        BackfillWindow {
            min_version_ms: None,
        },
        state.backfill_claims.register_pass(),
        &cancel,
        tuning,
    );
    tokio::pin!(pass);
    let mut check = tokio::time::interval(Duration::from_millis(100));
    loop {
        tokio::select! {
            biased;
            _ = check.tick() => match preparation_epoch {
                Some(epoch) => require_current_preparation(state, request, epoch)?,
                None => require_current_destination(state, request)?,
            },
            outcome = &mut pass => {
                return match outcome {
                    BackfillPassOutcome::Completed { stats, .. } => {
                        tracing::info!(event.name="kura.handover.reconciled", id=%request.intent.id,
                            listed=stats.tuples_listed, applied=stats.bodies_applied,
                            bytes=stats.bytes_applied, capacity_skipped=stats.tuples_capacity_skipped,
                            "Named destination reconciled before retained-corpus verification");
                        Ok(())
                    }
                    BackfillPassOutcome::Failed { error, .. } => Err(format!("retained corpus reconciliation failed: {}", bounded_detail(&error))),
                    BackfillPassOutcome::Cancelled { .. } => Err("retained corpus reconciliation cancelled".into()),
                };
            }
        }
    }
}

fn require_current_preparation(
    state: &SharedState,
    request: &VerifyRequest,
    epoch: u64,
) -> Result<(), String> {
    let authority = &state.runtime.authority;
    let grant = authority.intent().ok_or("no preparation intent")?;
    let now = crate::utils::now_ms();
    if state.runtime.is_draining()
        || grant.phase != "Serving"
        || grant.epoch != epoch
        || epoch == 0
        || grant.expires_ms <= now.saturating_add(2_000)
        || grant.holder != request.source
        || grant.holder == *authority.identity()
        || grant.handover.as_ref() != Some(&request.intent)
        || request.intent.destination != *authority.identity()
        || now >= request.intent.deadline_ms
    {
        return Err("preparation identity, grant or deadline mismatch".into());
    }
    Ok(())
}

async fn prepare_live_destination(
    state: &SharedState,
    preparation: &Preparation,
) -> Result<(), String> {
    let request = VerifyRequest {
        begin: false,
        intent: preparation.intent.clone(),
        source: preparation.source.clone(),
        record: None,
        records: Vec::new(),
        receipt: None,
    };
    let _preparation = state.runtime.authority.handover_preparation.lock().await;
    require_current_preparation(state, &request, preparation.epoch)?;
    reconcile_retained_corpus(state, &request, Some(preparation.epoch)).await?;
    // A live cache may evict on every walk. Waiting for an eviction-free pass
    // can starve until the deadline while the source keeps accepting writes.
    // Quiescing still repairs, atomically freezes and verifies the full corpus.
    require_current_preparation(state, &request, preparation.epoch)
}

async fn verify_record(state: &SharedState, expected: &Record) -> Result<(), String> {
    let kind =
        BackfillRecordKind::from_wire_name(&expected.kind).ok_or("unknown retained record kind")?;
    let actual = match record(state, kind, &expected.id, expected.version).await? {
        Some(actual) => actual,
        None => {
            let version = if kind == BackfillRecordKind::NamespaceTombstone {
                state.store.namespace_tombstone_version(&expected.id)?
            } else {
                state
                    .store
                    .manifest_from_db(&expected.id)?
                    .as_ref()
                    .map(manifest_version_ms)
            };
            return Err(format!(
                "retained record missing or version differs: expected_version={} actual_version={version:?}",
                expected.version
            ));
        }
    };
    if actual.size != expected.size || actual.digest != expected.digest {
        return Err(format!(
            "retained record content mismatch: expected_size={} actual_size={} expected_digest={} actual_digest={}",
            expected.size,
            actual.size,
            bounded_detail(&expected.digest),
            actual.digest
        ));
    }
    Ok(())
}

async fn send(
    state: &SharedState,
    intent: &Intent,
    request: &VerifyRequest,
) -> Result<serde_json::Value, String> {
    let response = state
        .peer_request(
            reqwest::Method::POST,
            &intent.destination_url,
            &format!("{}/_internal/handover/verify", intent.destination_url),
        )?
        .json(request)
        .timeout(Duration::from_secs(30))
        .send()
        .await
        .map_err(|e| e.to_string())?;
    let status = response.status();
    let bytes =
        crate::replication::read_bounded_body(response, 16 * 1024, "handover verification").await?;
    if !status.is_success() {
        return Err(format!(
            "destination rejected handover: {status}; {}; reason={:?}",
            verification_context(request),
            bounded_detail(&String::from_utf8_lossy(&bytes))
        ));
    }
    serde_json::from_slice(&bytes).map_err(|e| e.to_string())
}

fn check_destination(answer: &serde_json::Value, intent: &Intent) -> Result<(), String> {
    if answer["destination"]
        != serde_json::to_value(&intent.destination).map_err(|e| e.to_string())?
    {
        return Err("destination incarnation changed".into());
    }
    Ok(())
}

async fn send_records(
    state: &SharedState,
    intent: &Intent,
    source: &Holder,
    mut records: Vec<Record>,
    batched: bool,
) -> Result<(), String> {
    let count = records.len();
    let request = VerifyRequest {
        begin: false,
        intent: intent.clone(),
        source: source.clone(),
        record: if batched { None } else { records.pop() },
        records,
        receipt: None,
    };
    let answer = send(state, intent, &request).await?;
    check_destination(&answer, intent)?;
    if batched && answer["verified_records"].as_u64() != Some(count as u64) {
        return Err("destination did not acknowledge the complete batch".into());
    }
    Ok(())
}

async fn prepare(state: &SharedState, intent: &Intent) -> Result<Receipt, String> {
    let authority = &state.runtime.authority;
    if authority.mutations() != 0 || !state.store.backfill_index_built() {
        return Err("mutations or index build still in flight".into());
    }
    let feed = state.store.sync_feed();
    if !feed.enabled() {
        return Err("source feed disabled".into());
    }
    {
        let mut hold = state
            .store
            .handover_hold
            .lock()
            .map_err(|_| "handover hold poisoned")?;
        if hold.as_ref().is_some_and(|id| id != &intent.id) {
            return Err("another handover owns the retained corpus".into());
        }
        *hold = Some(intent.id.clone());
    }
    let (head, frontier_ms) = feed.head_and_frontier();
    let floor = feed.floor();
    let mut receipt = Receipt {
        id: intent.id.clone(),
        source: authority.identity().clone(),
        destination: intent.destination.clone(),
        incarnation: feed.incarnation(),
        head,
        frontier_ms,
        records: 0,
        digest: String::new(),
    };
    let mut after = None;
    let mut digest = Sha256::new();
    let answer = send(
        state,
        intent,
        &VerifyRequest {
            begin: true,
            intent: intent.clone(),
            source: receipt.source.clone(),
            records: Vec::new(),
            record: None,
            receipt: Some(receipt.clone()),
        },
    )
    .await?;
    check_destination(&answer, intent)?;
    let batch_size = answer["max_batch_records"]
        .as_u64()
        .unwrap_or(1)
        .clamp(1, MAX_BATCH_RECORDS as u64) as usize;
    loop {
        let page = state
            .store
            .backfill_index_page(after.as_deref(), MAX_BATCH_RECORDS)?;
        let mut batch = Vec::with_capacity(batch_size);
        let mut body_bytes = 0u64;
        let mut metadata_bytes = 0usize;
        for row in page.entries {
            // Stale index rows are not retained objects. Only the exact current
            // tuple is verified, and all subsequent pages are still visited.
            let Some(value) = record(state, row.kind, &row.record_id, row.version_ms).await? else {
                continue;
            };
            let encoded = serde_json::to_vec(&value).map_err(|e| e.to_string())?;
            if !batch.is_empty()
                && (body_bytes.saturating_add(value.size) > MAX_BATCH_BODY_BYTES
                    || metadata_bytes.saturating_add(encoded.len()) > MAX_BATCH_METADATA_BYTES)
            {
                send_records(
                    state,
                    intent,
                    &receipt.source,
                    std::mem::take(&mut batch),
                    batch_size > 1,
                )
                .await?;
                body_bytes = 0;
                metadata_bytes = 0;
            }
            metadata_bytes += encoded.len();
            digest.update((encoded.len() as u64).to_be_bytes());
            digest.update(encoded);
            body_bytes = body_bytes.saturating_add(value.size);
            batch.push(value);
            receipt.records += 1;
            if batch.len() == batch_size {
                send_records(
                    state,
                    intent,
                    &receipt.source,
                    std::mem::take(&mut batch),
                    batch_size > 1,
                )
                .await?;
                body_bytes = 0;
                metadata_bytes = 0;
            }
        }
        if !batch.is_empty() {
            send_records(state, intent, &receipt.source, batch, batch_size > 1).await?;
        }
        after = page.next_after;
        if after.is_none() {
            break;
        }
    }
    if feed.head() != head || feed.floor() != floor || authority.mutations() != 0 {
        return Err("source changed or feed trimmed during barrier".into());
    }
    receipt.digest = format!("{:x}", digest.finalize());
    let answer = send(
        state,
        intent,
        &VerifyRequest {
            begin: false,
            intent: intent.clone(),
            source: receipt.source.clone(),
            records: Vec::new(),
            record: None,
            receipt: Some(receipt.clone()),
        },
    )
    .await?;
    if answer["receipt"] != serde_json::to_value(&receipt).map_err(|e| e.to_string())? {
        return Err("destination receipt mismatch".into());
    }
    state
        .store
        .persist_handover_receipt(&serde_json::to_vec(&receipt).map_err(|e| e.to_string())?)
        .await?;
    Ok(receipt)
}

pub fn spawn(state: SharedState) {
    if !state.runtime.authority.enabled() {
        return;
    }
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_secs(1)).await;
            let authority = &state.runtime.authority;
            let Some(grant) = authority.intent() else {
                continue;
            };
            let Some(intent) = grant.handover.clone() else {
                continue;
            };
            if grant.phase == "Serving" && intent.destination == *authority.identity() {
                let mut preparation = Preparation {
                    intent: intent.clone(),
                    source: grant.holder,
                    epoch: grant.epoch,
                    complete: false,
                    error: None,
                };
                {
                    let mut current = authority
                        .preparation
                        .lock()
                        .unwrap_or_else(|e| e.into_inner());
                    if current.as_ref().is_some_and(|previous| {
                        previous.intent == intent
                            && previous.source == preparation.source
                            && previous.epoch == preparation.epoch
                    }) {
                        continue;
                    }
                    *current = Some(preparation.clone());
                }
                let remaining = intent
                    .deadline_ms
                    .saturating_sub(crate::utils::now_ms())
                    .min(1_200_000);
                match tokio::time::timeout(
                    Duration::from_millis(remaining),
                    prepare_live_destination(&state, &preparation),
                )
                .await
                {
                    Ok(Ok(())) => preparation.complete = true,
                    Ok(Err(error)) => preparation.error = Some(bounded_detail(&error)),
                    Err(_) => preparation.error = Some("live preparation deadline exceeded".into()),
                }
                tracing::info!(event.name="kura.handover.prepared", id=%intent.id,
                    complete=preparation.complete, error=?preparation.error,
                    "Finished standby preparation while the source serves");
                *authority
                    .preparation
                    .lock()
                    .unwrap_or_else(|e| e.into_inner()) = Some(preparation);
                continue;
            }
            if grant.phase != "Quiescing"
                || grant.holder != *authority.identity()
                || authority.mutations() != 0
            {
                continue;
            }
            if authority
                .barrier
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .as_ref()
                .is_some_and(|r| r.id == intent.id)
            {
                continue;
            }
            let remaining = intent.deadline_ms.saturating_sub(crate::utils::now_ms());
            if remaining == 0 {
                continue;
            }
            match tokio::time::timeout(
                Duration::from_millis(remaining.min(300_000)),
                prepare(&state, &intent),
            )
            .await
            {
                Ok(Ok(receipt)) => {
                    *authority.barrier.lock().unwrap_or_else(|e| e.into_inner()) = Some(receipt);
                }
                outcome => tracing::warn!(event.name="kura.handover.failed",id=%intent.id,?outcome),
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        artifact::producer::ArtifactProducer, serving_authority::Grant, sync::feed::SyncPosition,
        test_support::test_context,
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

    fn begin_request(state: &SharedState, source_url: String) -> VerifyRequest {
        let mut source = state.runtime.authority.identity().clone();
        source.pod_uid = "source".into();
        let intent = Intent {
            id: "repair".into(),
            destination: state.runtime.authority.identity().clone(),
            source_url,
            destination_url: "http://destination".into(),
            deadline_ms: crate::utils::now_ms() + 15_000,
        };
        state
            .runtime
            .authority
            .install(Grant {
                epoch: 1,
                holder: source.clone(),
                phase: "Quiescing".into(),
                expires_ms: crate::utils::now_ms() + 15_000,
                handover: Some(intent.clone()),
                barrier: None,
                resume_epoch: None,
            })
            .unwrap();
        state
            .store
            .write_sync_cursor(
                &intent.source_url,
                SyncPosition {
                    incarnation: 7,
                    seq: 9,
                },
            )
            .unwrap();
        VerifyRequest {
            begin: true,
            receipt: Some(Receipt {
                id: intent.id.clone(),
                source: source.clone(),
                destination: intent.destination.clone(),
                incarnation: 7,
                head: 9,
                frontier_ms: 100,
                records: 0,
                digest: String::new(),
            }),
            intent,
            source,
            records: Vec::new(),
            record: None,
        }
    }

    #[tokio::test]
    async fn live_preparation_copies_retained_data_without_holds_or_a_receipt() {
        let source = test_context(|_| {}).await;
        let target = test_context(|_| {}).await;
        source
            .state
            .store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "old-inline",
                "text/plain",
                b"retained",
                1000,
                None,
                None,
            )
            .await
            .unwrap();
        let blob = source
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "segment",
                "application/octet-stream",
                &vec![42; 128 * 1024],
            )
            .await
            .unwrap();
        let (url, server) = serve(source.state.clone()).await;
        let request = begin_request(&target.state, url);
        let mut grant = target.state.runtime.authority.intent().unwrap();
        grant.phase = "Serving".into();
        target
            .state
            .runtime
            .authority
            .install(grant.clone())
            .unwrap();
        let preparation = Preparation {
            intent: request.intent.clone(),
            source: request.source.clone(),
            epoch: grant.epoch,
            complete: false,
            error: None,
        };
        prepare_live_destination(&target.state, &preparation)
            .await
            .unwrap();
        let expected = record(
            &source.state,
            BackfillRecordKind::SegmentArtifact,
            &blob.artifact_id,
            blob.version_ms,
        )
        .await
        .unwrap()
        .unwrap();
        verify_record(&target.state, &expected).await.unwrap();
        let retained = source
            .state
            .store
            .backfill_index_page_ascending(0, None, 10, u64::MAX, None)
            .unwrap()
            .entries;
        assert_eq!(retained.len(), 2);
        for entry in retained {
            let retained = record(
                &source.state,
                entry.kind,
                &entry.record_id,
                entry.version_ms,
            )
            .await
            .unwrap()
            .unwrap();
            verify_record(&target.state, &retained).await.unwrap();
        }
        assert!(source.state.store.handover_hold.lock().unwrap().is_none());
        assert!(target.state.store.handover_hold.lock().unwrap().is_none());
        assert!(
            target
                .state
                .runtime
                .authority
                .barrier
                .lock()
                .unwrap()
                .is_none()
        );
        assert!(
            verify_inner(&target.state, request.clone())
                .await
                .unwrap_err()
                .contains("phase")
        );

        // A preparation result cannot stand in for the later frozen-corpus check.
        target.state.store.delete_namespace("ios").await.unwrap();
        assert!(verify_record(&target.state, &expected).await.is_err());
        server.abort();
    }

    #[tokio::test]
    async fn live_preparation_cancels_blocked_peer_io_on_authority_change() {
        for stop in ["abort", "epoch", "grant-expiry", "deadline", "drain"] {
            let target = test_context(|_| {}).await;
            let entered = std::sync::Arc::new(tokio::sync::Notify::new());
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let url = format!("http://{}", listener.local_addr().unwrap());
            let app = axum::Router::new().fallback({
                let entered = entered.clone();
                move || {
                    let entered = entered.clone();
                    async move {
                        entered.notify_one();
                        std::future::pending::<()>().await;
                        Json(serde_json::json!({"entries": [], "next_after": null}))
                    }
                }
            });
            let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
            let mut request = begin_request(&target.state, url);
            let mut grant = target.state.runtime.authority.intent().unwrap();
            grant.phase = "Serving".into();
            if stop == "deadline" {
                request.intent.deadline_ms = crate::utils::now_ms() + 1000;
            }
            grant.handover = Some(request.intent.clone());
            // An observed standby grant has no local writer lease; validate its
            // wall deadline in the preparation loop even if API polling stops.
            if stop == "grant-expiry" {
                // Advance the epoch so replacing the test's initial deadline is
                // not a same-epoch grant regression.
                grant.epoch += 1;
                grant.expires_ms = crate::utils::now_ms() + 3000;
            }
            target
                .state
                .runtime
                .authority
                .install(grant.clone())
                .unwrap();
            let preparation = Preparation {
                intent: request.intent,
                source: request.source,
                epoch: grant.epoch,
                complete: false,
                error: None,
            };
            let state = target.state.clone();
            let worker =
                tokio::spawn(async move { prepare_live_destination(&state, &preparation).await });
            tokio::time::timeout(Duration::from_secs(5), entered.notified())
                .await
                .unwrap();
            match stop {
                "abort" => {
                    grant.handover = None;
                    target.state.runtime.authority.install(grant).unwrap();
                }
                "epoch" => {
                    grant.epoch += 1;
                    target.state.runtime.authority.install(grant).unwrap();
                }
                "drain" => {
                    target.state.runtime.request_drain();
                }
                "deadline" | "grant-expiry" => {}
                _ => unreachable!(),
            }
            assert!(
                tokio::time::timeout(Duration::from_secs(3), worker)
                    .await
                    .unwrap()
                    .unwrap()
                    .is_err(),
                "{stop}"
            );
            assert!(
                target
                    .state
                    .runtime
                    .authority
                    .handover_preparation
                    .try_lock()
                    .is_ok(),
                "{stop}"
            );
            assert!(
                target.state.store.handover_hold.lock().unwrap().is_none(),
                "{stop}"
            );
            assert!(
                target
                    .state
                    .runtime
                    .authority
                    .barrier
                    .lock()
                    .unwrap()
                    .is_none(),
                "{stop}"
            );
            server.abort();
        }
    }

    #[tokio::test]
    async fn caught_up_cursor_repairs_missing_retained_records_before_freezing() {
        let source = test_context(|_| {}).await;
        let target = test_context(|_| {}).await;
        let state = &target.state;
        state.store.sync_feed_activate().await.unwrap();
        source
            .state
            .store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "old-inline",
                "text/plain",
                b"retained",
                1000,
                None,
                None,
            )
            .await
            .unwrap();
        let segment = source
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "segment",
                "application/octet-stream",
                &vec![42; 128 * 1024],
            )
            .await
            .unwrap();
        source
            .state
            .store
            .apply_replicated_namespace_delete("deleted", 1000)
            .await
            .unwrap();
        let (url, server) = serve(source.state.clone()).await;
        let request = begin_request(state, url);
        *source.state.store.handover_hold.lock().unwrap() = Some(request.intent.id.clone());
        let entries = source
            .state
            .store
            .backfill_index_page_ascending(0, None, 10, u64::MAX, None)
            .unwrap()
            .entries;
        assert_eq!(entries.len(), 3);
        let mut records = Vec::new();
        for entry in entries {
            let expected = record(
                &source.state,
                entry.kind,
                &entry.record_id,
                entry.version_ms,
            )
            .await
            .unwrap()
            .unwrap();
            assert!(verify_record(state, &expected).await.is_err());
            records.push(expected);
        }
        let before = state.store.sync_feed().head();
        verify_inner(state, request.clone()).await.unwrap();
        for expected in records {
            verify_record(state, &expected).await.unwrap();
        }
        assert!(
            state
                .store
                .manifest(&segment.artifact_id)
                .unwrap()
                .is_some()
        );
        assert_eq!(
            state.store.sync_feed().head(),
            before,
            "sibling repair must not echo arrivals"
        );
        assert_eq!(
            state.store.handover_hold.lock().unwrap().as_deref(),
            Some("repair")
        );
        assert!(
            state.runtime.authority.barrier.lock().unwrap().is_none(),
            "repair alone is not a receipt"
        );
        // A retry after freezing is idempotent and needs no peer I/O.
        server.abort();
        verify_inner(state, request).await.unwrap();
    }

    #[tokio::test]
    async fn retained_repair_reclaims_destination_only_segments_before_fetching() {
        use crate::segment::{reference::SegmentReference, state::SegmentState};
        use std::sync::{Arc, atomic::AtomicUsize};

        for listing_fails in [false, true] {
            let source = test_context(|_| {}).await;
            let target = test_context(|config| config.cas_capacity_bytes = Some(1)).await;
            let mut resident_id = String::new();
            let mut resident_segment = String::new();
            for ctx in [&source, &target] {
                ctx.state
                    .store
                    .apply_replicated_artifact_from_bytes(
                        ArtifactProducer::Gradle,
                        "ios",
                        "shared",
                        "application/octet-stream",
                        b"shared",
                        3000,
                    )
                    .await
                    .unwrap();
                resident_id = crate::utils::artifact_storage_id(
                    ArtifactProducer::Gradle,
                    "test-tenant",
                    "ios",
                    "shared",
                );
                resident_segment = ctx
                    .state
                    .store
                    .manifest(&resident_id)
                    .unwrap()
                    .unwrap()
                    .segment_id
                    .unwrap();
            }
            target
                .state
                .store
                .install_segment_state_for_testing(SegmentState {
                    old: vec![SegmentReference::new(resident_segment.clone(), 1)],
                    new: vec![SegmentReference::new("divergent".into(), 2)],
                    ..Default::default()
                })
                .await
                .unwrap();
            target
                .state
                .store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Gradle,
                    "ios",
                    "destination-only",
                    "application/octet-stream",
                    b"extra",
                    1,
                )
                .await
                .unwrap();
            let extra_id = crate::utils::artifact_storage_id(
                ArtifactProducer::Gradle,
                "test-tenant",
                "ios",
                "destination-only",
            );
            target
                .state
                .store
                .install_segment_state_for_testing(SegmentState {
                    old: vec![SegmentReference::new(resident_segment, 1)],
                    current: vec![SegmentReference::new("divergent".into(), 2)],
                    new: vec![SegmentReference::new("active".into(), 3)],
                })
                .await
                .unwrap();
            target
                .state
                .store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Gradle,
                    "ios",
                    "active-only",
                    "application/octet-stream",
                    b"active",
                    1,
                )
                .await
                .unwrap();
            source
                .state
                .store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Gradle,
                    "ios",
                    "missing",
                    "application/octet-stream",
                    b"missing",
                    1000,
                )
                .await
                .unwrap();
            source.state.store.run_backfill_index_build().unwrap();
            let bodies = Arc::new(AtomicUsize::new(0));
            let count = bodies.clone();
            let destination = target.state.clone();
            let checked_extra = extra_id.clone();
            let checked_resident = resident_id.clone();
            let app = crate::http::router(source.state.clone()).layer(axum::middleware::from_fn(
                move |request: axum::extract::Request, next: axum::middleware::Next| {
                    let destination = destination.clone();
                    let extra = checked_extra.clone();
                    let resident = checked_resident.clone();
                    let count = count.clone();
                    async move {
                        if listing_fails && request.uri().path() == "/_internal/backfill/entries" {
                            return axum::response::IntoResponse::into_response(
                                StatusCode::INTERNAL_SERVER_ERROR,
                            );
                        }
                        if request.uri().path() == "/_internal/backfill/bodies" {
                            count.fetch_add(1, Ordering::SeqCst);
                            assert!(
                                destination.store.manifest(&extra).unwrap().is_none(),
                                "reclaim destination-only storage before downloading missing bodies"
                            );
                            assert!(
                                destination.store.manifest(&resident).unwrap().is_some(),
                                "never evict shared retained data to make room"
                            );
                        }
                        next.run(request).await
                    }
                },
            ));
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let request = begin_request(
                &target.state,
                format!("http://{}", listener.local_addr().unwrap()),
            );
            *source.state.store.handover_hold.lock().unwrap() = Some(request.intent.id.clone());
            let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
            let result = verify_inner(&target.state, request).await;
            if listing_fails {
                assert!(result.is_err());
                assert!(target.state.store.manifest(&extra_id).unwrap().is_some());
                assert!(target.state.store.handover_hold.lock().unwrap().is_none());
                assert_eq!(bodies.load(Ordering::SeqCst), 0);
            } else {
                result.unwrap();
                assert_eq!(bodies.load(Ordering::SeqCst), 1);
                for entry in source
                    .state
                    .store
                    .backfill_index_page(None, 10)
                    .unwrap()
                    .entries
                {
                    let expected = record(
                        &source.state,
                        entry.kind,
                        &entry.record_id,
                        entry.version_ms,
                    )
                    .await
                    .unwrap()
                    .unwrap();
                    verify_record(&target.state, &expected).await.unwrap();
                }
            }
            assert!(target.state.store.manifest(&resident_id).unwrap().is_some());
            let active = crate::utils::artifact_storage_id(
                ArtifactProducer::Gradle,
                "test-tenant",
                "ios",
                "active-only",
            );
            assert!(target.state.store.manifest(&active).unwrap().is_some());
            server.abort();
        }
    }

    #[tokio::test]
    async fn retained_repair_revisits_records_evicted_after_their_presence_check() {
        use crate::{
            segment::{reference::SegmentReference, state::SegmentState},
            utils::artifact_storage_id,
        };
        use bazel_remote_apis::build::bazel::remote::execution::v2::{
            ActionResult, Digest, OutputFile,
        };
        use prost::Message;
        use std::sync::{
            Arc,
            atomic::{AtomicBool, Ordering},
        };

        let source = test_context(|_| {}).await;
        let target = test_context(|_| {}).await;
        let digest = Digest {
            hash: "ab".repeat(32),
            size_bytes: 8,
        };
        let key = crate::utils::blob_key(&format!("{}/8", digest.hash));
        let action_key = format!("action_cache/{}/0", "cd".repeat(32));
        let action = ActionResult {
            output_files: vec![OutputFile {
                path: "out".into(),
                digest: Some(digest),
                ..Default::default()
            }],
            ..Default::default()
        }
        .encode_to_vec();
        for ctx in [&source, &target] {
            ctx.state
                .store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Reapi,
                    "ios",
                    &key,
                    "application/octet-stream",
                    b"retained",
                    3000,
                )
                .await
                .unwrap();
            ctx.state
                .store
                .apply_replicated_inline_artifact_from_bytes(
                    ArtifactProducer::Reapi,
                    "ios",
                    &action_key,
                    "application/x-protobuf",
                    &action,
                    4000,
                    None,
                    None,
                )
                .await
                .unwrap();
        }
        source
            .state
            .store
            .apply_replicated_artifact_from_bytes(
                ArtifactProducer::Gradle,
                "ios",
                "missing-old",
                "application/octet-stream",
                b"old",
                1000,
            )
            .await
            .unwrap();
        let blob_id = artifact_storage_id(ArtifactProducer::Reapi, "test-tenant", "ios", &key);
        let action_id =
            artifact_storage_id(ArtifactProducer::Reapi, "test-tenant", "ios", &action_key);
        let segment = target
            .state
            .store
            .manifest(&blob_id)
            .unwrap()
            .unwrap()
            .segment_id
            .unwrap();
        // Seal the resident segment without a large allocation. The real eviction
        // path will remove both its blob and the referencing action-cache entry.
        let ring = SegmentState {
            old: vec![SegmentReference::new(segment.clone(), 3000)],
            new: vec![SegmentReference::new("empty-active".into(), 5000)],
            ..Default::default()
        };
        target
            .state
            .store
            .install_segment_state_for_testing(ring)
            .await
            .unwrap();
        source.state.store.run_backfill_index_build().unwrap();
        let evicted = Arc::new(AtomicBool::new(false));
        let did_evict = evicted.clone();
        let destination = target.state.clone();
        let app = crate::http::router(source.state.clone()).layer(axum::middleware::from_fn(
            move |request: axum::extract::Request, next: axum::middleware::Next| {
                let destination = destination.clone();
                let segment = segment.clone();
                let action_id = action_id.clone();
                let did_evict = did_evict.clone();
                async move {
                    // Newest-first listing has already skipped the resident blob
                    // and action when the older missing body's request is sent.
                    if request.uri().path() == "/_internal/backfill/bodies"
                        && !did_evict.swap(true, Ordering::SeqCst)
                    {
                        destination.store.evict_segment_for_testing(&segment).await;
                        assert!(
                            destination
                                .store
                                .manifest_from_db(&action_id)
                                .unwrap()
                                .is_none()
                        );
                    }
                    next.run(request).await
                }
            },
        ));
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let request = begin_request(
            &target.state,
            format!("http://{}", listener.local_addr().unwrap()),
        );
        *source.state.store.handover_hold.lock().unwrap() = Some(request.intent.id.clone());
        let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        verify_inner(&target.state, request).await.unwrap();
        assert!(evicted.load(Ordering::SeqCst));
        let entries = source
            .state
            .store
            .backfill_index_page(None, 10)
            .unwrap()
            .entries;
        assert_eq!(entries.len(), 3);
        for entry in entries {
            let expected = record(
                &source.state,
                entry.kind,
                &entry.record_id,
                entry.version_ms,
            )
            .await
            .unwrap()
            .unwrap();
            verify_record(&target.state, &expected).await.unwrap();
        }
        assert_eq!(
            target.state.store.handover_hold.lock().unwrap().as_deref(),
            Some("repair")
        );
        assert!(
            target
                .state
                .runtime
                .authority
                .barrier
                .lock()
                .unwrap()
                .is_none()
        );
        server.abort();
    }

    #[tokio::test]
    async fn repeated_eviction_cannot_freeze_an_unconverged_destination() {
        use crate::segment::{reference::SegmentReference, state::SegmentState};
        use std::sync::{Arc, atomic::AtomicUsize};

        let target = test_context(|_| {}).await;
        let state = target.state.clone();
        let walks = Arc::new(AtomicUsize::new(0));
        let count = walks.clone();
        let app = axum::Router::new().fallback(move || {
            let state = state.clone();
            let count = count.clone();
            async move {
                let pass = count.fetch_add(1, Ordering::SeqCst);
                let artifact = state
                    .store
                    .persist_artifact_from_bytes(
                        ArtifactProducer::Gradle,
                        "ios",
                        "destination-only",
                        "application/octet-stream",
                        b"extra",
                    )
                    .await
                    .unwrap();
                let segment = artifact.segment_id.unwrap();
                state
                    .store
                    .install_segment_state_for_testing(SegmentState {
                        old: vec![SegmentReference::new(segment.clone(), 1)],
                        new: vec![SegmentReference::new(format!("empty-{pass}"), 2)],
                        ..Default::default()
                    })
                    .await
                    .unwrap();
                state.store.evict_segment_for_testing(&segment).await;
                Json(serde_json::json!({"entries": [], "next_after": null}))
            }
        });
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let mut request = begin_request(
            &target.state,
            format!("http://{}", listener.local_addr().unwrap()),
        );
        let mut grant = target.state.runtime.authority.intent().unwrap();
        grant.phase = "Serving".into();
        target
            .state
            .runtime
            .authority
            .install(grant.clone())
            .unwrap();
        let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        // Live preparation is a scheduling hint. Real concurrent evictions must
        // not make it wait for a quiet window while the source keeps writing.
        let preparation = Preparation {
            intent: request.intent.clone(),
            source: request.source.clone(),
            epoch: grant.epoch,
            complete: false,
            error: None,
        };
        tokio::time::timeout(
            Duration::from_secs(3),
            prepare_live_destination(&target.state, &preparation),
        )
        .await
        .expect("live preparation must finish despite concurrent eviction")
        .unwrap();
        assert!(walks.load(Ordering::SeqCst) > 0);
        assert!(target.state.store.handover_hold.lock().unwrap().is_none());
        assert!(
            target
                .state
                .runtime
                .authority
                .barrier
                .lock()
                .unwrap()
                .is_none()
        );

        // The exact same churn must still prevent the final frozen-corpus hold.
        let preparation_walks = walks.load(Ordering::SeqCst);
        request.intent.deadline_ms = crate::utils::now_ms() + 2_000;
        grant.phase = "Quiescing".into();
        grant.handover = Some(request.intent.clone());
        target.state.runtime.authority.install(grant).unwrap();
        let error =
            tokio::time::timeout(Duration::from_secs(5), verify_inner(&target.state, request))
                .await
                .unwrap()
                .unwrap_err();
        assert!(
            walks.load(Ordering::SeqCst) > preparation_walks + 1,
            "must exercise repeat walks"
        );
        assert!(error.contains("deadline mismatch"), "{error}");
        assert!(target.state.store.handover_hold.lock().unwrap().is_none());
        assert!(
            target
                .state
                .runtime
                .authority
                .barrier
                .lock()
                .unwrap()
                .is_none()
        );
        server.abort();
    }

    #[tokio::test]
    async fn retained_repair_copies_missing_records_older_than_the_evictee() {
        use crate::segment::{reference::SegmentReference, state::SegmentState};

        let source = test_context(|_| {}).await;
        let target = test_context(|config| config.cas_capacity_bytes = Some(1)).await;
        for (ctx, key, version) in [(&source, "newer", 1000), (&source, "older", 400)] {
            ctx.state
                .store
                .apply_replicated_artifact_from_bytes(
                    ArtifactProducer::Gradle,
                    "ios",
                    key,
                    "application/octet-stream",
                    b"retained body",
                    version,
                )
                .await
                .unwrap();
        }
        let mut ring = SegmentState::default();
        for (index, stat) in [500, 600, 650, 700, 750].into_iter().enumerate() {
            let mut reference =
                SegmentReference::new(format!("capacity-{index}"), index as u64 + 1);
            reference.max_version_ms = Some(stat);
            match index {
                0 => ring.old.push(reference),
                1 | 2 => ring.current.push(reference),
                _ => ring.new.push(reference),
            }
        }
        target
            .state
            .store
            .install_segment_state_for_testing(ring)
            .await
            .unwrap();
        let (url, server) = serve(source.state.clone()).await;
        let request = begin_request(&target.state, url);
        *source.state.store.handover_hold.lock().unwrap() = Some(request.intent.id.clone());
        let entries = source
            .state
            .store
            .backfill_index_page_ascending(0, None, 10, u64::MAX, None)
            .unwrap()
            .entries;
        assert_eq!(entries.len(), 2);
        let mut expected = Vec::new();
        for entry in entries {
            expected.push(
                record(
                    &source.state,
                    entry.kind,
                    &entry.record_id,
                    entry.version_ms,
                )
                .await
                .unwrap()
                .unwrap(),
            );
        }
        // Both records are missing. The recency heuristic would reject the
        // older one even though it fits in the active segment without eviction.
        assert!(expected.iter().any(|r| r.version == 1000));
        verify_inner(&target.state, request).await.unwrap();
        for record in expected {
            verify_record(&target.state, &record).await.unwrap();
        }
        assert_eq!(
            target.state.store.handover_hold.lock().unwrap().as_deref(),
            Some("repair")
        );
        server.abort();
    }

    #[tokio::test]
    async fn repair_preserves_newer_destination_version_and_verification_refuses_it() {
        let source = test_context(|_| {}).await;
        let target = test_context(|_| {}).await;
        for (ctx, version, body) in [
            (&source, 1000, b"old".as_slice()),
            (&target, 2000, b"new".as_slice()),
        ] {
            ctx.state
                .store
                .apply_replicated_inline_artifact_from_bytes(
                    ArtifactProducer::Xcode,
                    "ios",
                    "same-key",
                    "text/plain",
                    body,
                    version,
                    None,
                    None,
                )
                .await
                .unwrap();
        }
        let (url, server) = serve(source.state.clone()).await;
        let entry = source
            .state
            .store
            .backfill_index_page_ascending(0, None, 1, u64::MAX, None)
            .unwrap()
            .entries
            .remove(0);
        let expected = record(
            &source.state,
            entry.kind,
            &entry.record_id,
            entry.version_ms,
        )
        .await
        .unwrap()
        .unwrap();
        verify_inner(&target.state, begin_request(&target.state, url))
            .await
            .unwrap();
        assert_eq!(
            target
                .state
                .store
                .manifest(&entry.record_id)
                .unwrap()
                .unwrap()
                .version_ms,
            2000
        );
        let error = verify_record(&target.state, &expected).await.unwrap_err();
        assert!(error.contains("actual_version=Some(2000)"), "{error}");
        assert!(
            target
                .state
                .runtime
                .authority
                .barrier
                .lock()
                .unwrap()
                .is_none()
        );
        server.abort();
    }

    #[tokio::test]
    async fn disconnected_begin_keeps_one_repair_until_authority_cancels_it() {
        for stop in ["complete", "abort", "deadline", "drain"] {
            let target = test_context(|_| {}).await;
            let entered = std::sync::Arc::new(tokio::sync::Notify::new());
            let release = std::sync::Arc::new(tokio::sync::Notify::new());
            let requests = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let url = format!("http://{}", listener.local_addr().unwrap());
            let app = axum::Router::new().fallback({
                let entered = entered.clone();
                let release = release.clone();
                let requests = requests.clone();
                move || {
                    let entered = entered.clone();
                    let release = release.clone();
                    let requests = requests.clone();
                    async move {
                        requests.fetch_add(1, Ordering::SeqCst);
                        entered.notify_one();
                        release.notified().await;
                        Json(serde_json::json!({"entries": [], "next_after": null}))
                    }
                }
            });
            let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
            let mut request = begin_request(&target.state, url);
            if stop == "deadline" {
                request.intent.deadline_ms = crate::utils::now_ms() + 1_000;
                let mut grant = target.state.runtime.authority.intent().unwrap();
                grant.handover = Some(request.intent.clone());
                target.state.runtime.authority.install(grant).unwrap();
            }
            let state = target.state.clone();
            let first = request.clone();
            let caller = tokio::spawn(async move { verify(State(state), Json(first)).await });
            tokio::time::timeout(Duration::from_secs(5), entered.notified())
                .await
                .unwrap();
            caller.abort();
            assert!(caller.await.unwrap_err().is_cancelled());
            assert!(
                target
                    .state
                    .runtime
                    .authority
                    .handover_preparation
                    .try_lock()
                    .is_err(),
                "{stop}: caller cancellation must not abandon the repair"
            );
            let rejection = verify(State(target.state.clone()), Json(request.clone()))
                .await
                .unwrap_err();
            assert!(
                rejection.1.contains("reconciliation in progress"),
                "{rejection:?}"
            );
            assert_eq!(requests.load(Ordering::SeqCst), 1);
            match stop {
                "complete" => release.notify_one(),
                "abort" => {
                    let mut grant = target.state.runtime.authority.intent().unwrap();
                    grant.phase = "Serving".into();
                    grant.handover = None;
                    target.state.runtime.authority.install(grant).unwrap();
                }
                "deadline" => {}
                "drain" => {
                    target.state.runtime.request_drain();
                }
                _ => unreachable!(),
            }
            tokio::time::timeout(Duration::from_secs(3), async {
                loop {
                    if target
                        .state
                        .runtime
                        .authority
                        .handover_preparation
                        .try_lock()
                        .is_ok()
                    {
                        break;
                    }
                    tokio::time::sleep(Duration::from_millis(10)).await;
                }
            })
            .await
            .unwrap();
            if stop == "complete" {
                assert_eq!(
                    target.state.store.handover_hold.lock().unwrap().as_deref(),
                    Some("repair")
                );
                let response = verify(State(target.state.clone()), Json(request))
                    .await
                    .unwrap();
                assert_eq!(response.0["max_batch_records"], MAX_BATCH_RECORDS);
                assert_eq!(requests.load(Ordering::SeqCst), 1);
            } else {
                assert!(
                    target.state.store.handover_hold.lock().unwrap().is_none(),
                    "{stop}"
                );
            }
            assert!(
                target
                    .state
                    .runtime
                    .authority
                    .barrier
                    .lock()
                    .unwrap()
                    .is_none()
            );
            server.abort();
        }
    }

    #[tokio::test]
    async fn abort_or_deadline_cancels_repair_and_never_freezes_destination() {
        for abort in [true, false] {
            let target = test_context(|_| {}).await;
            let entered = std::sync::Arc::new(tokio::sync::Notify::new());
            let signal = entered.clone();
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let url = format!("http://{}", listener.local_addr().unwrap());
            let app = axum::Router::new().fallback(move || {
                let signal = signal.clone();
                async move {
                    signal.notify_one();
                    std::future::pending::<StatusCode>().await
                }
            });
            let server = tokio::spawn(async move {
                axum::serve(listener, app).await.unwrap();
            });
            let mut request = begin_request(&target.state, url);
            if !abort {
                request.intent.deadline_ms = crate::utils::now_ms() + 1_000;
                let mut grant = target.state.runtime.authority.intent().unwrap();
                grant.handover = Some(request.intent.clone());
                target.state.runtime.authority.install(grant).unwrap();
            }
            let concurrent = request.clone();
            let state = target.state.clone();
            let repair = tokio::spawn(async move { verify_inner(&state, request).await });
            tokio::time::timeout(Duration::from_secs(5), entered.notified())
                .await
                .unwrap();
            assert!(
                verify_inner(&target.state, concurrent)
                    .await
                    .unwrap_err()
                    .contains("reconciliation in progress")
            );
            let mut grant = target.state.runtime.authority.intent().unwrap();
            if abort {
                grant.phase = "Serving".into();
                grant.handover = None;
                target.state.runtime.authority.install(grant).unwrap();
            }
            let error = tokio::time::timeout(Duration::from_secs(2), repair)
                .await
                .unwrap()
                .unwrap()
                .unwrap_err();
            assert!(
                error.contains("identity, phase or deadline mismatch"),
                "{error}"
            );
            assert!(target.state.store.handover_hold.lock().unwrap().is_none());
            assert!(
                target
                    .state
                    .runtime
                    .authority
                    .barrier
                    .lock()
                    .unwrap()
                    .is_none()
            );
            assert!(
                target
                    .state
                    .runtime
                    .authority
                    .handover_preparation
                    .try_lock()
                    .is_ok()
            );
            server.abort();
        }
    }

    #[tokio::test]
    async fn peer_rejection_keeps_stage_record_and_bounded_reason() {
        let ctx = test_context(|_| {}).await;
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let app = axum::Router::new().route(
            "/_internal/handover/verify",
            axum::routing::post(|| async {
                (
                    StatusCode::CONFLICT,
                    format!("version mismatch {}", "é".repeat(2048)),
                )
            }),
        );
        let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        let holder = ctx.state.runtime.authority.identity().clone();
        let intent = Intent {
            id: "diagnostics".into(),
            destination: holder.clone(),
            destination_url: format!("http://{address}"),
            source_url: "http://source".into(),
            deadline_ms: crate::utils::now_ms() + 300_000,
        };
        let request = VerifyRequest {
            begin: false,
            intent: intent.clone(),
            source: holder,
            records: Vec::new(),
            record: Some(Record {
                kind: "segment".into(),
                id: "artifact-id".into(),
                version: 17,
                size: 42,
                digest: "expected-digest".into(),
            }),
            receipt: None,
        };
        let error = send(&ctx.state, &intent, &request).await.unwrap_err();
        server.abort();
        assert!(error.contains("409 Conflict"), "{error}");
        assert!(
            error.contains("record kind=segment id=\"artifact-id\" version=17 size=42"),
            "{error}"
        );
        assert!(error.contains("version mismatch"), "{error}");
        assert!(error.chars().count() < 1200);
    }

    #[tokio::test]
    async fn named_barrier_checks_inline_segment_tombstone_and_holds_corpus() {
        let ctx = test_context(|config| {
            config.serving_authority = Some(crate::serving_authority::AuthorityConfig {
                instance: "test".into(),
                namespace: "test".into(),
                instance_uid: "test".into(),
                pod_uid: "test".into(),
                host: "test".into(),
            });
        })
        .await;
        let state = &ctx.state;
        let inline = state
            .store
            .persist_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "test/project",
                "inline",
                "text/plain",
                b"inline",
            )
            .await
            .unwrap();
        let segment = state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "test/project",
                "segment",
                "application/octet-stream",
                &vec![42; 128 * 1024],
            )
            .await
            .unwrap();
        state.store.delete_namespace("test/deleted").await.unwrap();
        let tombstone = state
            .store
            .namespace_tombstone_version("test/deleted")
            .unwrap()
            .unwrap();
        let mut stale = inline.clone();
        stale.version_ms -= 1;
        state.store.seed_stale_manifest_cache(stale.clone());
        assert_eq!(
            state
                .store
                .manifest(&inline.artifact_id)
                .unwrap()
                .unwrap()
                .version_ms,
            stale.version_ms
        );
        assert!(
            record(
                state,
                BackfillRecordKind::InlineArtifact,
                &inline.artifact_id,
                inline.version_ms
            )
            .await
            .unwrap()
            .is_some()
        );
        let mut source = state.runtime.authority.identity().clone();
        source.pod_uid = "source".into();
        let (source_url, server) = serve(state.clone()).await;
        let intent = Intent {
            id: "named".into(),
            destination: state.runtime.authority.identity().clone(),
            source_url,
            destination_url: "http://destination".into(),
            deadline_ms: crate::utils::now_ms() + 300_000,
        };
        let grant = Grant {
            epoch: 1,
            holder: source.clone(),
            phase: "Quiescing".into(),
            expires_ms: crate::utils::now_ms() + 15_000,
            handover: Some(intent.clone()),
            barrier: None,
            resume_epoch: None,
        };
        let _ = state.runtime.authority.install(grant);
        let receipt = Receipt {
            id: intent.id.clone(),
            source: source.clone(),
            destination: intent.destination.clone(),
            incarnation: 7,
            head: 9,
            frontier_ms: 100,
            records: 3,
            digest: "full-corpus".into(),
        };
        let request = |begin, record, receipt| VerifyRequest {
            begin,
            intent: intent.clone(),
            source: source.clone(),
            records: Vec::new(),
            record,
            receipt,
        };
        assert!(
            verify_inner(state, request(true, None, Some(receipt.clone())))
                .await
                .is_err()
        );
        state
            .store
            .write_sync_cursor(
                &intent.source_url,
                SyncPosition {
                    incarnation: 7,
                    seq: 9,
                },
            )
            .unwrap();
        verify_inner(state, request(true, None, Some(receipt.clone())))
            .await
            .unwrap();
        let mut records = Vec::new();
        for (kind, id, version) in [
            (
                BackfillRecordKind::InlineArtifact,
                inline.artifact_id.as_str(),
                inline.version_ms,
            ),
            (
                BackfillRecordKind::SegmentArtifact,
                segment.artifact_id.as_str(),
                segment.version_ms,
            ),
            (
                BackfillRecordKind::NamespaceTombstone,
                "test/deleted",
                tombstone,
            ),
        ] {
            let expected = record(state, kind, id, version).await.unwrap().unwrap();
            records.push(expected.clone());
            let mut wrong = expected.clone();
            wrong.digest.push('0');
            let error = verify_inner(state, request(false, Some(wrong), None))
                .await
                .unwrap_err();
            assert!(error.contains("retained record content mismatch"));
            assert!(error.contains(&format!("actual_digest={}", expected.digest)));
            verify_inner(state, request(false, Some(expected), None))
                .await
                .unwrap();
        }
        let mut batch = request(false, None, None);
        batch.records = records.clone();
        let answer = verify_inner(state, batch).await.unwrap();
        assert_eq!(answer["verified_records"], 3);
        let mut batch = request(false, None, None);
        batch.records = records.clone();
        batch.records[2].digest.push('0');
        let error = verify_inner(state, batch).await.unwrap_err();
        assert!(
            error.contains("test/deleted") && error.contains("content mismatch"),
            "{error}"
        );
        let mut batch = request(false, None, None);
        batch.records = vec![records[0].clone(); MAX_BATCH_RECORDS + 1];
        assert!(
            verify_inner(state, batch)
                .await
                .unwrap_err()
                .contains("invalid retained record batch")
        );
        let mut batch = request(false, Some(records[0].clone()), None);
        batch.records = records;
        assert!(
            verify_inner(state, batch)
                .await
                .unwrap_err()
                .contains("invalid retained record batch")
        );
        assert!(
            state
                .store
                .persist_inline_artifact_from_bytes(
                    ArtifactProducer::Xcode,
                    "test/project",
                    "later",
                    "text/plain",
                    b"later"
                )
                .await
                .is_err()
        );
        assert!(state.store.delete_namespace("test/project").await.is_err());
        verify_inner(state, request(false, None, Some(receipt.clone())))
            .await
            .unwrap();
        assert_eq!(
            *state.runtime.authority.barrier.lock().unwrap(),
            Some(receipt)
        );
        let mut wrong_destination = request(false, None, None);
        wrong_destination.intent.destination.incarnation.push('x');
        assert!(verify_inner(state, wrong_destination).await.is_err());
        server.abort();
    }
    #[tokio::test]
    async fn batches_require_complete_acknowledgments_and_legacy_requests_stay_individual() {
        let ctx = test_context(|_| {}).await;
        for (batched, complete) in [(true, true), (true, false), (false, true)] {
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let address = listener.local_addr().unwrap();
            let holder = ctx.state.runtime.authority.identity().clone();
            let destination = holder.clone();
            let app = axum::Router::new().route("/_internal/handover/verify", axum::routing::post(
                move |Json(request): Json<VerifyRequest>| {
                    let destination = destination.clone();
                    async move {
                        if batched {
                            assert!(request.record.is_none());
                            assert_eq!(request.records.len(), 2);
                            Json(serde_json::json!({"destination": destination, "verified_records": if complete { 2 } else { 1 }}))
                        } else {
                            assert!(request.record.is_some());
                            assert!(request.records.is_empty());
                            // The preceding runtime does not send a record count.
                            Json(serde_json::json!({"destination": destination}))
                        }
                    }
                }
            ));
            let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
            let intent = Intent {
                id: "batch".into(),
                destination: holder.clone(),
                destination_url: format!("http://{address}"),
                source_url: "http://source".into(),
                deadline_ms: crate::utils::now_ms() + 300_000,
            };
            let records = vec![
                Record {
                    kind: "inline".into(),
                    id: "record".into(),
                    version: 1,
                    size: 1,
                    digest: "digest".into()
                };
                if batched { 2 } else { 1 }
            ];
            let result = send_records(&ctx.state, &intent, &holder, records, batched).await;
            server.abort();
            assert_eq!(result.is_ok(), complete, "{result:?}");
        }
    }
}
