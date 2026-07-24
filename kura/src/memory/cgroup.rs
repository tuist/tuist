#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ContainerMemorySnapshot {
    pub current_bytes: u64,
    pub limit_bytes: Option<u64>,
    pub anon_bytes: Option<u64>,
    pub file_bytes: Option<u64>,
    pub kernel_bytes: Option<u64>,
    pub inactive_file_bytes: Option<u64>,
    pub oom_events: Option<u64>,
    pub oom_kill_events: Option<u64>,
}

pub fn container_memory_working_set_bytes() -> Option<u64> {
    #[cfg(target_os = "linux")]
    {
        if let Some(current_bytes) = read_u64_file("/sys/fs/cgroup/memory.current") {
            let inactive_file_bytes = std::fs::read_to_string("/sys/fs/cgroup/memory.stat")
                .ok()
                .and_then(|value| named_value(&value, "inactive_file"))
                .unwrap_or(0);
            return Some(working_set_bytes(current_bytes, Some(inactive_file_bytes)));
        }

        let current_bytes = read_u64_file("/sys/fs/cgroup/memory/memory.usage_in_bytes")?;
        let inactive_file_bytes = std::fs::read_to_string("/sys/fs/cgroup/memory/memory.stat")
            .ok()
            .and_then(|value| named_value(&value, "total_inactive_file"))
            .unwrap_or(0);
        Some(working_set_bytes(current_bytes, Some(inactive_file_bytes)))
    }
    #[cfg(not(target_os = "linux"))]
    {
        None
    }
}

#[cfg(any(target_os = "linux", test))]
fn working_set_bytes(current_bytes: u64, inactive_file_bytes: Option<u64>) -> u64 {
    current_bytes.saturating_sub(inactive_file_bytes.unwrap_or(0))
}

pub fn container_memory_snapshot() -> Option<ContainerMemorySnapshot> {
    #[cfg(target_os = "linux")]
    {
        if let Some(current_bytes) = read_u64_file("/sys/fs/cgroup/memory.current") {
            let stat = std::fs::read_to_string("/sys/fs/cgroup/memory.stat").ok();
            let events = std::fs::read_to_string("/sys/fs/cgroup/memory.events").ok();
            return Some(ContainerMemorySnapshot {
                current_bytes,
                limit_bytes: read_memory_limit_file("/sys/fs/cgroup/memory.max"),
                anon_bytes: stat.as_deref().and_then(|value| named_value(value, "anon")),
                file_bytes: stat.as_deref().and_then(|value| named_value(value, "file")),
                kernel_bytes: stat
                    .as_deref()
                    .and_then(|value| named_value(value, "kernel")),
                inactive_file_bytes: stat
                    .as_deref()
                    .and_then(|value| named_value(value, "inactive_file")),
                oom_events: events
                    .as_deref()
                    .and_then(|value| named_value(value, "oom")),
                oom_kill_events: events
                    .as_deref()
                    .and_then(|value| named_value(value, "oom_kill")),
            });
        }

        let current_bytes = read_u64_file("/sys/fs/cgroup/memory/memory.usage_in_bytes")?;
        let stat = std::fs::read_to_string("/sys/fs/cgroup/memory/memory.stat").ok();
        let events = std::fs::read_to_string("/sys/fs/cgroup/memory/memory.failcnt").ok();
        Some(ContainerMemorySnapshot {
            current_bytes,
            limit_bytes: read_memory_limit_file("/sys/fs/cgroup/memory/memory.limit_in_bytes"),
            anon_bytes: stat.as_deref().and_then(|value| named_value(value, "rss")),
            file_bytes: stat
                .as_deref()
                .and_then(|value| named_value(value, "cache")),
            kernel_bytes: None,
            inactive_file_bytes: stat
                .as_deref()
                .and_then(|value| named_value(value, "total_inactive_file")),
            oom_events: events
                .as_deref()
                .and_then(|value| value.trim().parse::<u64>().ok()),
            oom_kill_events: None,
        })
    }
    #[cfg(not(target_os = "linux"))]
    {
        None
    }
}

#[cfg(target_os = "linux")]
fn read_u64_file(path: &str) -> Option<u64> {
    std::fs::read_to_string(path).ok()?.trim().parse().ok()
}

#[cfg(target_os = "linux")]
fn read_memory_limit_file(path: &str) -> Option<u64> {
    let value = std::fs::read_to_string(path).ok()?;
    let value = value.trim();
    if value.is_empty() || value == "max" {
        None
    } else {
        value.parse().ok()
    }
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
    fn working_set_excludes_reclaimable_inactive_file_pages() {
        assert_eq!(working_set_bytes(100, Some(30)), 70);
        assert_eq!(working_set_bytes(100, None), 100);
    }
}
