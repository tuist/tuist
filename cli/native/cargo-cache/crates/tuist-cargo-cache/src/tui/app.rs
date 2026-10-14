//! What the dashboard knows, and how an event changes it.
//!
//! Kept apart from the drawing so the state machine can be tested without a
//! terminal: every screen is a function of this struct, and this struct is a
//! function of the events read so far.

use crate::events::{ActionOutcome, SessionEvent, SessionState, SessionTail};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

/// How many action rows one session keeps for display.
///
/// The stream on disk holds the whole build; this is the scrollback the TUI
/// offers over it, bounded so a long build cannot grow the process.
const MAX_ROWS: usize = 2_000;

/// Which screen is showing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Tab {
    Live,
    Sessions,
    Store,
    Insights,
}

impl Tab {
    pub(crate) const ALL: [Tab; 4] = [Tab::Live, Tab::Sessions, Tab::Store, Tab::Insights];

    pub(crate) fn title(self) -> &'static str {
        match self {
            Self::Live => "Live",
            Self::Sessions => "Sessions",
            Self::Store => "Store",
            Self::Insights => "Insights",
        }
    }

    fn next(self) -> Self {
        match self {
            Self::Live => Self::Sessions,
            Self::Sessions => Self::Store,
            Self::Store => Self::Insights,
            Self::Insights => Self::Live,
        }
    }
}

/// One action, as a row.
#[derive(Debug, Clone)]
pub(crate) struct Row {
    pub outcome: ActionOutcome,
    pub crate_name: Option<String>,
    pub duration_ns: u64,
    pub avoided_compiler_ns: u64,
}

/// What one build's stream has said so far.
#[derive(Debug, Default)]
pub(crate) struct Session {
    pub id: String,
    pub workspace_root: Option<PathBuf>,
    pub command: Vec<String>,
    pub state: SessionState,
    pub started_ms: u64,
    pub finished_ms: Option<u64>,
    pub truncated: bool,
    /// Per-outcome counts, keyed by the same labels the summary uses.
    pub counts: BTreeMap<String, u64>,
    pub avoided_compiler_ns: u64,
    pub restored_bytes: u64,
    /// The most recent [`MAX_ROWS`] actions, oldest first.
    pub rows: Vec<Row>,
    /// A finished session's own totals.
    pub totals: Option<serde_json::Value>,
}

impl Session {
    fn apply(&mut self, event: SessionEvent) {
        match event {
            SessionEvent::SessionStarted {
                ts_ms,
                workspace_root,
                command,
                ..
            } => {
                self.started_ms = ts_ms;
                self.workspace_root = Some(workspace_root);
                self.command = command;
            }
            SessionEvent::Action {
                outcome,
                crate_name,
                duration_ns,
                detail,
                ..
            } => {
                *self.counts.entry(outcome.label().to_string()).or_insert(0) += 1;
                self.avoided_compiler_ns = self
                    .avoided_compiler_ns
                    .saturating_add(detail.avoided_compiler_ns);
                self.restored_bytes = self.restored_bytes.saturating_add(detail.output_bytes);
                if self.rows.len() == MAX_ROWS {
                    self.rows.remove(0);
                }
                self.rows.push(Row {
                    outcome,
                    crate_name,
                    duration_ns,
                    avoided_compiler_ns: detail.avoided_compiler_ns,
                });
            }
            SessionEvent::WrapperTiming { .. } => {}
            SessionEvent::Truncated { .. } => self.truncated = true,
            SessionEvent::SessionFinished { ts_ms, stats, .. } => {
                self.finished_ms = Some(ts_ms);
                self.totals = Some(stats);
            }
        }
    }

    /// What this session is called on screen: its command, or failing that its
    /// id.
    pub(crate) fn title(&self) -> String {
        if self.command.is_empty() {
            return self.id.clone();
        }
        format!("tuist_cargo_cache {}", self.command.join(" "))
    }

    /// The workspace's last path component, which is what a reader recognizes.
    pub(crate) fn workspace_name(&self) -> Option<&str> {
        self.workspace_root
            .as_deref()
            .and_then(Path::file_name)
            .and_then(std::ffi::OsStr::to_str)
    }

    pub(crate) fn count(&self, label: &str) -> u64 {
        self.counts.get(label).copied().unwrap_or(0)
    }

    /// Compilations that entered the cache, hit or miss.
    fn consulted(&self) -> u64 {
        self.count("hit").saturating_add(self.count("miss"))
    }

    /// Share of attempted lookups that hit, as a percentage.
    ///
    /// Deliberately over attempted lookups alone, matching the summary: rolling
    /// bypassed and unconsulted work into the denominator would report a number
    /// no cache could ever move.
    pub(crate) fn hit_rate(&self) -> Option<f64> {
        let consulted = self.consulted();
        (consulted > 0).then(|| self.count("hit") as f64 * 100.0 / consulted as f64)
    }

