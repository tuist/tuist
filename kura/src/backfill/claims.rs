//! The shared to-retrieve set with exclusive claims (R10): concurrent
//! per-peer passes dedup their listings here so each tuple is fetched once,
//! while drain accounting (R6) guarantees no tuple is ever silently dropped —
//! every listed tuple reaches a terminal resolution for every pass that
//! listed it. Entries are reference-counted by the passes that listed them
//! and removed at zero references, so the set is empty whenever no passes are
//! in flight. Purely in-memory (R5): a restart re-lists.
//!
//! Resolution states, per the four-way contract:
//! - *applied* — the fetch applied (possibly under a newer version than the
//!   listed one, the frame-provenance case); resolves every referencing pass.
//! - *absent* — the fetcher's peer does not have the tuple; resolves only the
//!   fetching pass, and the claim is released so each waiter re-claims
//!   through its own peer. A waiter's watermark must never advance over an
//!   entry its own peer still serves.
//! - *released* — batch failure or pass cancellation; waiters re-claim
//!   through the same exclusive claim set (one winner, the rest wait).
//! - *capacity-skipped* — once a pass's marginal-trade completion fires,
//!   segmented tuples resolve without fetching: they satisfy drain and never
//!   block the watermark (the segmented guarantee narrows to the newest
//!   ring-worth).
//!
//! The no-leaked-claims invariant is structural, not cooperative: claims are
//! held through [`PassClaimGuard`], whose `Drop` releases everything the pass
//! still references on every termination path (panic, cancellation, error).

use std::{
    collections::{BTreeMap, BTreeSet},
    sync::{Arc, Mutex, MutexGuard, PoisonError},
};

use tokio::sync::{Notify, futures::Notified};

use crate::utils::BackfillRecordKind;

/// Identity of one listed tuple. Two versions of the same record are
/// distinct tuples: the version is part of what a pass listed, and the
/// apply-time presence check owns cross-version reconciliation.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct ClaimKey {
    pub kind: BackfillRecordKind,
    pub record_id: String,
    pub version_ms: u64,
}

/// What a pass must do with a tuple it just listed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ListDecision {
    /// This pass holds the exclusive claim and fetches through its peer.
    Claimed,
    /// Another pass is fetching. Drain-responsibility transfers here: the
    /// tuple joined this pass's drain set and resolves with the claim (or
    /// re-claims to this pass if the claim releases).
    Waiting,
    /// This pass is capacity-completed and the tuple is a segmented
    /// artifact: neither added nor claimed, resolved immediately.
    CapacitySkipped,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
struct PassId(u64);

/// One tuple's entry: the exclusive claim plus the unresolved referencing
/// passes. `refs` keeps listing order — re-claim arbitration is
/// first-comes-first (deterministic), with a batch-failed holder re-queued at
/// the back so waiters win.
struct Entry {
    holder: PassId,
    /// The claim rides in a dispatched bodies batch. In-flight batches run
    /// to completion even after capacity completion fires.
    in_flight: bool,
    refs: Vec<PassId>,
}

struct PassState {
    /// The unresolved remainder of the pass's drain set. Drain-aware
    /// completion (R6) = this set emptied after listing finished.
    tuples: BTreeSet<ClaimKey>,
    /// Marginal-trade completion fired: segmented tuples resolve
    /// capacity-skipped from here on.
    capacity_complete: bool,
    /// Claims won through re-claim arbitration, not yet handed to the
    /// driver via [`PassClaimGuard::take_reclaimed`].
    reclaimed: Vec<ClaimKey>,
    notify: Arc<Notify>,
}

#[derive(Default)]
struct Core {
    entries: BTreeMap<ClaimKey, Entry>,
    passes: BTreeMap<PassId, PassState>,
    next_pass_id: u64,
}

/// Why a claim is being released. Every cause frees the entry's exclusive
/// claim; they differ in what happens to the releasing pass's reference.
enum ReleaseCause {
    /// Batch failure: the releaser stays a re-claim candidate, queued
    /// behind the waiters.
    // The pass driver retries failed batches in place instead of releasing,
    // so this cause is reached only through `release_failed` in tests.
    #[allow(dead_code)]
    Failure,
    /// The releaser's reference is already being torn down by the guard's
    /// `Drop`; only the waiters matter.
    Cancel,
    /// Absent resolves the releaser (its peer does not have the tuple);
    /// each waiter re-claims through its own peer.
    Absent,
    /// Capacity completion released a composed-but-unfetched segmented
    /// claim: capacity-skipped for the releaser.
    CapacityUnfetched,
}

impl Core {
    fn pass(&self, pass_id: PassId) -> &PassState {
        self.passes.get(&pass_id).expect("pass is registered")
    }

