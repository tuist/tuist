//! Wrapper timings use monotonic intervals; wall time only positions trace lanes.
//! Totals are exclusive, while trace spans retain their nesting. Uninstrumented
//! work stays visible as `unattributed`. Telemetry delivery is outside the timer.
use std::cell::RefCell;
#[cfg(test)]
use std::collections::BTreeMap;
use std::sync::OnceLock;
use std::time::{Instant, SystemTime, UNIX_EPOCH};
use tuist_cargo_cache_core::{AgentRequest, WrapperSpan, WrapperTiming};

static ENTRY: OnceLock<(Instant, u64)> = OnceLock::new();
thread_local! { static ACTIVE: RefCell<Option<Tracker>> = const { RefCell::new(None) }; }

/// Record executable entry before dispatch, without initializing any runtime.
pub fn initialize() {
    ENTRY.get_or_init(|| {
        (
            Instant::now(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map_or(0, |d| d.as_micros().try_into().unwrap_or(u64::MAX)),
        )
    });
}

struct Tracker {
    start: Instant,
    timing: WrapperTiming,
    stack: Vec<Frame>,
}
struct Frame {
    name: &'static str,
    start: u64,
    children: u64,
}
pub(crate) struct Invocation;
pub(crate) struct Phase(bool);

pub(crate) fn start(adapter: &str, unit: Option<String>) -> Invocation {
    initialize();
    let (start, start_us) = *ENTRY.get().unwrap();
    let startup = nanos(start.elapsed());
    let mut timing = WrapperTiming::default();
    timing.adapter = adapter.into();
    timing.unit = unit;
    timing.pid = std::process::id();
    timing.start_us = start_us;
    timing.phases_ns.insert("startup".into(), startup);
    timing.spans.push(span("startup", 0, startup));
    ACTIVE.with(|active| {
        *active.borrow_mut() = Some(Tracker {
            start,
            timing,
            stack: Vec::new(),
        })
    });
    Invocation
}

/// Name the build unit this invocation produces and the units it consumed.
pub(crate) fn identify(unit_id: Option<String>, dependencies: Vec<String>) {
    ACTIVE.with(|active| {
        if let Some(tracker) = active.borrow_mut().as_mut() {
            tracker.timing.unit_id = unit_id;
            tracker.timing.dependencies = dependencies;
        }
    });
}

pub(crate) fn phase(name: &'static str) -> Phase {
    Phase(ACTIVE.with(|active| {
        let mut active = active.borrow_mut();
        let Some(tracker) = active.as_mut() else {
            return false;
        };
        tracker.stack.push(Frame {
            name,
            start: nanos(tracker.start.elapsed()),
            children: 0,
        });
        true
    }))
}

pub(crate) fn measure<T>(name: &'static str, f: impl FnOnce() -> T) -> T {
    let _phase = phase(name);
    f()
}

impl Tracker {
    fn end_phase(&mut self, end: u64) {
        let Some(frame) = self.stack.pop() else {
            return;
        };
        let duration = end.saturating_sub(frame.start);
        if let Some(parent) = self.stack.last_mut() {
            parent.children = parent.children.saturating_add(duration);
        }
        let total = self.timing.phases_ns.entry(frame.name.into()).or_default();
        *total = total.saturating_add(duration.saturating_sub(frame.children));
        if self.timing.spans.len() < 512 {
            self.timing
                .spans
                .push(span(frame.name, frame.start, duration));
        }
    }

    fn finish(mut self, elapsed: u64) -> WrapperTiming {
        // Windows can finish explicitly before ExitProcess, while RAII phase
        // guards are still alive. Close those intervals at the same boundary.
        while !self.stack.is_empty() {
            self.end_phase(elapsed);
        }
        self.timing.duration_ns = elapsed;
        let attributed = self
            .timing
            .phases_ns
            .values()
            .fold(0u64, |sum, n| sum.saturating_add(*n));
        self.timing
            .phases_ns
            .insert("unattributed".into(), elapsed.saturating_sub(attributed));
        self.timing
    }
}

impl Drop for Phase {
    fn drop(&mut self) {
        if self.0 {
            ACTIVE.with(|active| {
                if let Some(tracker) = active.borrow_mut().as_mut() {
                    tracker.end_phase(nanos(tracker.start.elapsed()));
                }
            });
        }
    }
}
impl Drop for Invocation {
    fn drop(&mut self) {
        finish();
    }
}

/// Send the completed timing once, including when the platform exit path
/// terminates without running destructors. Later guard drops become no-ops.
pub(crate) fn finish() {
    let tracker = ACTIVE.with(|active| active.borrow_mut().take());
    if let Some(tracker) = tracker {
        let elapsed = nanos(tracker.start.elapsed());
        let timing = tracker.finish(elapsed);
        // A failed telemetry request must neither affect compilation nor
        // pollute compiler stderr (cc-rs uses stderr to interpret probes).
        let _ = crate::session::request_agent(&[AgentRequest::RecordWrapperTiming { timing }]);
    }
}
fn nanos(duration: std::time::Duration) -> u64 {
    duration.as_nanos().try_into().unwrap_or(u64::MAX)
}
fn span(name: &str, start_ns: u64, duration_ns: u64) -> WrapperSpan {
    let mut span = WrapperSpan::default();
    span.name = name.into();
    span.start_ns = start_ns;
    span.duration_ns = duration_ns;
    span
}

/// Convert a saved session stream to Chrome Trace JSON, accepted by Perfetto.
pub(crate) fn export(path: &std::path::Path) -> eyre::Result<serde_json::Value> {
    use std::io::BufRead;
    let file = std::io::BufReader::new(std::fs::File::open(path)?);
    let mut events = Vec::new();
    for line in file.lines() {
        let line = line?;
        if let Ok(crate::events::SessionEvent::WrapperTiming { timing, .. }) =
            serde_json::from_str(&line)
        {
            events.extend(trace_events(&timing));
        }
    }
    Ok(serde_json::json!({"traceEvents": events, "displayTimeUnit": "ms"}))
}
fn trace_events(timing: &WrapperTiming) -> Vec<serde_json::Value> {
    let event = |name: &str, start: u64, duration: u64| {
        serde_json::json!({
            "name": name, "cat": timing.adapter, "ph": "X", "pid": timing.pid, "tid": 0,
            "ts": timing.start_us as f64 + start as f64 / 1000.0,
            "dur": duration as f64 / 1000.0,
        })
    };
    let mut events = vec![event(
        timing.unit.as_deref().unwrap_or(&timing.adapter),
        0,
        timing.duration_ns,
    )];
    // Older/future writers or truncated spans must never escape their parent.
    let mut spans: Vec<_> = timing.spans.iter().collect();
    spans.sort_by_key(|s| (s.start_ns, std::cmp::Reverse(s.duration_ns)));
    for span in spans {
        let start = span.start_ns.min(timing.duration_ns);
        let duration = span
            .duration_ns
            .min(timing.duration_ns.saturating_sub(start));
        if duration > 0 {
            events.push(event(&span.name, start, duration));
        }
    }
    events
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn nested_totals_are_exclusive_and_leave_a_remainder() {
        let mut tracker = Tracker {
            start: Instant::now(),
            timing: WrapperTiming::default(),
            stack: vec![Frame {
                name: "key",
                start: 10,
                children: 0,
            }],
        };
        tracker.stack.push(Frame {
            name: "lookup",
            start: 20,
            children: 0,
        });
        tracker.end_phase(40);
        tracker.end_phase(80);
        let timing = tracker.finish(100);
        assert_eq!(
            timing.phases_ns,
            BTreeMap::from([
                ("key".into(), 50),
                ("lookup".into(), 20),
                ("unattributed".into(), 30)
            ])
        );
        assert_eq!(timing.spans[1].duration_ns, 70);
        assert_eq!(timing.phases_ns.values().sum::<u64>(), timing.duration_ns);
    }
    #[test]
    fn explicit_finish_closes_nested_phases_before_process_exit() {
        let tracker = Tracker {
            start: Instant::now(),
            timing: WrapperTiming::default(),
            stack: vec![
                Frame {
                    name: "key",
                    start: 10,
                    children: 0,
                },
                Frame {
                    name: "lookup",
                    start: 20,
                    children: 0,
                },
            ],
        };
        let timing = tracker.finish(100);
        assert_eq!(timing.phases_ns["key"], 10);
        assert_eq!(timing.phases_ns["lookup"], 80);
        assert_eq!(timing.phases_ns["unattributed"], 10);
        assert_eq!(timing.spans.len(), 2);
        assert_eq!(timing.phases_ns.values().sum::<u64>(), timing.duration_ns);
    }

    #[test]
    fn trace_keeps_submicrosecond_work_and_clamps_children() {
        let mut timing = WrapperTiming::default();
        timing.duration_ns = 1000;
        timing.start_us = 100;
        timing.pid = 42;
        timing.spans = vec![span("key", 100, 5000), span("lookup", 2000, 50)];
        let events = trace_events(&timing);
        assert_eq!(events.len(), 2);
        assert_eq!(events[1]["ts"], 100.1);
        assert_eq!(events[1]["dur"], 0.9);
        assert_eq!(events[1]["pid"], 42);
    }
    #[test]
    fn capped_traces_still_account_for_every_phase() {
        let mut tracker = Tracker {
            start: Instant::now(),
            timing: WrapperTiming::default(),
            stack: Vec::new(),
        };
        for n in 0..600 {
            tracker.stack.push(Frame {
                name: "lookup",
                start: n * 10,
                children: 0,
            });
            tracker.end_phase(n * 10 + 5);
        }
        let timing = tracker.finish(6000);
        assert_eq!(timing.spans.len(), 512);
        assert_eq!(timing.phases_ns["lookup"], 3000);
        assert_eq!(timing.phases_ns["unattributed"], 3000);
    }
}
