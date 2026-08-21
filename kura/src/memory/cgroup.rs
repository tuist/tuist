#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ContainerMemorySnapshot {
    pub current_bytes: u64,
    pub limit_bytes: Option<u64>,
    pub anon_bytes: Option<u64>,
    pub file_bytes: Option<u64>,
    pub kernel_bytes: Option<u64>,
    pub slab_reclaimable_bytes: Option<u64>,
    pub slab_unreclaimable_bytes: Option<u64>,
    pub inactive_file_bytes: Option<u64>,
    pub shmem_bytes: Option<u64>,
    pub sock_bytes: Option<u64>,
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
    pub pressure_bytes: u64,
    pub working_set_bytes: u64,
    pub reclaimable_inactive_file_bytes: u64,
    pub limit_bytes: Option<u64>,
}

#[derive(Clone, Copy)]
struct MemoryPressureComponents {
    current_bytes: u64,
    anon_bytes: Option<u64>,
    file_bytes: Option<u64>,
    kernel_bytes: Option<u64>,
    slab_reclaimable_bytes: Option<u64>,
    shmem_bytes: Option<u64>,
    sock_bytes: Option<u64>,
    file_dirty_bytes: Option<u64>,
    file_writeback_bytes: Option<u64>,
    inactive_file_bytes: Option<u64>,
}

impl ContainerMemorySnapshot {
    pub fn working_set_bytes(&self) -> u64 {
        working_set_bytes(self.current_bytes, self.inactive_file_bytes)
    }

    pub fn pressure_bytes(&self) -> u64 {
        pressure_bytes(MemoryPressureComponents {
            current_bytes: self.current_bytes,
            anon_bytes: self.anon_bytes,
            file_bytes: self.file_bytes,
            kernel_bytes: self.kernel_bytes,
            slab_reclaimable_bytes: self.slab_reclaimable_bytes,
            shmem_bytes: self.shmem_bytes,
            sock_bytes: self.sock_bytes,
            file_dirty_bytes: self.file_dirty_bytes,
            file_writeback_bytes: self.file_writeback_bytes,
            inactive_file_bytes: self.inactive_file_bytes,
        })
    }

