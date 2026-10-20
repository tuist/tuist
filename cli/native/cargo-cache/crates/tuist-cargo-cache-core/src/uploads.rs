//! Deferred remote publication for a build session.
//!
//! Publishing a compilation result is not on the critical path of the build that
//! produced it: the local CAS already holds every object before the shim is told
//! the result was stored. Uploading inside that request would make every miss
//! wait for a round trip that only later builds benefit from, and Cargo cannot
//! schedule a dependent crate until the wrapper it is waiting on exits.
//!
//! This module accepts uploads into a queue instead, hands each caller a ticket
//! it can await, and drains the queue before the session exits. The queue also
//! gives the client one place where several pending blobs are visible at once,
//! which is what lets them be coalesced into a single request.
//!
//! # Ordering
//!
//! A remote action result may only be published once every blob it references is
//! visible remotely; a server validates the output tree before committing one.
//! Deferring uploads removes the transport ordering that used to guarantee that,
//! so an action result carries the tickets of the blobs enqueued before it and
//! waits for them itself.

use crate::{
    ActionDiagnostic, BlobPackLimits, BlobSource, BlobUpload, CacheDigest, RemoteActionResult,
    RemoteCacheClient,
};
use futures_util::future::{BoxFuture, Shared};
use futures_util::{FutureExt, StreamExt, stream};
use log::warn;
use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

/// Uploads performed concurrently by the background queue.
///
/// Deliberately below the agent's overall remote transfer budget: a queue
/// working through a large build's output must not crowd out the foreground
/// downloads a later compilation is waiting on.
const MAX_UPLOAD_TRANSFERS: usize = 32;

/// How one queued upload finished.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum UploadOutcome {
    /// The object is now visible to the remote cache.
    Uploaded,
    /// There was nothing to upload, so nothing depends on this having happened.
    ///
    /// A local object collected between its store and its upload produces this:
    /// the blob it would have published no longer exists to read.
    Skipped,
    /// The upload was attempted and did not succeed.
    Failed,
}

impl UploadOutcome {
    fn published(self) -> bool {
        matches!(self, Self::Uploaded)
    }
}

/// A handle for awaiting one queued upload, shared by everything that depends on
/// it.
pub(crate) type UploadTicket = Shared<BoxFuture<'static, UploadOutcome>>;

/// Tickets for the uploads a single agent connection has queued so far.
///
/// A shim publishes every blob of a compilation before the action result that
/// references them, over one connection, so this is exactly the set an action
/// result must wait for -- including the directory objects that name the rest.
#[derive(Default)]
pub(crate) struct ConnectionUploads {
    tickets: Vec<UploadTicket>,
    /// Diagnostic sent immediately before its action-accounting request.
    action_diagnostic: Option<(String, Option<String>, ActionDiagnostic)>,
    /// A bypass reason still waiting for the compiler run it describes.
    bypass: Option<String>,
}

impl ConnectionUploads {
    fn record(&mut self, ticket: UploadTicket) {
        self.tickets.push(ticket);
    }

    fn prerequisites(&self) -> Vec<UploadTicket> {
        self.tickets.clone()
    }

    pub(crate) fn record_action_diagnostic(
        &mut self,
        outcome: String,
        crate_name: Option<String>,
        diagnostic: ActionDiagnostic,
    ) {
        self.action_diagnostic = Some((outcome, crate_name, diagnostic));
    }

    /// Hold a bypass reason for the compilation that follows it, returning one
    /// already held that no compilation claimed.
    pub(crate) fn hold_bypass(&mut self, kind: String) -> Option<String> {
        self.bypass.replace(kind)
    }

    /// The bypass reason this connection is holding, if any.
    pub(crate) fn take_bypass(&mut self) -> Option<String> {
        self.bypass.take()
    }

    pub(crate) fn take_action_diagnostic(
        &mut self,
        outcome: &str,
        crate_name: Option<&str>,
    ) -> Option<ActionDiagnostic> {
        let matches =
            self.action_diagnostic
                .as_ref()
                .is_some_and(|(pending_outcome, pending_crate, _)| {
                    pending_outcome == outcome && pending_crate.as_deref() == crate_name
                });
        if matches {
            self.action_diagnostic
                .take()
                .map(|(_, _, diagnostic)| diagnostic)
        } else {
            None
        }
    }
}

