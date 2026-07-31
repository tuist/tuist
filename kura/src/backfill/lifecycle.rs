//! Level-triggered backfill lifecycle: the node-side state machine that
//! decides, at membership cadence, which peers need a pass, runs one pass per
//! peer at a time, cancels on peer loss, retries with bounded backoff under a
//! non-resetting initial-cycle failure budget, and persists per-peer
//! watermarks on completion. Selected at boot by `KURA_BACKFILL_ENABLED`; the
//! legacy bootstrap walker runs untouched when the flag is off, and the two
//! paths share no state.
//!
//! The scheduling rules live in [`LifecycleMachine`], a synchronous state
//! machine that consumes membership ticks and pass resolutions and emits
//! [`Action`]s — so every transition is testable with injected outcomes,
//! without a network. The async shell ([`BackfillLifecycle`]) owns the pass
//! tasks: it spawns them, wires cancellation tokens, converts pass outcomes
//! into resolutions (watermark writes, wall-clock-cap conversions), and feeds
//! them back into the machine.

use std::{
    collections::{BTreeMap, BTreeSet, HashMap},
    pin::pin,
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, Ordering},
    },
    time::Duration,
};

use tokio::time::Instant;
use tokio_util::sync::CancellationToken;
use tracing::{Instrument, info, warn};

use crate::{
    backfill::{
        claims::ClaimSet,
        pass::{BackfillPassOutcome, BackfillPassTuning, run_backfill_pass_with_tuning},
        window::{advance_watermark, compute_window},
    },
    constants::{
        BACKFILL_CAP_POLL_INTERVAL_MS, BACKFILL_INITIAL_CYCLE_FAILURE_BUDGET,
        BACKFILL_PASS_RETRY_BACKOFF_BASE_MS, BACKFILL_PASS_RETRY_BACKOFF_MAX_MS,
        BACKFILL_RETRYABLE_WAIT_CAP_MS, BACKFILL_SEAM_FOLLOWUP_DELAY_MS,
    },
    state::{MembershipUpdate, SharedState},
    utils::now_ms,
};

/// Why a peer's failure budget was charged. The distinction feeds Unit 9's
/// cycle mode: a budget consumed purely by capability-class waits resolves
/// the peer *capability-excluded* (it stops gating readiness without
/// degrading the cycle), while any real failure resolves it degraded.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BudgetChargeKind {
    /// A hard pass failure, or a cap conversion whose budget-exempt retries
    /// included non-capability classes (backpressure, tmp budget).
    Real,
    /// A cap conversion whose budget-exempt retries were purely the
    /// capability classes (not-capable/endpoint-absent, index-building).
    Capability,
}

/// The shell's summary of one fully terminated pass, fed to the machine after
/// the pass future resolved — the claim guard has dropped by then, so claim
/// release strictly precedes any successor re-claim the machine schedules.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PassResolution {
    Completed,
    Failed,
    /// Cooperative cancellation. `budget_charge` is `None` for a peer-loss
    /// cancel (never charged) and `Some` when the retryable-wait cap
    /// converted the pass into a budget-charged failure.
    Cancelled {
        budget_charge: Option<BudgetChargeKind>,
    },
}

/// Terminal status of one initial-cycle peer, the per-peer input of Unit 9's
/// cycle mode (`pending` / `complete` / `degraded`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PeerBackfillStatus {
    /// Passes outstanding: needed, in flight, dirty, backing off, or a seam
    /// follow-up pending — and budget remains.
    Pending,
    /// At least one pass completed and nothing is outstanding.
    Completed,
    /// Budget exhausted with at least one real-failure charge; background
    /// retries continue and a later completion advances this to `Completed`.
    BudgetExhaustedReal,
    /// Budget exhausted purely by capability-class charges: the peer stops
    /// gating readiness without degrading the cycle (a pre-AB bystander).
    BudgetExhaustedCapability,
    /// The peer left the membership view with nothing outstanding;
    /// rediscovery starts fresh and never gates first readiness again.
    Removed,
}

/// Mode of the initial join cycle, reported as `backfill_initial_cycle` in
/// the rollout-status JSON and consumed by the kura-controller's promotion
/// gate (Unit 9b). A mode rather than a boolean: a budget-exhausted cycle
/// must not read as caught-up.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BackfillInitialCycleMode {
    /// The cycle is still running (membership not fixed yet, or in-cycle
    /// peers have passes outstanding under budget).
    Pending,
    /// The cycle settled and every in-cycle peer resolved cleanly: completed,
    /// removed, or capability-excluded (a never-capable bystander must not
    /// degrade the cycle).
    Complete,
    /// The cycle settled with at least one in-cycle peer exhausting its
    /// budget through real failures. Not terminal: background retries that
    /// complete the pass advance the mode to `Complete`.
    Degraded,
}

impl BackfillInitialCycleMode {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Complete => "complete",
            Self::Degraded => "degraded",
        }
    }

    pub fn as_i64(&self) -> i64 {
        match self {
            Self::Pending => 0,
            Self::Complete => 1,
            Self::Degraded => 2,
        }
    }
}

/// Snapshot of the initial join cycle for the latched readiness gate and the
/// rollout report.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BackfillCycleSnapshot {
    /// Whether the cycle membership has been fixed (initial discovery ∪ first
    /// control-plane peer view). Until then every discovered peer gates.
    pub cycle_fixed: bool,
    /// The fixed (or still-accumulating) initial-cycle peer set.
    pub cycle_peers: BTreeSet<String>,
    pub statuses: BTreeMap<String, PeerBackfillStatus>,
    /// In-cycle peers with passes outstanding under budget — the node is
    /// "backfilling" while this is non-zero (or the cycle is not yet fixed).
    pub backfilling_peers: usize,
    pub budget_exhausted_real: usize,
    pub budget_exhausted_capability: usize,
    /// The cycle is fixed and no in-cycle peer has passes outstanding.
    pub settled: bool,
}

impl BackfillCycleSnapshot {
    pub fn is_backfilling(&self) -> bool {
        !self.settled
    }

    /// Derives the cycle mode: `pending` until settled, then `degraded` while
    /// any in-cycle peer sits budget-exhausted on real failures, `complete`
    /// otherwise (completed, removed, and capability-excluded peers all count
    /// complete). Statuses are recomputed per snapshot, so a real-failure
    /// peer whose background retries later complete moves the mode
    /// `degraded → complete` without the readiness latch ever regressing.
    pub fn initial_cycle_mode(&self) -> BackfillInitialCycleMode {
        if !self.settled {
            BackfillInitialCycleMode::Pending
        } else if self.budget_exhausted_real > 0 {
            BackfillInitialCycleMode::Degraded
        } else {
            BackfillInitialCycleMode::Complete
        }
    }
}

/// One membership-cadence evaluation input.
pub(crate) struct MembershipTick<'a> {
    pub discovered: &'a [String],
    pub lost: &'a [String],
    /// Both discovery gates hold: initial discovery completed and the
    /// control-plane peer view arrived. The first settled tick fixes the
    /// initial-cycle membership.
    pub view_settled: bool,
    /// The control-plane peer view, unioned into the cycle at fix time.
    pub control_plane_peers: &'a [String],
    /// Memory admission for background work; when false no new pass starts
    /// this tick (the level trigger re-fires next tick).
    pub admission: bool,
}

