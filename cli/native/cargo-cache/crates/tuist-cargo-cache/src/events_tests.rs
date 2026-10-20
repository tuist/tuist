use super::*;

fn write_line(path: &Path, line: &str) {
    use std::io::Write as _;
    let mut file = File::options()
        .create(true)
        .append(true)
        .open(path)
        .unwrap();
    file.write_all(line.as_bytes()).unwrap();
}

#[test]
fn a_stream_records_a_build_from_start_to_totals() {
    let store = tempfile::tempdir().unwrap();
    let writer =
        EventWriter::with_limit(store.path(), Some(crate::config::DEFAULT_EVENTS_MAX_SIZE));
    writer.started(Path::new("/workspace"), &["build".into()], None);
    writer.action(
        ActionOutcome::Hit,
        Some("serde".into()),
        11,
        ActionDetail {
            avoided_compiler_ns: 1_000,
            output_files: 2,
            output_bytes: 64,
            reflinked_output_bytes: 64,
            hardlinked_output_bytes: 0,
            copied_output_bytes: 0,
        },
    );
    writer.action(
        ActionOutcome::Bypass {
            reason: "incremental".into(),
        },
        Some("tuist_cargo_cache".into()),
        22,
        ActionDetail::default(),
    );
    writer.finished(serde_json::json!({ "hits": 1, "misses": 0 }));

    let paths = session_paths(store.path(), writer.id());
    let contents = std::fs::read_to_string(&paths.events).unwrap();
    let events = parse_events(&contents);
    assert_eq!(events.len(), 4);
    assert!(matches!(
        &events[0],
        SessionEvent::SessionStarted { command, .. } if command == &["build".to_string()]
    ));
    assert!(matches!(
        &events[1],
        SessionEvent::Action {
            outcome: ActionOutcome::Hit,
            crate_name: Some(name),
            duration_ns: 11,
            detail,
            ..
        } if name == "serde" && detail.output_bytes == 64
    ));
    assert_eq!(events[2].outcome_label(), Some("incremental"));
    assert!(matches!(
        &events[3],
        SessionEvent::SessionFinished { stats, .. } if stat(stats, "hits") == 1
    ));
}

#[test]
fn a_command_that_records_nothing_leaves_no_stream() {
    let store = tempfile::tempdir().unwrap();
    let writer =
        EventWriter::with_limit(store.path(), Some(crate::config::DEFAULT_EVENTS_MAX_SIZE));
    let paths = session_paths(store.path(), writer.id());
    drop(writer);

    assert!(!paths.events.exists());
    assert!(session_ids(store.path()).is_empty());
}

#[test]
fn a_tail_reads_only_what_was_appended() {
    let store = tempfile::tempdir().unwrap();
    let writer =
        EventWriter::with_limit(store.path(), Some(crate::config::DEFAULT_EVENTS_MAX_SIZE));
    writer.started(Path::new("/workspace"), &["build".into()], None);
    let id = writer.id().to_string();

    let mut tail = SessionTail::new(store.path(), id);
    assert_eq!(tail.read().len(), 1);
    // Nothing new: a second read of an unchanged stream yields nothing rather
    // than the whole file again.
    assert!(tail.read().is_empty());

    writer.action(ActionOutcome::Miss, None, 5, ActionDetail::default());
    let appended = tail.read();
    assert_eq!(appended.len(), 1);
    assert_eq!(appended[0].outcome_label(), Some("miss"));
}

#[test]
fn a_tail_holds_back_a_line_that_has_no_newline_yet() {
    let store = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(store.path().join(SESSIONS_DIR)).unwrap();
    let paths = session_paths(store.path(), "1-1-aaaa");
    let complete = r#"{"type":"action","v":1,"ts_ms":1,"outcome":{"kind":"miss"},"duration_ns":1}"#;

    write_line(&paths.events, &format!("{complete}\n"));
    // A row the writer is still in the middle of appending.
    write_line(&paths.events, r#"{"type":"action","v":1,"ts_"#);

    let mut tail = SessionTail::new(store.path(), "1-1-aaaa".into());
    assert_eq!(tail.read().len(), 1);

    // The rest of the partial line arrives.
    write_line(
        &paths.events,
        "ms\":2,\"outcome\":{\"kind\":\"hit\"},\"duration_ns\":2}\n",
    );
    let appended = tail.read();
    assert_eq!(appended.len(), 1);
    assert_eq!(appended[0].outcome_label(), Some("hit"));
}

#[test]
fn a_reader_skips_a_line_it_cannot_parse() {
    let store = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(store.path().join(SESSIONS_DIR)).unwrap();
    let paths = session_paths(store.path(), "1-1-aaaa");
    write_line(&paths.events, "not json at all\n");
    write_line(
        &paths.events,
        "{\"type\":\"action\",\"v\":1,\"ts_ms\":1,\"outcome\":{\"kind\":\"hit\"},\"duration_ns\":1}\n",
    );
    // A record type this build does not know about.
    write_line(&paths.events, "{\"type\":\"from_the_future\",\"v\":9}\n");

    let mut tail = SessionTail::new(store.path(), "1-1-aaaa".into());
    let events = tail.read();
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].outcome_label(), Some("hit"));
}

#[test]
fn an_event_keeps_its_meaning_when_a_newer_field_is_added() {
    let line = r#"{"type":"action","v":1,"ts_ms":1,"outcome":{"kind":"hit"},"duration_ns":7,"crate_name":"serde","invented_later":{"a":1}}"#;
    let events = parse_events(line);
    assert_eq!(events.len(), 1);
    assert!(matches!(
        &events[0],
        SessionEvent::Action {
            crate_name: Some(name),
            duration_ns: 7,
            ..
        } if name == "serde"
    ));
}