/// Statistics recorded for background uploads.
///
/// The queue reports through this rather than owning counters so that a session's
/// figures stay in one place.
pub(crate) trait UploadSink: Send + Sync {
    /// Record a blob published with the given payload size.
    fn record_blob_uploaded(&self, bytes: u64);
    /// Record an action result published.
    fn record_action_uploaded(&self);
    /// Record one framed request that published `blobs` blobs.
    fn record_blob_pack_uploaded(&self, blobs: u64);
    /// Record an upload that did not publish, having already been reported.
    fn record_upload_failure(&self);
}

enum QueuedUpload {
    Blob {
        digest: CacheDigest,
        path: PathBuf,
        done: tokio::sync::oneshot::Sender<UploadOutcome>,
    },
    ActionResult {
        result: RemoteActionResult,
        prerequisites: Vec<UploadTicket>,
        done: tokio::sync::oneshot::Sender<UploadOutcome>,
    },
}

impl QueuedUpload {
    fn is_blob(&self) -> bool {
        matches!(self, Self::Blob { .. })
    }
}

/// A queued blob considered for packing with others.
struct PackMember {
    digest: CacheDigest,
    path: PathBuf,
    done: tokio::sync::oneshot::Sender<UploadOutcome>,
}

/// Split blobs into packs the server will accept, plus the ones to send alone.
///
/// A blob too large for any pack, or left over as a group of one, is not worth
/// framing: a pack of one costs the same round trip as the blob itself.
fn group_into_packs(
    members: Vec<PackMember>,
    limits: BlobPackLimits,
) -> (Vec<Vec<PackMember>>, Vec<PackMember>) {
    let mut packs = Vec::new();
    let mut singles = Vec::new();
    let mut current: Vec<PackMember> = Vec::new();
    let mut current_bytes = 0u64;
    for member in members {
        if member.digest.size > limits.max_bytes {
            singles.push(member);
            continue;
        }
        let would_exceed = current.len() >= limits.max_items
            || current_bytes.saturating_add(member.digest.size) > limits.max_bytes;
        if would_exceed && !current.is_empty() {
            close_pack(std::mem::take(&mut current), &mut packs, &mut singles);
            current_bytes = 0;
        }
        current_bytes = current_bytes.saturating_add(member.digest.size);
        current.push(member);
    }
    close_pack(current, &mut packs, &mut singles);
    (packs, singles)
}

fn close_pack(
    pack: Vec<PackMember>,
    packs: &mut Vec<Vec<PackMember>>,
    singles: &mut Vec<PackMember>,
) {
    if pack.len() < 2 {
        singles.extend(pack);
    } else {
        packs.push(pack);
    }
}

/// A queue of remote publications that outlives the requests that asked for them.
#[derive(Clone)]
pub(crate) struct UploadQueue {
    inner: Arc<Inner>,
}

struct Inner {
    remote: Arc<RemoteCacheClient>,
    sink: Arc<dyn UploadSink>,
    transfers: Arc<tokio::sync::Semaphore>,
    remote_transfers: Arc<tokio::sync::Semaphore>,
    pending: Mutex<Vec<QueuedUpload>>,
    /// Tickets for blobs already queued, so the same object is uploaded once.
    blob_tickets: Mutex<BTreeMap<CacheDigest, UploadTicket>>,
    /// Tickets for action results, so a task manifest can wait for the results
    /// it names without waiting for the whole queue.
    action_tickets: Mutex<BTreeMap<CacheDigest, UploadTicket>>,
    work: tokio::sync::Notify,
    draining: AtomicBool,
    worker: Mutex<Option<tokio::task::JoinHandle<()>>>,
}

impl UploadQueue {
    /// Create a queue that publishes through `remote`.
    pub(crate) fn new(
        remote: Arc<RemoteCacheClient>,
        sink: Arc<dyn UploadSink>,
        remote_transfers: Arc<tokio::sync::Semaphore>,
    ) -> Self {
        Self {
            inner: Arc::new(Inner {
                remote,
                sink,
                transfers: Arc::new(tokio::sync::Semaphore::new(MAX_UPLOAD_TRANSFERS)),
                remote_transfers,
                pending: Mutex::new(Vec::new()),
                blob_tickets: Mutex::new(BTreeMap::new()),
                action_tickets: Mutex::new(BTreeMap::new()),
                work: tokio::sync::Notify::new(),
                draining: AtomicBool::new(false),
                worker: Mutex::new(None),
            }),
        }
    }