#[derive(Debug)]
enum Action {
    StartPass(String),
    CancelPass(String),
    BudgetCharged {
        peer: String,
        kind: BudgetChargeKind,
        remaining: u32,
        exhausted: bool,
    },
}

#[derive(Debug, Default)]
struct PeerBudget {
    charges: u32,
    capability_charges: u32,
}

impl PeerBudget {
    fn exhausted(&self) -> bool {
        self.charges >= BACKFILL_INITIAL_CYCLE_FAILURE_BUDGET
    }

    fn purely_capability(&self) -> bool {
        self.charges > 0 && self.capability_charges == self.charges
    }
}

#[derive(Debug)]
struct PeerEntry {
    /// False once the peer left the membership view while its cancelled pass
    /// is still terminating; the entry (and the per-peer slot) survives until
    /// the pass reports, which is what serializes claim release before any
    /// successor re-claim.
    present: bool,
    in_flight: bool,
    needed: bool,
    /// Rediscovered while a pass held the slot: one fresh pass with a new
    /// window top runs after the current one ends. Also covers the residual
    /// sub-tick flap seam only partially — a peer that dies and returns
    /// between membership evaluations produces neither lost nor discovered,
    /// which is accepted (bounded by heartbeat cadence, repaired by the next
    /// re-join pass and narrowed by the seam follow-up below).
    dirty: bool,
    backoff_until: Option<Instant>,
    consecutive_failures: u32,
    completed_pass: bool,
    /// The pending seam follow-up: after the first completed pass the peer is
    /// marked dirty once, ~2× the membership cadence later, validated against
    /// the membership view at fire time (loss drops the timer for good).
    seam_fire_at: Option<Instant>,
    seam_used: bool,
}

impl PeerEntry {
    fn discovered() -> Self {
        Self {
            present: true,
            in_flight: false,
            needed: true,
            dirty: false,
            backoff_until: None,
            consecutive_failures: 0,
            completed_pass: false,
            seam_fire_at: None,
            seam_used: false,
        }
    }

    /// Whether the peer still has passes outstanding: the "backfilling"
    /// predicate's per-peer term.
    fn outstanding(&self) -> bool {
        self.present
            && (self.in_flight
                || self.needed
                || self.dirty
                || self.backoff_until.is_some()
                || self.seam_fire_at.is_some())
    }
}

/// The synchronous scheduling core. Holds no tasks, tokens, or clocks of its
/// own — callers pass `now` — so every transition is drivable from tests.
#[derive(Debug, Default)]
struct LifecycleMachine {
    peers: BTreeMap<String, PeerEntry>,
    /// Failure budgets keyed by peer identity (node URL). Never cleared on
    /// removal or rediscovery within the process lifetime: a flapping peer
    /// that reset its own budget would gate first readiness forever.
    budgets: BTreeMap<String, PeerBudget>,
    cycle_fixed: bool,
    cycle_peers: BTreeSet<String>,
}

impl LifecycleMachine {
    fn evaluate(&mut self, tick: &MembershipTick<'_>, now: Instant) -> Vec<Action> {
        let mut actions = Vec::new();

        for peer in tick.lost {
            let Some(entry) = self.peers.get_mut(peer) else {
                continue;
            };
            // Removal clears dirty/failed/seam state but never the budget.
            entry.present = false;
            entry.needed = false;
            entry.dirty = false;
            entry.backoff_until = None;
            entry.consecutive_failures = 0;
            entry.seam_fire_at = None;
            if entry.in_flight {
                actions.push(Action::CancelPass(peer.clone()));
            } else {
                self.peers.remove(peer);
            }
        }

        for peer in tick.discovered {
            if !self.cycle_fixed {
                self.cycle_peers.insert(peer.clone());
            }
            match self.peers.get_mut(peer) {
                Some(entry) if entry.in_flight => {
                    entry.present = true;
                    entry.dirty = true;
                }
                Some(entry) => {
                    entry.present = true;
                    entry.needed = true;
                }
                None => {
                    self.peers.insert(peer.clone(), PeerEntry::discovered());
                }
            }
        }

        if !self.cycle_fixed && tick.view_settled {
            // Fix the initial-cycle membership at (initial discovery ∪ first
            // control-plane peer view). Peers discovered after this point are
            // ordinary re-join backfills that never gate first readiness —
            // their passes still run.
            self.cycle_peers
                .extend(tick.control_plane_peers.iter().cloned());
            self.cycle_peers.extend(
                self.peers
                    .iter()
                    .filter(|(_, entry)| entry.present)
                    .map(|(peer, _)| peer.clone()),
            );
            self.cycle_fixed = true;
        }

        for (peer, entry) in &mut self.peers {
            if !entry.present {
                continue;
            }
            if entry.seam_fire_at.is_some_and(|fire_at| now >= fire_at) {
                // Validated against the current membership view at fire time
                // by construction: a lost peer's timer was already dropped.
                entry.seam_fire_at = None;
                if entry.in_flight {
                    entry.dirty = true;
                } else {
                    entry.needed = true;
                }
            }
            if tick.admission
                && entry.needed
                && !entry.in_flight
                && entry.backoff_until.is_none_or(|until| now >= until)
            {
                entry.in_flight = true;
                entry.needed = false;
                entry.backoff_until = None;
                actions.push(Action::StartPass(peer.clone()));
            }
        }

        actions
    }

    fn on_pass_finished(
        &mut self,
        peer: &str,
        resolution: PassResolution,
        now: Instant,
    ) -> Vec<Action> {
        let mut actions = Vec::new();
        if !self.peers.contains_key(peer) {
            return actions;
        }

        // Budget charges land even when the resolution races removal: the
        // budget is keyed by identity and must survive the flap.
        let charge = match resolution {
            PassResolution::Failed => Some(BudgetChargeKind::Real),
            PassResolution::Cancelled { budget_charge } => budget_charge,
            PassResolution::Completed => None,
        };
        if let Some(kind) = charge {
            let budget = self.budgets.entry(peer.to_owned()).or_default();
            let was_exhausted = budget.exhausted();
            budget.charges = budget.charges.saturating_add(1);
            if kind == BudgetChargeKind::Capability {
                budget.capability_charges = budget.capability_charges.saturating_add(1);
            }
            actions.push(Action::BudgetCharged {
                peer: peer.to_owned(),
                kind,
                remaining: BACKFILL_INITIAL_CYCLE_FAILURE_BUDGET.saturating_sub(budget.charges),
                exhausted: !was_exhausted && budget.exhausted(),
            });
        }

        let entry = self.peers.get_mut(peer).expect("checked above");
        entry.in_flight = false;
        if !entry.present {
            // Lost mid-pass: the slot is now free and the entry goes with it;
            // rediscovery re-enters through the discovered path with a fresh
            // window.
            self.peers.remove(peer);
            return actions;
        }

        match resolution {
            PassResolution::Completed => {
                entry.consecutive_failures = 0;
                entry.backoff_until = None;
                let first_completion = !entry.completed_pass;
                entry.completed_pass = true;
                if first_completion && !entry.seam_used {
                    entry.seam_used = true;
                    entry.seam_fire_at =
                        Some(now + Duration::from_millis(BACKFILL_SEAM_FOLLOWUP_DELAY_MS));
                }
                if entry.dirty {
                    entry.dirty = false;
                    entry.needed = true;
                }
            }
            PassResolution::Failed
            | PassResolution::Cancelled {
                budget_charge: Some(_),
            } => {
                // Background retries continue after budget exhaustion —
                // bounded backoff, metered by the pass-event counter — they
                // just stop counting toward "backfilling".
                entry.dirty = false;
                entry.needed = true;
                entry.consecutive_failures = entry.consecutive_failures.saturating_add(1);
                entry.backoff_until = Some(now + pass_retry_delay(entry.consecutive_failures));
            }
            PassResolution::Cancelled {
                budget_charge: None,
            } => {
                // A peer-loss cancel whose peer was rediscovered while the
                // pass terminated: no charge, no backoff, fresh pass on the
                // next tick.
                entry.dirty = false;
                entry.needed = true;
            }
        }
        actions
    }