    /// Rows whose outcome is none of the accounted three, which is to say the
    /// bypasses, grouped by reason.
    pub(crate) fn bypasses(&self) -> Vec<(&str, u64)> {
        let mut bypasses: Vec<(&str, u64)> = self
            .counts
            .iter()
            .filter(|(label, _)| {
                !matches!(
                    label.as_str(),
                    "hit" | "miss" | "unconsulted" | "verification"
                )
            })
            .map(|(label, count)| (label.as_str(), *count))
            .collect();
        // Most frequent first: the reason worth acting on is the common one.
        bypasses.sort_by_key(|(label, count)| (std::cmp::Reverse(*count), *label));
        bypasses
    }
}

/// The dashboard.
pub(crate) struct App {
    store: PathBuf,
    tails: Vec<(SessionTail, Session)>,
    pub tab: Tab,
    pub selected: usize,
    pub scroll: usize,
    /// Rows back from the newest action; zero follows the build.
    pub action_scroll: usize,
    pub insight_scroll: usize,
    pub store_scroll: usize,
    pub cheeky: bool,
    pub paused: bool,
    pub store_stats: Option<crate::store::StoreStats>,
    pub savings: crate::savings::Tally,
    pub sharing: Option<crate::stats::SharingEstimate>,
    pub health: super::health::Health,
    pub store_budget: Option<u64>,
    pub gc_auto: bool,
    monitoring_since_ms: u64,
    last_sharing_refresh: Option<Instant>,
    sharing_worker: Option<std::sync::mpsc::Receiver<Option<crate::stats::SharingEstimate>>>,
}

impl App {
    pub(crate) fn new(store: &Path, limit: usize) -> Self {
        let mut app = Self {
            store: store.to_path_buf(),
            tails: Vec::new(),
            tab: Tab::Live,
            selected: 0,
            scroll: 0,
            action_scroll: 0,
            insight_scroll: 0,
            store_scroll: 0,
            cheeky: true,
            paused: false,
            store_stats: None,
            savings: crate::savings::Tally::default(),
            sharing: None,
            health: super::health::Health::default(),
            store_budget: None,
            gc_auto: true,
            monitoring_since_ms: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64,
            last_sharing_refresh: None,
            sharing_worker: None,
        };
        app.discover(limit);
        app.refresh_store();
        app
    }

    /// Pick up streams that have appeared since the last look, and read what
    /// every known stream has appended.
    pub(crate) fn tick(&mut self, limit: usize) {
        if self.paused {
            return;
        }
        let selected_id = self
            .selected_session()
            .filter(|session| session.workspace_root.is_some())
            .map(|session| session.id.clone());
        self.discover(limit);
        let now = Instant::now();
        let recent_since_ms = self.monitoring_since_ms.max(
            (SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64)
                .saturating_sub(super::health::WINDOW.as_millis() as u64),
        );
        let (mut hits, mut misses) = (0, 0);
        for (tail, session) in &mut self.tails {
            for event in tail.read() {
                if let SessionEvent::Action { ts_ms, outcome, .. } = &event
                    && *ts_ms > recent_since_ms
                {
                    hits += u64::from(matches!(outcome, ActionOutcome::Hit));
                    misses += u64::from(matches!(outcome, ActionOutcome::Miss));
                }
                // Keep the same activity in view while new work arrives. Once
                // retained history rolls off, the oldest available row wins.
                if self.action_scroll > 0
                    && selected_id.as_deref() == Some(session.id.as_str())
                    && matches!(&event, SessionEvent::Action { .. })
                {
                    self.action_scroll = (self.action_scroll + 1).min(MAX_ROWS - 1);
                }
                session.apply(event);
            }
            session.state = tail.state();
        }
        self.health.lookups(now, hits, misses);
        // Newest first, and a running build always above a finished one: the
        // build somebody is watching is the reason they opened this.
        self.tails.sort_by_key(|(tail, session)| {
            (
                session.state != SessionState::Live,
                std::cmp::Reverse(tail.id().to_string()),
            )
        });
        if let Some(id) = selected_id
            && let Some(index) = self.tails.iter().position(|(_, session)| session.id == id)
        {
            self.selected = index;
        }
        self.selected = self.selected.min(self.tails.len().saturating_sub(1));
        self.refresh_sharing();
    }

    pub(crate) fn sharing_loading(&self) -> bool {
        self.sharing_worker.is_some()
    }

