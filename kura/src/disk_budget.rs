//! Node-owned budget files are mounted read-only, outside the tenant's data
//! directory. The host enforces the current budget with a project quota; this
//! protocol supplies a lower reclamation target without prematurely releasing
//! the old allowance. A missing/stale file never authorizes expansion.

use serde::Deserialize;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

#[derive(Clone, Debug)]
pub struct Config {
    pub file: PathBuf,
    pub volume_id: String,
}

#[derive(Clone, Debug, Deserialize)]
pub(crate) struct Budget {
    version: u32,
    volume_id: String,
    generation: u64,
    expires_ms: u64,
    floor_bytes: u64,
    ceiling_bytes: u64,
    current_bytes: u64,
    target_bytes: u64,
    #[serde(default)]
    allow_writes: bool,
}

pub(crate) struct Controller {
    config: Config,
    observed: Mutex<Option<(Budget, Instant)>>,
}

impl Controller {
    pub fn new(config: Config) -> Self {
        Self {
            config,
            observed: Mutex::new(None),
        }
    }

    pub async fn refresh(&self) -> Result<(), String> {
        use tokio::io::AsyncReadExt;
        let file = tokio::fs::File::open(&self.config.file)
            .await
            .map_err(|e| e.to_string())?;
        let mut bytes = Vec::new();
        file.take(4097)
            .read_to_end(&mut bytes)
            .await
            .map_err(|e| e.to_string())?;
        if bytes.len() > 4096 {
            return Err("disk budget exceeds 4096 bytes".into());
        }
        let budget: Budget = serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
        self.observe(budget, unix_ms())
    }

    fn observe(&self, budget: Budget, now_ms: u64) -> Result<(), String> {
        if budget.version != 1
            || budget.volume_id != self.config.volume_id
            || budget.floor_bytes < 4 * 1024 * 1024 * 1024
            || budget.floor_bytes > budget.target_bytes
            || budget.target_bytes > budget.current_bytes
            || budget.target_bytes > budget.ceiling_bytes
            || budget.current_bytes > 1 << 50
            || budget.ceiling_bytes > 1 << 50
            || budget.expires_ms <= now_ms
            || budget.expires_ms - now_ms > 30_000
        {
            return Err("invalid disk budget authorization".into());
        }
        let mut observed = self.observed.lock().expect("disk budget lock");
        if observed
            .as_ref()
            .is_some_and(|(old, _)| budget.generation < old.generation)
        {
            return Err("disk budget generation regressed".into());
        }
        if let Some((old, _)) = observed.as_ref()
            && budget.generation == old.generation
        {
            // Re-reading a file cannot extend its monotonic expiry.
            return if old.expires_ms == budget.expires_ms
                && old.current_bytes == budget.current_bytes
                && old.target_bytes == budget.target_bytes
                && old.floor_bytes == budget.floor_bytes
                && old.ceiling_bytes == budget.ceiling_bytes
                && old.allow_writes == budget.allow_writes
            {
                Ok(())
            } else {
                Err("disk budget changed without a new generation".into())
            };
        }
        let deadline = Instant::now() + Duration::from_millis(budget.expires_ms - now_ms);
        *observed = Some((budget, deadline));
        Ok(())
    }

    pub fn target_bytes(&self) -> Option<u64> {
        self.observed
            .lock()
            .expect("disk budget lock")
            .as_ref()
            .map(|(b, _)| b.target_bytes)
    }

    pub fn writable(&self) -> bool {
        self.observed
            .lock()
            .expect("disk budget lock")
            .as_ref()
            .is_some_and(|(b, deadline)| {
                b.allow_writes && Instant::now() < *deadline && unix_ms() < b.expires_ms
            })
    }

    pub fn contended(&self) -> bool {
        self.observed
            .lock()
            .expect("disk budget lock")
            .as_ref()
            .is_some_and(|(b, _)| b.target_bytes < b.ceiling_bytes)
    }

    pub fn reclamation_headroom_bytes(&self) -> u64 {
        self.observed
            .lock()
            .expect("disk budget lock")
            .as_ref()
            .map_or(0, |(b, _)| b.current_bytes.saturating_sub(b.target_bytes))
    }
}

fn unix_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

#[cfg(test)]
mod tests {
    use super::*;

    fn budget() -> Budget {
        Budget {
            version: 1,
            volume_id: "volume-a".into(),
            generation: 1,
            expires_ms: unix_ms() + 15_000,
            floor_bytes: 4 << 30,
            ceiling_bytes: 8 << 30,
            current_bytes: 8 << 30,
            target_bytes: 6 << 30,
            allow_writes: true,
        }
    }

    #[test]
    fn rejects_wrong_volume_invalid_limits_and_replays() {
        let controller = Controller::new(Config {
            file: "unused".into(),
            volume_id: "volume-a".into(),
        });
        assert!(!controller.writable());
        let good = budget();
        controller.observe(good.clone(), unix_ms()).unwrap();
        assert!(controller.writable());
        assert_eq!(controller.target_bytes(), Some(6 << 30));
        let mut bad = good.clone();
        bad.volume_id = "volume-b".into();
        assert!(controller.observe(bad, unix_ms()).is_err());
        let mut bad = good.clone();
        bad.target_bytes = 9 << 30;
        assert!(controller.observe(bad, unix_ms()).is_err());
        let mut bad = good.clone();
        bad.generation = 0;
        assert!(controller.observe(bad, unix_ms()).is_err());
        let mut bad = good;
        bad.target_bytes = 7 << 30;
        assert!(controller.observe(bad, unix_ms()).is_err());
    }

    #[test]
    fn expired_authorization_retains_reclamation_target_but_blocks_writes() {
        let controller = Controller::new(Config {
            file: "unused".into(),
            volume_id: "volume-a".into(),
        });
        controller.observe(budget(), unix_ms()).unwrap();
        controller.observed.lock().unwrap().as_mut().unwrap().1 = Instant::now();
        assert!(!controller.writable());
        assert_eq!(controller.target_bytes(), Some(6 << 30));
    }

    #[test]
    fn ceiling_pressure_is_distinct_from_contention_and_can_shrink_in_place() {
        let controller = Controller::new(Config {
            file: "unused".into(),
            volume_id: "volume-a".into(),
        });
        let mut allocation = budget();
        controller.observe(allocation.clone(), unix_ms()).unwrap();
        assert!(controller.contended());
        allocation.generation += 1;
        allocation.target_bytes = allocation.ceiling_bytes;
        controller.observe(allocation.clone(), unix_ms()).unwrap();
        assert!(!controller.contended());
        allocation.generation += 1;
        allocation.ceiling_bytes = 4 << 30;
        allocation.target_bytes = 4 << 30;
        controller.observe(allocation, unix_ms()).unwrap();
        assert!(controller.writable());
        assert_eq!(controller.target_bytes(), Some(4 << 30));
    }
}
