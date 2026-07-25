use crate::memory::{
    ForegroundAdmissionTimeout, ForegroundMemoryReservation, MemoryController, MemoryPressure,
};

pub const FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES: u64 = 8 * 1024 * 1024;
pub const FOREGROUND_STAGING_WINDOW_BYTES: u64 = 16 * 1024 * 1024;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FileCachePolicy {
    Adaptive,
    Foreground { reservation_bytes: u64 },
    Bounded,
}

pub struct ForegroundFileCacheReservation {
    memory: ForegroundMemoryReservation,
    policy: FileCachePolicy,
}

impl ForegroundFileCacheReservation {
    pub(crate) fn new(memory: ForegroundMemoryReservation, policy: FileCachePolicy) -> Self {
        Self { memory, policy }
    }

    pub fn file_cache_policy(&self) -> FileCachePolicy {
        self.policy
    }

    pub(crate) fn try_resize(&mut self, requested_bytes: u64) -> Result<(), ()> {
        self.memory.try_resize(requested_bytes)
    }

    pub(crate) fn set_policy(&mut self, policy: FileCachePolicy) {
        self.policy = policy;
    }
}

impl FileCachePolicy {
    pub fn should_drop(self, pressure: MemoryPressure, transient_reserved_bytes: u64) -> bool {
        match self {
            Self::Adaptive => pressure != MemoryPressure::Normal,
            Self::Foreground { reservation_bytes } => {
                pressure != MemoryPressure::Normal || transient_reserved_bytes > reservation_bytes
            }
            Self::Bounded => true,
        }
    }

    pub fn drop_failure_is_fatal(self) -> bool {
        self != Self::Adaptive
    }
}

/// Reserves the maximum source-plus-destination file-cache working set for a
/// disk-backed foreground upload. Objects larger than one working window keep
/// both staging and segment-copy cache ranges bounded while this guard is held.
pub(crate) async fn reserve_foreground_staging(
    memory: &MemoryController,
    declared_or_max_bytes: u64,
) -> Result<ForegroundFileCacheReservation, ForegroundAdmissionTimeout> {
    let desired_working_set_bytes = declared_or_max_bytes.min(FOREGROUND_STAGING_WINDOW_BYTES);
    let working_set_bytes =
        desired_working_set_bytes.min(memory.transient_capacity_bytes().saturating_div(2));
    let reservation_was_clamped = working_set_bytes < desired_working_set_bytes;
    let requested_bytes = working_set_bytes.saturating_mul(2);
    let (reservation, waited) = memory.reserve_foreground_memory(requested_bytes).await?;
    let policy = if waited
        || reservation_was_clamped
        || declared_or_max_bytes > FOREGROUND_STAGING_WINDOW_BYTES
    {
        FileCachePolicy::Bounded
    } else {
        FileCachePolicy::Foreground {
            reservation_bytes: requested_bytes,
        }
    };
    Ok(ForegroundFileCacheReservation::new(reservation, policy))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::metrics::Metrics;

    #[tokio::test]
    async fn queued_uploads_use_bounded_file_cache() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let memory = MemoryController::with_runtime_limit(
            metrics,
            64 * 1024 * 1024,
            24 * 1024 * 1024,
            56 * 1024 * 1024,
        );
        let first = reserve_foreground_staging(&memory, FOREGROUND_STAGING_WINDOW_BYTES)
            .await
            .expect("first reservation should fit");
        assert_eq!(
            first.file_cache_policy(),
            FileCachePolicy::Foreground {
                reservation_bytes: 32 * 1024 * 1024,
            }
        );

        let waiting = tokio::spawn({
            let memory = memory.clone();
            async move { reserve_foreground_staging(&memory, 1024).await }
        });
        tokio::task::yield_now().await;
        assert!(!waiting.is_finished());
        drop(first);

        let second = waiting
            .await
            .expect("reservation task should not panic")
            .expect("queued reservation should fit after release");
        assert_eq!(second.file_cache_policy(), FileCachePolicy::Bounded);
        drop(second);
        memory.observe(0);
        assert_eq!(memory.transient_reserved_bytes(), 0);
    }

    #[tokio::test]
    async fn clamped_uploads_use_bounded_file_cache() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let memory = MemoryController::with_runtime_limit(
            metrics.clone(),
            64 * 1024 * 1024,
            24 * 1024 * 1024,
            32 * 1024 * 1024,
        );

        let reservation = reserve_foreground_staging(&memory, FOREGROUND_STAGING_WINDOW_BYTES)
            .await
            .expect("clamped reservation should fit");

        assert_eq!(reservation.file_cache_policy(), FileCachePolicy::Bounded);
        assert_eq!(memory.transient_reserved_bytes(), 8 * 1024 * 1024);

        let tiny_memory = MemoryController::with_runtime_limit(
            metrics,
            64 * 1024 * 1024,
            32 * 1024 * 1024,
            32 * 1024 * 1024 + 1,
        );
        let tiny_reservation = reserve_foreground_staging(&tiny_memory, 1)
            .await
            .expect("zero-byte clamped reservation should use bounded cache handling");
        assert_eq!(
            tiny_reservation.file_cache_policy(),
            FileCachePolicy::Bounded
        );
        assert_eq!(tiny_memory.transient_reserved_bytes(), 0);
    }

    #[tokio::test]
    async fn foreground_policy_drops_cache_when_uploads_overlap() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let memory = MemoryController::with_runtime_limit(
            metrics,
            160 * 1024 * 1024,
            64 * 1024 * 1024,
            128 * 1024 * 1024,
        );
        let first = reserve_foreground_staging(&memory, FOREGROUND_STAGING_WINDOW_BYTES)
            .await
            .expect("first reservation should fit");
        assert!(
            !first
                .file_cache_policy()
                .should_drop(MemoryPressure::Normal, memory.transient_reserved_bytes())
        );

        let second = reserve_foreground_staging(&memory, 1024)
            .await
            .expect("second reservation should fit");
        assert!(
            first
                .file_cache_policy()
                .should_drop(MemoryPressure::Normal, memory.transient_reserved_bytes())
        );

        drop(second);
        drop(first);
    }
}
