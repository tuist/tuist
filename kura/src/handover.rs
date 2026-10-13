//! Named, retained-corpus handover verification. A feed cursor alone can skip
//! capacity-rejected data, so every retained body and metadata record is checked.
//! A record the destination lacks passes only when the destination dropped it
//! for a node-local reason replication does not carry: capacity eviction, a
//! capacity-declined fetch, action-cache expiry, or the cascade that removes
//! entries and recipes whose referenced blobs it evicted.
use crate::{
    artifact::producer::ArtifactProducer,
    backfill::window::capacity_complete,
    constants::REAPI_ACTION_CACHE_TTL_MS,
    http::BackfillBodyManifestMeta,
    reapi::chunking::is_recipe_key,
    serving_authority::Holder,
    state::SharedState,
    store::manifest_version_ms,
    utils::{BackfillRecordKind, action_cache_manifest_hash},
};
use axum::{Json, extract::State, http::StatusCode};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{collections::BTreeMap, time::Duration};

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
    /// Set by the source for records a replica removes once a blob they
    /// reference is gone. Absent from older sources, which keeps the strict check.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    derived: Option<Derived>,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum DerivedKind {
    ActionCacheEntry,
    ChunkRecipe,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct Derived {
    kind: DerivedKind,
    blobs: Vec<String>,
}

#[derive(Deserialize, Serialize)]
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
                derived: None,
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
    let derived_kind = derived_kind(&manifest);
    let mut body = Vec::new();
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
        if derived_kind.is_some() {
            body.extend_from_slice(&chunk);
        }
    }
    if bytes != manifest.size {
        return Err("retained body length mismatch".into());
    }
    let derived = derived_kind.map(|kind| Derived {
        kind,
        blobs: match kind {
            DerivedKind::ActionCacheEntry => state
                .store
                .action_cache_entry_blob_ids(&manifest.namespace_id, &body),
            DerivedKind::ChunkRecipe => {
                state
                    .store
                    .chunk_recipe_blob_ids(&manifest.namespace_id, &manifest.key, &body)
            }
        },
    });
    Ok(Some(Record {
        kind: kind.as_str().into(),
        id: id.into(),
        version,
        size: bytes,
        digest: format!("{:x}", digest.finalize()),
        derived,
    }))
}

fn derived_kind(manifest: &crate::artifact::manifest::ArtifactManifest) -> Option<DerivedKind> {
    if manifest.producer != ArtifactProducer::Reapi || !manifest.inline {
        None
    } else if action_cache_manifest_hash(&manifest.key).is_some() {
        Some(DerivedKind::ActionCacheEntry)
    } else if is_recipe_key(&manifest.key) {
        Some(DerivedKind::ChunkRecipe)
    } else {
        None
    }
}

/// Why the destination may lack `expected` although the source retains it,
/// or `None` when the absence is a replication gap. Only called once no local
/// manifest exists at any version.
fn dropped_locally(state: &SharedState, expected: &Record) -> Result<Option<&'static str>, String> {
    let store = &state.store;
    if expected.kind == BackfillRecordKind::SegmentArtifact.as_str() {
        if expected.version <= store.capacity_dropped_through_ms() {
            return Ok(Some("evicted"));
        }
        let inputs = store.backfill_capacity_inputs();
        if capacity_complete(
            inputs.segment_count,
            inputs.ring_total_segments,
            inputs.next_evictee_stat_ms,
            expected.version,
        ) {
            return Ok(Some("capacity_declined"));
        }
    }
    let Some(derived) = &expected.derived else {
        return Ok(None);
    };
    if derived.kind == DerivedKind::ActionCacheEntry
        && expected.version < crate::utils::now_ms().saturating_sub(REAPI_ACTION_CACHE_TTL_MS)
    {
        return Ok(Some("expired"));
    }
    for blob in &derived.blobs {
        if store.manifest_from_db(blob)?.is_none() {
            return Ok(Some("dead_reference"));
        }
    }
    Ok(None)
}

