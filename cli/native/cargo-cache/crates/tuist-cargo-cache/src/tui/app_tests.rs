use super::*;
use crate::events::{ActionDetail, EventWriter};

fn writer(store: &Path) -> EventWriter {
    let writer = EventWriter::with_limit(store, Some(crate::config::DEFAULT_EVENTS_MAX_SIZE));
    writer.started(Path::new("/checkouts/fixture"), &["build".into()], None);
    writer
}

#[test]
fn a_session_takes_its_name_and_counts_from_its_stream() {
    let store = tempfile::tempdir().unwrap();
    let build = writer(store.path());
    build.action(
        ActionOutcome::Hit,
        Some("serde".into()),
        10,
        ActionDetail {
            avoided_compiler_ns: 5_000,
            output_bytes: 128,
            ..ActionDetail::default()
        },
    );
    build.action(
        ActionOutcome::Miss,
        Some("tuist_cargo_cache".into()),
        20,
        ActionDetail::default(),
    );
    build.action(
        ActionOutcome::Bypass {
            reason: "incremental".into(),
        },
        None,
        0,
        ActionDetail::default(),
    );

    let mut app = App::new(store.path(), 10);
    app.tick(10);

    let session = app.selected_session().expect("the build should be listed");
    assert_eq!(session.title(), "tuist_cargo_cache build");
    assert_eq!(session.workspace_name(), Some("fixture"));
    assert_eq!(session.count("hit"), 1);
    assert_eq!(session.count("miss"), 1);
    assert_eq!(session.count("incremental"), 1);
    assert_eq!(session.avoided_compiler_ns, 5_000);
    assert_eq!(session.restored_bytes, 128);
    assert_eq!(session.rows.len(), 3);
    assert_eq!(session.bypasses(), vec![("incremental", 1)]);
    assert_eq!(session.state, SessionState::Live);
}

#[test]
fn the_hit_rate_counts_only_attempted_lookups() {
    let store = tempfile::tempdir().unwrap();
    let build = writer(store.path());
    build.action(ActionOutcome::Hit, None, 1, ActionDetail::default());
    build.action(ActionOutcome::Hit, None, 1, ActionDetail::default());
    build.action(ActionOutcome::Hit, None, 1, ActionDetail::default());
    build.action(ActionOutcome::Miss, None, 1, ActionDetail::default());
    // Neither of these was ever looked up, so neither can move a hit rate.
    build.action(ActionOutcome::Unconsulted, None, 1, ActionDetail::default());
    build.action(
        ActionOutcome::Bypass {
            reason: "native-library".into(),
        },
        None,
        0,
        ActionDetail::default(),
    );

    let mut app = App::new(store.path(), 10);
    app.tick(10);

    let session = app.selected_session().unwrap();
    assert_eq!(session.hit_rate(), Some(75.0));
}

#[test]
fn a_build_with_no_lookups_reports_no_hit_rate() {
    let store = tempfile::tempdir().unwrap();
    let build = writer(store.path());
    build.action(ActionOutcome::Unconsulted, None, 1, ActionDetail::default());

    let mut app = App::new(store.path(), 10);
    app.tick(10);

    // Zero of zero is not zero percent: a cold build looked nothing up, and
    // "0%" would read as a cache that failed rather than one never asked.
    assert_eq!(app.selected_session().unwrap().hit_rate(), None);
}

#[test]
fn a_finished_session_carries_the_totals_its_stream_ended_with() {
    let store = tempfile::tempdir().unwrap();
    let build = writer(store.path());
    build.action(ActionOutcome::Hit, None, 1, ActionDetail::default());
    build.finished(serde_json::json!({ "hits": 41, "misses": 1 }));

    let mut app = App::new(store.path(), 10);
    app.tick(10);

    let session = app.selected_session().unwrap();
    assert_eq!(session.state, SessionState::Finished);
    let totals = session.totals.as_ref().expect("totals should be recorded");
    assert_eq!(crate::events::stat(totals, "hits"), 41);
}

