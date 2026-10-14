//! Resolve memory limits at the process's cgroup and every visible ancestor.
//!
//! Parent usage includes sibling workloads. Subtracting only the leaf's usage
//! from a parent's limit would overestimate how much memory a compiler can use.
use crate::util::{parse_cgroup_stat, read_cgroup_text};
use std::ffi::OsString;
use std::os::unix::ffi::OsStringExt;
use std::path::{Component, Path, PathBuf};

#[derive(Debug, Default, PartialEq, Eq)]
pub(crate) struct Memory {
    pub limit: Option<u64>,
    pub headroom: Option<u64>,
}

#[derive(Debug)]
struct Domain {
    mount: PathBuf,
    current: PathBuf,
    v2: bool,
}

/// PSI files for every visible v2 ancestor, including unlimited ancestors.
pub(crate) fn pressure_files() -> Vec<PathBuf> {
    visible_domains()
        .into_iter()
        .filter(|domain| domain.v2)
        .flat_map(|domain| {
            domain
                .current
                .ancestors()
                .take_while(|path| path.starts_with(&domain.mount))
                .map(|path| path.join("memory.pressure"))
                .collect::<Vec<_>>()
        })
        .collect()
}

/// Every visible memory cgroup directory, v1 or v2, from this process's group
/// up to its mount: the directories whose files the memory probes read.
pub(crate) fn memory_directories() -> Vec<PathBuf> {
    visible_domains()
        .into_iter()
        .flat_map(|domain| {
            domain
                .current
                .ancestors()
                .take_while(|path| path.starts_with(&domain.mount))
                .map(Path::to_path_buf)
                .collect::<Vec<_>>()
        })
        .collect()
}

pub(crate) fn memory() -> Memory {
    snapshot(&visible_domains())
}

fn visible_domains() -> Vec<Domain> {
    let domains = std::fs::read_to_string("/proc/self/cgroup")
        .ok()
        .zip(std::fs::read_to_string("/proc/self/mountinfo").ok())
        .map(|(groups, mounts)| domains(&groups, &mounts))
        .unwrap_or_default();
    if domains.is_empty() {
        // Preserve detection in containers that hide proc membership or mounts.
        return vec![
            Domain {
                mount: "/sys/fs/cgroup".into(),
                current: "/sys/fs/cgroup".into(),
                v2: true,
            },
            Domain {
                mount: "/sys/fs/cgroup/memory".into(),
                current: "/sys/fs/cgroup/memory".into(),
                v2: false,
            },
        ];
    }
    domains
}

fn domains(groups: &str, mounts: &str) -> Vec<Domain> {
    let memberships: Vec<_> = groups
        .lines()
        .filter_map(|line| {
            let mut fields = line.splitn(3, ':');
            fields.next()?;
            let controllers = fields.next()?;
            let path = Path::new(fields.next()?);
            let v2 = controllers.is_empty();
            (v2 || controllers.split(',').any(|name| name == "memory")).then_some((v2, path))
        })
        .collect();
    mounts
        .lines()
        .filter_map(|line| {
            let (left, right) = line.split_once(" - ")?;
            let fields: Vec<_> = left.split_whitespace().collect();
            let mut options = right.split_whitespace();
            let fs = options.next()?;
            options.next()?;
            let super_options = options.next()?;
            let v2 = match fs {
                "cgroup2" => true,
                "cgroup" if super_options.split(',').any(|name| name == "memory") => false,
                _ => return None,
            };
            let root = mount_path(fields.get(3)?)?;
            let mount = mount_path(fields.get(4)?)?;
            let (_, member) = memberships
                .iter()
                .find(|(version, path)| *version == v2 && path.starts_with(&root))?;
            // Membership is relative to the cgroup namespace. Mount roots use
            // that same namespace; component checks reject prefix lookalikes and
            // proc paths that would escape the visible mount through '..'.
            if !safe_absolute(member) || !safe_absolute(&root) || !safe_absolute(&mount) {
                return None;
            }
            let current = mount.join(member.strip_prefix(&root).ok()?);
            Some(Domain { mount, current, v2 })
        })
        .collect()
}

fn safe_absolute(path: &Path) -> bool {
    path.is_absolute() && !path.components().any(|c| matches!(c, Component::ParentDir))
}

/// mountinfo escapes spaces, tabs, newlines and backslashes with octal bytes.
fn mount_path(value: &str) -> Option<PathBuf> {
    let mut bytes = Vec::new();
    let mut input = value.as_bytes().iter().copied();
    while let Some(byte) = input.next() {
        if byte == b'\\' {
            let mut decoded = 0u16;
            for _ in 0..3 {
                let digit = input.next()?;
                if !(b'0'..=b'7').contains(&digit) {
                    return None;
                }
                decoded = decoded * 8 + u16::from(digit - b'0');
            }
            bytes.push(u8::try_from(decoded).ok()?);
        } else {
            bytes.push(byte);
        }
    }
    Some(OsString::from_vec(bytes).into())
}