#[test]
fn a_live_stream_is_told_apart_from_a_finished_and_an_abandoned_one() {
    let store = tempfile::tempdir().unwrap();

    let writer =
        EventWriter::with_limit(store.path(), Some(crate::config::DEFAULT_EVENTS_MAX_SIZE));
    writer.started(Path::new("/workspace"), &["build".into()], None);
    let mut live = SessionTail::new(store.path(), writer.id().to_string());
    live.read();
    assert_eq!(live.state(), SessionState::Live);

    // The build ends with its totals.
    writer.finished(serde_json::json!({ "hits": 0 }));
    let mut finished = SessionTail::new(store.path(), writer.id().to_string());
    finished.read();
    assert_eq!(finished.state(), SessionState::Finished);

    // The build dies: the lock goes with the process, and no totals were ever
    // written.
    let abandoned =
        EventWriter::with_limit(store.path(), Some(crate::config::DEFAULT_EVENTS_MAX_SIZE));
    abandoned.started(Path::new("/workspace"), &["build".into()], None);
    let id = abandoned.id().to_string();
    drop(abandoned);
    let mut tail = SessionTail::new(store.path(), id);
    tail.read();
    assert_eq!(tail.state(), SessionState::Abandoned);
}

#[test]
fn a_stream_stops_growing_at_its_cap_but_still_reports_its_totals() {
    let store = tempfile::tempdir().unwrap();
    // A cap of one byte: the first row reaches it, so every later row is
    // dropped, which is the same path a 16 MiB build takes.
    let writer = EventWriter::with_cap(store.path(), 1);
    writer.started(Path::new("/workspace"), &["build".into()], None);
    for _ in 0..5 {
        writer.action(
            ActionOutcome::Miss,
            Some("serde".into()),
            1,
            ActionDetail::default(),
        );
    }
    writer.finished(serde_json::json!({ "hits": 3 }));

    let paths = session_paths(store.path(), writer.id());
    let events = parse_events(&std::fs::read_to_string(&paths.events).unwrap());
    // One truncation notice however many rows were dropped, and the totals.
    assert_eq!(
        events
            .iter()
            .filter(|event| matches!(event, SessionEvent::Truncated { .. }))
            .count(),
        1
    );
    assert!(
        !events
            .iter()
            .any(|event| matches!(event, SessionEvent::Action { .. }))
    );
    assert!(matches!(
        events.last(),
        Some(SessionEvent::SessionFinished { stats, .. }) if stat(stats, "hits") == 3
    ));
}

#[test]
fn tails_open_newest_first_and_no_more_than_asked() {
    let store = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(store.path().join(SESSIONS_DIR)).unwrap();
    for id in ["100-1-aaaa", "200-1-bbbb", "300-1-cccc"] {
        write_line(&session_paths(store.path(), id).events, "\n");
    }

    let tails = open_tails(store.path(), 2);
    let ids: Vec<&str> = tails.iter().map(SessionTail::id).collect();
    assert_eq!(ids, ["300-1-cccc", "200-1-bbbb"]);
}

/// A cap smaller than the first row still leaves a readable stream.
///
/// The event that names the build is what makes the file worth anything:
/// without it `tuist_cargo_cache explain` skips the stream entirely and explains an older
/// build instead, which is worse than saying the history was truncated.
#[test]
fn a_stream_records_what_it_is_before_any_cap_applies() {
    let store = tempfile::tempdir().unwrap();
    let writer = EventWriter::with_limit(store.path(), Some(0));
    writer.started(Path::new("/workspace"), &["build".into()], None);
    writer.action(
        ActionOutcome::Miss,
        Some("serde".into()),
        1,
        ActionDetail::default(),
    );
    writer.finished(serde_json::json!({ "hits": 0 }));

    let paths = session_paths(store.path(), writer.id());
    let events = parse_events(&std::fs::read_to_string(&paths.events).unwrap());
    assert!(
        events
            .iter()
            .any(|event| matches!(event, SessionEvent::SessionStarted { .. })),
        "{events:?}"
    );
    assert!(
        events
            .iter()
            .any(|event| matches!(event, SessionEvent::Truncated { .. })),
        "{events:?}"
    );
    assert!(
        events
            .iter()
            .any(|event| matches!(event, SessionEvent::SessionFinished { .. })),
        "{events:?}"
    );
}

/// No limit records the whole build, for anyone diagnosing a miss on a
/// workspace large enough to reach the default cap partway through.
#[test]
fn an_unlimited_stream_records_past_the_default_cap() {
    let store = tempfile::tempdir().unwrap();
    let writer = EventWriter::with_limit(store.path(), None);
    writer.started(Path::new("/workspace"), &["build".into()], None);
    for _ in 0..50 {
        writer.action(
            ActionOutcome::Hit,
            Some("serde".into()),
            1,
            ActionDetail::default(),
        );
    }

    let paths = session_paths(store.path(), writer.id());
    let events = parse_events(&std::fs::read_to_string(&paths.events).unwrap());
    assert!(
        !events
            .iter()
            .any(|event| matches!(event, SessionEvent::Truncated { .. })),
        "an unlimited stream should not truncate"
    );
    assert_eq!(
        events
            .iter()
            .filter(|event| matches!(event, SessionEvent::Action { .. }))
            .count(),
        50
    );
}