    /// Terminally resolves `key` for one pass: the tuple leaves its drain
    /// set (and pending re-claim queue) and the pass is woken.
    fn resolve_for_pass(&mut self, pass_id: PassId, key: &ClaimKey) {
        let pass = self.passes.get_mut(&pass_id).expect("pass is registered");
        pass.tuples.remove(key);
        pass.reclaimed.retain(|reclaimed| reclaimed != key);
        pass.notify.notify_waiters();
    }

    /// The fetch applied: resolves every referencing pass and removes the
    /// entry.
    fn resolve_applied(&mut self, key: &ClaimKey, holder: PassId) {
        let entry = self.entries.remove(key).expect("applied claim exists");
        assert_eq!(entry.holder, holder, "only the claim holder may resolve");
        for pass_id in entry.refs {
            self.resolve_for_pass(pass_id, key);
        }
    }

    /// Releases the exclusive claim on `key` and re-arbitrates it. The
    /// four-way resolution contract funnels through here: the releaser's
    /// fate depends on `cause`, capacity-completed passes resolve
    /// capacity-skipped on segmented tuples, and exactly one surviving
    /// reference — waiters first, in listing order — wins the re-claim.
    fn release(&mut self, key: &ClaimKey, releaser: PassId, cause: ReleaseCause) {
        let mut entry = self.entries.remove(key).expect("released claim exists");
        assert_eq!(entry.holder, releaser, "only the claim holder may release");
        entry.refs.retain(|pass_id| *pass_id != releaser);

        // A failed batch's claims resolve capacity-skipped for a
        // capacity-completed releaser (it cannot fetch segmented data any
        // more); otherwise the releaser re-queues behind the waiters.
        let segmented = key.kind == BackfillRecordKind::SegmentArtifact;
        match cause {
            ReleaseCause::Failure if !(segmented && self.pass(releaser).capacity_complete) => {
                entry.refs.push(releaser);
            }
            ReleaseCause::Cancel => {}
            _ => self.resolve_for_pass(releaser, key),
        }

        // Released segmented claims resolve capacity-skipped for
        // capacity-completed waiters; only the rest re-claim.
        if segmented {
            let (skipped, candidates): (Vec<PassId>, Vec<PassId>) = entry
                .refs
                .iter()
                .partition(|pass_id| self.pass(**pass_id).capacity_complete);
            for pass_id in skipped {
                self.resolve_for_pass(pass_id, key);
            }
            entry.refs = candidates;
        }

        // Exactly one winner; the other references wait on the new claim.
        // The entry disappears with its last reference (no orphan growth).
        if let Some(&winner) = entry.refs.first() {
            entry.holder = winner;
            entry.in_flight = false;
            self.entries.insert(key.clone(), entry);
            let pass = self.passes.get_mut(&winner).expect("winner is registered");
            pass.reclaimed.push(key.clone());
            pass.notify.notify_waiters();
        }
    }
}

/// The shared claim set. One per node, shared by every in-flight pass.
#[derive(Default)]
pub struct ClaimSet {
    core: Mutex<Core>,
}

/// Pass-scoped handle to the claim set. Dropping it cancels the pass:
/// every claim it holds is released (waiters re-claim), every tuple it
/// merely waits on is de-referenced, and entries it alone listed disappear.
pub struct PassClaimGuard {
    set: Arc<ClaimSet>,
    pass_id: PassId,
    notify: Arc<Notify>,
}

impl ClaimSet {
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    /// Registers a new pass and returns its claim guard.
    pub fn register_pass(self: &Arc<Self>) -> PassClaimGuard {
        let notify = Arc::new(Notify::new());
        let mut core = self.lock_core();
        let pass_id = PassId(core.next_pass_id);
        core.next_pass_id += 1;
        core.passes.insert(
            pass_id,
            PassState {
                tuples: BTreeSet::new(),
                capacity_complete: false,
                reclaimed: Vec::new(),
                notify: notify.clone(),
            },
        );
        PassClaimGuard {
            set: self.clone(),
            pass_id,
            notify,
        }
    }

    /// True when no tuple is listed by any in-flight pass.
    #[allow(dead_code)] // invariant probe used by the claims and lifecycle tests
    pub fn is_empty(&self) -> bool {
        self.lock_core().entries.is_empty()
    }

