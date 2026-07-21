#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ContainerMemorySnapshot {
    pub current_bytes: u64,
    pub limit_bytes: Option<u64>,
    pub anon_bytes: Option<u64>,
    pub file_bytes: Option<u64>,
    pub kernel_bytes: Option<u64>,
    pub inactive_file_bytes: Option<u64>,
    pub shmem_bytes: Option<u64>,
    pub file_dirty_bytes: Option<u64>,
    pub file_writeback_bytes: Option<u64>,
    pub max_events: Option<u64>,
    pub oom_events: Option<u64>,
    pub oom_kill_events: Option<u64>,
    pub workingset_refault_file: Option<u64>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ContainerMemoryPressureSample {
    pub current_bytes: u64,
    pub working_set_bytes: u64,
    pub reclaimable_inactive_file_bytes: u64,
    pub limit_bytes: Option<u64>,
}

impl ContainerMemorySnapshot {
    pub fn working_set_bytes(&self) -> u64 {
        working_set_bytes(
            self.current_bytes,
            self.inactive_file_bytes,
            self.shmem_bytes,
            self.file_dirty_bytes,
            self.file_writeback_bytes,
        )
    }

    pub fn reclaimable_inactive_file_bytes(&self) -> u64 {
        reclaimable_inactive_file_bytes(
            self.inactive_file_bytes,
            self.shmem_bytes,
            self.file_dirty_bytes,
            self.file_writeback_bytes,
        )
    }
}

pub fn container_memory_pressure_sample() -> Option<ContainerMemoryPressureSample> {
    #[cfg(target_os = "linux")]
    {
        if let Some(current_before) = read_u64_file("/sys/fs/cgroup/memory.current")
            && let Ok(stat) = std::fs::read_to_string("/sys/fs/cgroup/memory.stat")
            && let Some(current_after) = read_u64_file("/sys/fs/cgroup/memory.current")
            && let Some(limit_bytes) =
                read_required_memory_limit_file("/sys/fs/cgroup/memory.max", None)
        {
            let reclaimable_inactive_file_bytes = reclaimable_inactive_file_bytes(
                named_value(&stat, "inactive_file"),
                named_value(&stat, "shmem"),
                named_value(&stat, "file_dirty"),
                named_value(&stat, "file_writeback"),
            );
            return Some(ContainerMemoryPressureSample {
                current_bytes: current_before.max(current_after),
                working_set_bytes: bracketed_working_set_bytes(
                    current_before,
                    current_after,
                    reclaimable_inactive_file_bytes,
                ),
                reclaimable_inactive_file_bytes,
                limit_bytes,
            });
        }

        let current_before = read_u64_file("/sys/fs/cgroup/memory/memory.usage_in_bytes")?;
        let stat = std::fs::read_to_string("/sys/fs/cgroup/memory/memory.stat").ok()?;
        let current_after = read_u64_file("/sys/fs/cgroup/memory/memory.usage_in_bytes")?;
        let limit_bytes = read_required_memory_limit_file(
            "/sys/fs/cgroup/memory/memory.limit_in_bytes",
            Some(CGROUP_V1_UNLIMITED_THRESHOLD_BYTES),
        )?;
        let reclaimable_inactive_file_bytes = reclaimable_inactive_file_bytes(
            named_value(&stat, "total_inactive_file"),
            named_value(&stat, "total_shmem"),
            named_value(&stat, "total_dirty"),
            named_value(&stat, "total_writeback"),
        );
        Some(ContainerMemoryPressureSample {
            current_bytes: current_before.max(current_after),
            working_set_bytes: bracketed_working_set_bytes(
                current_before,
                current_after,
                reclaimable_inactive_file_bytes,
            ),
            reclaimable_inactive_file_bytes,
            limit_bytes,
        })
    }
    #[cfg(not(target_os = "linux"))]
    {
        None
    }
}