#[test]
fn a_running_build_sorts_above_a_finished_one() {
    let store = tempfile::tempdir().unwrap();
    let done = writer(store.path());
    done.action(ActionOutcome::Hit, None, 1, ActionDetail::default());
    done.finished(serde_json::json!({ "hits": 1 }));
    drop(done);
    let running = writer(store.path());
    running.action(ActionOutcome::Miss, None, 1, ActionDetail::default());

    let mut app = App::new(store.path(), 10);
    app.tick(10);

    let states: Vec<SessionState> = app.sessions().map(|session| session.state).collect();
    assert_eq!(
        states,
        vec![SessionState::Live, SessionState::Finished],
        "the build somebody is watching belongs at the top"
    );
}

#[test]
fn a_build_that_starts_later_is_picked_up_without_a_restart() {
    let store = tempfile::tempdir().unwrap();
    let mut app = App::new(store.path(), 10);
    app.tick(10);
    assert!(app.is_empty());

    let build = writer(store.path());
    build.action(
        ActionOutcome::Hit,
        Some("serde".into()),
        1,
        ActionDetail::default(),
    );
    app.tick(10);

    assert_eq!(app.sessions().count(), 1);
    assert_eq!(app.selected_session().unwrap().count("hit"), 1);
}

#[test]
fn pausing_stops_reading_and_resuming_catches_up() {
    let store = tempfile::tempdir().unwrap();
    let build = writer(store.path());
    build.action(ActionOutcome::Hit, None, 1, ActionDetail::default());
    let mut app = App::new(store.path(), 10);
    app.tick(10);
    assert_eq!(app.selected_session().unwrap().count("hit"), 1);

    app.toggle_pause();
    build.action(ActionOutcome::Hit, None, 1, ActionDetail::default());
    app.tick(10);
    assert_eq!(
        app.selected_session().unwrap().count("hit"),
        1,
        "a paused dashboard should not move"
    );

    app.toggle_pause();
    app.tick(10);
    assert_eq!(
        app.selected_session().unwrap().count("hit"),
        2,
        "resuming should pick up what was appended while paused"
    );
}

#[test]
fn a_capped_stream_says_so() {
    let store = tempfile::tempdir().unwrap();
    let build = crate::events::EventWriter::with_cap_for_test(store.path(), 1);
    build.started(Path::new("/checkouts/fixture"), &["build".into()], None);
    build.action(ActionOutcome::Hit, None, 1, ActionDetail::default());

    let mut app = App::new(store.path(), 10);
    app.tick(10);

    assert!(app.selected_session().unwrap().truncated);
}

#[test]
fn tabs_cycle_and_can_be_jumped_to() {
    let store = tempfile::tempdir().unwrap();
    let mut app = App::new(store.path(), 10);
    assert_eq!(app.tab, Tab::Live);

    app.next_tab();
    assert_eq!(app.tab, Tab::Sessions);
    app.next_tab();
    assert_eq!(app.tab, Tab::Store);
    app.next_tab();
    assert_eq!(app.tab, Tab::Insights);
    app.next_tab();
    assert_eq!(app.tab, Tab::Live);

    app.select_tab(Tab::Store);
    assert_eq!(app.tab, Tab::Store);
}

#[test]
fn selection_stays_inside_the_list() {
    let store = tempfile::tempdir().unwrap();
    let build = writer(store.path());
    build.action(ActionOutcome::Hit, None, 1, ActionDetail::default());
    let mut app = App::new(store.path(), 10);
    app.tick(10);

    // One session: moving either way keeps the selection on it rather than
    // running off the end.
    app.select_next();
    assert_eq!(app.selected, 0);
    app.select_previous();
    assert_eq!(app.selected, 0);
    assert!(app.selected_session().is_some());
}