    /// Queue a blob held in the local CAS, returning the ticket for its upload.
    ///
    /// A digest still in flight, or already published, returns the existing
    /// ticket rather than sending the same bytes twice. One that finished
    /// without publishing is queued again: many compilations share a blob --
    /// every empty stdout is the same object -- so handing a settled failure to
    /// later requests would let one transient error withhold every action result
    /// after it.
    pub(crate) fn queue_blob(
        &self,
        digest: &CacheDigest,
        path: PathBuf,
        connection: &mut ConnectionUploads,
    ) {
        let ticket = {
            let mut tickets = self.inner.blob_tickets.lock().unwrap();
            match tickets
                .get(digest)
                .map(|ticket| (ticket.clone(), ticket.peek().copied()))
            {
                Some((ticket, None | Some(UploadOutcome::Uploaded))) => ticket,
                _ => {
                    let (done, ticket) = ticket_channel();
                    tickets.insert(digest.clone(), ticket.clone());
                    self.push(QueuedUpload::Blob {
                        digest: digest.clone(),
                        path,
                        done,
                    });
                    ticket
                }
            }
        };
        connection.record(ticket);
    }

    /// Queue an action result, to be published once this connection's blobs are.
    pub(crate) fn queue_action_result(
        &self,
        result: &RemoteActionResult,
        connection: &ConnectionUploads,
    ) {
        let mut prerequisites = connection.prerequisites();
        if prerequisites.is_empty() {
            // A caller with no connection of its own cannot say which blobs this
            // result references, so every blob the session has queued is treated
            // as one. A shim always stores a result's blobs first, over the same
            // connection, so this only covers requests made outside that path.
            prerequisites = self
                .inner
                .blob_tickets
                .lock()
                .unwrap()
                .values()
                .cloned()
                .collect();
        }
        let (done, ticket) = ticket_channel();
        self.inner
            .action_tickets
            .lock()
            .unwrap()
            .insert(result.action.clone(), ticket);
        self.push(QueuedUpload::ActionResult {
            result: result.clone(),
            prerequisites,
            done,
        });
    }

    fn push(&self, upload: QueuedUpload) {
        self.inner.pending.lock().unwrap().push(upload);
        self.ensure_worker();
        self.inner.work.notify_one();
    }

    fn ensure_worker(&self) {
        let mut worker = self.inner.worker.lock().unwrap();
        if worker.is_some() {
            return;
        }
        let inner = self.inner.clone();
        *worker = Some(tokio::spawn(async move { inner.run().await }));
    }

    /// Wait for the action results covering `actions`, reporting the ones that
    /// did not publish.
    ///
    /// A task manifest names the actions it predicts, so publishing it before
    /// those results exist would advertise work a reader cannot fetch. An action
    /// this queue never held is not reported: it was published by an earlier
    /// session, which is what a manifest baseline is made of.
    pub(crate) async fn wait_for_actions(&self, actions: &[CacheDigest]) -> BTreeSet<CacheDigest> {
        self.wait_for_action_outcomes(actions).await.1
    }

    /// Wait for action results while preserving which ones this queue actually
    /// held. A successful queued upload is proof that a locally observed value
    /// may be advertised even when it was not in the remote manifest baseline.
    pub(crate) async fn wait_for_action_outcomes(
        &self,
        actions: &[CacheDigest],
    ) -> (BTreeSet<CacheDigest>, BTreeSet<CacheDigest>) {
        let tickets: Vec<(CacheDigest, UploadTicket)> = {
            let queued = self.inner.action_tickets.lock().unwrap();
            actions
                .iter()
                .filter_map(|action| {
                    queued
                        .get(action)
                        .map(|ticket| (action.clone(), ticket.clone()))
                })
                .collect()
        };
        let held = tickets.iter().map(|(action, _)| action.clone()).collect();
        let mut unpublished = BTreeSet::new();
        for (action, ticket) in tickets {
            if !ticket.await.published() {
                unpublished.insert(action);
            }
        }
        (held, unpublished)
    }

    /// Publish everything queued, then stop the worker.
    ///
    /// Called once the session can no longer accept requests. Uploads run on the
    /// session's runtime, so this has to finish before that runtime goes away.
    pub(crate) async fn drain(&self) {
        self.inner.draining.store(true, Ordering::Release);
        let worker = self.inner.worker.lock().unwrap().take();
        match worker {
            Some(worker) => {
                self.inner.work.notify_one();
                if let Err(error) = worker.await {
                    warn!("remote cache upload queue failed: {error}");
                }
            }
            // Nothing was ever queued, so there is no worker to wind down.
            None => self.inner.run().await,
        }
    }
}