pub fn container_memory_snapshot() -> Option<ContainerMemorySnapshot> {
    #[cfg(target_os = "linux")]
    {
        if let Some(current_before) = read_u64_file("/sys/fs/cgroup/memory.current")
            && let Ok(stat) = std::fs::read_to_string("/sys/fs/cgroup/memory.stat")
            && let Some(current_after) = read_u64_file("/sys/fs/cgroup/memory.current")
        {
            let events = std::fs::read_to_string("/sys/fs/cgroup/memory.events").ok();
            return Some(ContainerMemorySnapshot {
                current_bytes: current_before.max(current_after),
                limit_bytes: read_memory_limit_file("/sys/fs/cgroup/memory.max"),
                anon_bytes: named_value(&stat, "anon"),
                file_bytes: named_value(&stat, "file"),
                kernel_bytes: named_value(&stat, "kernel"),
                inactive_file_bytes: named_value(&stat, "inactive_file"),
                shmem_bytes: named_value(&stat, "shmem"),
                file_dirty_bytes: named_value(&stat, "file_dirty"),
                file_writeback_bytes: named_value(&stat, "file_writeback"),
                max_events: events
                    .as_deref()
                    .and_then(|value| named_value(value, "max")),
                oom_events: events
                    .as_deref()
                    .and_then(|value| named_value(value, "oom")),
                oom_kill_events: events
                    .as_deref()
                    .and_then(|value| named_value(value, "oom_kill")),
                workingset_refault_file: named_value(&stat, "workingset_refault_file"),
            });
        }

        let current_before = read_u64_file("/sys/fs/cgroup/memory/memory.usage_in_bytes")?;
        let stat = std::fs::read_to_string("/sys/fs/cgroup/memory/memory.stat").ok()?;
        let current_after = read_u64_file("/sys/fs/cgroup/memory/memory.usage_in_bytes")?;
        let events = std::fs::read_to_string("/sys/fs/cgroup/memory/memory.failcnt").ok();
        Some(ContainerMemorySnapshot {
            current_bytes: current_before.max(current_after),
            limit_bytes: read_v1_memory_limit_file("/sys/fs/cgroup/memory/memory.limit_in_bytes"),
            anon_bytes: named_value(&stat, "rss"),
            file_bytes: named_value(&stat, "cache"),
            kernel_bytes: None,
            inactive_file_bytes: named_value(&stat, "total_inactive_file"),
            shmem_bytes: named_value(&stat, "total_shmem"),
            file_dirty_bytes: named_value(&stat, "total_dirty"),
            file_writeback_bytes: named_value(&stat, "total_writeback"),
            max_events: events
                .as_deref()
                .and_then(|value| value.trim().parse::<u64>().ok()),
            oom_events: None,
            oom_kill_events: None,
            workingset_refault_file: named_value(&stat, "total_workingset_refault"),
        })
    }
    #[cfg(not(target_os = "linux"))]
    {
        None
    }
}

fn working_set_bytes(
    current_bytes: u64,
    inactive_file_bytes: Option<u64>,
    shmem_bytes: Option<u64>,
    file_dirty_bytes: Option<u64>,
    file_writeback_bytes: Option<u64>,
) -> u64 {
    current_bytes.saturating_sub(reclaimable_inactive_file_bytes(
        inactive_file_bytes,
        shmem_bytes,
        file_dirty_bytes,
        file_writeback_bytes,
    ))
}

#[cfg(any(target_os = "linux", test))]
fn bracketed_working_set_bytes(
    current_before: u64,
    current_after: u64,
    reclaimable_inactive_file_bytes: u64,
) -> u64 {
    // A charge or reclaim can happen while memory.stat flushes its counters.
    // The larger bracketing total reduces ordinary monotonic skew without
    // paying for a second statistics flush. Admission separately caps this
    // cross-file estimate with the raw charge because non-monotonic churn can
    // still decouple the values.
    current_before
        .max(current_after)
        .saturating_sub(reclaimable_inactive_file_bytes)
}