    fn refresh_sharing(&mut self) {
        if let Some(worker) = &self.sharing_worker {
            match worker.try_recv() {
                Ok(sharing) => {
                    self.sharing = sharing;
                    self.sharing_worker = None;
                    self.last_sharing_refresh = Some(Instant::now());
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => return,
                Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                    self.sharing_worker = None;
                    self.last_sharing_refresh = Some(Instant::now());
                }
            }
        }
        // Attribution walks every workspace's cache closure. Never wait for it
        // on the input thread, and allow only one scan in flight at a time.
        if self.tab != Tab::Store
            || self
                .last_sharing_refresh
                .is_some_and(|last| last.elapsed() < Duration::from_secs(30))
        {
            return;
        }
        let Some(stats) = &self.store_stats else {
            return;
        };
        let bytes = stats.total_bytes();
        let store = self.store.clone();
        let (sender, receiver) = std::sync::mpsc::channel();
        match std::thread::Builder::new()
            .name("tui-sharing".into())
            .spawn(move || {
                let result = crate::stats::SharingEstimate::read(&store, bytes).ok();
                let _ = sender.send(result);
            }) {
            Ok(_) => self.sharing_worker = Some(receiver),
            Err(_) => self.last_sharing_refresh = Some(Instant::now()),
        }
    }

    fn discover(&mut self, limit: usize) {
        for tail in crate::events::open_tails(&self.store, limit) {
            if self.tails.iter().any(|(known, _)| known.id() == tail.id()) {
                continue;
            }
            let session = Session {
                id: tail.id().to_string(),
                ..Session::default()
            };
            self.tails.push((tail, session));
        }
    }

    pub(crate) fn refresh_store(&mut self) {
        if self.paused {
            return;
        }
        self.store_stats = crate::store::stats(&self.store).ok();
        self.savings = crate::savings::read_tally(&self.store);
        self.health.observe_evictions(
            Instant::now(),
            self.savings.since_secs,
            self.savings.freed_store_bytes,
        );
    }

    pub(crate) fn sessions(&self) -> impl Iterator<Item = &Session> {
        self.tails.iter().map(|(_, session)| session)
    }

    pub(crate) fn is_empty(&self) -> bool {
        self.tails.is_empty()
    }

    pub(crate) fn selected_session(&self) -> Option<&Session> {
        self.tails.get(self.selected).map(|(_, session)| session)
    }

    pub(crate) fn store_dir(&self) -> &Path {
        &self.store
    }

    pub(crate) fn next_tab(&mut self) {
        self.tab = self.tab.next();
        self.scroll = 0;
    }

    pub(crate) fn previous_tab(&mut self) {
        let current = Tab::ALL
            .iter()
            .position(|tab| *tab == self.tab)
            .unwrap_or(0);
        self.select_tab(Tab::ALL[(current + Tab::ALL.len() - 1) % Tab::ALL.len()]);
    }

    pub(crate) fn select_tab(&mut self, tab: Tab) {
        self.tab = tab;
        self.scroll = 0;
    }

    pub(crate) fn select_next(&mut self) {
        if matches!(self.tab, Tab::Live | Tab::Insights) {
            let next = (self.selected + 1).min(self.tails.len().saturating_sub(1));
            if next != self.selected {
                self.selected = next;
                self.action_scroll = 0;
                self.insight_scroll = 0;
            }
        } else if self.tab == Tab::Sessions {
            self.scroll = (self.scroll + 1).min(self.tails.len().saturating_sub(1));
        }
    }

    pub(crate) fn select_previous(&mut self) {
        if matches!(self.tab, Tab::Live | Tab::Insights) {
            if self.selected > 0 {
                self.selected -= 1;
                self.action_scroll = 0;
                self.insight_scroll = 0;
            }
        } else if self.tab == Tab::Sessions {
            self.scroll = self.scroll.saturating_sub(1);
        }
    }

    pub(crate) fn older_actions(&mut self, page: usize) {
        if self.tab == Tab::Live {
            let max = self
                .selected_session()
                .map_or(0, |session| session.rows.len().saturating_sub(page.max(1)));
            self.action_scroll = self.action_scroll.saturating_add(page).min(max);
        }
    }

    pub(crate) fn newer_actions(&mut self, page: usize) {
        if self.tab == Tab::Live {
            self.action_scroll = self.action_scroll.saturating_sub(page);
        }
    }

    pub(crate) fn follow_actions(&mut self) {
        self.action_scroll = 0;
    }

    pub(crate) fn toggle_pause(&mut self) {
        self.paused = !self.paused;
        if !self.paused {
            // Changes accumulated during a pause are not a five-minute sample.
            self.health = super::health::Health::default();
            self.monitoring_since_ms = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64;
        }
    }
}

#[cfg(test)]
#[path = "app_tests.rs"]
mod tests;