impl Inner {
    async fn run(&self) {
        loop {
            let batch = std::mem::take(&mut *self.pending.lock().unwrap());
            if batch.is_empty() {
                if self.draining.load(Ordering::Acquire) {
                    return;
                }
                self.work.notified().await;
                continue;
            }
            self.run_batch(batch).await;
        }
    }

    /// Run one batch of queued uploads, blobs first.
    ///
    /// The two phases are what keeps an action result from occupying a transfer
    /// slot while the blobs it is waiting for sit unstarted behind it. Every
    /// prerequisite of an action result was queued before it, so it is either in
    /// this batch's blob phase or in a batch that has already run.
    async fn run_batch(&self, batch: Vec<QueuedUpload>) {
        let (blobs, results): (Vec<_>, Vec<_>) = batch.into_iter().partition(QueuedUpload::is_blob);
        self.run_blob_phase(blobs).await;
        self.run_phase(results).await;
    }

    async fn run_phase(&self, uploads: Vec<QueuedUpload>) {
        stream::iter(uploads)
            .map(|upload| self.run_upload(upload))
            .buffer_unordered(MAX_UPLOAD_TRANSFERS)
            .collect::<Vec<()>>()
            .await;
    }

    /// Publish this batch's blobs, packing them together where the server takes
    /// packs.
    ///
    /// Rustc output is many small objects, so one request per object spends most
    /// of its time in round trips rather than in transfer.
    async fn run_blob_phase(&self, blobs: Vec<QueuedUpload>) {
        if blobs.len() < 2 {
            return self.run_phase(blobs).await;
        }
        // A negotiation this cannot complete is not worth failing the uploads
        // over; individual requests still publish everything.
        let limits = self
            .remote
            .blob_pack_upload_limits()
            .await
            .unwrap_or_default();
        let Some(limits) = limits else {
            return self.run_phase(blobs).await;
        };
        let mut members = Vec::with_capacity(blobs.len());
        for upload in blobs {
            match upload {
                QueuedUpload::Blob { digest, path, done } => {
                    members.push(PackMember { digest, path, done });
                }
                // The partition in `run_batch` leaves only blobs here.
                other => self.run_upload(other).await,
            }
        }
        let (packs, singles) = group_into_packs(members, limits);
        let packed = stream::iter(packs)
            .map(|pack| self.upload_pack(pack))
            .buffer_unordered(MAX_UPLOAD_TRANSFERS)
            .collect::<Vec<()>>();
        futures_util::future::join(packed, self.upload_members(singles)).await;
    }

    /// Publish one group of blobs in a single framed request.
    ///
    /// A pack the server will not take -- because it does not serve the
    /// extension, or because the request failed -- leaves its members to be sent
    /// individually, which also reports precisely which blob was the problem.
    async fn upload_pack(&self, pack: Vec<PackMember>) {
        let mut present = Vec::with_capacity(pack.len());
        for member in pack {
            if tokio::fs::try_exists(&member.path).await.unwrap_or(false) {
                present.push(member);
            } else {
                warn!(
                    "remote cache blob upload skipped for {}: the local object is gone",
                    member.digest.hash
                );
                self.sink.record_upload_failure();
                let _ = member.done.send(UploadOutcome::Skipped);
            }
        }
        if present.len() < 2 {
            self.upload_members(present).await;
            return;
        }
        let uploads: Vec<BlobUpload> = present
            .iter()
            .map(|member| BlobUpload {
                digest: member.digest.clone(),
                source: BlobSource::Path(member.path.clone()),
            })
            .collect();
        let receipt = {
            let Ok(_permit) = self.transfers.acquire().await else {
                return;
            };
            let Ok(_transfer) = self.remote_transfers.acquire().await else {
                return;
            };
            self.remote.put_blob_pack(&uploads).await
        };
        match receipt {
            Ok(Some(_)) => {
                self.sink.record_blob_pack_uploaded(present.len() as u64);
                for member in present {
                    self.sink.record_blob_uploaded(member.digest.size);
                    let _ = member.done.send(UploadOutcome::Uploaded);
                }
            }
            Ok(None) => self.upload_members(present).await,
            Err(error) => {
                warn!("remote cache blob pack upload failed: {error}");
                self.upload_members(present).await;
            }
        }
    }

