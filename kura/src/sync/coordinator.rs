//! Opens and closes the pull links the role rule asks for, one task per
//! link, and answers the two questions the rest of the node asks about them:
//! is this node the gateway, and has its bootstrap settled (design §3.6).

use std::{
    collections::{BTreeMap, HashMap},
    sync::{Arc, Mutex, PoisonError},
    time::{Duration, Instant},
};

use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;
use tracing::{Instrument, info};

use crate::{
    state::SharedState,
    sync::roles::{RoleInputs, Roles, derive_roles},
    utils::now_ms,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LinkKind {
    Replica,
    Region,
}

impl LinkKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Replica => "replica",
            Self::Region => "region",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LinkPhase {
    /// Snapshot taken or pending, backward pass running.
    Bootstrapping,
    /// Reading forward.
    Forward,
    /// The last attempt failed; retrying on backoff.
    Retrying,
}

impl LinkPhase {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Bootstrapping => "bootstrapping",
            Self::Forward => "forward",
            Self::Retrying => "retrying",
        }
    }
}

/// What a link task last reported about itself.
#[derive(Clone, Debug)]
pub struct LinkStatus {
    pub kind: LinkKind,
    pub peer: String,
    pub region: String,
    pub phase: LinkPhase,
    /// The bootstrap outcome readiness waits on: the initial backward pass
    /// completed and the first forward page applied, or the failure budget
    /// was spent (ready-but-cold, as the backfill cycle already allows).
    pub settled: bool,
    pub last_success: Option<Instant>,
    /// Replica links: rows between our cursor and the sibling's head.
    pub lag_entries: u64,
}

/// Shared between a link task and the coordinator.
pub struct LinkStatusCell {
    status: Mutex<LinkStatus>,
}

impl LinkStatusCell {
    fn new(status: LinkStatus) -> Arc<Self> {
        Arc::new(Self {
            status: Mutex::new(status),
        })
    }

    pub fn update(&self, update: impl FnOnce(&mut LinkStatus)) {
        let mut status = self.status.lock().unwrap_or_else(PoisonError::into_inner);
        update(&mut status);
    }

    pub fn snapshot(&self) -> LinkStatus {
        self.status
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .clone()
    }
}

struct Link {
    cancel: CancellationToken,
    status: Arc<LinkStatusCell>,
    _handle: JoinHandle<()>,
}

#[derive(Default)]
struct Links {
    replica: HashMap<String, Link>,
    region: HashMap<String, Link>,
}

pub struct SyncCoordinator {
    links: Mutex<Links>,
    roles: Mutex<Roles>,
    role_known: Mutex<bool>,
    /// When this process started: the reference for "no sibling has asked
    /// for the whole stale-peer window" before any consumer was seen.
    started_at: Instant,
    feed_deactivation_in_flight: Mutex<bool>,
}

impl Default for SyncCoordinator {
    fn default() -> Self {
        Self::new()
    }
}

impl SyncCoordinator {
    pub fn new() -> Self {
        Self {
            links: Mutex::new(Links::default()),
            roles: Mutex::new(Roles::default()),
            role_known: Mutex::new(false),
            started_at: Instant::now(),
            feed_deactivation_in_flight: Mutex::new(false),
        }
    }

    pub fn roles(&self) -> Roles {
        self.roles
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .clone()
    }

    pub fn own_gateway(&self) -> bool {
        self.roles().own_gateway
    }

    /// One level-triggered evaluation per membership tick: derive the roles
    /// from the current view and reconcile the link tasks against them.
    pub fn evaluate(self: &Arc<Self>, app: &SharedState) {
        let views = app.peer_views.load();
        let published = app.published_roles.load();
        let roles = derive_roles(&RoleInputs {
            own_url: &app.config.node_url,
            own_region: &app.config.region,
            own_pulling: app.replication_pull(),
            own_serving: app.runtime.is_serving(),
            own_draining: app.runtime.is_draining(),
            peers: &views,
            published: &published,
        });

        let previous = std::mem::replace(
            &mut *self.roles.lock().unwrap_or_else(PoisonError::into_inner),
            roles.clone(),
        );
        let mut role_known = self
            .role_known
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        if !*role_known || previous.own_gateway != roles.own_gateway {
            if *role_known {
                app.metrics.record_gateway_role_change();
            }
            *role_known = true;
            info!(
                gateway = roles.own_gateway,
                siblings = ?roles.siblings,
                remote_gateways = ?roles.remote_gateways,
                push_targets = roles.push_targets.len(),
                "replication roles derived"
            );
        }
        drop(role_known);
        app.metrics.update_gateway_role(roles.own_gateway);

        let desired_region: BTreeMap<String, String> = if roles.own_gateway {
            roles.remote_gateways.iter().cloned().collect()
        } else {
            BTreeMap::new()
        };
        let mut links = self.links.lock().unwrap_or_else(PoisonError::into_inner);
        reconcile(
            &mut links.replica,
            roles
                .siblings
                .iter()
                .map(|peer| (peer.clone(), app.config.region.clone())),
            |peer, region| spawn_link(app, LinkKind::Replica, peer, region),
        )
        .into_iter()
        .for_each(|closed| app.metrics.clear_sync_forward_cursor_lag(&closed.peer));
        reconcile(
            &mut links.region,
            desired_region.into_iter(),
            |peer, region| spawn_link(app, LinkKind::Region, peer, region),
        )
        .into_iter()
        .for_each(|closed| app.metrics.clear_region_sync_gauges(&closed.region));
        self.observe_feed(app);
        app.metrics
            .update_sync_pull_links("replica", links.replica.len());
        app.metrics
            .update_sync_pull_links("region", links.region.len());
        for link in links.region.values() {
            let status = link.status.snapshot();
            let age = status
                .last_success
                .map_or(u64::MAX / 2, |at| at.elapsed().as_secs());
            app.metrics
                .set_region_sync_last_success_age(&status.region, age);
            if let Ok(Some(watermark)) = app.store.sync_watermark(&status.region) {
                app.metrics.set_region_watermark_age(
                    &status.region,
                    now_ms().saturating_sub(watermark) / 1000,
                );
            }
        }
    }