    fn lock_core(&self) -> MutexGuard<'_, Core> {
        // Drop-based release must proceed even if another task panicked
        // inside the set; critical sections mutate atomically, so a
        // poisoned core is still consistent.
        self.core.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

impl PassClaimGuard {
    /// Records that this pass listed `key` and decides who fetches it.
    /// Re-listing a tuple that is still unresolved for this pass is
    /// idempotent and returns the current role.
    pub fn list(&self, key: ClaimKey) -> ListDecision {
        let mut core = self.set.lock_core();
        let pass = core.pass(self.pass_id);
        if pass.capacity_complete && key.kind == BackfillRecordKind::SegmentArtifact {
            return ListDecision::CapacitySkipped;
        }
        if pass.tuples.contains(&key) {
            let entry = core
                .entries
                .get(&key)
                .expect("unresolved tuple has an entry");
            return if entry.holder == self.pass_id {
                ListDecision::Claimed
            } else {
                ListDecision::Waiting
            };
        }
        let decision = match core.entries.get_mut(&key) {
            Some(entry) => {
                entry.refs.push(self.pass_id);
                ListDecision::Waiting
            }
            None => {
                core.entries.insert(
                    key.clone(),
                    Entry {
                        holder: self.pass_id,
                        in_flight: false,
                        refs: vec![self.pass_id],
                    },
                );
                ListDecision::Claimed
            }
        };
        let pass = core
            .passes
            .get_mut(&self.pass_id)
            .expect("pass is registered");
        pass.tuples.insert(key);
        decision
    }

    /// Marks a held claim as riding in a dispatched bodies batch. In-flight
    /// claims are exempt from the capacity-completion release: their batch
    /// runs to completion.
    pub fn mark_in_flight(&self, key: &ClaimKey) {
        let mut core = self.set.lock_core();
        let entry = core.entries.get_mut(key).expect("in-flight claim exists");
        assert_eq!(
            entry.holder, self.pass_id,
            "only the claim holder may mark it in flight"
        );
        entry.in_flight = true;
    }

    /// The fetch applied. Resolves every pass referencing the tuple —
    /// including when the applied version differs from the listed one (the
    /// frame carries the sender's current manifest version): resolution is
    /// keyed by the *listed* tuple regardless.
    pub fn resolve_applied(&self, key: &ClaimKey) {
        self.set.lock_core().resolve_applied(key, self.pass_id);
    }

    /// The fetcher's peer does not have the tuple. Resolves only this pass;
    /// the claim releases so each waiter re-claims through its own peer.
    pub fn resolve_absent(&self, key: &ClaimKey) {
        self.set
            .lock_core()
            .release(key, self.pass_id, ReleaseCause::Absent);
    }

    /// A bodies batch carrying this claim failed. The claim releases;
    /// waiters win the re-claim first, and this pass re-queues behind them
    /// (a sole-reference pass re-wins its own claim). Every re-claim —
    /// including a self re-win — is delivered through
    /// [`Self::take_reclaimed`].
    #[allow(dead_code)] // the pass driver retries batches in place; exercised by tests
    pub fn release_failed(&self, key: &ClaimKey) {
        self.set
            .lock_core()
            .release(key, self.pass_id, ReleaseCause::Failure);
    }

    /// Marginal-trade completion fired for this pass. Segmented claims it
    /// holds that are not in an in-flight batch are released — resolved
    /// capacity-skipped for this pass, re-claimed by non-capacity waiters —
    /// otherwise the pass would deadlock on its own now-unfetchable claims.
    pub fn mark_capacity_complete(&self) {
        let mut core = self.set.lock_core();
        {
            let pass = core
                .passes
                .get_mut(&self.pass_id)
                .expect("pass is registered");
            if pass.capacity_complete {
                return;
            }
            pass.capacity_complete = true;
        }
        let unfetched: Vec<ClaimKey> = core
            .pass(self.pass_id)
            .tuples
            .iter()
            .filter(|key| {
                key.kind == BackfillRecordKind::SegmentArtifact
                    && core
                        .entries
                        .get(key)
                        .is_some_and(|entry| entry.holder == self.pass_id && !entry.in_flight)
            })
            .cloned()
            .collect();
        for key in unfetched {
            core.release(&key, self.pass_id, ReleaseCause::CapacityUnfetched);
        }
    }

    /// Claims won through re-claim arbitration since the last call. The
    /// driver fetches these through its own peer. Never returns a segmented
    /// tuple to a capacity-completed pass.
    pub fn take_reclaimed(&self) -> Vec<ClaimKey> {
        let mut core = self.set.lock_core();
        let pass = core
            .passes
            .get_mut(&self.pass_id)
            .expect("pass is registered");
        std::mem::take(&mut pass.reclaimed)
    }

    /// True when every tuple in this pass's drain set is resolved.
    /// Meaningful for completion once the pass has finished listing.
    pub fn is_drained(&self) -> bool {
        self.set.lock_core().pass(self.pass_id).tuples.is_empty()
    }

