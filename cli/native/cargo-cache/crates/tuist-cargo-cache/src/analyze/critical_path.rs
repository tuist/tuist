//! The chain of units a recorded build waited on, and the stretches where only
//! one unit was running.
//!
//! Every rustc and build-script wrapper records when it started, how long it
//! took, which unit it produced, and which units it consumed. Walking back from
//! the unit that finished last, each step follows the dependency that became
//! ready last, which is the one the unit was waiting for. With pipelining a
//! dependent can start before its dependency finishes, so a dependency counts
//! as ready at the earlier of its end and the dependent's start.
//!
//! Each unit on the path is credited with the time from the moment the unit
//! before it handed over to the moment it handed over to the next. Those spans
//! add up exactly to the path, so the list reads as where the build's length
//! came from.

use crate::events::SessionEvent;
use std::collections::{BTreeMap, BTreeSet};

/// One recorded unit with its wall-clock interval, in microseconds.
#[derive(Debug, Clone)]
struct Node {
    label: String,
    start_us: u64,
    end_us: u64,
    dependencies: Vec<String>,
}

/// One unit on the critical path.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Step {
    pub(crate) label: String,
    /// Time this unit added to the path.
    pub(crate) span_us: u64,
    /// Of that, time between its last dependency becoming ready and its start.
    pub(crate) waited_us: u64,
}

/// The critical path of one build and where it ran alone.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct CriticalPath {
    pub(crate) steps: Vec<Step>,
    pub(crate) path_us: u64,
    /// From the first unit's start to the last unit's end.
    pub(crate) span_us: u64,
    /// Time exactly one unit was running, by unit, costliest first.
    pub(crate) alone: Vec<(String, u64)>,
    pub(crate) alone_us: u64,
}

impl CriticalPath {
    /// Read the path out of a session's wrapper timings, if it recorded any
    /// units.
    pub(crate) fn of(events: &[SessionEvent]) -> Option<Self> {
        let nodes = nodes(events);
        let (last_id, last) = nodes.iter().max_by_key(|(id, node)| (node.end_us, *id))?;

        // Walk back from the last unit to finish.
        let mut chain = vec![last_id.as_str()];
        let mut seen = BTreeSet::from([last_id.as_str()]);
        let mut handoffs = Vec::new();
        let mut current = last;
        loop {
            let ready = current
                .dependencies
                .iter()
                .filter_map(|id| nodes.get_key_value(id.as_str()))
                .filter(|(id, _)| !seen.contains(id.as_str()))
                .map(|(id, node)| (node.end_us.min(current.start_us), node.end_us, id))
                .max();
            let Some((handoff, _, id)) = ready else {
                handoffs.push(current.start_us);
                break;
            };
            handoffs.push(handoff);
            seen.insert(id);
            chain.push(id);
            current = &nodes[id.as_str()];
        }

        let mut boundary = last.end_us;
        let mut steps = Vec::new();
        for (id, handoff) in chain.iter().zip(&handoffs) {
            let node = &nodes[*id];
            steps.push(Step {
                label: node.label.clone(),
                span_us: boundary.saturating_sub(*handoff),
                waited_us: node.start_us.saturating_sub(*handoff),
            });
            boundary = *handoff;
        }
        steps.reverse();
        let first_start = nodes.values().map(|node| node.start_us).min()?;
        let (alone, alone_us) = alone(&nodes);
        Some(Self {
            path_us: last.end_us.saturating_sub(boundary),
            span_us: last.end_us.saturating_sub(first_start),
            steps,
            alone,
            alone_us,
        })
    }
}

/// The units a session recorded, keyed by unit id, with readable labels.
fn nodes(events: &[SessionEvent]) -> BTreeMap<String, Node> {
    let mut nodes = BTreeMap::new();
    for event in events {
        let SessionEvent::WrapperTiming { timing, .. } = event else {
            continue;
        };
        let Some(id) = &timing.unit_id else {
            continue;
        };
        let label = timing
            .unit
            .clone()
            .unwrap_or_else(|| timing.adapter.clone());
        nodes.insert(
            id.clone(),
            Node {
                label,
                start_us: timing.start_us,
                end_us: timing.start_us.saturating_add(timing.duration_ns / 1_000),
                dependencies: timing.dependencies.clone(),
            },
        );
    }
    // Every package's build script compiles as `build_script_build`; the run
    // that consumes it knows which package it belongs to.
    let renames: Vec<_> = nodes
        .values()
        .filter(|node| node.label.ends_with(" build script"))
        .flat_map(|node| {
            node.dependencies
                .iter()
                .map(|dependency| (dependency.clone(), format!("{} (compile)", node.label)))
        })
        .collect();
    for (id, label) in renames {
        if let Some(node) = nodes.get_mut(&id)
            && node.label.starts_with("build_script_")
        {
            node.label = label;
        }
    }
    nodes
}