fn reclaimable_inactive_file_bytes(
    inactive_file_bytes: Option<u64>,
    shmem_bytes: Option<u64>,
    file_dirty_bytes: Option<u64>,
    file_writeback_bytes: Option<u64>,
) -> u64 {
    // These exclusions are not exact subsets of inactive_file. Subtracting all
    // of them deliberately underestimates reclaimable memory, so shared,
    // dirty, and writeback-heavy workloads enter pressure early rather than
    // receiving optimistic headroom.
    let reclaim_exclusions = shmem_bytes
        .unwrap_or(0)
        .saturating_add(file_dirty_bytes.unwrap_or(0))
        .saturating_add(file_writeback_bytes.unwrap_or(0));
    inactive_file_bytes
        .unwrap_or(0)
        .saturating_sub(reclaim_exclusions)
}

#[cfg(target_os = "linux")]
fn read_u64_file(path: &str) -> Option<u64> {
    std::fs::read_to_string(path).ok()?.trim().parse().ok()
}

#[cfg(target_os = "linux")]
fn read_memory_limit_file(path: &str) -> Option<u64> {
    read_required_memory_limit_file(path, None).flatten()
}

#[cfg(target_os = "linux")]
fn read_v1_memory_limit_file(path: &str) -> Option<u64> {
    read_required_memory_limit_file(path, Some(CGROUP_V1_UNLIMITED_THRESHOLD_BYTES)).flatten()
}

#[cfg(target_os = "linux")]
fn read_required_memory_limit_file(
    path: &str,
    unlimited_threshold_bytes: Option<u64>,
) -> Option<Option<u64>> {
    let value = std::fs::read_to_string(path).ok()?;
    let value = value.trim();
    if value == "max" {
        return Some(None);
    }
    let value = value.parse::<u64>().ok()?;
    if unlimited_threshold_bytes.is_some_and(|threshold| value >= threshold) {
        return Some(None);
    }
    Some(Some(value))
}

#[cfg(any(target_os = "linux", test))]
pub(super) fn named_value(input: &str, name: &str) -> Option<u64> {
    input.lines().find_map(|line| {
        let mut fields = line.split_ascii_whitespace();
        if fields.next()? != name {
            return None;
        }
        fields.next()?.parse().ok()
    })
}

#[cfg(target_os = "linux")]
const CGROUP_V1_UNLIMITED_THRESHOLD_BYTES: u64 = 1 << 53;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_named_control_group_memory_values() {
        let stat = "anon 123\nfile 456\ninactive_file 78\n";

        assert_eq!(named_value(stat, "anon"), Some(123));
        assert_eq!(named_value(stat, "file"), Some(456));
        assert_eq!(named_value(stat, "inactive_file"), Some(78));
        assert_eq!(named_value(stat, "missing"), None);
    }

    #[test]
    fn working_set_excludes_reclaimable_inactive_file_memory() {
        let snapshot = ContainerMemorySnapshot {
            current_bytes: 1_000,
            limit_bytes: Some(2_000),
            anon_bytes: Some(600),
            file_bytes: Some(300),
            kernel_bytes: Some(100),
            inactive_file_bytes: Some(250),
            shmem_bytes: Some(25),
            file_dirty_bytes: Some(10),
            file_writeback_bytes: Some(5),
            max_events: Some(2),
            oom_events: Some(0),
            oom_kill_events: Some(0),
            workingset_refault_file: Some(3),
        };

        assert_eq!(snapshot.working_set_bytes(), 790);
        assert_eq!(snapshot.reclaimable_inactive_file_bytes(), 210);
    }

    #[test]
    fn working_set_does_not_discount_shared_or_unflushed_file_memory() {
        assert_eq!(
            working_set_bytes(1_000, Some(300), Some(200), Some(75), Some(25)),
            1_000
        );
        assert_eq!(
            working_set_bytes(1_000, Some(300), Some(0), Some(100), Some(50)),
            850
        );
    }

    #[test]
    fn bracketed_working_set_uses_the_larger_total_during_reclaim() {
        assert_eq!(bracketed_working_set_bytes(900, 400, 600), 300);
        assert_eq!(bracketed_working_set_bytes(400, 900, 600), 300);
    }
}