pub async fn verify(
    State(state): State<SharedState>,
    Json(request): Json<VerifyRequest>,
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
    let grant = authority.intent().ok_or("no handover intent")?;
    if grant.phase != "Quiescing"
        || grant.holder != request.source
        || grant.handover.as_ref() != Some(&request.intent)
        || request.intent.destination != *authority.identity()
        || crate::utils::now_ms() >= request.intent.deadline_ms
    {
        return Err("handover identity, phase or deadline mismatch".into());
    }
    if request.begin {
        let receipt = request.receipt.as_ref().ok_or("missing source position")?;
        let mut hold = state
            .store
            .handover_hold
            .lock()
            .map_err(|_| "handover hold poisoned")?;
        let cursor = state
            .store
            .sync_cursor(&request.intent.source_url)?
            .ok_or("missing source cursor")?;
        if cursor.incarnation != receipt.incarnation || cursor.seq < receipt.head {
            return Err("source feed not yet applied".into());
        }
        if hold.as_ref().is_some_and(|id| id != &request.intent.id) {
            return Err("another handover owns the retained corpus".into());
        }
        *hold = Some(request.intent.id.clone());
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
        let mut dropped = BTreeMap::<&'static str, u64>::new();
        for expected in records {
            if let Some(reason) = verify_record(state, &expected)
                .await
                .map_err(|error| format!("{}; {error}", record_context(&expected)))?
            {
                *dropped.entry(reason).or_default() += 1;
            }
            count += 1;
        }
        return Ok(serde_json::json!({
            "destination": authority.identity(),
            "verified_records": count,
            "dropped": dropped,
        }));
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

/// `Some(reason)` when the destination lacks the record because it dropped it
/// locally.
async fn verify_record(
    state: &SharedState,
    expected: &Record,
) -> Result<Option<&'static str>, String> {
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
            if version.is_none()
                && kind != BackfillRecordKind::NamespaceTombstone
                && let Some(reason) = dropped_locally(state, expected)?
            {
                return Ok(Some(reason));
            }
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
    Ok(None)
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
    dropped: &mut BTreeMap<String, u64>,
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
    if let Some(reasons) = answer["dropped"].as_object() {
        for (reason, records) in reasons {
            *dropped.entry(bounded_detail(reason)).or_default() += records.as_u64().unwrap_or(0);
        }
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
    let mut dropped = BTreeMap::<String, u64>::new();
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
                    &mut dropped,
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
                    &mut dropped,
                )
                .await?;
                body_bytes = 0;
                metadata_bytes = 0;
            }
        }
        if !batch.is_empty() {
            send_records(
                state,
                intent,
                &receipt.source,
                batch,
                batch_size > 1,
                &mut dropped,
            )
            .await?;
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
    tracing::info!(
        event.name = "kura.handover.prepared",
        id = %intent.id,
        records = receipt.records,
        ?dropped,
        "Retained-corpus barrier prepared"
    );
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
            let Some(intent) = grant.handover else {
                continue;
            };
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
                derived: None,
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
        let intent = Intent {
            id: "named".into(),
            destination: state.runtime.authority.identity().clone(),
            source_url: "http://source".into(),
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
                    digest: "digest".into(),
                    derived: None,
                };
                if batched { 2 } else { 1 }
            ];
            let result = send_records(
                &ctx.state,
                &intent,
                &holder,
                records,
                batched,
                &mut BTreeMap::new(),
            )
            .await;
            server.abort();
            assert_eq!(result.is_ok(), complete, "{result:?}");
        }
    }

    #[tokio::test]
    async fn destination_accepts_only_records_it_dropped_locally() {
        use bazel_remote_apis::build::bazel::remote::execution::v2 as reapi;
        use prost::Message;

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
        let present_hash = "ab".repeat(32);
        let absent_hash = "cd".repeat(32);
        let blob = state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                "test/project",
                &format!("blob/{present_hash}/5"),
                "application/octet-stream",
                b"hello",
            )
            .await
            .unwrap();
        let digest = |hash: &str, size_bytes| reapi::Digest {
            hash: hash.into(),
            size_bytes,
        };
        let action_result = reapi::ActionResult {
            output_files: vec![reapi::OutputFile {
                path: "out".into(),
                digest: Some(digest(&present_hash, 5)),
                ..Default::default()
            }],
            stdout_digest: Some(digest(&absent_hash, 7)),
            ..Default::default()
        };
        let entry = state
            .store
            .persist_inline_artifact_from_bytes(
                ArtifactProducer::Reapi,
                "test/project",
                &format!("action_cache/{}/10", "ef".repeat(32)),
                "application/octet-stream",
                &action_result.encode_to_vec(),
            )
            .await
            .unwrap();
        let sourced = record(
            state,
            BackfillRecordKind::InlineArtifact,
            &entry.artifact_id,
            entry.version_ms,
        )
        .await
        .unwrap()
        .unwrap();
        let derived = sourced.derived.clone().unwrap();
        assert_eq!(derived.kind, DerivedKind::ActionCacheEntry);
        assert_eq!(derived.blobs.len(), 2);
        assert!(derived.blobs.contains(&blob.artifact_id));
        let absent_blob = derived
            .blobs
            .iter()
            .find(|id| **id != blob.artifact_id)
            .unwrap()
            .clone();

        let mut evicted = crate::segment::reference::SegmentReference::new("evicted".into(), 1);
        evicted.max_version_ms = Some(5_000);
        state
            .store
            .retire_segment_for_testing(evicted)
            .await
            .unwrap();

        let mut source = state.runtime.authority.identity().clone();
        source.pod_uid = "source".into();
        let intent = Intent {
            id: "drops".into(),
            destination: state.runtime.authority.identity().clone(),
            source_url: "http://source".into(),
            destination_url: "http://destination".into(),
            deadline_ms: crate::utils::now_ms() + 300_000,
        };
        let _ = state.runtime.authority.install(Grant {
            epoch: 1,
            holder: source.clone(),
            phase: "Quiescing".into(),
            expires_ms: crate::utils::now_ms() + 15_000,
            handover: Some(intent.clone()),
            barrier: None,
            resume_epoch: None,
        });
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
        let request = |begin, records: Vec<Record>, receipt| VerifyRequest {
            begin,
            intent: intent.clone(),
            source: source.clone(),
            record: None,
            records,
            receipt,
        };
        verify_inner(
            state,
            request(
                true,
                Vec::new(),
                Some(Receipt {
                    id: intent.id.clone(),
                    source: source.clone(),
                    destination: intent.destination.clone(),
                    incarnation: 7,
                    head: 9,
                    frontier_ms: 100,
                    records: 0,
                    digest: String::new(),
                }),
            ),
        )
        .await
        .unwrap();

        let now = crate::utils::now_ms();
        let missing = |kind: BackfillRecordKind, id: &str, version, derived| Record {
            kind: kind.as_str().into(),
            id: id.into(),
            version,
            size: 10,
            digest: "source-digest".into(),
            derived,
        };
        let action_cache = |blobs: Vec<String>| {
            Some(Derived {
                kind: DerivedKind::ActionCacheEntry,
                blobs,
            })
        };

        let accepted = vec![
            missing(BackfillRecordKind::SegmentArtifact, "evicted", 4_000, None),
            missing(
                BackfillRecordKind::InlineArtifact,
                "cascaded",
                now,
                action_cache(vec![blob.artifact_id.clone(), absent_blob.clone()]),
            ),
            missing(
                BackfillRecordKind::InlineArtifact,
                "expired",
                1,
                action_cache(vec![blob.artifact_id.clone()]),
            ),
        ];
        let answer = verify_inner(state, request(false, accepted, None))
            .await
            .unwrap();
        assert_eq!(answer["verified_records"], 3);
        assert_eq!(
            answer["dropped"],
            serde_json::json!({"dead_reference": 1, "evicted": 1, "expired": 1})
        );

        for record in [
            missing(BackfillRecordKind::InlineArtifact, "gap", now, None),
            missing(BackfillRecordKind::SegmentArtifact, "recent", now, None),
            missing(
                BackfillRecordKind::InlineArtifact,
                "live-entry",
                now,
                action_cache(vec![blob.artifact_id.clone()]),
            ),
            missing(
                BackfillRecordKind::InlineArtifact,
                "inline-old",
                4_000,
                None,
            ),
            missing(
                BackfillRecordKind::NamespaceTombstone,
                "test/never-deleted",
                4_000,
                None,
            ),
            missing(
                BackfillRecordKind::SegmentArtifact,
                &blob.artifact_id,
                4_000,
                None,
            ),
        ] {
            let error = verify_inner(state, request(false, vec![record], None))
                .await
                .unwrap_err();
            assert!(error.contains("retained record missing"), "{error}");
        }
    }
}