    fn peer_status(&self, peer: &str) -> PeerBackfillStatus {
        let budget = self.budgets.get(peer);
        let exhausted = budget.is_some_and(PeerBudget::exhausted);
        match self.peers.get(peer) {
            Some(entry) if entry.present => {
                if entry.outstanding() {
                    if exhausted {
                        if budget.is_some_and(PeerBudget::purely_capability) {
                            PeerBackfillStatus::BudgetExhaustedCapability
                        } else {
                            PeerBackfillStatus::BudgetExhaustedReal
                        }
                    } else {
                        PeerBackfillStatus::Pending
                    }
                } else if entry.completed_pass {
                    PeerBackfillStatus::Completed
                } else {
                    PeerBackfillStatus::Pending
                }
            }
            _ => PeerBackfillStatus::Removed,
        }
    }

    /// In-cycle peers still gating: outstanding passes under a live budget.
    fn backfilling_peer_count(&self) -> usize {
        self.cycle_peers
            .iter()
            .filter(|peer| {
                !self
                    .budgets
                    .get(peer.as_str())
                    .is_some_and(PeerBudget::exhausted)
                    && self
                        .peers
                        .get(peer.as_str())
                        .is_some_and(PeerEntry::outstanding)
            })
            .count()
    }

    fn snapshot(&self) -> BackfillCycleSnapshot {
        let statuses: BTreeMap<String, PeerBackfillStatus> = self
            .cycle_peers
            .iter()
            .map(|peer| (peer.clone(), self.peer_status(peer)))
            .collect();
        let budget_exhausted_real = statuses
            .values()
            .filter(|status| **status == PeerBackfillStatus::BudgetExhaustedReal)
            .count();
        let budget_exhausted_capability = statuses
            .values()
            .filter(|status| **status == PeerBackfillStatus::BudgetExhaustedCapability)
            .count();
        let backfilling_peers = self.backfilling_peer_count();
        BackfillCycleSnapshot {
            cycle_fixed: self.cycle_fixed,
            cycle_peers: self.cycle_peers.clone(),
            statuses,
            backfilling_peers,
            budget_exhausted_real,
            budget_exhausted_capability,
            settled: self.cycle_fixed && backfilling_peers == 0,
        }
    }

    fn present_peers(&self) -> Vec<String> {
        self.peers
            .iter()
            .filter(|(_, entry)| entry.present)
            .map(|(peer, _)| peer.clone())
            .collect()
    }
}

/// Bounded backoff between whole-pass retries over one peer.
fn pass_retry_delay(consecutive_failures: u32) -> Duration {
    let exponent = consecutive_failures.saturating_sub(1).min(6);
    let delay_ms = BACKFILL_PASS_RETRY_BACKOFF_BASE_MS
        .saturating_mul(1_u64 << exponent)
        .min(BACKFILL_PASS_RETRY_BACKOFF_MAX_MS);
    Duration::from_millis(delay_ms)
}

struct ActivePass {
    cancel: CancellationToken,
    // Held so tests and shutdown paths can observe termination; the pass task
    // clears its own slot via `finish_pass` after the pass future resolved
    // (guard dropped, claims released), which is the release-before-re-claim
    // ordering the design pins.
    _handle: tokio::task::JoinHandle<()>,
}

/// The async shell around [`LifecycleMachine`]: owns the per-peer pass tasks
/// and the node's one shared claim set, and is the surface the membership
/// loop drives under `KURA_BACKFILL_ENABLED`.
pub struct BackfillLifecycle {
    machine: Mutex<LifecycleMachine>,
    passes: Mutex<HashMap<String, ActivePass>>,
    claims: Arc<ClaimSet>,
    /// Peers whose watermark-age gauge has been exported, so a lost peer's
    /// series is zeroed instead of freezing at its last value.
    watermark_gauge_peers: Mutex<BTreeSet<String>>,
}