#[test]
fn selection_follows_the_build_when_sessions_reorder() {
    let store = tempfile::tempdir().unwrap();
    let first = writer(store.path());
    let second = writer(store.path());
    let mut app = App::new(store.path(), 10);
    app.tick(10);
    let selected_id = app.selected_session().unwrap().id.clone();
    // Finish the selected build, forcing it below the other running build.
    let selected_writer = if selected_id == first.id() {
        &first
    } else {
        &second
    };
    selected_writer.finished(serde_json::json!({}));
    app.tick(10);
    assert_eq!(app.selected, 1);
    assert_eq!(app.selected_session().unwrap().id, selected_id);
}

#[test]
fn new_actions_do_not_shift_the_history_being_read() {
    let store = tempfile::tempdir().unwrap();
    let build = writer(store.path());
    for i in 0..30 {
        build.action(
            ActionOutcome::Hit,
            Some(format!("crate_{i}")),
            1,
            ActionDetail::default(),
        );
    }
    let mut app = App::new(store.path(), 10);
    app.tick(10);
    app.older_actions(10);
    let end = app.selected_session().unwrap().rows.len() - app.action_scroll;
    build.action(
        ActionOutcome::Miss,
        Some("new_crate".into()),
        1,
        ActionDetail::default(),
    );
    app.tick(10);
    assert_eq!(
        app.selected_session().unwrap().rows.len() - app.action_scroll,
        end
    );
    app.newer_actions(10);
    assert_eq!(app.action_scroll, 1);
    app.follow_actions();
    assert_eq!(app.action_scroll, 0);
}

#[test]
fn sessions_scroll_is_bounded_and_store_does_not_scroll() {
    let store = tempfile::tempdir().unwrap();
    let _build = writer(store.path());
    let mut app = App::new(store.path(), 10);
    app.tick(10);
    for tab in [Tab::Sessions, Tab::Store] {
        app.select_tab(tab);
        for _ in 0..10 {
            app.select_next();
        }
        assert_eq!(app.scroll, 0);
    }
}

#[test]
fn resuming_does_not_count_paused_evictions_as_recent() {
    let store = tempfile::tempdir().unwrap();
    let mut app = App::new(store.path(), 50);
    let now = Instant::now();
    app.health.observe_evictions(now, 1, 0);
    app.health.observe_evictions(now, 1, 100);
    assert_eq!(app.health.evicted, 100);
    app.toggle_pause();
    app.toggle_pause();
    app.health.observe_evictions(now, 1, 10_000);
    assert_eq!(app.health.evicted, 0);
}

#[test]
fn pending_sharing_does_not_block_navigation_and_applies_when_ready() {
    let store = tempfile::tempdir().unwrap();
    let mut app = App::new(store.path(), 50);
    let (sender, receiver) = std::sync::mpsc::channel();
    app.sharing_worker = Some(receiver);
    app.select_tab(Tab::Store);
    // The worker has not sent anything: this must return without waiting.
    app.tick(50);
    assert!(app.sharing_loading());
    app.select_tab(Tab::Live);
    app.tick(50);
    assert_eq!(app.tab, Tab::Live);
    assert!(app.sharing_loading());
    sender
        .send(Some(crate::stats::SharingEstimate {
            live_workspaces: 7,
            ..Default::default()
        }))
        .unwrap();
    app.tick(50);
    assert!(!app.sharing_loading());
    assert_eq!(app.sharing.as_ref().unwrap().live_workspaces, 7);
    app.select_tab(Tab::Store);
    app.tick(50);
    assert!(
        !app.sharing_loading(),
        "do not immediately repeat a completed scan"
    );
}

#[test]
fn failed_sharing_worker_does_not_restart_every_tick() {
    let store = tempfile::tempdir().unwrap();
    let mut app = App::new(store.path(), 50);
    let (sender, receiver) = std::sync::mpsc::channel();
    app.sharing_worker = Some(receiver);
    app.select_tab(Tab::Store);
    drop(sender);
    app.tick(50);
    assert!(!app.sharing_loading());
    assert!(app.last_sharing_refresh.is_some());
    app.tick(50);
    assert!(!app.sharing_loading());
}