    pub fn reclaimable_inactive_file_bytes(&self) -> u64 {
        self.inactive_file_bytes.unwrap_or(0)
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
            let reclaimable_inactive_file_bytes = named_value(&stat, "inactive_file").unwrap_or(0);
            let current_bytes = current_before.max(current_after);
            return Some(ContainerMemoryPressureSample {
                current_bytes,
                pressure_bytes: pressure_bytes(MemoryPressureComponents {
                    current_bytes,
                    anon_bytes: named_value(&stat, "anon"),
                    file_bytes: named_value(&stat, "file"),
                    kernel_bytes: named_value(&stat, "kernel"),
                    slab_reclaimable_bytes: named_value(&stat, "slab_reclaimable"),
                    shmem_bytes: named_value(&stat, "shmem"),
                    sock_bytes: named_value(&stat, "sock"),
                    file_dirty_bytes: named_value(&stat, "file_dirty"),
                    file_writeback_bytes: named_value(&stat, "file_writeback"),
                    inactive_file_bytes: Some(reclaimable_inactive_file_bytes),
                }),
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
        let reclaimable_inactive_file_bytes =
            named_value(&stat, "total_inactive_file").unwrap_or(0);
        let current_bytes = current_before.max(current_after);
        Some(ContainerMemoryPressureSample {
            current_bytes,
            pressure_bytes: pressure_bytes(MemoryPressureComponents {
                current_bytes,
                anon_bytes: named_value(&stat, "total_rss"),
                file_bytes: named_value(&stat, "cache"),
                kernel_bytes: None,
                slab_reclaimable_bytes: None,
                shmem_bytes: named_value(&stat, "total_shmem"),
                sock_bytes: None,
                file_dirty_bytes: named_value(&stat, "total_dirty"),
                file_writeback_bytes: named_value(&stat, "total_writeback"),
                inactive_file_bytes: Some(reclaimable_inactive_file_bytes),
            }),
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

fn working_set_bytes(current_bytes: u64, inactive_file_bytes: Option<u64>) -> u64 {
    current_bytes.saturating_sub(inactive_file_bytes.unwrap_or(0))
}

fn pressure_bytes(components: MemoryPressureComponents) -> u64 {
    let MemoryPressureComponents {
        current_bytes,
        anon_bytes,
        file_bytes,
        kernel_bytes,
        slab_reclaimable_bytes,
        shmem_bytes,
        sock_bytes,
        file_dirty_bytes,
        file_writeback_bytes,
        inactive_file_bytes,
    } = components;
    if let (Some(anon_bytes), Some(kernel_bytes)) = (anon_bytes, kernel_bytes) {
        // `slab_reclaimable` is nested inside `kernel`, but it is cache the kernel drops
        // on demand, not memory this process can release, so it is excluded for the same
        // reason clean file cache is excluded below. Scoped to this signal only:
        // `working_set_bytes` stays the conventional `current - inactive_file`, so it
        // still counts reclaimable slab and can hold `should_reclaim_file_cache` on. That
        // costs a warm node its mmap-serving fast path, not its correctness, and keeping
        // the working-set figure comparable to what the kubelet reports is worth more.
        //
        // It normally stays small: it is dominated by `buffer_head`, ~105B per resident
        // page-cache page (measured at 104.9B/page on a healthy node), and page cache is
        // itself charged to the cgroup — so a 2GiB limit caps it near 52MiB even if the
        // container held nothing else. One production node nevertheless accumulated
        // ~1GiB of it, ~19x that ceiling, against only 255MiB of page cache. Why is not
        // yet understood; the gauges added alongside this exist to catch the next one.
        //
        // Counting it pinned that node at Critical, which both zeroes the action-cache
        // snapshot index and denies its rebuild (rebuilds require Normal), so it served
        // 0% hits while staying Ready until restarted. Kura cannot trim its way out: the
        // charge is the kernel's, not its own.
        //
        // Subtracted from the aggregate rather than summing `kernel`'s other leaves on
        // purpose: an allowlist of leaves silently drops rows this code does not know
        // about (see `sock`), and for a pressure signal undercounting is the more
        // dangerous error.
        //
        // `sock` (network transmission buffers) is charged separately from `anon`,
        // `kernel`, and the file rows in cgroup v2 `memory.stat`, so it has to be added
        // back explicitly. The old `current - inactive_file` signal counted it, and a node
        // streaming to many slow clients can hold a meaningful amount of it. The v1 and
        // working-set fallbacks below keep it implicitly through `current`.
        return anon_bytes
            .saturating_add(kernel_bytes.saturating_sub(slab_reclaimable_bytes.unwrap_or(0)))
            .saturating_add(shmem_bytes.unwrap_or(0))
            .saturating_add(sock_bytes.unwrap_or(0))
            .saturating_add(file_dirty_bytes.unwrap_or(0))
            .saturating_add(file_writeback_bytes.unwrap_or(0))
            .min(current_bytes);
    }
    let Some(file_bytes) = file_bytes else {
        return working_set_bytes(current_bytes, inactive_file_bytes);
    };
    current_bytes
        .saturating_sub(file_bytes)
        .saturating_add(shmem_bytes.unwrap_or(0))
        .saturating_add(file_dirty_bytes.unwrap_or(0))
        .saturating_add(file_writeback_bytes.unwrap_or(0))
        .min(current_bytes)
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
                slab_reclaimable_bytes: named_value(&stat, "slab_reclaimable"),
                slab_unreclaimable_bytes: named_value(&stat, "slab_unreclaimable"),
                inactive_file_bytes: named_value(&stat, "inactive_file"),
                shmem_bytes: named_value(&stat, "shmem"),
                sock_bytes: named_value(&stat, "sock"),
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
            slab_reclaimable_bytes: None,
            slab_unreclaimable_bytes: None,
            inactive_file_bytes: named_value(&stat, "total_inactive_file"),
            shmem_bytes: named_value(&stat, "total_shmem"),
            sock_bytes: None,
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

/// The reclaim protection the orchestrator has granted this container, as
/// `(memory.min, memory.low)`.
///
/// Both are zero unless the kubelet runs with the MemoryQoS feature gate, which
/// is what maps a Pod's memory request onto them. That makes this the signal for
/// whether the memory floor is actually enforced or merely a scheduling promise
/// — a distinction nothing else observable makes, and one that changes silently:
/// a kubelet upgrade can stop applying protection without any error surfacing.
///
/// Deliberately separate from the pressure sample. Kura never reads these to
/// decide anything; they describe what the kernel will do on Kura's behalf, so
/// folding them into admission input would confuse two different things.
pub fn container_memory_protection() -> Option<(u64, u64)> {
    #[cfg(target_os = "linux")]
    {
        // memory.min is absent on cgroup v1 and on a v2 root cgroup; treat an
        // unreadable file as no protection rather than as missing data, because
        // "no protection" is exactly what it means for the caller.
        let limit_bytes = read_memory_limit_file("/sys/fs/cgroup/memory.max");
        Some((
            read_protection_file("/sys/fs/cgroup/memory.min", limit_bytes),
            read_protection_file("/sys/fs/cgroup/memory.low", limit_bytes),
        ))
    }
    #[cfg(not(target_os = "linux"))]
    {
        None
    }
}

#[cfg(target_os = "linux")]
fn read_protection_file(path: &str, limit_bytes: Option<u64>) -> u64 {
    std::fs::read_to_string(path)
        .map(|raw| protection_bytes(&raw, limit_bytes))
        .unwrap_or(0)
}

/// Maps the contents of a `memory.min`/`memory.low` file to a byte count.
///
/// Both accept the cgroup-v2 `max` sentinel, which protects the whole cgroup.
/// Zero is the alertable value for this gauge, so treating an unparsed `max` as
/// zero would report no protection at the one point protection is total.
#[cfg(any(target_os = "linux", test))]
fn protection_bytes(raw: &str, limit_bytes: Option<u64>) -> u64 {
    match raw.trim() {
        "max" => limit_bytes.unwrap_or(u64::MAX),
        value => value.parse().unwrap_or(0),
    }
}

#[cfg(any(target_os = "linux", test))]
fn bracketed_working_set_bytes(
    current_before: u64,
    current_after: u64,
    reclaimable_inactive_file_bytes: u64,
) -> u64 {
    // A charge or reclaim can happen while memory.stat flushes its counters.
    // The larger bracketing total reduces ordinary monotonic skew without
    // paying for a second statistics flush.
    current_before
        .max(current_after)
        .saturating_sub(reclaimable_inactive_file_bytes)
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
    fn reads_the_max_protection_sentinel_as_protected_rather_than_unprotected() {
        // The kubelet writes concrete bytes, but an operator override or
        // systemd's MemoryLow=infinity leaves the cgroup-v2 `max` sentinel here.
        // Zero is what the alert fires on, so `max` must never land on it.
        assert_eq!(protection_bytes("max\n", Some(4096)), 4096);
        assert_eq!(protection_bytes("max", None), u64::MAX);

        assert_eq!(protection_bytes("1073741824\n", Some(4096)), 1_073_741_824);
        // A genuinely absent or malformed value stays zero: no protection.
        assert_eq!(protection_bytes("", Some(4096)), 0);
        assert_eq!(protection_bytes("garbage", Some(4096)), 0);
    }

    #[test]
    fn parses_named_control_group_memory_values() {
        let stat = "anon 123\nfile 456\ninactive_file 78\n";

        assert_eq!(named_value(stat, "anon"), Some(123));
        assert_eq!(named_value(stat, "file"), Some(456));
        assert_eq!(named_value(stat, "inactive_file"), Some(78));
        assert_eq!(named_value(stat, "missing"), None);
    }

    #[test]
    fn working_set_excludes_reclaimable_inactive_file_pages() {
        assert_eq!(working_set_bytes(100, Some(30)), 70);
        assert_eq!(working_set_bytes(100, None), 100);
    }

    #[test]
    fn snapshot_working_set_excludes_inactive_file_memory() {
        let snapshot = ContainerMemorySnapshot {
            current_bytes: 1_000,
            limit_bytes: Some(2_000),
            anon_bytes: Some(600),
            file_bytes: Some(300),
            kernel_bytes: Some(100),
            slab_reclaimable_bytes: None,
            slab_unreclaimable_bytes: None,
            inactive_file_bytes: Some(250),
            shmem_bytes: Some(25),
            sock_bytes: Some(15),
            file_dirty_bytes: Some(10),
            file_writeback_bytes: Some(5),
            max_events: Some(2),
            oom_events: Some(0),
            oom_kill_events: Some(0),
            workingset_refault_file: Some(3),
        };

        assert_eq!(snapshot.working_set_bytes(), 750);
        assert_eq!(snapshot.pressure_bytes(), 600 + 100 + 25 + 15 + 10 + 5);
        assert_eq!(snapshot.reclaimable_inactive_file_bytes(), 250);
    }

    #[test]
    fn pressure_excludes_reclaimable_slab_nested_in_kernel() {
        // Reproduces the production wedge: a node carried ~1GiB of reclaimable slab
        // nested inside `kernel`, which counting put over the recovery watermark on its
        // own, latching Critical. Figures are the observed ones, in MiB.
        let observed = |slab_reclaimable_bytes| {
            pressure_bytes(MemoryPressureComponents {
                current_bytes: 1_827,
                anon_bytes: Some(544),
                file_bytes: Some(255),
                kernel_bytes: Some(1_029),
                slab_reclaimable_bytes,
                shmem_bytes: Some(0),
                sock_bytes: Some(0),
                file_dirty_bytes: Some(0),
                file_writeback_bytes: Some(0),
                inactive_file_bytes: Some(255),
            })
        };

        // Reclaimable slab is excluded, leaving the ~9MiB of kernel memory the process
        // genuinely cannot release.
        assert_eq!(observed(Some(1_020)), 544 + 9);
        // The pre-fix accounting, kept explicit.
        assert_eq!(observed(None), 544 + 1_029);

        // Why the node never recovered: leaving Critical for Normal means dropping below
        // the soft watermark's recovery line, and only Normal lets the cache targets stop
        // trimming the index to zero. Counting reclaimable slab left the node above that
        // line with every Kura-owned cache already trimmed to zero, so there was no path
        // back. Call the real transition rule rather than restating it, so this keeps
        // testing recovery if the watermark or the recovery ratio moves.
        let normal_recovery = crate::memory::pressure::recovery_bytes(1_228);
        assert!(observed(None) > normal_recovery);
        assert!(observed(Some(1_020)) < normal_recovery);
    }

    #[test]
    fn pressure_never_underflows_when_reclaimable_slab_exceeds_kernel() {
        // `slab_reclaimable` is nested in `kernel`, so this cannot happen on a coherent
        // read, but the two rows are parsed independently and must not wrap.
        assert_eq!(
            pressure_bytes(MemoryPressureComponents {
                current_bytes: 1_000,
                anon_bytes: Some(300),
                file_bytes: Some(0),
                kernel_bytes: Some(40),
                slab_reclaimable_bytes: Some(500),
                shmem_bytes: None,
                sock_bytes: None,
                file_dirty_bytes: None,
                file_writeback_bytes: None,
                inactive_file_bytes: None,
            }),
            300
        );
    }

    #[test]
    fn pressure_excludes_clean_file_cache_regardless_of_recency() {
        assert_eq!(
            pressure_bytes(MemoryPressureComponents {
                current_bytes: 1_000,
                anon_bytes: Some(300),
                file_bytes: Some(700),
                kernel_bytes: Some(40),
                slab_reclaimable_bytes: None,
                shmem_bytes: Some(25),
                sock_bytes: None,
                file_dirty_bytes: Some(10),
                file_writeback_bytes: Some(5),
                inactive_file_bytes: Some(50),
            }),
            380
        );
        assert_eq!(
            pressure_bytes(MemoryPressureComponents {
                current_bytes: 1_000,
                anon_bytes: Some(300),
                file_bytes: Some(700),
                kernel_bytes: Some(40),
                slab_reclaimable_bytes: None,
                shmem_bytes: Some(25),
                sock_bytes: None,
                file_dirty_bytes: Some(10),
                file_writeback_bytes: Some(5),
                inactive_file_bytes: Some(650),
            }),
            380
        );
    }

    #[test]
    fn pressure_includes_socket_buffers_without_exceeding_current() {
        assert_eq!(
            pressure_bytes(MemoryPressureComponents {
                current_bytes: 1_000,
                anon_bytes: Some(300),
                file_bytes: Some(700),
                kernel_bytes: Some(40),
                slab_reclaimable_bytes: None,
                shmem_bytes: Some(25),
                sock_bytes: Some(60),
                file_dirty_bytes: Some(10),
                file_writeback_bytes: Some(5),
                inactive_file_bytes: Some(50),
            }),
            440
        );
        assert_eq!(
            pressure_bytes(MemoryPressureComponents {
                current_bytes: 300,
                anon_bytes: Some(100),
                file_bytes: Some(50),
                kernel_bytes: Some(40),
                slab_reclaimable_bytes: None,
                shmem_bytes: Some(60),
                sock_bytes: Some(200),
                file_dirty_bytes: Some(10),
                file_writeback_bytes: Some(5),
                inactive_file_bytes: Some(50),
            }),
            300
        );
    }

    #[test]
    fn pressure_prefers_point_in_time_accounting_during_charge_changes() {
        assert_eq!(
            pressure_bytes(MemoryPressureComponents {
                current_bytes: 1_900,
                anon_bytes: Some(300),
                file_bytes: Some(1_500),
                kernel_bytes: Some(40),
                slab_reclaimable_bytes: None,
                shmem_bytes: None,
                sock_bytes: None,
                file_dirty_bytes: None,
                file_writeback_bytes: None,
                inactive_file_bytes: Some(50),
            }),
            340
        );
        assert_eq!(
            pressure_bytes(MemoryPressureComponents {
                current_bytes: 500,
                anon_bytes: Some(300),
                file_bytes: Some(100),
                kernel_bytes: Some(40),
                slab_reclaimable_bytes: None,
                shmem_bytes: None,
                sock_bytes: None,
                file_dirty_bytes: None,
                file_writeback_bytes: None,
                inactive_file_bytes: Some(300),
            }),
            340
        );
    }

    #[test]
    fn pressure_falls_back_to_the_working_set_without_file_accounting() {
        assert_eq!(
            pressure_bytes(MemoryPressureComponents {
                current_bytes: 1_000,
                anon_bytes: None,
                file_bytes: None,
                kernel_bytes: None,
                slab_reclaimable_bytes: None,
                shmem_bytes: None,
                sock_bytes: None,
                file_dirty_bytes: None,
                file_writeback_bytes: None,
                inactive_file_bytes: Some(250),
            }),
            750
        );
    }

    #[test]
    fn pressure_never_exceeds_current_without_kernel_accounting() {
        assert_eq!(
            pressure_bytes(MemoryPressureComponents {
                current_bytes: 300,
                anon_bytes: Some(100),
                file_bytes: Some(200),
                kernel_bytes: None,
                slab_reclaimable_bytes: None,
                shmem_bytes: Some(150),
                sock_bytes: None,
                file_dirty_bytes: Some(100),
                file_writeback_bytes: Some(50),
                inactive_file_bytes: Some(100),
            }),
            300
        );
    }

    #[test]
    fn bracketed_working_set_uses_the_larger_total_during_reclaim() {
        assert_eq!(bracketed_working_set_bytes(900, 400, 600), 300);
        assert_eq!(bracketed_working_set_bytes(400, 900, 600), 300);
    }
}
