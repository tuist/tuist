//! Named, retained-corpus handover verification. A feed cursor alone can skip
//! capacity-rejected data, so every retained body and metadata record is checked.
use crate::{
    http::BackfillBodyManifestMeta, serving_authority::Holder, state::SharedState,
    store::manifest_version_ms, utils::BackfillRecordKind,
};
use axum::{Json, extract::State, http::StatusCode};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::time::Duration;

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
}

#[derive(Deserialize, Serialize)]
pub struct VerifyRequest {
    #[serde(default)]
    begin: bool,
    intent: Intent,
    source: Holder,
    record: Option<Record>,
    receipt: Option<Receipt>,
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
    verify_inner(&state, request)
        .await
        .map(Json)
        .map_err(|e| (StatusCode::CONFLICT, e))
}

async fn verify_inner(
    state: &SharedState,
    request: VerifyRequest,
) -> Result<serde_json::Value, String> {
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
        return Ok(serde_json::json!({"destination": authority.identity()}));
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
    if let Some(expected) = request.record {
        let kind = BackfillRecordKind::from_wire_name(&expected.kind)
            .ok_or("unknown retained record kind")?;
        let actual = record(state, kind, &expected.id, expected.version)
            .await?
            .ok_or("retained record missing or version differs")?;
        if actual.size != expected.size || actual.digest != expected.digest {
            return Err("retained record content mismatch".into());
        }
        return Ok(serde_json::json!({"destination": authority.identity()}));
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
        return Err(format!("destination rejected handover: {status}"));
    }
    serde_json::from_slice(&bytes).map_err(|e| e.to_string())
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
    send(
        state,
        intent,
        &VerifyRequest {
            begin: true,
            intent: intent.clone(),
            source: receipt.source.clone(),
            record: None,
            receipt: Some(receipt.clone()),
        },
    )
    .await?;
    loop {
        let page = state.store.backfill_index_page(after.as_deref(), 32)?;
        for row in page.entries {
            // Stale index rows are not retained objects. Only the exact current
            // tuple is verified, and all subsequent pages are still visited.
            let Some(value) = record(state, row.kind, &row.record_id, row.version_ms).await? else {
                continue;
            };
            let encoded = serde_json::to_vec(&value).map_err(|e| e.to_string())?;
            digest.update((encoded.len() as u64).to_be_bytes());
            digest.update(encoded);
            let answer = send(
                state,
                intent,
                &VerifyRequest {
                    begin: false,
                    intent: intent.clone(),
                    source: receipt.source.clone(),
                    record: Some(value),
                    receipt: None,
                },
            )
            .await?;
            if answer["destination"]
                != serde_json::to_value(&intent.destination).map_err(|e| e.to_string())?
            {
                return Err("destination incarnation changed".into());
            }
            receipt.records += 1;
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
            let mut wrong = expected.clone();
            wrong.digest.push('0');
            assert!(
                verify_inner(state, request(false, Some(wrong), None))
                    .await
                    .is_err()
            );
            verify_inner(state, request(false, Some(expected), None))
                .await
                .unwrap();
        }
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
}
