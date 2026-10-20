//! Resource accounting for local and remote action scheduling.

use std::collections::BTreeMap;
use std::num::NonZeroUsize;
use std::sync::{Arc, Mutex};

use serde::{Deserialize, Serialize};
use tokio::sync::Notify;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResourceRequest {
    pub cpu_slots: usize,
    pub memory_bytes: u64,
    /// Named "shared resource" slots the action needs to hold for the
    /// duration of its run. Plugins use this to declare that they
    /// compete for a typed, host-wide resource that the cpu/memory
    /// axes can't model. The Pinned plugin, for example, asks for one
    /// `ELIXIR_COMPILE_SLOT` so the runner schedules Pinned actions
    /// in line with what the compile daemon can absorb.
    ///
    /// Skipped from JSON when empty so existing actions (which don't
    /// request any named slots) keep their action digest stable.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub slots: BTreeMap<String, usize>,
}

impl ResourceRequest {
    pub fn new(cpu_slots: usize, memory_bytes: u64) -> Self {
        Self {
            cpu_slots: if cpu_slots == 0 { 1 } else { cpu_slots },
            memory_bytes,
            slots: BTreeMap::new(),
        }
    }

    /// Attach a named-slot requirement. Repeated keys overwrite to
    /// match how a plugin would tighten its own resource declaration;
    /// passing 0 removes the entry so callers can clear an inherited
    /// default.
    #[must_use]
    pub fn with_slot(mut self, name: impl Into<String>, count: usize) -> Self {
        let name = name.into();
        if count == 0 {
            self.slots.remove(&name);
        } else {
            self.slots.insert(name, count);
        }
        self
    }

    pub fn is_default(&self) -> bool {
        *self == Self::default()
    }

    fn bounded_by(self, limits: &ResourceLimits) -> Self {
        let cpu_slots = self.cpu_slots.clamp(1, limits.cpu_slots);
        let memory_bytes = if limits.memory_bytes == 0 {
            self.memory_bytes
        } else {
            self.memory_bytes.min(limits.memory_bytes)
        };
        // Clamp each named slot request to whatever the pool publishes
        // for that name; missing pool entries default to 1 so an
        // unknown slot doesn't deadlock. Plugins that need a slot
        // should configure the pool to publish it explicitly.
        let mut slots = self.slots;
        for (name, requested) in &mut slots {
            let cap = limits.slot_limits.get(name).copied().unwrap_or(1).max(1);
            *requested = (*requested).clamp(1, cap);
        }
        Self {
            cpu_slots,
            memory_bytes,
            slots,
        }
    }
}