/// Time exactly one unit was running, charged to that unit.
fn alone(nodes: &BTreeMap<String, Node>) -> (Vec<(String, u64)>, u64) {
    // Starts sort before ends at the same instant, so back-to-back units never
    // look like a moment with nothing running.
    let mut edges: Vec<(u64, bool, &str)> = nodes
        .iter()
        .flat_map(|(id, node)| {
            [
                (node.start_us, false, id.as_str()),
                (node.end_us, true, id.as_str()),
            ]
        })
        .collect();
    edges.sort();
    let mut running: BTreeSet<&str> = BTreeSet::new();
    let mut charged: BTreeMap<&str, u64> = BTreeMap::new();
    let mut previous = edges.first().map_or(0, |edge| edge.0);
    for (at, ends, id) in edges {
        if running.len() == 1
            && let Some(only) = running.first()
        {
            *charged.entry(only).or_default() += at.saturating_sub(previous);
        }
        previous = at;
        if ends {
            running.remove(id);
        } else {
            running.insert(id);
        }
    }
    let total = charged.values().sum();
    let mut by_label: BTreeMap<String, u64> = BTreeMap::new();
    for (id, duration) in charged {
        *by_label.entry(nodes[id].label.clone()).or_default() += duration;
    }
    let mut ranked: Vec<_> = by_label.into_iter().filter(|(_, us)| *us > 0).collect();
    ranked.sort_by(|left, right| right.1.cmp(&left.1).then_with(|| left.0.cmp(&right.0)));
    (ranked, total)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tuist_cargo_cache_core::WrapperTiming;

    const MS: u64 = 1_000;

    fn unit(
        label: &str,
        id: &str,
        start_ms: u64,
        end_ms: u64,
        dependencies: &[&str],
    ) -> SessionEvent {
        let mut timing = WrapperTiming::default();
        timing.adapter = "rustc".into();
        timing.unit = Some(label.into());
        timing.unit_id = Some(id.into());
        timing.start_us = start_ms * MS;
        timing.duration_ns = (end_ms - start_ms) * MS * 1_000;
        timing.dependencies = dependencies.iter().map(|id| id.to_string()).collect();
        SessionEvent::WrapperTiming {
            v: 1,
            ts_ms: 0,
            timing,
        }
    }

    fn labels(path: &CriticalPath) -> Vec<(&str, u64, u64)> {
        path.steps
            .iter()
            .map(|step| (step.label.as_str(), step.span_us / MS, step.waited_us / MS))
            .collect()
    }

    #[test]
    fn the_path_follows_the_dependency_that_was_ready_last() {
        let path = CriticalPath::of(&[
            unit("syn", "a1", 0, 400, &[]),
            unit("small", "b2", 0, 100, &[]),
            unit("derive", "c3", 400, 700, &["a1", "b2"]),
            unit("app", "d4", 700, 1000, &["c3", "b2"]),
            // Off the path: finished well before anything waited on it.
            unit("side", "e5", 100, 300, &["b2"]),
        ])
        .unwrap();

        assert_eq!(
            labels(&path),
            [("syn", 400, 0), ("derive", 300, 0), ("app", 300, 0)]
        );
        assert_eq!(path.path_us, 1000 * MS);
        assert_eq!(path.span_us, 1000 * MS);
    }

    #[test]
    fn a_pipelined_dependent_is_credited_from_where_it_started() {
        // `app` starts once `engine`'s metadata exists, before `engine` ends.
        let path = CriticalPath::of(&[
            unit("engine", "a1", 0, 600, &[]),
            unit("app", "b2", 400, 900, &["a1"]),
        ])
        .unwrap();

        assert_eq!(labels(&path), [("engine", 400, 0), ("app", 500, 0)]);
        assert_eq!(path.path_us, 900 * MS);
    }

    #[test]
    fn a_gap_before_a_start_is_waiting() {
        let path = CriticalPath::of(&[
            unit("engine", "a1", 0, 100, &[]),
            unit("app", "b2", 250, 400, &["a1"]),
        ])
        .unwrap();

        assert_eq!(labels(&path), [("engine", 100, 0), ("app", 300, 150)]);
    }

    #[test]
    fn time_with_one_unit_running_is_charged_to_it() {
        let path = CriticalPath::of(&[
            unit("engine", "a1", 0, 500, &[]),
            unit("other", "b2", 0, 200, &[]),
            unit("app", "c3", 500, 800, &["a1"]),
        ])
        .unwrap();

        assert_eq!(
            path.alone,
            [
                ("app".to_string(), 300 * MS),
                ("engine".to_string(), 300 * MS)
            ]
        );
        assert_eq!(path.alone_us, 600 * MS);
    }

    #[test]
    fn a_build_script_compile_is_named_for_its_package() {
        let path = CriticalPath::of(&[
            unit("build_script_build", "a1", 0, 100, &[]),
            unit("ring build script", "run-b2", 100, 400, &["a1"]),
            unit("ring", "c3", 400, 500, &["run-b2"]),
        ])
        .unwrap();

        assert_eq!(path.steps[0].label, "ring build script (compile)");
        assert_eq!(path.steps[1].label, "ring build script");
    }

    #[test]
    fn a_session_without_unit_timings_has_no_path() {
        assert_eq!(CriticalPath::of(&[]), None);
    }
}