fn snapshot(domains: &[Domain]) -> Memory {
    let mut result = Memory::default();
    for domain in domains {
        for directory in domain.current.ancestors() {
            if !directory.starts_with(&domain.mount) {
                break;
            }
            let (limit_name, usage_name, reclaim_field) = if domain.v2 {
                ("memory.max", "memory.current", "inactive_file")
            } else {
                (
                    "memory.limit_in_bytes",
                    "memory.usage_in_bytes",
                    "total_inactive_file",
                )
            };
            let Some(limit) = std::fs::read_to_string(directory.join(limit_name))
                .ok()
                .and_then(|s| {
                    if s.trim() == "0" {
                        Some(0)
                    } else {
                        read_cgroup_text(&s)
                    }
                })
            else {
                continue;
            };
            let usage = std::fs::read_to_string(directory.join(usage_name))
                .ok()
                .and_then(|s| s.trim().parse::<u64>().ok());
            let reclaimable = std::fs::read_to_string(directory.join("memory.stat"))
                .ok()
                .and_then(|s| parse_cgroup_stat(&s, reclaim_field))
                .unwrap_or(0);
            let headroom = usage.map_or(limit, |used| {
                limit.saturating_sub(used.saturating_sub(reclaimable))
            });
            result.limit = Some(result.limit.map_or(limit, |old| old.min(limit)));
            result.headroom = Some(result.headroom.map_or(headroom, |old| old.min(headroom)));
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write_memory(path: &Path, limit: &str, usage: u64, inactive: u64, v2: bool) {
        std::fs::create_dir_all(path).unwrap();
        let (limit_name, usage_name, field) = if v2 {
            ("memory.max", "memory.current", "inactive_file")
        } else {
            (
                "memory.limit_in_bytes",
                "memory.usage_in_bytes",
                "total_inactive_file",
            )
        };
        std::fs::write(path.join(limit_name), limit).unwrap();
        std::fs::write(path.join(usage_name), usage.to_string()).unwrap();
        std::fs::write(path.join("memory.stat"), format!("{field} {inactive}\n")).unwrap();
    }

    #[test]
    fn nested_membership_uses_parent_headroom_including_siblings() {
        let temp = tempfile::tempdir().unwrap();
        let mount = temp.path();
        write_memory(mount, "max", 0, 0, true);
        write_memory(&mount.join("slice"), "1000", 950, 100, true);
        write_memory(&mount.join("slice/build"), "800", 200, 50, true);
        let mounts = format!("1 0 0:1 / {} rw - cgroup2 cgroup rw", mount.display());
        let domains = domains("0::/slice/build\n", &mounts);
        assert_eq!(
            snapshot(&domains),
            Memory {
                limit: Some(800),
                headroom: Some(150)
            }
        );
        write_memory(&mount.join("slice"), "1000", 1100, 0, true);
        assert_eq!(snapshot(&domains).headroom, Some(0));
    }

    #[test]
    fn v1_memory_controller_and_subtree_mount() {
        let temp = tempfile::tempdir().unwrap();
        let mount = temp.path().join("memory mount");
        write_memory(&mount, "1000", 950, 300, false);
        write_memory(&mount.join("build"), "9223372036854771712", 100, 0, false);
        let escaped = mount.to_string_lossy().replace(' ', "\\040");
        let mounts = format!("1 0 0:1 /slice {escaped} rw - cgroup cgroup rw,memory\n");
        let found = domains("2:cpu,cpuacct:/other\n3:memory:/slice/build\n", &mounts);
        assert_eq!(found[0].current, mount.join("build"));
        assert_eq!(
            snapshot(&found),
            Memory {
                limit: Some(1000),
                headroom: Some(350)
            }
        );
        assert!(domains("3:memory:/slice-other/build", &mounts).is_empty());
    }

    #[test]
    fn bind_mounts_do_not_hide_visible_ancestor_limits() {
        let temp = tempfile::tempdir().unwrap();
        let full = temp.path().join("full");
        let bind = temp.path().join("bind");
        write_memory(&full, "1000", 900, 0, true);
        write_memory(&full.join("slice"), "max", 0, 0, true);
        write_memory(&bind, "max", 0, 0, true);
        let mounts = format!(
            "1 0 0:1 /slice {} rw - cgroup2 cgroup rw\n2 0 0:1 / {} rw - cgroup2 cgroup rw",
            bind.display(),
            full.display()
        );
        assert_eq!(snapshot(&domains("0::/slice", &mounts)).headroom, Some(100));
    }

    #[test]
    fn missing_stats_count_all_usage_and_zero_limit_is_real() {
        let temp = tempfile::tempdir().unwrap();
        write_memory(temp.path(), "1000", 700, 600, true);
        let domains = [Domain {
            mount: temp.path().into(),
            current: temp.path().into(),
            v2: true,
        }];
        std::fs::remove_file(temp.path().join("memory.stat")).unwrap();
        assert_eq!(snapshot(&domains).headroom, Some(300));
        std::fs::write(temp.path().join("memory.max"), "0").unwrap();
        assert_eq!(
            snapshot(&domains),
            Memory {
                limit: Some(0),
                headroom: Some(0)
            }
        );
    }

    #[test]
    fn malformed_mounts_and_escaping_memberships_are_ignored() {
        let mounts = "broken\n1 0 0:1 / /sys/fs/cgroup rw - cgroup2 cgroup rw";
        assert!(domains("0::/../escape", mounts).is_empty());
        assert!(domains("0::relative", mounts).is_empty());
        assert_eq!(mount_path("/a\\040b\\134c"), Some("/a b\\c".into()));
        assert!(mount_path("/bad\\999").is_none());
    }
}