impl Default for ResourceRequest {
    fn default() -> Self {
        Self {
            cpu_slots: 1,
            memory_bytes: 0,
            slots: BTreeMap::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResourceLimits {
    pub cpu_slots: usize,
    pub memory_bytes: u64,
    /// Per-name pool size for shared slots. A name absent from this
    /// map is treated as if its limit were 1, so even un-configured
    /// slots still serialize correctly rather than allowing unbounded
    /// concurrency.
    pub slot_limits: BTreeMap<String, usize>,
}

impl ResourceLimits {
    pub fn new(cpu_slots: usize, memory_bytes: u64) -> Self {
        Self {
            cpu_slots: if cpu_slots == 0 { 1 } else { cpu_slots },
            memory_bytes,
            slot_limits: BTreeMap::new(),
        }
    }

    /// Publish a pool size for a named slot. Plugins call this when
    /// constructing the Runner so the scheduler knows how many of
    /// that slot's actions can run concurrently. A `count` of 0 is
    /// rounded up to 1 to keep the bounded-pool invariant.
    #[must_use]
    pub fn with_slot_limit(mut self, name: impl Into<String>, count: usize) -> Self {
        self.slot_limits
            .insert(name.into(), if count == 0 { 1 } else { count });
        self
    }

    /// Pool size for a named slot. Returns the configured value, or
    /// `default_value` when the slot isn't published.
    pub fn slot_limit(&self, name: &str, default_value: usize) -> usize {
        self.slot_limits.get(name).copied().unwrap_or(default_value)
    }
}

impl Default for ResourceLimits {
    fn default() -> Self {
        let cpu_slots = std::thread::available_parallelism()
            .map(NonZeroUsize::get)
            .unwrap_or(8);
        Self::new(cpu_slots, 0)
    }
}

#[derive(Debug, Default)]
struct State {
    cpu_slots: usize,
    memory_bytes: u64,
    /// Live slot counts keyed by slot name. Entries are created on
    /// first use and stay around to avoid map churn under load.
    slots: BTreeMap<String, usize>,
}

#[derive(Debug)]
pub struct ResourcePool {
    limits: ResourceLimits,
    state: Mutex<State>,
    notify: Notify,
}

impl ResourcePool {
    pub fn new(limits: ResourceLimits) -> Self {
        let limits = ResourceLimits {
            cpu_slots: if limits.cpu_slots == 0 {
                1
            } else {
                limits.cpu_slots
            },
            memory_bytes: limits.memory_bytes,
            slot_limits: limits.slot_limits,
        };
        Self {
            limits,
            state: Mutex::new(State::default()),
            notify: Notify::new(),
        }
    }

    pub fn limits(&self) -> ResourceLimits {
        self.limits.clone()
    }

    pub async fn acquire(self: &Arc<Self>, request: ResourceRequest) -> ResourcePermit {
        let request = request.bounded_by(&self.limits);
        loop {
            let notified = self.notify.notified();
            {
                let mut state = self.state.lock().expect("resource pool lock poisoned");
                if can_acquire(&state, &request, &self.limits) {
                    state.cpu_slots += request.cpu_slots;
                    state.memory_bytes = state.memory_bytes.saturating_add(request.memory_bytes);
                    for (name, count) in &request.slots {
                        *state.slots.entry(name.clone()).or_insert(0) += count;
                    }
                    return ResourcePermit {
                        pool: Arc::clone(self),
                        request,
                    };
                }
            }
            notified.await;
        }
    }
}

fn can_acquire(state: &State, request: &ResourceRequest, limits: &ResourceLimits) -> bool {
    let cpu_ok = state.cpu_slots <= limits.cpu_slots.saturating_sub(request.cpu_slots);
    let memory_ok = limits.memory_bytes == 0
        || state.memory_bytes <= limits.memory_bytes.saturating_sub(request.memory_bytes);
    let slots_ok = request.slots.iter().all(|(name, requested)| {
        let in_use = state.slots.get(name).copied().unwrap_or(0);
        // Unpublished slots default to a pool of 1 so unknown names
        // don't accidentally permit unbounded concurrency.
        let cap = limits.slot_limits.get(name).copied().unwrap_or(1).max(1);
        in_use <= cap.saturating_sub(*requested)
    });
    cpu_ok && memory_ok && slots_ok
}

#[derive(Debug)]
pub struct ResourcePermit {
    pool: Arc<ResourcePool>,
    request: ResourceRequest,
}

impl Drop for ResourcePermit {
    fn drop(&mut self) {
        {
            let mut state = self.pool.state.lock().expect("resource pool lock poisoned");
            state.cpu_slots = state.cpu_slots.saturating_sub(self.request.cpu_slots);
            state.memory_bytes = state.memory_bytes.saturating_sub(self.request.memory_bytes);
            for (name, count) in &self.request.slots {
                if let Some(entry) = state.slots.get_mut(name) {
                    *entry = entry.saturating_sub(*count);
                }
            }
        }
        self.pool.notify.notify_waiters();
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;
    use std::time::Duration;

    use super::*;

    #[tokio::test]
    async fn cpu_slots_block_until_released() {
        let pool = Arc::new(ResourcePool::new(ResourceLimits::new(1, 0)));
        let first = pool.acquire(ResourceRequest::default()).await;
        let waiting_pool = Arc::clone(&pool);
        let waiting = tokio::spawn(async move {
            let _permit = waiting_pool.acquire(ResourceRequest::default()).await;
        });

        tokio::time::sleep(Duration::from_millis(50)).await;
        assert!(!waiting.is_finished());

        drop(first);
        tokio::time::timeout(Duration::from_secs(1), waiting)
            .await
            .unwrap()
            .unwrap();
    }

    #[tokio::test]
    async fn memory_budget_blocks_until_released() {
        let pool = Arc::new(ResourcePool::new(ResourceLimits::new(4, 100)));
        let first = pool.acquire(ResourceRequest::new(1, 80)).await;
        let waiting_pool = Arc::clone(&pool);
        let waiting = tokio::spawn(async move {
            let _permit = waiting_pool.acquire(ResourceRequest::new(1, 40)).await;
        });

        tokio::time::sleep(Duration::from_millis(50)).await;
        assert!(!waiting.is_finished());

        drop(first);
        tokio::time::timeout(Duration::from_secs(1), waiting)
            .await
            .unwrap()
            .unwrap();
    }

    #[tokio::test]
    async fn oversized_request_is_clamped_to_pool_limits() {
        let pool = Arc::new(ResourcePool::new(ResourceLimits::new(2, 100)));
        let _permit = pool.acquire(ResourceRequest::new(8, 1_000)).await;
    }

    #[tokio::test]
    async fn named_slot_blocks_when_pool_is_saturated() {
        // Pool publishes one "exclusive_slot" slot; two requests for
        // that slot must serialize through it even though the cpu
        // pool has plenty of headroom.
        let limits = ResourceLimits::new(8, 0).with_slot_limit("exclusive_slot", 1);
        let pool = Arc::new(ResourcePool::new(limits));

        let first = pool
            .acquire(ResourceRequest::default().with_slot("exclusive_slot", 1))
            .await;

        let waiting_pool = Arc::clone(&pool);
        let waiting = tokio::spawn(async move {
            let _permit = waiting_pool
                .acquire(ResourceRequest::default().with_slot("exclusive_slot", 1))
                .await;
        });

        tokio::time::sleep(Duration::from_millis(50)).await;
        assert!(
            !waiting.is_finished(),
            "second slot acquirer should block while first holds the slot"
        );

        drop(first);
        tokio::time::timeout(Duration::from_secs(1), waiting)
            .await
            .unwrap()
            .unwrap();
    }

    #[tokio::test]
    async fn unrelated_actions_dont_compete_for_named_slots() {
        // An action that doesn't request the named slot must run
        // alongside one that does, even when the slot pool size is 1.
        let limits = ResourceLimits::new(8, 0).with_slot_limit("exclusive_slot", 1);
        let pool = Arc::new(ResourcePool::new(limits));

        let named = pool
            .acquire(ResourceRequest::default().with_slot("exclusive_slot", 1))
            .await;

        let pool2 = Arc::clone(&pool);
        let other = tokio::time::timeout(Duration::from_millis(200), async move {
            let _permit = pool2.acquire(ResourceRequest::default()).await;
        })
        .await;
        assert!(other.is_ok(), "non-slot action should not block");
        drop(named);
    }

    #[test]
    fn default_request_serializes_without_slots_field() {
        // Action-digest stability: requests that don't use named
        // slots must omit the field entirely so existing actions keep
        // the same JSON encoding (and the same cache key). The check
        // looks for the quoted `"slots":` key to avoid matching the
        // `cpu_slots` substring.
        let r = ResourceRequest::default();
        let json = serde_json::to_string(&r).unwrap();
        assert!(!json.contains("\"slots\":"), "got {json}");
    }

    #[test]
    fn request_with_slot_round_trips_through_json() {
        let r = ResourceRequest::default().with_slot("exclusive_slot", 1);
        let json = serde_json::to_string(&r).unwrap();
        assert!(json.contains("exclusive_slot"));
        let decoded: ResourceRequest = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded.slots.get("exclusive_slot"), Some(&1));
    }

    #[test]
    fn slot_with_zero_count_clears_the_entry() {
        let r = ResourceRequest::default()
            .with_slot("exclusive_slot", 1)
            .with_slot("exclusive_slot", 0);
        assert!(r.slots.is_empty());
    }
}