    /// Wakes on any event affecting this pass (a resolution draining a
    /// tuple, or a re-claim win). Create the future *before* checking
    /// state, or the wakeup can be missed.
    pub fn changed(&self) -> Notified<'_> {
        self.notify.notified()
    }

    /// Resolves once every tuple in the drain set is resolved.
    #[allow(dead_code)] // the pass driver inlines this wait loop; exercised by tests
    pub async fn drained(&self) {
        loop {
            let changed = self.changed();
            if self.is_drained() {
                return;
            }
            changed.await;
        }
    }
}

impl Drop for PassClaimGuard {
    fn drop(&mut self) {
        // Unconditional release on every termination path — panic,
        // cancellation, error — is what makes the no-leaked-claims
        // invariant structural. Cancellation resolves nothing for this
        // pass; it de-references, releasing held claims to waiters.
        let mut core = self.set.lock_core();
        let tuples = std::mem::take(
            &mut core
                .passes
                .get_mut(&self.pass_id)
                .expect("pass is registered")
                .tuples,
        );
        for key in tuples {
            let entry = core
                .entries
                .get_mut(&key)
                .expect("listed tuple has an entry");
            if entry.holder == self.pass_id {
                core.release(&key, self.pass_id, ReleaseCause::Cancel);
            } else {
                // De-reference a waited tuple; the holder's reference keeps
                // the entry alive, so this never strands an empty entry.
                entry.refs.retain(|pass_id| *pass_id != self.pass_id);
            }
        }
        core.passes.remove(&self.pass_id);
    }
}

