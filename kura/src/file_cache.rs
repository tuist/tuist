use crate::memory::{ForegroundAdmissionTimeout, ForegroundMemoryReservation, MemoryController};

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
    pub fn should_drop(self, reclaim_file_cache: bool, transient_reserved_bytes: u64) -> bool {
        match self {
            Self::Adaptive => reclaim_file_cache,
            Self::Foreground { reservation_bytes } => {
                reclaim_file_cache || transient_reserved_bytes > reservation_bytes
            }
            Self::Bounded => true,
        }
    }

    pub fn drop_failure_is_fatal(self) -> bool {
        self != Self::Adaptive
    }
}

/// Reserves the maximum source-plus-destination file-cache working set for a
/// disk-backed foreground upload. An object larger than one working window is
/// copied under the bounded policy, which releases completed staging and
/// segment ranges every drop interval, so it is charged for one drop interval
/// rather than for a whole window it never holds.
pub(crate) async fn reserve_foreground_staging(
    memory: &MemoryController,
    declared_or_max_bytes: u64,
) -> Result<ForegroundFileCacheReservation, ForegroundAdmissionTimeout> {
    let exceeds_window = declared_or_max_bytes > FOREGROUND_STAGING_WINDOW_BYTES;
    let desired_working_set_bytes = if exceeds_window {
        FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES
    } else {
        declared_or_max_bytes
    };
    let working_set_bytes =
        desired_working_set_bytes.min(memory.transient_capacity_bytes().saturating_div(2));
    let reservation_was_clamped = working_set_bytes < desired_working_set_bytes;
    let requested_bytes = working_set_bytes.saturating_mul(2);
    let (reservation, waited) = memory.reserve_foreground_memory(requested_bytes).await?;
    let policy = if waited || reservation_was_clamped || exceeds_window {
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
                .should_drop(false, memory.transient_reserved_bytes())
        );

        let second = reserve_foreground_staging(&memory, 1024)
            .await
            .expect("second reservation should fit");
        assert!(
            first
                .file_cache_policy()
                .should_drop(false, memory.transient_reserved_bytes())
        );

        drop(second);
        drop(first);
    }

    const MIB: u64 = 1024 * 1024;

    /// A 64 MiB floor-derived pool under 256 MiB of ceiling headroom, the shape
    /// of a governed production instance.
    fn floor_governed_memory() -> MemoryController {
        MemoryController::with_anon_budget(
            Metrics::new("eu-west".into(), "tenant".into()),
            1024 * MIB,
            512 * MIB,
            768 * MIB,
            Some(64 * MIB),
        )
    }

    #[tokio::test]
    async fn objects_larger_than_the_window_reserve_one_drop_interval() {
        let metrics = Metrics::new("eu-west".into(), "tenant".into());
        let memory =
            MemoryController::with_runtime_limit(metrics, 1024 * MIB, 512 * MIB, 768 * MIB);

        let reservation = reserve_foreground_staging(&memory, 64 * MIB)
            .await
            .expect("reservation should fit");

        assert_eq!(reservation.file_cache_policy(), FileCachePolicy::Bounded);
        assert_eq!(
            memory.transient_reserved_bytes(),
            2 * FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES
        );
    }

    #[tokio::test]
    async fn staging_borrows_ceiling_headroom_before_queueing() {
        let memory = floor_governed_memory();
        let floor = memory
            .try_reserve_foreground_memory(memory.transient_capacity_bytes())
            .expect("the floor pool should admit its own capacity");

        let staged = tokio::time::timeout(
            std::time::Duration::from_millis(100),
            reserve_foreground_staging(&memory, FOREGROUND_STAGING_WINDOW_BYTES),
        )
        .await
        .expect("a full floor should not queue while headroom is free")
        .expect("reservation should fit");

        assert_eq!(
            staged.file_cache_policy(),
            FileCachePolicy::Foreground {
                reservation_bytes: 2 * FOREGROUND_STAGING_WINDOW_BYTES,
            }
        );
        assert_eq!(
            memory.elastic_transient_reserved_bytes(),
            2 * FOREGROUND_STAGING_WINDOW_BYTES
        );
        drop(staged);
        assert_eq!(memory.elastic_transient_reserved_bytes(), 0);
        drop(floor);
    }

    #[tokio::test]
    async fn a_borrowed_upload_still_counts_as_an_overlap() {
        let memory = floor_governed_memory();
        let first = reserve_foreground_staging(&memory, FOREGROUND_STAGING_WINDOW_BYTES)
            .await
            .expect("first reservation should fit");
        let rest_of_floor = memory
            .try_reserve_foreground_memory(
                memory.transient_capacity_bytes() - memory.transient_reserved_bytes(),
            )
            .expect("the rest of the floor pool should admit");
        let borrowed = reserve_foreground_staging(&memory, FOREGROUND_STAGING_WINDOW_BYTES)
            .await
            .expect("second reservation should borrow");
        assert!(memory.elastic_transient_reserved_bytes() > 0);
        drop(rest_of_floor);

        assert!(
            first
                .file_cache_policy()
                .should_drop(false, memory.foreground_transient_reserved_bytes())
        );
        drop(borrowed);
        assert!(
            !first
                .file_cache_policy()
                .should_drop(false, memory.foreground_transient_reserved_bytes())
        );
    }

    #[tokio::test]
    async fn staging_queues_on_the_floor_above_normal_pressure() {
        let memory = floor_governed_memory();
        memory.observe(512 * MIB + 1);
        assert_eq!(
            memory.pressure(),
            crate::memory::MemoryPressure::Constrained
        );
        let floor = memory
            .try_reserve_foreground_memory(memory.transient_capacity_bytes())
            .expect("the floor pool should admit its own capacity");

        let waiting = tokio::spawn({
            let memory = memory.clone();
            async move { reserve_foreground_staging(&memory, 1024).await }
        });
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;
        assert!(!waiting.is_finished());
        assert_eq!(memory.elastic_transient_reserved_bytes(), 0);
        drop(floor);

        let staged = waiting
            .await
            .expect("reservation task should not panic")
            .expect("queued reservation should fit after release");
        assert_eq!(staged.file_cache_policy(), FileCachePolicy::Bounded);
        assert_eq!(memory.elastic_transient_reserved_bytes(), 0);
    }

    #[test]
    fn adaptive_policy_drops_cache_when_reclaim_is_requested() {
        assert!(!FileCachePolicy::Adaptive.should_drop(false, 0));
        assert!(FileCachePolicy::Adaptive.should_drop(true, 0));
    }
}