    /// Publish these blobs individually, as concurrently as any other upload.
    ///
    /// This is the path a pack falls back to, so it has to match what the
    /// unpacked path would have done: sending a whole group one round trip at a
    /// time is worst exactly when the server has just refused a request.
    async fn upload_members(&self, members: Vec<PackMember>) {
        stream::iter(members)
            .map(|member| self.upload_member(member))
            .buffer_unordered(MAX_UPLOAD_TRANSFERS)
            .collect::<Vec<()>>()
            .await;
    }

    async fn upload_member(&self, member: PackMember) {
        let outcome = self.upload_blob(&member.digest, &member.path).await;
        let _ = member.done.send(outcome);
    }

    async fn run_upload(&self, upload: QueuedUpload) {
        match upload {
            QueuedUpload::Blob { digest, path, done } => {
                let outcome = self.upload_blob(&digest, &path).await;
                let _ = done.send(outcome);
            }
            QueuedUpload::ActionResult {
                result,
                prerequisites,
                done,
            } => {
                let outcome = self.upload_action_result(&result, prerequisites).await;
                let _ = done.send(outcome);
            }
        }
    }

    async fn upload_blob(&self, digest: &CacheDigest, path: &PathBuf) -> UploadOutcome {
        // Reading the object confirms it survived long enough to publish. A
        // collection between the store and this upload is a lost upload, not a
        // failed one -- there is no longer anything to send.
        if !tokio::fs::try_exists(path).await.unwrap_or(false) {
            warn!(
                "remote cache blob upload skipped for {}: the local object is gone",
                digest.hash
            );
            self.sink.record_upload_failure();
            return UploadOutcome::Skipped;
        }
        let _permit = match self.transfers.acquire().await {
            Ok(permit) => permit,
            Err(_) => return UploadOutcome::Failed,
        };
        let _transfer = match self.remote_transfers.acquire().await {
            Ok(permit) => permit,
            Err(_) => return UploadOutcome::Failed,
        };
        let upload = BlobUpload {
            digest: digest.clone(),
            source: BlobSource::Path(path.clone()),
        };
        match self.remote.put_blob(&upload).await {
            Ok(()) => {
                self.sink.record_blob_uploaded(digest.size);
                UploadOutcome::Uploaded
            }
            Err(error) => {
                if missing_source(&error) {
                    warn!(
                        "remote cache blob upload skipped for {}: the local object is gone",
                        digest.hash
                    );
                    self.sink.record_upload_failure();
                    return UploadOutcome::Skipped;
                }
                warn!(
                    "remote cache blob upload failed for {}: {error}",
                    digest.hash
                );
                self.sink.record_upload_failure();
                UploadOutcome::Failed
            }
        }
    }

    async fn upload_action_result(
        &self,
        result: &RemoteActionResult,
        prerequisites: Vec<UploadTicket>,
    ) -> UploadOutcome {
        for prerequisite in prerequisites {
            if !prerequisite.await.published() {
                // The server validates an action result against the blobs it
                // references, so publishing this one now would be rejected. The
                // blob failure has already been reported.
                warn!(
                    "remote cache action upload skipped for {}: a referenced blob was not published",
                    result.action.hash
                );
                return UploadOutcome::Skipped;
            }
        }
        let _permit = match self.transfers.acquire().await {
            Ok(permit) => permit,
            Err(_) => return UploadOutcome::Failed,
        };
        let _transfer = match self.remote_transfers.acquire().await {
            Ok(permit) => permit,
            Err(_) => return UploadOutcome::Failed,
        };
        match self.remote.put_action_result(result).await {
            Ok(()) => {
                self.sink.record_action_uploaded();
                UploadOutcome::Uploaded
            }
            Err(error) => {
                warn!(
                    "remote cache action upload failed for {}: {error}",
                    result.action.hash
                );
                self.sink.record_upload_failure();
                UploadOutcome::Failed
            }
        }
    }
}

fn ticket_channel() -> (tokio::sync::oneshot::Sender<UploadOutcome>, UploadTicket) {
    let (sender, receiver) = tokio::sync::oneshot::channel();
    let ticket = receiver
        // A dropped sender means the upload never reported an outcome, which
        // nothing may treat as a successful publication.
        .map(|outcome| outcome.unwrap_or(UploadOutcome::Failed))
        .boxed()
        .shared();
    (sender, ticket)
}

/// Whether a failed upload failed because its local source had been collected.
fn missing_source(error: &eyre::Report) -> bool {
    error.chain().any(|cause| {
        cause
            .downcast_ref::<std::io::Error>()
            .is_some_and(|error| error.kind() == std::io::ErrorKind::NotFound)
    })
}