#[cfg(test)]
impl ClaimSet {
    /// Cross-checks the structural invariants the resolution contract relies
    /// on; the property harness calls this after every step.
    fn assert_invariants(&self) {
        let core = self.lock_core();
        for (key, entry) in &core.entries {
            assert!(!entry.refs.is_empty(), "entry without references: {key:?}");
            assert!(
                entry.refs.contains(&entry.holder),
                "holder is not a reference: {key:?}"
            );
            let mut seen = BTreeSet::new();
            for pass_id in &entry.refs {
                assert!(seen.insert(*pass_id), "duplicate reference: {key:?}");
                let pass = core.passes.get(pass_id).expect("reference to live pass");
                assert!(
                    pass.tuples.contains(key),
                    "reference missing from the pass drain set: {key:?}"
                );
            }
            let holder = core.passes.get(&entry.holder).expect("holder is live");
            if holder.capacity_complete && key.kind == BackfillRecordKind::SegmentArtifact {
                assert!(
                    entry.in_flight,
                    "capacity-completed pass holds a fetchable segmented claim: {key:?}"
                );
            }
        }
        for (pass_id, pass) in &core.passes {
            for key in &pass.tuples {
                let entry = core.entries.get(key).expect("drain tuple has an entry");
                assert!(entry.refs.contains(pass_id));
            }
            for key in &pass.reclaimed {
                let entry = core.entries.get(key).expect("reclaimed tuple has an entry");
                assert_eq!(entry.holder, *pass_id, "reclaimed tuple not held: {key:?}");
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::*;

    fn segment(id: &str, version_ms: u64) -> ClaimKey {
        ClaimKey {
            kind: BackfillRecordKind::SegmentArtifact,
            record_id: id.into(),
            version_ms,
        }
    }

    fn inline(id: &str, version_ms: u64) -> ClaimKey {
        ClaimKey {
            kind: BackfillRecordKind::InlineArtifact,
            record_id: id.into(),
            version_ms,
        }
    }

    fn tombstone(id: &str, version_ms: u64) -> ClaimKey {
        ClaimKey {
            kind: BackfillRecordKind::NamespaceTombstone,
            record_id: id.into(),
            version_ms,
        }
    }

    #[test]
    fn one_pass_claims_applies_and_both_passes_drain() {
        let set = ClaimSet::new();
        let fetcher = set.register_pass();
        let waiter = set.register_pass();
        let key = inline("artifact-a", 1_000);

        assert_eq!(fetcher.list(key.clone()), ListDecision::Claimed);
        assert_eq!(waiter.list(key.clone()), ListDecision::Waiting);
        assert!(!fetcher.is_drained());
        assert!(!waiter.is_drained());

        // The applied version may differ from the listed one (the frame
        // carries the sender's current manifest version); resolution is
        // keyed by the listed tuple either way, and resolves everyone.
        fetcher.resolve_applied(&key);
        assert!(fetcher.is_drained());
        assert!(waiter.is_drained());
        assert!(set.is_empty());
    }

    #[test]
    fn duplicate_discard_transfers_drain_responsibility_to_the_discarding_pass() {
        let set = ClaimSet::new();
        let fetcher = set.register_pass();
        let discarder = set.register_pass();
        let key = segment("artifact-a", 1_000);

        assert_eq!(fetcher.list(key.clone()), ListDecision::Claimed);
        // The discarding pass does not fetch, but the tuple joins its drain
        // set: it cannot complete until the tuple resolves.
        assert_eq!(discarder.list(key.clone()), ListDecision::Waiting);
        assert!(!discarder.is_drained());

        fetcher.resolve_applied(&key);
        assert!(discarder.is_drained());
    }

    #[test]
    fn relisting_an_unresolved_tuple_is_idempotent() {
        let set = ClaimSet::new();
        let fetcher = set.register_pass();
        let waiter = set.register_pass();
        let key = inline("artifact-a", 1_000);

        assert_eq!(fetcher.list(key.clone()), ListDecision::Claimed);
        assert_eq!(fetcher.list(key.clone()), ListDecision::Claimed);
        assert_eq!(waiter.list(key.clone()), ListDecision::Waiting);
        assert_eq!(waiter.list(key.clone()), ListDecision::Waiting);

        fetcher.resolve_applied(&key);
        assert!(set.is_empty());
    }

    #[test]
    fn batch_failure_reclaims_exactly_one_waiter() {
        let set = ClaimSet::new();
        let fetcher = set.register_pass();
        let first_waiter = set.register_pass();
        let second_waiter = set.register_pass();
        let key = inline("artifact-a", 1_000);

        assert_eq!(fetcher.list(key.clone()), ListDecision::Claimed);
        assert_eq!(first_waiter.list(key.clone()), ListDecision::Waiting);
        assert_eq!(second_waiter.list(key.clone()), ListDecision::Waiting);

        fetcher.mark_in_flight(&key);
        fetcher.release_failed(&key);

        // Winner arbitration: exactly one re-claim, in listing order.
        assert_eq!(first_waiter.take_reclaimed(), vec![key.clone()]);
        assert!(second_waiter.take_reclaimed().is_empty());
        assert!(fetcher.take_reclaimed().is_empty());

        // The failed fetcher re-queued behind the waiters: it drains with
        // everyone else when the new claim applies.
        first_waiter.resolve_applied(&key);
        assert!(fetcher.is_drained());
        assert!(first_waiter.is_drained());
        assert!(second_waiter.is_drained());
        assert!(set.is_empty());
    }

    #[test]
    fn sole_reference_pass_rewins_its_own_claim_after_batch_failure() {
        let set = ClaimSet::new();
        let fetcher = set.register_pass();
        let key = inline("artifact-a", 1_000);

        assert_eq!(fetcher.list(key.clone()), ListDecision::Claimed);
        fetcher.release_failed(&key);

        // No waiters: the pass re-wins its own claim, delivered through the
        // same take_reclaimed path so the driver's re-fetch flow is uniform.
        assert_eq!(fetcher.take_reclaimed(), vec![key.clone()]);
        fetcher.resolve_applied(&key);
        assert!(fetcher.is_drained());
        assert!(set.is_empty());
    }

    #[test]
    fn absent_resolves_only_the_fetcher_and_the_waiter_reclaims_through_its_own_peer() {
        let set = ClaimSet::new();
        let fetcher = set.register_pass();
        let waiter = set.register_pass();
        let key = inline("artifact-a", 1_000);

        assert_eq!(fetcher.list(key.clone()), ListDecision::Claimed);
        assert_eq!(waiter.list(key.clone()), ListDecision::Waiting);

        // The fetcher's peer does not have the tuple: per-peer resolution.
        fetcher.resolve_absent(&key);
        assert!(fetcher.is_drained());
        assert!(!waiter.is_drained());

        // The waiter re-claims and fetches through its own peer — its
        // watermark must not advance over an entry its peer still serves.
        assert_eq!(waiter.take_reclaimed(), vec![key.clone()]);
        waiter.resolve_absent(&key);
        assert!(waiter.is_drained());
        assert!(set.is_empty());
    }

    #[test]
    fn cancelled_pass_releases_claims_and_a_successor_relists_cleanly() {
        let set = ClaimSet::new();
        let cancelled = set.register_pass();
        assert_eq!(
            cancelled.list(segment("artifact-a", 1_000)),
            ListDecision::Claimed
        );
        assert_eq!(
            cancelled.list(inline("artifact-b", 2_000)),
            ListDecision::Claimed
        );

        drop(cancelled);
        // Entries listed only by the cancelled pass are gone: no orphans.
        assert!(set.is_empty());

        // A successor pass over the same peer re-lists cleanly.
        let successor = set.register_pass();
        assert_eq!(
            successor.list(segment("artifact-a", 1_000)),
            ListDecision::Claimed
        );
        assert_eq!(
            successor.list(inline("artifact-b", 2_000)),
            ListDecision::Claimed
        );
        successor.resolve_applied(&segment("artifact-a", 1_000));
        successor.resolve_applied(&inline("artifact-b", 2_000));
        assert!(successor.is_drained());
    }

    #[test]
    fn cancelled_holder_hands_the_claim_to_a_waiter() {
        let set = ClaimSet::new();
        let cancelled = set.register_pass();
        let waiter = set.register_pass();
        let key = tombstone("ios", 1_000);

        assert_eq!(cancelled.list(key.clone()), ListDecision::Claimed);
        assert_eq!(waiter.list(key.clone()), ListDecision::Waiting);

        drop(cancelled);
        assert_eq!(waiter.take_reclaimed(), vec![key.clone()]);
        waiter.resolve_applied(&key);
        assert!(waiter.is_drained());
        assert!(set.is_empty());
    }

    #[test]
    fn cancelled_waiter_leaves_the_claim_with_its_holder() {
        let set = ClaimSet::new();
        let fetcher = set.register_pass();
        let cancelled_waiter = set.register_pass();
        let key = inline("artifact-a", 1_000);

        assert_eq!(fetcher.list(key.clone()), ListDecision::Claimed);
        assert_eq!(cancelled_waiter.list(key.clone()), ListDecision::Waiting);

        drop(cancelled_waiter);
        assert!(!set.is_empty());
        fetcher.resolve_applied(&key);
        assert!(set.is_empty());
    }

    #[test]
    fn capacity_completed_pass_skips_segmented_listings_but_still_claims_inline() {
        let set = ClaimSet::new();
        let pass = set.register_pass();
        pass.mark_capacity_complete();

        // Segmented tuples are neither added nor claimed: capacity-skipped
        // satisfies drain immediately and never blocks the watermark.
        assert_eq!(
            pass.list(segment("artifact-a", 1_000)),
            ListDecision::CapacitySkipped
        );
        assert!(pass.is_drained());
        assert!(set.is_empty());

        // The capacity test narrows only the segmented guarantee: inline
        // artifacts and tombstones still fetch.
        assert_eq!(pass.list(inline("artifact-b", 900)), ListDecision::Claimed);
        assert_eq!(pass.list(tombstone("ios", 800)), ListDecision::Claimed);
        assert!(!pass.is_drained());
    }

    #[test]
    fn released_segmented_claim_capacity_skips_completed_waiters_and_reclaims_the_rest() {
        let set = ClaimSet::new();
        let fetcher = set.register_pass();
        let capacity_waiter = set.register_pass();
        let cold_waiter = set.register_pass();
        let key = segment("artifact-a", 1_000);

        assert_eq!(fetcher.list(key.clone()), ListDecision::Claimed);
        assert_eq!(capacity_waiter.list(key.clone()), ListDecision::Waiting);
        assert_eq!(cold_waiter.list(key.clone()), ListDecision::Waiting);

        // The waiter capacity-completes while waiting (it holds no claim on
        // the tuple, so nothing releases yet).
        capacity_waiter.mark_capacity_complete();
        assert!(!capacity_waiter.is_drained());

        // The claim releases: the capacity-completed waiter resolves
        // capacity-skipped — drains without fetching — and only the
        // non-capacity waiter re-claims.
        fetcher.release_failed(&key);
        assert!(capacity_waiter.is_drained());
        assert!(capacity_waiter.take_reclaimed().is_empty());
        assert_eq!(cold_waiter.take_reclaimed(), vec![key.clone()]);

        cold_waiter.resolve_applied(&key);
        assert!(fetcher.is_drained());
        assert!(cold_waiter.is_drained());
        assert!(set.is_empty());
    }

    #[test]
    fn capacity_completion_releases_unfetched_segmented_claims_without_self_deadlock() {
        let set = ClaimSet::new();
        let pass = set.register_pass();
        let waiter = set.register_pass();
        let unfetched = segment("artifact-a", 1_000);
        let in_flight = segment("artifact-b", 900);
        let inline_claim = inline("artifact-c", 800);

        assert_eq!(pass.list(unfetched.clone()), ListDecision::Claimed);
        assert_eq!(pass.list(in_flight.clone()), ListDecision::Claimed);
        assert_eq!(pass.list(inline_claim.clone()), ListDecision::Claimed);
        assert_eq!(waiter.list(unfetched.clone()), ListDecision::Waiting);
        pass.mark_in_flight(&in_flight);

        // Capacity completion fires with a composed-but-not-dispatched
        // segmented claim outstanding: without releasing it the pass would
        // deadlock on its own now-unfetchable claim.
        pass.mark_capacity_complete();

        // The unfetched segmented claim resolved capacity-skipped for the
        // firing pass and released to the non-capacity waiter.
        assert_eq!(waiter.take_reclaimed(), vec![unfetched.clone()]);

        // The in-flight batch runs to completion; the inline claim is
        // untouched by capacity completion.
        pass.resolve_applied(&in_flight);
        pass.resolve_applied(&inline_claim);
        assert!(pass.is_drained());

        waiter.resolve_applied(&unfetched);
        assert!(waiter.is_drained());
        assert!(set.is_empty());
    }

    #[test]
    fn failed_in_flight_segmented_claim_of_a_capacity_completed_pass_resolves_skipped() {
        let set = ClaimSet::new();
        let pass = set.register_pass();
        let key = segment("artifact-a", 1_000);

        assert_eq!(pass.list(key.clone()), ListDecision::Claimed);
        pass.mark_in_flight(&key);
        pass.mark_capacity_complete();

        // The in-flight batch ran to completion — with a failure. The pass
        // is capacity-completed, so it resolves capacity-skipped instead of
        // re-winning a claim it can no longer fetch.
        pass.release_failed(&key);
        assert!(pass.take_reclaimed().is_empty());
        assert!(pass.is_drained());
        assert!(set.is_empty());
    }

    #[tokio::test]
    async fn drained_wakes_when_the_last_tuple_resolves() {
        let set = ClaimSet::new();
        let fetcher = set.register_pass();
        let waiter = set.register_pass();
        let key = inline("artifact-a", 1_000);

        assert_eq!(fetcher.list(key.clone()), ListDecision::Claimed);
        assert_eq!(waiter.list(key.clone()), ListDecision::Waiting);

        let drained = waiter.drained();
        fetcher.resolve_applied(&key);
        tokio::time::timeout(Duration::from_secs(5), drained)
            .await
            .expect("drained wakes after the resolving pass applies");
    }

    #[tokio::test]
    async fn changed_wakes_a_waiter_on_a_reclaim_win() {
        let set = ClaimSet::new();
        let fetcher = set.register_pass();
        let waiter = set.register_pass();
        let key = inline("artifact-a", 1_000);

        assert_eq!(fetcher.list(key.clone()), ListDecision::Claimed);
        assert_eq!(waiter.list(key.clone()), ListDecision::Waiting);

        let changed = waiter.changed();
        fetcher.resolve_absent(&key);
        tokio::time::timeout(Duration::from_secs(5), changed)
            .await
            .expect("changed wakes on the re-claim win");
        assert_eq!(waiter.take_reclaimed(), vec![key]);
    }

    // ---- Property: randomized interleavings -------------------------------
    //
    // Drives arbitrary interleavings of listing, batch dispatch, batch
    // failure, absent resolution, capacity completion, and cancellation over
    // a shared tuple universe, with a seeded (reproducible) schedule. The
    // named correctness invariant: every listed tuple eventually reaches a
    // terminal resolution for every listing pass — no leaked claims, no
    // stuck completions — and the set is empty when no passes are in flight.

    fn next_random(seed: &mut u64) -> u64 {
        *seed = seed
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        *seed >> 33
    }

    fn shuffled(mut values: Vec<ClaimKey>, seed: &mut u64) -> Vec<ClaimKey> {
        for index in (1..values.len()).rev() {
            let other = (next_random(seed) % (index as u64 + 1)) as usize;
            values.swap(index, other);
        }
        values
    }

    struct ModelPass {
        guard: PassClaimGuard,
        to_list: Vec<ClaimKey>,
        next_index: usize,
        /// Claims this pass believes it holds — Claimed decisions plus
        /// taken re-claims, minus resolutions, releases, and the automatic
        /// capacity-completion release of non-in-flight segmented claims.
        held: BTreeSet<ClaimKey>,
        in_flight: BTreeSet<ClaimKey>,
        capacity_complete: bool,
    }

    impl ModelPass {
        fn new(set: &Arc<ClaimSet>, to_list: Vec<ClaimKey>) -> Self {
            Self {
                guard: set.register_pass(),
                to_list,
                next_index: 0,
                held: BTreeSet::new(),
                in_flight: BTreeSet::new(),
                capacity_complete: false,
            }
        }

        fn list_next(&mut self) {
            let Some(key) = self.to_list.get(self.next_index).cloned() else {
                return;
            };
            self.next_index += 1;
            let decision = self.guard.list(key.clone());
            let must_skip =
                self.capacity_complete && key.kind == BackfillRecordKind::SegmentArtifact;
            assert_eq!(
                decision == ListDecision::CapacitySkipped,
                must_skip,
                "capacity-skip exactly for segmented tuples of a capacity-completed pass"
            );
            if decision == ListDecision::Claimed {
                self.held.insert(key);
            }
        }

        fn take_reclaimed(&mut self) {
            for key in self.guard.take_reclaimed() {
                assert!(
                    !(self.capacity_complete && key.kind == BackfillRecordKind::SegmentArtifact),
                    "a capacity-completed pass must never re-claim a segmented tuple"
                );
                self.held.insert(key);
            }
        }

        fn resolve_one(&mut self, seed: &mut u64) {
            let Some(key) = self
                .held
                .iter()
                .nth((next_random(seed) as usize) % self.held.len().max(1))
                .cloned()
            else {
                return;
            };
            match next_random(seed) % 4 {
                0 => {
                    self.guard.mark_in_flight(&key);
                    self.in_flight.insert(key);
                    return;
                }
                1 => self.guard.resolve_applied(&key),
                2 => self.guard.resolve_absent(&key),
                _ => self.guard.release_failed(&key),
            }
            self.held.remove(&key);
            self.in_flight.remove(&key);
        }

        fn mark_capacity_complete(&mut self) {
            if self.capacity_complete {
                return;
            }
            self.guard.mark_capacity_complete();
            self.capacity_complete = true;
            // Mirror the automatic release: segmented claims not in an
            // in-flight batch are no longer held.
            self.held.retain(|key| {
                key.kind != BackfillRecordKind::SegmentArtifact || self.in_flight.contains(key)
            });
        }

        fn drain_step(&mut self, seed: &mut u64) {
            while self.next_index < self.to_list.len() {
                self.list_next();
            }
            self.take_reclaimed();
            while let Some(key) = self.held.iter().next().cloned() {
                if next_random(seed).is_multiple_of(2) {
                    self.guard.resolve_applied(&key);
                } else {
                    self.guard.resolve_absent(&key);
                }
                self.held.remove(&key);
                self.in_flight.remove(&key);
            }
        }
    }

    fn tuple_universe() -> Vec<ClaimKey> {
        (0..10u64)
            .map(|index| {
                let id = format!("record-{index}");
                match index % 3 {
                    0 => segment(&id, 1_000 + index),
                    1 => inline(&id, 1_000 + index),
                    _ => tombstone(&id, 1_000 + index),
                }
            })
            .collect()
    }

    fn run_schedule(mut seed: u64) {
        let set = ClaimSet::new();
        let universe = tuple_universe();
        let mut passes: Vec<ModelPass> = (0..4)
            .map(|_| ModelPass::new(&set, shuffled(universe.clone(), &mut seed)))
            .collect();
        let mut cancels_left = 2;

        for _ in 0..300 {
            if passes.is_empty() {
                break;
            }
            let index = (next_random(&mut seed) as usize) % passes.len();
            match next_random(&mut seed) % 100 {
                0..=39 => passes[index].list_next(),
                40..=54 => passes[index].take_reclaimed(),
                55..=89 => {
                    let pass = &mut passes[index];
                    pass.resolve_one(&mut seed);
                }
                90..=95 => passes[index].mark_capacity_complete(),
                _ => {
                    if cancels_left > 0 {
                        cancels_left -= 1;
                        drop(passes.swap_remove(index));
                    }
                }
            }
            set.assert_invariants();
        }

        // A successor pass joins after the chaos and must list cleanly.
        passes.push(ModelPass::new(&set, shuffled(universe, &mut seed)));

        // Drain to quiescence: every surviving pass finishes listing and
        // resolves everything it holds; re-claims bounce at most once per
        // referencing pass, so this terminates fast — a round cap turns a
        // stuck completion into a failure instead of a hang.
        let mut rounds = 0;
        loop {
            for pass in &mut passes {
                pass.drain_step(&mut seed);
            }
            set.assert_invariants();
            if passes.iter().all(|pass| pass.guard.is_drained()) {
                break;
            }
            rounds += 1;
            assert!(rounds < 1_000, "stuck completion for seed {seed:#x}");
        }

        // Every pass drained ⇒ no references remain ⇒ no leaked claims.
        assert!(set.is_empty(), "leaked claims for seed {seed:#x}");
        drop(passes);
        assert!(set.is_empty());
    }

    #[test]
    fn randomized_interleavings_leave_no_leaked_claims_and_no_stuck_completions() {
        for seed in 0..64u64 {
            run_schedule(0x5eed_c1a1_0000 + seed);
        }
    }
}