impl BackfillLifecycle {
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            machine: Mutex::new(LifecycleMachine::default()),
            passes: Mutex::new(HashMap::new()),
            claims: ClaimSet::new(),
            watermark_gauge_peers: Mutex::new(BTreeSet::new()),
        })
    }

    /// One level-triggered evaluation, called from the membership loop at its
    /// cadence with that tick's membership delta.
    pub fn evaluate(self: &Arc<Self>, app: &SharedState, update: &MembershipUpdate) {
        let control_plane_peers: Vec<String> = app
            .dynamic_peers
            .load()
            .iter()
            .filter(|url| **url != app.config.node_url)
            .cloned()
            .collect();
        let tick = MembershipTick {
            discovered: &update.discovered_peers,
            lost: &update.lost_peers,
            view_settled: update.initial_discovery_completed && !app.runtime.peer_view_pending(),
            control_plane_peers: &control_plane_peers,
            admission: app.memory.allow_background_admission(),
        };
        let actions = self
            .machine
            .lock()
            .expect("backfill lifecycle machine lock")
            .evaluate(&tick, Instant::now());
        self.apply_actions(app, actions);
        self.refresh_gauges(app);
    }

    /// Snapshot of the initial join cycle for the readiness gate and the
    /// rollout report.
    pub fn cycle_snapshot(&self) -> BackfillCycleSnapshot {
        self.machine
            .lock()
            .expect("backfill lifecycle machine lock")
            .snapshot()
    }

    /// Drives the scheduling machine without spawning pass tasks, so state
    /// and router tests can shape the cycle (peers in flight, settled,
    /// budget-exhausted) deterministically and without a network.
    #[cfg(test)]
    pub(crate) fn test_evaluate(&self, tick: &MembershipTick<'_>, now: Instant) {
        let _ = self
            .machine
            .lock()
            .expect("backfill lifecycle machine lock")
            .evaluate(tick, now);
    }

    #[cfg(test)]
    pub(crate) fn test_finish_pass(&self, peer: &str, resolution: PassResolution, now: Instant) {
        let _ = self
            .machine
            .lock()
            .expect("backfill lifecycle machine lock")
            .on_pass_finished(peer, resolution, now);
    }

    fn apply_actions(self: &Arc<Self>, app: &SharedState, actions: Vec<Action>) {
        for action in actions {
            match action {
                Action::StartPass(peer) => self.spawn_pass(app, peer),
                Action::CancelPass(peer) => {
                    info!(
                        peer,
                        "cancelling backfill pass: peer left the membership view"
                    );
                    if let Some(pass) = self
                        .passes
                        .lock()
                        .expect("backfill lifecycle passes lock")
                        .get(&peer)
                    {
                        pass.cancel.cancel();
                    }
                }
                Action::BudgetCharged {
                    peer,
                    kind,
                    remaining,
                    exhausted,
                } => {
                    if exhausted {
                        app.metrics.record_backfill_pass_event("budget_exhausted");
                        warn!(
                            peer,
                            ?kind,
                            "backfill failure budget exhausted; the peer stops gating the initial cycle while background retries continue"
                        );
                    } else {
                        warn!(
                            peer,
                            ?kind,
                            budget_remaining = remaining,
                            "backfill pass charged the peer's failure budget"
                        );
                    }
                }
            }
        }
    }

    fn spawn_pass(self: &Arc<Self>, app: &SharedState, peer: String) {
        let cancel = CancellationToken::new();
        let lifecycle = self.clone();
        let task_app = app.clone();
        let task_peer = peer.clone();
        let task_cancel = cancel.clone();
        // The passes lock is held across the spawn so the task's own
        // `finish_pass` (which removes the slot) can never observe the map
        // before this insert.
        let mut passes = self.passes.lock().expect("backfill lifecycle passes lock");
        let handle = tokio::spawn(
            async move {
                let resolution =
                    run_managed_pass(&task_app, &task_peer, &lifecycle.claims, &task_cancel).await;
                lifecycle.finish_pass(&task_app, &task_peer, resolution);
            }
            .in_current_span(),
        );
        passes.insert(
            peer,
            ActivePass {
                cancel,
                _handle: handle,
            },
        );
    }

    /// Runs on the pass task itself, strictly after the pass future resolved:
    /// the claim guard has dropped, so clearing the slot here (and any
    /// successor pass the next tick starts) can never re-claim before the
    /// predecessor released.
    fn finish_pass(self: &Arc<Self>, app: &SharedState, peer: &str, resolution: PassResolution) {
        self.passes
            .lock()
            .expect("backfill lifecycle passes lock")
            .remove(peer);
        let actions = self
            .machine
            .lock()
            .expect("backfill lifecycle machine lock")
            .on_pass_finished(peer, resolution, Instant::now());
        self.apply_actions(app, actions);
        self.refresh_gauges(app);
    }

    fn refresh_gauges(&self, app: &SharedState) {
        let (backfilling, exhausted, present_peers) = {
            let machine = self
                .machine
                .lock()
                .expect("backfill lifecycle machine lock");
            let snapshot = machine.snapshot();
            (
                snapshot.backfilling_peers,
                snapshot.budget_exhausted_real + snapshot.budget_exhausted_capability,
                machine.present_peers(),
            )
        };
        app.metrics
            .update_backfill_cycle_peers(backfilling, exhausted);

        let now = now_ms();
        let mut exported = self
            .watermark_gauge_peers
            .lock()
            .expect("backfill watermark gauge lock");
        for peer in exported.iter() {
            if !present_peers.contains(peer) {
                app.metrics.clear_backfill_watermark_age(peer);
            }
        }
        exported.retain(|peer| present_peers.contains(peer));
        for peer in &present_peers {
            if let Ok(Some(watermark_ms)) = app.store.backfill_watermark(peer) {
                app.metrics
                    .set_backfill_watermark_age_ms(peer, now.saturating_sub(watermark_ms));
                exported.insert(peer.clone());
            }
        }
    }
}

async fn run_managed_pass(
    app: &SharedState,
    peer: &str,
    claims: &Arc<ClaimSet>,
    cancel: &CancellationToken,
) -> PassResolution {
    run_managed_pass_with_cap(
        app,
        peer,
        claims,
        cancel,
        Duration::from_millis(BACKFILL_RETRYABLE_WAIT_CAP_MS),
        Duration::from_millis(BACKFILL_CAP_POLL_INTERVAL_MS),
    )
    .await
}

/// Runs one pass end to end: window computation (watermark read + horizon),
/// the pass itself under the wall-clock cap watchdog, and the completion-side
/// watermark write. Returns the machine-facing resolution.
async fn run_managed_pass_with_cap(
    app: &SharedState,
    peer: &str,
    claims: &Arc<ClaimSet>,
    cancel: &CancellationToken,
    retryable_wait_cap: Duration,
    cap_poll: Duration,
) -> PassResolution {
    // The pass start point (R7): requester wall clock at window computation
    // time, captured before any listing request leaves.
    let pass_start_wallclock_ms = now_ms();
    let existing_watermark = match app.store.backfill_watermark(peer) {
        Ok(watermark) => watermark,
        Err(error) => {
            warn!(
                peer,
                error, "failed to read backfill watermark; running an unshallowed pass"
            );
            None
        }
    };
    let age_ordered_stats = app.store.backfill_age_ordered_stats();
    let window = compute_window(
        &age_ordered_stats,
        app.config.backfill_margin_percent,
        existing_watermark,
        pass_start_wallclock_ms,
        &app.metrics,
    );

    let guard = claims.register_pass();
    let retryable_wait_ms = Arc::new(AtomicU64::new(0));
    let mut tuning = BackfillPassTuning::from_config(&app.config);
    tuning.retryable_wait_observer = Some(retryable_wait_ms.clone());
    app.metrics.record_backfill_pass_event("started");

    let mut pass = pin!(run_backfill_pass_with_tuning(
        app, peer, window, guard, cancel, tuning
    ));
    let mut cap_converted = false;
    let outcome = tokio::select! {
        outcome = &mut pass => outcome,
        () = watch_retryable_wait_cap(&retryable_wait_ms, retryable_wait_cap, cap_poll) => {
            cap_converted = true;
            cancel.cancel();
            pass.as_mut().await
        }
    };

    match outcome {
        BackfillPassOutcome::Completed { .. } => {
            let watermark_ms = advance_watermark(existing_watermark, pass_start_wallclock_ms);
            // Written even when the completion races peer removal: the
            // monotonic guard makes a stale write harmless and rediscovery
            // benefits from the shallower window.
            if let Err(error) = app
                .store
                .write_backfill_watermark(peer, watermark_ms, now_ms())
            {
                warn!(peer, error, "failed to persist backfill watermark");
            }
            app.metrics.record_backfill_pass_event("completed");
            PassResolution::Completed
        }
        BackfillPassOutcome::Failed { .. } => {
            app.metrics.record_backfill_pass_event("failed");
            PassResolution::Failed
        }
        BackfillPassOutcome::Cancelled { stats } => {
            if cap_converted {
                // Purely-capability waits resolve the eventual exhaustion
                // capability-excluded; any non-capability exempt wait
                // (backpressure, tmp budget) makes this a real failure.
                let kind = if stats.retryable_wait == stats.capability_wait {
                    BudgetChargeKind::Capability
                } else {
                    BudgetChargeKind::Real
                };
                warn!(
                    peer,
                    retryable_wait_ms = stats.retryable_wait.as_millis() as u64,
                    capability_wait_ms = stats.capability_wait.as_millis() as u64,
                    ?kind,
                    "backfill pass exceeded the budget-exempt retry cap; converted to a budget-charged failure"
                );
                app.metrics.record_backfill_pass_event("cap_converted");
                PassResolution::Cancelled {
                    budget_charge: Some(kind),
                }
            } else {
                app.metrics.record_backfill_pass_event("cancelled");
                PassResolution::Cancelled {
                    budget_charge: None,
                }
            }
        }
    }
}

/// Resolves when the pass's cumulative budget-exempt backoff crosses the cap.
async fn watch_retryable_wait_cap(waited_ms: &AtomicU64, cap: Duration, poll: Duration) {
    loop {
        if Duration::from_millis(waited_ms.load(Ordering::Relaxed)) >= cap {
            return;
        }
        tokio::time::sleep(poll).await;
    }
}