    /// The feed's gauges, and its switch-off once no sibling has asked for
    /// the whole stale-peer window (design §3.1).
    fn observe_feed(self: &Arc<Self>, app: &SharedState) {
        let feed = app.store.sync_feed();
        app.metrics.update_sync_feed_depth(feed.depth());
        if !feed.enabled() {
            return;
        }
        let stale = Duration::from_secs(app.config.sync_feed_stale_peer_secs);
        let last_seen = feed.last_consumer_seen().unwrap_or(self.started_at);
        if last_seen.elapsed() < stale {
            return;
        }
        let mut in_flight = self
            .feed_deactivation_in_flight
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        if *in_flight {
            return;
        }
        *in_flight = true;
        let task_app = app.clone();
        let coordinator = Arc::clone(self);
        tokio::spawn(async move {
            if let Err(error) = task_app.store.sync_feed_deactivate().await {
                tracing::warn!("arrival feed deactivation failed: {error}");
            }
            *coordinator
                .feed_deactivation_in_flight
                .lock()
                .unwrap_or_else(PoisonError::into_inner) = false;
        });
    }

    /// Every link this node keeps open, for `/status/cluster`.
    pub fn link_statuses(&self) -> Vec<LinkStatus> {
        let links = self.links.lock().unwrap_or_else(PoisonError::into_inner);
        links
            .replica
            .values()
            .chain(links.region.values())
            .map(|link| link.status.snapshot())
            .collect()
    }

    /// The readiness term (design §3.6): with a sibling, every replica link
    /// settled; without one — a region of one — every region link settled.
    /// A node that is not pulling has nothing to settle here.
    pub fn bootstrap_settled(&self, pulling: bool) -> bool {
        if !pulling {
            return true;
        }
        let links = self.links.lock().unwrap_or_else(PoisonError::into_inner);
        if !links.replica.is_empty() {
            return links
                .replica
                .values()
                .all(|link| link.status.snapshot().settled);
        }
        links
            .region
            .values()
            .all(|link| link.status.snapshot().settled)
    }

    /// Cancels every link; the drain path calls it so no pass keeps writing
    /// while the process exits.
    pub fn shutdown(&self) {
        let mut links = self.links.lock().unwrap_or_else(PoisonError::into_inner);
        for link in links.replica.values().chain(links.region.values()) {
            link.cancel.cancel();
        }
        links.replica.clear();
        links.region.clear();
    }
}

/// Returns the statuses of the links it closed.
fn reconcile(
    links: &mut HashMap<String, Link>,
    desired: impl Iterator<Item = (String, String)>,
    spawn: impl Fn(&str, &str) -> Link,
) -> Vec<LinkStatus> {
    let desired: BTreeMap<String, String> = desired.collect();
    let stale: Vec<String> = links
        .keys()
        .filter(|peer| !desired.contains_key(*peer))
        .cloned()
        .collect();
    let mut closed = Vec::new();
    for peer in stale {
        if let Some(link) = links.remove(&peer) {
            info!(peer, "closing pull link: the role no longer names it");
            link.cancel.cancel();
            closed.push(link.status.snapshot());
        }
    }
    for (peer, region) in desired {
        if !links.contains_key(&peer) {
            info!(peer, region, "opening pull link");
            links.insert(peer.clone(), spawn(&peer, &region));
        }
    }
    closed
}

fn spawn_link(app: &SharedState, kind: LinkKind, peer: &str, region: &str) -> Link {
    let cancel = CancellationToken::new();
    let status = LinkStatusCell::new(LinkStatus {
        kind,
        peer: peer.to_owned(),
        region: region.to_owned(),
        phase: LinkPhase::Bootstrapping,
        settled: false,
        last_success: None,
        lag_entries: 0,
    });
    let task_app = app.clone();
    let task_peer = peer.to_owned();
    let task_region = region.to_owned();
    let task_cancel = cancel.clone();
    let task_status = status.clone();
    let handle = tokio::spawn(
        async move {
            match kind {
                LinkKind::Replica => {
                    crate::sync::replica::run(task_app, task_peer, task_cancel, task_status).await;
                }
                LinkKind::Region => {
                    crate::sync::region::run(
                        task_app,
                        task_peer,
                        task_region,
                        task_cancel,
                        task_status,
                    )
                    .await;
                }
            }
        }
        .in_current_span(),
    );
    Link {
        cancel,
        status,
        _handle: handle,
    }
}

/// Exponential backoff shared by both link tasks: the backfill's request
/// backoff constants, so a failing link paces itself like a failing pass.
pub(crate) fn backoff(attempt: u32) -> Duration {
    let base = crate::constants::BACKFILL_RETRY_BACKOFF_BASE_MS;
    let max = crate::constants::BACKFILL_RETRY_BACKOFF_MAX_MS;
    Duration::from_millis(base.saturating_mul(1_u64 << attempt.min(16)).min(max))
}

/// The backoff between failed passes (bootstrap retries), the lifecycle's
/// pass-retry constants.
pub(crate) fn pass_backoff(attempt: u32) -> Duration {
    let base = crate::constants::BACKFILL_PASS_RETRY_BACKOFF_BASE_MS;
    let max = crate::constants::BACKFILL_PASS_RETRY_BACKOFF_MAX_MS;
    Duration::from_millis(base.saturating_mul(1_u64 << attempt.min(16)).min(max))
}