#[cfg(test)]
mod tests {
    use axum::Router;
    use reqwest::StatusCode;
    use tokio::net::TcpListener;

    use super::*;
    use crate::{
        artifact::producer::ArtifactProducer,
        constants::{BACKFILL_WATERMARK_RETENTION_MS, BACKFILL_WATERMARK_SKEW_ALLOWANCE_MS},
        http::router,
        test_support::test_context,
    };

    fn peer_url(index: usize) -> String {
        format!("http://peer-{index}.kura.internal:7443")
    }

    fn tick_with<'a>(
        discovered: &'a [String],
        lost: &'a [String],
        control_plane_peers: &'a [String],
    ) -> MembershipTick<'a> {
        MembershipTick {
            discovered,
            lost,
            view_settled: true,
            control_plane_peers,
            admission: true,
        }
    }

    fn tick<'a>(discovered: &'a [String], lost: &'a [String]) -> MembershipTick<'a> {
        tick_with(discovered, lost, &[])
    }

    fn started_peers(actions: &[Action]) -> Vec<String> {
        actions
            .iter()
            .filter_map(|action| match action {
                Action::StartPass(peer) => Some(peer.clone()),
                _ => None,
            })
            .collect()
    }

    fn cancelled_peers(actions: &[Action]) -> Vec<String> {
        actions
            .iter()
            .filter_map(|action| match action {
                Action::CancelPass(peer) => Some(peer.clone()),
                _ => None,
            })
            .collect()
    }

    fn charges(actions: &[Action]) -> Vec<(String, BudgetChargeKind, bool)> {
        actions
            .iter()
            .filter_map(|action| match action {
                Action::BudgetCharged {
                    peer,
                    kind,
                    exhausted,
                    ..
                } => Some((peer.clone(), *kind, *exhausted)),
                _ => None,
            })
            .collect()
    }

    fn cap_converted() -> PassResolution {
        PassResolution::Cancelled {
            budget_charge: Some(BudgetChargeKind::Real),
        }
    }

    #[test]
    fn initial_discovery_starts_one_pass_per_peer_and_completions_settle_the_cycle() {
        let mut machine = LifecycleMachine::default();
        let now = Instant::now();
        let peers = vec![peer_url(1), peer_url(2)];

        let actions = machine.evaluate(&tick(&peers, &[]), now);
        assert_eq!(started_peers(&actions), peers);
        assert!(machine.snapshot().is_backfilling());
        assert_eq!(
            machine.snapshot().cycle_peers,
            peers.iter().cloned().collect()
        );

        // A repeated tick with no changes starts nothing (one pass per peer).
        let actions = machine.evaluate(&tick(&[], &[]), now);
        assert!(started_peers(&actions).is_empty());

        machine.on_pass_finished(&peer_url(1), PassResolution::Completed, now);
        assert!(machine.snapshot().is_backfilling());
        machine.on_pass_finished(&peer_url(2), PassResolution::Completed, now);

        // The seam follow-up timers are still pending, so the node keeps
        // backfilling until they fire and their passes complete.
        let snapshot = machine.snapshot();
        assert!(!snapshot.settled);
        let seam = now + Duration::from_millis(BACKFILL_SEAM_FOLLOWUP_DELAY_MS);
        let actions = machine.evaluate(&tick(&[], &[]), seam);
        assert_eq!(started_peers(&actions), peers);
        machine.on_pass_finished(&peer_url(1), PassResolution::Completed, seam);
        machine.on_pass_finished(&peer_url(2), PassResolution::Completed, seam);

        let snapshot = machine.snapshot();
        assert!(snapshot.settled);
        assert!(!snapshot.is_backfilling());
        assert_eq!(snapshot.backfilling_peers, 0);
        assert_eq!(
            snapshot.statuses.values().collect::<Vec<_>>(),
            vec![
                &PeerBackfillStatus::Completed,
                &PeerBackfillStatus::Completed
            ]
        );
    }

    #[test]
    fn rediscovery_while_in_flight_sets_dirty_and_queues_one_fresh_pass() {
        let mut machine = LifecycleMachine::default();
        let now = Instant::now();
        let peers = vec![peer_url(1)];
        machine.evaluate(&tick(&peers, &[]), now);

        // The flap: lost and rediscovered while the pass is still running.
        let actions = machine.evaluate(&tick(&[], &peers), now);
        assert_eq!(cancelled_peers(&actions), peers);
        let actions = machine.evaluate(&tick(&peers, &[]), now);
        assert!(started_peers(&actions).is_empty(), "slot still held");

        // The cancelled pass terminates; the dirty flag re-arms a fresh pass
        // with a new window top on the next tick — the flap is not swallowed.
        let actions = machine.on_pass_finished(
            &peer_url(1),
            PassResolution::Cancelled {
                budget_charge: None,
            },
            now,
        );
        assert!(
            charges(&actions).is_empty(),
            "peer-loss cancel never charges"
        );
        let actions = machine.evaluate(&tick(&[], &[]), now);
        assert_eq!(started_peers(&actions), peers);

        // Dirty during a live (uncancelled) pass queues exactly one follow-up.
        let actions = machine.evaluate(&tick(&peers, &[]), now);
        assert!(started_peers(&actions).is_empty());
        machine.on_pass_finished(&peer_url(1), PassResolution::Completed, now);
        let actions = machine.evaluate(&tick(&[], &[]), now);
        assert_eq!(started_peers(&actions), peers);
    }

    #[test]
    fn failed_pass_retries_with_backoff() {
        let mut machine = LifecycleMachine::default();
        let now = Instant::now();
        let peers = vec![peer_url(1)];
        machine.evaluate(&tick(&peers, &[]), now);

        let actions = machine.on_pass_finished(&peer_url(1), PassResolution::Failed, now);
        assert_eq!(
            charges(&actions),
            vec![(peer_url(1), BudgetChargeKind::Real, false)]
        );

        // Not retried before the backoff elapses; retried after.
        let actions = machine.evaluate(&tick(&[], &[]), now);
        assert!(started_peers(&actions).is_empty());
        let after_backoff = now + pass_retry_delay(1);
        let actions = machine.evaluate(&tick(&[], &[]), after_backoff);
        assert_eq!(started_peers(&actions), peers);

        // A second failure backs off longer.
        machine.on_pass_finished(&peer_url(1), PassResolution::Failed, after_backoff);
        let actions = machine.evaluate(&tick(&[], &[]), after_backoff + pass_retry_delay(1));
        assert!(started_peers(&actions).is_empty());
        let actions = machine.evaluate(&tick(&[], &[]), after_backoff + pass_retry_delay(2));
        assert_eq!(started_peers(&actions), peers);
        assert!(machine.snapshot().is_backfilling());
    }

    #[test]
    fn peer_lost_mid_pass_cancels_without_charge_and_rediscovery_starts_fresh() {
        let mut machine = LifecycleMachine::default();
        let now = Instant::now();
        let peers = vec![peer_url(1)];
        machine.evaluate(&tick(&peers, &[]), now);

        let actions = machine.evaluate(&tick(&[], &peers), now);
        assert_eq!(cancelled_peers(&actions), peers);
        // While the cancelled pass terminates the peer no longer gates.
        assert_eq!(machine.snapshot().backfilling_peers, 0);
        assert_eq!(
            machine.snapshot().statuses[&peer_url(1)],
            PeerBackfillStatus::Removed
        );

        let actions = machine.on_pass_finished(
            &peer_url(1),
            PassResolution::Cancelled {
                budget_charge: None,
            },
            now,
        );
        assert!(charges(&actions).is_empty());
        assert!(machine.peers.is_empty(), "entry cleared after termination");

        let actions = machine.evaluate(&tick(&peers, &[]), now);
        assert_eq!(started_peers(&actions), peers);
    }

    #[test]
    fn flapping_peer_budget_survives_removal_and_exhaustion_stops_gating() {
        let mut machine = LifecycleMachine::default();
        let mut now = Instant::now();
        let peers = vec![peer_url(1)];
        machine.evaluate(&tick(&peers, &[]), now);

        // Repeated fail → flap-out → flap-in cycles: the budget never resets.
        for round in 1..=BACKFILL_INITIAL_CYCLE_FAILURE_BUDGET {
            let actions = machine.on_pass_finished(&peer_url(1), PassResolution::Failed, now);
            let charged = charges(&actions);
            assert_eq!(charged.len(), 1);
            assert_eq!(
                charged[0].2,
                round == BACKFILL_INITIAL_CYCLE_FAILURE_BUDGET,
                "exhaustion fires exactly on the last charge"
            );
            machine.evaluate(&tick(&[], &peers), now);
            now += Duration::from_secs(1);
            let actions = machine.evaluate(&tick(&peers, &[]), now);
            // Rediscovery resets backoff (fresh pass immediately) but not the
            // budget.
            assert_eq!(started_peers(&actions), peers);
        }

        // Exhausted: the peer stops counting toward backfilling while its
        // background retries keep running.
        let snapshot = machine.snapshot();
        assert_eq!(snapshot.backfilling_peers, 0);
        assert!(snapshot.settled);
        assert_eq!(
            snapshot.statuses[&peer_url(1)],
            PeerBackfillStatus::BudgetExhaustedReal
        );
        let actions = machine.on_pass_finished(&peer_url(1), PassResolution::Failed, now);
        assert!(
            charges(&actions).iter().all(|(_, _, exhausted)| !exhausted),
            "exhaustion is reported once"
        );
        now += pass_retry_delay(2);
        let actions = machine.evaluate(&tick(&[], &[]), now);
        assert_eq!(
            started_peers(&actions),
            peers,
            "background retries continue"
        );

        // A background retry that completes advances the peer to Completed.
        machine.on_pass_finished(&peer_url(1), PassResolution::Completed, now);
        machine.evaluate(
            &tick(&[], &[]),
            now + Duration::from_millis(BACKFILL_SEAM_FOLLOWUP_DELAY_MS),
        );
        machine.on_pass_finished(&peer_url(1), PassResolution::Completed, now);
        assert_eq!(
            machine.snapshot().statuses[&peer_url(1)],
            PeerBackfillStatus::Completed
        );
    }

    #[test]
    fn dirty_then_lost_before_the_queued_pass_starts_clears_state() {
        let mut machine = LifecycleMachine::default();
        let now = Instant::now();
        let peers = vec![peer_url(1)];
        machine.evaluate(&tick(&peers, &[]), now);
        machine.evaluate(&tick(&peers, &[]), now); // dirty while in flight
        machine.evaluate(&tick(&[], &peers), now); // lost: dirty cleared, cancel

        let actions = machine.on_pass_finished(
            &peer_url(1),
            PassResolution::Cancelled {
                budget_charge: None,
            },
            now,
        );
        assert!(charges(&actions).is_empty());
        assert!(machine.peers.is_empty());
        let actions = machine.evaluate(&tick(&[], &[]), now);
        assert!(started_peers(&actions).is_empty());
        assert_eq!(machine.snapshot().backfilling_peers, 0);
    }

    #[test]
    fn seam_timer_fires_once_and_is_dropped_when_the_peer_leaves_first() {
        let mut machine = LifecycleMachine::default();
        let now = Instant::now();
        let peers = vec![peer_url(1)];
        machine.evaluate(&tick(&peers, &[]), now);
        machine.on_pass_finished(&peer_url(1), PassResolution::Completed, now);

        // The peer is removed before the seam follow-up fires: the timer is
        // validated against the membership view at fire time and dropped —
        // no ghost dirty flag wedges the backfilling predicate.
        machine.evaluate(&tick(&[], &peers), now);
        let fire = now + Duration::from_millis(BACKFILL_SEAM_FOLLOWUP_DELAY_MS);
        let actions = machine.evaluate(&tick(&[], &[]), fire);
        assert!(started_peers(&actions).is_empty());
        assert_eq!(machine.snapshot().backfilling_peers, 0);
        assert!(machine.snapshot().settled);

        // Rediscovery starts fresh: a pass, its completion, ONE seam
        // follow-up (seam_used survives via a fresh entry — the follow-up
        // re-arms because the entry is new, which is intended: a re-joined
        // peer has a fresh seam).
        let actions = machine.evaluate(&tick(&peers, &[]), fire);
        assert_eq!(started_peers(&actions), peers);
    }

    #[test]
    fn seam_followup_marks_dirty_once_after_first_completion_only() {
        let mut machine = LifecycleMachine::default();
        let now = Instant::now();
        let peers = vec![peer_url(1)];
        machine.evaluate(&tick(&peers, &[]), now);
        machine.on_pass_finished(&peer_url(1), PassResolution::Completed, now);

        // Before the delay: nothing fires.
        let actions = machine.evaluate(&tick(&[], &[]), now);
        assert!(started_peers(&actions).is_empty());

        let fire = now + Duration::from_millis(BACKFILL_SEAM_FOLLOWUP_DELAY_MS);
        let actions = machine.evaluate(&tick(&[], &[]), fire);
        assert_eq!(started_peers(&actions), peers);
        machine.on_pass_finished(&peer_url(1), PassResolution::Completed, fire);

        // The second completion does not re-arm the seam timer.
        let later = fire + Duration::from_millis(BACKFILL_SEAM_FOLLOWUP_DELAY_MS);
        let actions = machine.evaluate(&tick(&[], &[]), later);
        assert!(started_peers(&actions).is_empty());
        assert!(machine.snapshot().settled);
    }

    #[test]
    fn capability_only_exhaustion_resolves_capability_excluded() {
        let mut machine = LifecycleMachine::default();
        let mut now = Instant::now();
        let peers = vec![peer_url(1)];
        machine.evaluate(&tick(&peers, &[]), now);

        for _ in 0..BACKFILL_INITIAL_CYCLE_FAILURE_BUDGET {
            machine.on_pass_finished(
                &peer_url(1),
                PassResolution::Cancelled {
                    budget_charge: Some(BudgetChargeKind::Capability),
                },
                now,
            );
            now += Duration::from_secs(3_600);
            machine.evaluate(&tick(&[], &[]), now);
        }

        let snapshot = machine.snapshot();
        assert_eq!(
            snapshot.statuses[&peer_url(1)],
            PeerBackfillStatus::BudgetExhaustedCapability
        );
        assert_eq!(snapshot.budget_exhausted_capability, 1);
        assert_eq!(snapshot.budget_exhausted_real, 0);
        assert_eq!(snapshot.backfilling_peers, 0);
        assert!(snapshot.settled);
    }

    #[test]
    fn initial_cycle_mode_derivation_and_wire_values() {
        // The wire values are the Unit 9b promotion-gate contract: the
        // kura-controller and server reconciler parse these exact strings
        // out of `backfill_initial_cycle`.
        assert_eq!(BackfillInitialCycleMode::Pending.as_str(), "pending");
        assert_eq!(BackfillInitialCycleMode::Complete.as_str(), "complete");
        assert_eq!(BackfillInitialCycleMode::Degraded.as_str(), "degraded");
        assert_eq!(BackfillInitialCycleMode::Pending.as_i64(), 0);
        assert_eq!(BackfillInitialCycleMode::Complete.as_i64(), 1);
        assert_eq!(BackfillInitialCycleMode::Degraded.as_i64(), 2);

        let mut machine = LifecycleMachine::default();
        let mut now = Instant::now();
        let peers = vec![peer_url(1)];
        machine.evaluate(&tick(&peers, &[]), now);
        assert_eq!(
            machine.snapshot().initial_cycle_mode(),
            BackfillInitialCycleMode::Pending
        );

        // Real-failure exhaustion settles the cycle degraded.
        for _ in 0..BACKFILL_INITIAL_CYCLE_FAILURE_BUDGET {
            machine.on_pass_finished(&peer_url(1), PassResolution::Failed, now);
            now += Duration::from_secs(3_600);
            machine.evaluate(&tick(&[], &[]), now);
        }
        assert_eq!(
            machine.snapshot().initial_cycle_mode(),
            BackfillInitialCycleMode::Degraded
        );

        // Degraded is not terminal: the background retry (and seam
        // follow-up) completing advances the mode to complete.
        machine.on_pass_finished(&peer_url(1), PassResolution::Completed, now);
        let seam = now + Duration::from_millis(BACKFILL_SEAM_FOLLOWUP_DELAY_MS);
        machine.evaluate(&tick(&[], &[]), seam);
        machine.on_pass_finished(&peer_url(1), PassResolution::Completed, seam);
        assert_eq!(
            machine.snapshot().initial_cycle_mode(),
            BackfillInitialCycleMode::Complete
        );
    }

    #[test]
    fn mixed_charges_resolve_as_real_failures() {
        let mut machine = LifecycleMachine::default();
        let mut now = Instant::now();
        let peers = vec![peer_url(1)];
        machine.evaluate(&tick(&peers, &[]), now);

        machine.on_pass_finished(
            &peer_url(1),
            PassResolution::Cancelled {
                budget_charge: Some(BudgetChargeKind::Capability),
            },
            now,
        );
        for _ in 1..BACKFILL_INITIAL_CYCLE_FAILURE_BUDGET {
            now += Duration::from_secs(3_600);
            machine.evaluate(&tick(&[], &[]), now);
            machine.on_pass_finished(&peer_url(1), cap_converted(), now);
        }

        assert_eq!(
            machine.snapshot().statuses[&peer_url(1)],
            PeerBackfillStatus::BudgetExhaustedReal
        );
    }

    #[test]
    fn cycle_membership_is_fixed_at_the_first_settled_view() {
        let mut machine = LifecycleMachine::default();
        let now = Instant::now();
        let early = vec![peer_url(1)];
        let control_plane = vec![peer_url(2)];

        // Pre-settlement discoveries accumulate into the cycle.
        let unsettled = MembershipTick {
            discovered: &early,
            lost: &[],
            view_settled: false,
            control_plane_peers: &[],
            admission: true,
        };
        machine.evaluate(&unsettled, now);
        assert!(!machine.snapshot().cycle_fixed);
        assert!(machine.snapshot().is_backfilling());

        // The first settled view fixes the cycle at discovered ∪ control-plane.
        machine.evaluate(&tick_with(&[], &[], &control_plane), now);
        let snapshot = machine.snapshot();
        assert!(snapshot.cycle_fixed);
        assert_eq!(
            snapshot.cycle_peers,
            BTreeSet::from([peer_url(1), peer_url(2)])
        );

        // A peer discovered after the fix runs passes but never gates.
        let late = vec![peer_url(3)];
        let actions = machine.evaluate(&tick(&late, &[]), now);
        assert_eq!(started_peers(&actions), late);
        machine.on_pass_finished(&peer_url(1), PassResolution::Completed, now);
        let fire = now + Duration::from_millis(BACKFILL_SEAM_FOLLOWUP_DELAY_MS);
        machine.evaluate(&tick(&[], &[]), fire);
        machine.on_pass_finished(&peer_url(1), PassResolution::Completed, fire);
        let snapshot = machine.snapshot();
        // peer-2 was never discovered, so it has no outstanding passes and
        // does not gate; peer-3's in-flight pass does not gate either.
        assert_eq!(snapshot.backfilling_peers, 0);
        assert!(snapshot.settled);
        assert_eq!(snapshot.statuses[&peer_url(2)], PeerBackfillStatus::Removed);
        assert!(!snapshot.statuses.contains_key(&peer_url(3)));
    }

    #[test]
    fn admission_denial_defers_pass_starts_to_a_later_tick() {
        let mut machine = LifecycleMachine::default();
        let now = Instant::now();
        let peers = vec![peer_url(1)];
        let denied = MembershipTick {
            discovered: &peers,
            lost: &[],
            view_settled: true,
            control_plane_peers: &[],
            admission: false,
        };
        let actions = machine.evaluate(&denied, now);
        assert!(started_peers(&actions).is_empty());
        assert!(machine.snapshot().is_backfilling(), "the need is retained");

        let actions = machine.evaluate(&tick(&[], &[]), now);
        assert_eq!(started_peers(&actions), peers);
    }

    // ---- Shell + store integration -----------------------------------------

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

    async fn wait_for<F>(mut condition: F, message: &str)
    where
        F: FnMut() -> bool,
    {
        for _ in 0..600 {
            if condition() {
                return;
            }
            tokio::time::sleep(Duration::from_millis(25)).await;
        }
        panic!("timed out waiting for: {message}");
    }

    fn membership_update(discovered: Vec<String>, lost: Vec<String>) -> MembershipUpdate {
        MembershipUpdate {
            discovered_peers: discovered,
            lost_peers: lost,
            known_peer_count: 0,
            initial_discovery_completed: true,
            generation_changed: true,
        }
    }

    #[tokio::test]
    async fn lifecycle_completes_passes_advances_watermarks_and_settles() {
        let peer = test_context(|_| {}).await;
        peer.state
            .store
            .apply_replicated_inline_artifact_from_bytes(
                ArtifactProducer::Xcode,
                "ios",
                "inl-a",
                "application/octet-stream",
                b"inline-body",
                900,
                None,
                None,
            )
            .await
            .expect("inline artifact should apply");
        peer.state
            .store
            .run_backfill_index_build()
            .expect("index build should run");
        let (peer_url, _server) = spawn_server(router(peer.state.clone())).await;

        let local = test_context(|_| {}).await;
        let lifecycle = &local.state.backfill;
        let before_ms = now_ms();
        lifecycle.evaluate(
            &local.state,
            &membership_update(vec![peer_url.clone()], vec![]),
        );
        assert!(lifecycle.cycle_snapshot().is_backfilling());

        wait_for(
            || {
                local
                    .state
                    .store
                    .backfill_watermark(&peer_url)
                    .expect("watermark should read")
                    .is_some()
            },
            "first pass completion",
        )
        .await;
        let watermark = local
            .state
            .store
            .backfill_watermark(&peer_url)
            .expect("watermark should read")
            .expect("watermark should exist");
        assert!(watermark >= before_ms.saturating_sub(BACKFILL_WATERMARK_SKEW_ALLOWANCE_MS));

        // Drive ticks until the seam follow-up ran and the cycle settles.
        wait_for(
            || {
                lifecycle.evaluate(&local.state, &membership_update(vec![], vec![]));
                lifecycle.cycle_snapshot().settled
            },
            "cycle settling after the seam follow-up",
        )
        .await;
        assert_eq!(
            lifecycle.cycle_snapshot().statuses[&peer_url],
            PeerBackfillStatus::Completed
        );
        assert!(
            local
                .state
                .store
                .fetch_artifact(ArtifactProducer::Xcode, "ios", "inl-a")
                .await
                .expect("fetch should succeed")
                .is_some(),
            "the pass replicated the peer's artifact"
        );
        let rendered = local.state.metrics.render();
        assert!(rendered.contains("kura_backfill_backfilling_peers 0"));
    }

    #[tokio::test]
    async fn not_capable_peer_past_the_cap_charges_a_capability_only_failure() {
        // A pre-AB peer: every backfill route answers 404 (the not-capable
        // class), which never fails the pass on its own.
        let (peer_url, _server) = spawn_server(Router::new()).await;
        let local = test_context(|_| {}).await;

        let claims = ClaimSet::new();
        let cancel = CancellationToken::new();
        let resolution = run_managed_pass_with_cap(
            &local.state,
            &peer_url,
            &claims,
            &cancel,
            Duration::from_millis(50),
            Duration::from_millis(10),
        )
        .await;

        assert_eq!(
            resolution,
            PassResolution::Cancelled {
                budget_charge: Some(BudgetChargeKind::Capability),
            }
        );
        assert!(claims.is_empty(), "cap cancellation released all claims");
        assert!(
            local
                .state
                .store
                .backfill_watermark(&peer_url)
                .expect("watermark should read")
                .is_none(),
            "a converted pass never advances the watermark"
        );
    }

    #[tokio::test]
    async fn shedding_peer_past_the_cap_charges_a_real_failure() {
        // A peer shedding under pressure: 429 backpressure on every request —
        // budget-exempt, but not a capability class.
        let shedding = Router::new().fallback(|| async { StatusCode::TOO_MANY_REQUESTS });
        let (peer_url, _server) = spawn_server(shedding).await;
        let local = test_context(|_| {}).await;

        let claims = ClaimSet::new();
        let cancel = CancellationToken::new();
        let resolution = run_managed_pass_with_cap(
            &local.state,
            &peer_url,
            &claims,
            &cancel,
            Duration::from_millis(50),
            Duration::from_millis(10),
        )
        .await;

        assert_eq!(
            resolution,
            PassResolution::Cancelled {
                budget_charge: Some(BudgetChargeKind::Real),
            }
        );
    }

    #[tokio::test]
    async fn peer_loss_cancellation_frees_the_slot_after_termination() {
        // A hanging peer: the listing request never resolves, so only the
        // cancellation path can end the pass.
        let hanging = Router::new().fallback(|| async {
            tokio::time::sleep(Duration::from_secs(3_600)).await;
            StatusCode::OK
        });
        let (peer_url, _server) = spawn_server(hanging).await;

        let local = test_context(|_| {}).await;
        let lifecycle = &local.state.backfill;
        lifecycle.evaluate(
            &local.state,
            &membership_update(vec![peer_url.clone()], vec![]),
        );
        wait_for(
            || !lifecycle.passes.lock().expect("passes lock").is_empty(),
            "pass task registration",
        )
        .await;

        lifecycle.evaluate(
            &local.state,
            &membership_update(vec![], vec![peer_url.clone()]),
        );
        wait_for(
            || lifecycle.passes.lock().expect("passes lock").is_empty(),
            "cancelled pass termination",
        )
        .await;

        let snapshot = lifecycle.cycle_snapshot();
        assert_eq!(snapshot.backfilling_peers, 0);
        assert!(lifecycle.claims.is_empty());
        assert!(
            local
                .state
                .store
                .backfill_watermark(&peer_url)
                .expect("watermark should read")
                .is_none(),
            "a cancelled pass never advances the watermark"
        );
        let rendered = local.state.metrics.render();
        assert!(rendered.contains("event=\"cancelled\"} 1"));
    }

    #[tokio::test]
    async fn watermark_rows_survive_reopen_and_shallow_windows_after_a_flag_flip() {
        let node_url = "http://peer-a.kura.internal:7443";
        let shared_dir = tempfile::tempdir().expect("shared temp dir");
        let data_dir = shared_dir.path().join("data");
        let tmp_dir = shared_dir.path().join("tmp");

        {
            let dirs = (data_dir.clone(), tmp_dir.clone());
            let context = test_context(move |config| {
                config.data_dir = dirs.0;
                config.tmp_dir = dirs.1;
            })
            .await;
            context
                .state
                .store
                .write_backfill_watermark(node_url, 5_000, now_ms())
                .expect("watermark should write");

            // Monotonic guard: an older pass completing later never regresses
            // the row (a retried pass finishing after a dirty-triggered newer
            // pass).
            context
                .state
                .store
                .write_backfill_watermark(node_url, 4_000, now_ms())
                .expect("stale watermark write should be absorbed");
            assert_eq!(
                context
                    .state
                    .store
                    .backfill_watermark(node_url)
                    .expect("watermark should read"),
                Some(5_000)
            );
        }

        // Survives a restart (the flip-off → flip-on shape: rows sit inert
        // while the legacy walker runs, and still shallow windows after).
        let dirs = (data_dir, tmp_dir);
        let reopened = test_context(move |config| {
            config.data_dir = dirs.0;
            config.tmp_dir = dirs.1;
        })
        .await;
        let watermark = reopened
            .state
            .store
            .backfill_watermark(node_url)
            .expect("watermark should read after reopen");
        assert_eq!(watermark, Some(5_000));
        let window = compute_window(&[], 40, watermark, now_ms(), &reopened.state.metrics);
        assert_eq!(window.min_version_ms, Some(5_000));
    }

    #[tokio::test]
    async fn watermark_gc_removes_only_rows_past_retention() {
        let context = test_context(|_| {}).await;
        let now = now_ms();
        let fresh = "http://fresh.kura.internal:7443";
        let stale = "http://stale.kura.internal:7443";
        context
            .state
            .store
            .write_backfill_watermark(fresh, 1_000, now)
            .expect("fresh watermark should write");
        context
            .state
            .store
            .write_backfill_watermark(
                stale,
                2_000,
                now.saturating_sub(BACKFILL_WATERMARK_RETENTION_MS + 1),
            )
            .expect("stale watermark should write");

        let removed = context
            .state
            .store
            .gc_backfill_watermarks(now, BACKFILL_WATERMARK_RETENTION_MS)
            .expect("gc should run");
        assert_eq!(removed, 1);
        assert_eq!(
            context
                .state
                .store
                .backfill_watermark(fresh)
                .expect("fresh watermark should read"),
            Some(1_000)
        );
        // The GC'd row's only cost: the next pass runs an unbounded window.
        assert_eq!(
            context
                .state
                .store
                .backfill_watermark(stale)
                .expect("stale watermark should read"),
            None
        );
        let window = compute_window(&[], 40, None, now, &context.state.metrics);
        assert_eq!(window.min_version_ms, None);
    }
}
