use super::*;
use crate::events::{ActionDetail, EventWriter};
use ratatui::backend::TestBackend;
use std::path::Path;

fn render(app: &App, width: u16, height: u16) -> String {
    let mut terminal = ratatui::Terminal::new(TestBackend::new(width, height)).unwrap();
    terminal.draw(|frame| draw(frame, app)).unwrap();
    let buffer = terminal.backend().buffer();
    (0..height)
        .map(|y| {
            (0..width)
                .map(|x| buffer[(x, y)].symbol())
                .collect::<String>()
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn build(store: &Path, name: &str, actions: usize) -> EventWriter {
    let writer = EventWriter::with_limit(store, Some(crate::config::DEFAULT_EVENTS_MAX_SIZE));
    writer.started(Path::new("/checkouts/fixture"), &[name.into()], None);
    for i in 0..actions {
        writer.action(
            ActionOutcome::Miss,
            Some(format!("crate_{i:03}")),
            1_500_000,
            ActionDetail::default(),
        );
    }
    writer
}

#[test]
fn selected_build_stays_visible_beyond_the_first_page() {
    let store = tempfile::tempdir().unwrap();
    let builds: Vec<_> = (0..12)
        .map(|i| build(store.path(), &format!("build-{i:02}"), 1))
        .collect();
    let mut app = App::new(store.path(), 50);
    app.tick(50);
    for _ in 0..9 {
        app.select_next();
    }
    for width in [48, 80, 120, 160] {
        let screen = render(&app, width, 30);
        let selected = app.selected_session().unwrap().title();
        assert!(
            screen
                .lines()
                .any(|line| line.contains(&format!("▸ {selected}"))),
            "{screen}"
        );
        assert!(screen.contains("Builds · 10/12"));
        assert!(screen.contains("crate_000"));
    }
    drop(builds);
}

#[test]
fn activity_pages_cover_history_and_return_to_latest() {
    let store = tempfile::tempdir().unwrap();
    let _build = build(store.path(), "build", 100);
    let mut app = App::new(store.path(), 50);
    app.tick(50);
    let area = Rect::new(0, 0, 80, 30);
    let page = action_page_size(area, &app);
    let screen = render(&app, area.width, area.height);
    assert!(screen.contains("crate_099"));
    assert!(!screen.contains("crate_000"));
    app.older_actions(page);
    let screen = render(&app, area.width, area.height);
    assert!(screen.contains("Activity · history"));
    assert!(!screen.contains("crate_099"));
    assert!(screen.contains(&format!("crate_{:03}", 99 - page)));
    for _ in 0..100 {
        app.older_actions(page);
    }
    assert!(render(&app, 80, 30).contains("crate_000"));
    app.follow_actions();
    assert!(render(&app, 80, 30).contains("crate_099"));
}

#[test]
fn every_tab_handles_small_and_empty_terminals() {
    let store = tempfile::tempdir().unwrap();
    let mut app = App::new(store.path(), 50);
    for tab in Tab::ALL {
        app.select_tab(tab);
        for (width, height) in [(0, 0), (1, 1), (40, 10), (48, 16), (80, 24), (160, 48)] {
            render(&app, width, height);
        }
    }
    app.select_tab(Tab::Live);
    assert!(render(&app, 80, 24).contains("Waiting for builds"));
    assert!(render(&app, 40, 10).contains("Enlarge the terminal"));
}

#[test]
fn savings_remain_visible_with_a_long_store_path() {
    let store = tempfile::tempdir().unwrap();
    let mut app = App::new(&store.path().join("a".repeat(150)), 50);
    app.savings.avoided_compiler_ns = 3_059_100_000_000;
    app.savings.since_secs = 1_700_000_000;
    let screen = render(&app, 80, 24);
    assert!(screen.contains("50m 59s compiling saved since 2023-11-14"));
    app.toggle_pause();
    assert!(render(&app, 80, 24).contains("PAUSED"));
}

#[test]
fn populated_tabs_render_at_supported_sizes() {
    let store = tempfile::tempdir().unwrap();
    let writer = build(store.path(), "build --all-features", 80);
    writer.finished(serde_json::json!({"hits": 1318, "misses": 68}));
    let mut app = App::new(store.path(), 50);
    app.tick(50);
    for tab in Tab::ALL {
        app.select_tab(tab);
        for (width, height) in [(48, 16), (80, 24), (110, 33), (120, 36), (160, 48)] {
            let screen = render(&app, width, height);
            assert!(screen.contains("q quit"), "{screen}");
        }
    }
}

#[test]
fn wide_dashboard_shows_charts_and_narrow_layout_keeps_activity() {
    let store = tempfile::tempdir().unwrap();
    let _build = build(store.path(), "build", 100);
    let mut app = App::new(store.path(), 50);
    app.tick(50);
    let wide = render(&app, 120, 36);
    assert!(wide.contains("Lookup traffic / 5m"), "{wide}");
    assert!(wide.contains("Selected build / cache"));
    assert!(wide.contains("Biggest cache wins"));
    assert!(wide.contains("crate_099"));
    let narrow = render(&app, 80, 24);
    assert!(!narrow.contains("Lookup traffic / 5m"));
    assert!(narrow.contains("crate_099"));
    app.select_tab(Tab::Insights);
    let wide = render(&app, 120, 36);
    assert!(wide.contains("Recent actions / duration"));
    assert!(wide.contains("Bypass reasons / most frequent"));
    scroll_page(&mut app, Rect::new(0, 0, 120, 36), true);
    assert!(render(&app, 120, 36).contains("Rankings cover 100 retained actions"));
}

#[test]
fn insights_scroll_to_rankings_and_clamp_after_resize() {
    let store = tempfile::tempdir().unwrap();
    let _build = build(store.path(), "build", 100);
    let mut app = App::new(store.path(), 50);
    app.tick(50);
    app.select_tab(Tab::Insights);
    let small = Rect::new(0, 0, 80, 24);
    assert!(render(&app, 80, 24).contains("Cache outcomes"));
    for _ in 0..10 {
        scroll_page(&mut app, small, true);
    }
    assert!(render(&app, 80, 24).contains("Rankings cover 100 retained actions"));
    let wide = render(&app, 120, 40);
    assert!(wide.contains("Cache outcomes"));
    assert!(wide.contains("Slowest recorded actions"));
    assert!(wide.contains("Biggest cache wins"));
    scroll_page(&mut app, Rect::new(0, 0, 120, 40), false);
    assert_eq!(app.insight_scroll, 0);
}

#[test]
fn store_scroll_reaches_the_report_notes_and_plain_mode_omits_quips() {
    let store = tempfile::tempdir().unwrap();
    let mut app = App::new(store.path(), 50);
    app.savings.since_secs = 1_700_000_000;
    app.savings.auto_pruned_since_secs = 1_700_000_000;
    app.savings.auto_pruned_bytes = 1_000_000;
    app.select_tab(Tab::Store);
    let area = Rect::new(0, 0, 48, 22);
    for _ in 0..10 {
        scroll_page(&mut app, area, true);
    }
    let narrow = render(&app, 48, 22);
    // The last note wraps after "current" at this width; its tail shows the
    // scroll reached the bottom of the report.
    assert!(narrow.contains("Copying avoided is cumulative"), "{narrow}");
    assert!(narrow.contains("disk savings."), "{narrow}");
    app.store_scroll = 0;
    // macOS and Windows temporary roots can exceed one dashboard column.
    // Give this fixture enough room to exercise the panel layout, rather than
    // the intentional fallback used when the store path cannot fit.
    let wide_width = (Line::from(store.path().display().to_string()).width() * 2 + 10)
        .max(120)
        .try_into()
        .unwrap();
    let wide = render(&app, wide_width, 40);
    assert!(wide.contains("You did not lift a finger"));
    assert!(wide.contains("Store / inventory"));
    assert!(wide.contains("Workspace sharing / estimated"));
    app.cheeky = false;
    let screen = render(&app, wide_width, 40);
    assert!(!screen.contains("You did not lift a finger"));
    assert!(screen.contains("automatically pruned"));
}

#[test]
fn capacity_handles_over_budget_and_zero_budget() {
    let store = tempfile::tempdir().unwrap();
    let mut app = App::new(store.path(), 50);
    app.store_budget = Some(1000);
    app.store_stats = Some(crate::store::StoreStats {
        object_bytes: 1500,
        ..Default::default()
    });
    assert!(render(&app, 80, 24).contains("150%"));
    assert!(render(&app, 120, 36).contains("150%"));
    app.store_budget = Some(0);
    assert!(render(&app, 80, 24).contains("zero budget"));
    assert!(render(&app, 120, 36).contains("zero budget"));
    app.store_stats = None;
    assert!(render(&app, 80, 24).contains("Store usage unavailable"));
}

#[test]
fn thrashing_is_prominent_on_every_tab_and_both_flash_phases() {
    let store = tempfile::tempdir().unwrap();
    let mut app = App::new(store.path(), 50);
    app.store_budget = Some(1000);
    let now = std::time::Instant::now();
    app.health.observe_evictions(now, 1, 0);
    for i in 1..=3 {
        app.health
            .observe_evictions(now + Duration::from_secs(i * 2), 1, i * 100);
    }
    app.health.lookups(now + Duration::from_secs(7), 0, 30);
    for tab in Tab::ALL {
        app.select_tab(tab);
        assert!(render(&app, 80, 24).contains("POSSIBLE CACHE THRASHING"));
        assert!(render(&app, 120, 36).contains("POSSIBLE CACHE THRASHING"));
    }
    let mut terminal = ratatui::Terminal::new(TestBackend::new(80, 24)).unwrap();
    terminal.draw(|frame| draw(frame, &app)).unwrap();
    let first_color = terminal.backend().buffer()[(1, 3)].bg;
    app.health.advance(now + Duration::from_secs(8));
    terminal.draw(|frame| draw(frame, &app)).unwrap();
    assert_ne!(terminal.backend().buffer()[(1, 3)].bg, first_color);
    assert!(render(&app, 48, 22).contains("POSSIBLE CACHE THRASHING"));
}

fn mouse(kind: MouseEventKind, x: u16, y: u16) -> MouseEvent {
    MouseEvent {
        kind,
        column: x,
        row: y,
        modifiers: ratatui::crossterm::event::KeyModifiers::NONE,
    }
}

#[test]
fn mouse_tabs_use_rendered_bounds_and_ignore_other_buttons() {
    let store = tempfile::tempdir().unwrap();
    let mut app = App::new(store.path(), 50);
    let area = Rect::new(3, 2, 80, 24);
    for (tab, rect) in tab_areas(main_area(area)[1]) {
        handle_mouse(
            &mut app,
            mouse(MouseEventKind::Down(MouseButton::Left), rect.x, rect.y),
            area,
        );
        assert_eq!(app.tab, tab);
    }
    handle_mouse(
        &mut app,
        mouse(MouseEventKind::Down(MouseButton::Right), 3, 7),
        area,
    );
    assert_eq!(app.tab, Tab::Insights);
    handle_mouse(
        &mut app,
        mouse(MouseEventKind::Down(MouseButton::Left), 0, 0),
        Rect::new(0, 0, 40, 20),
    );
    assert_eq!(app.tab, Tab::Insights);
}

#[test]
fn mouse_selects_visible_builds_and_scrolls_only_hovered_panel() {
    let store = tempfile::tempdir().unwrap();
    let _builds: Vec<_> = (0..12)
        .map(|i| build(store.path(), &format!("build-{i:02}"), 40))
        .collect();
    let mut app = App::new(store.path(), 50);
    app.tick(50);
    for width in [48, 80, 120, 160] {
        let area = Rect::new(0, 0, width, 30);
        app.select_tab(Tab::Live);
        app.selected = 9;
        let panels = live_areas(live_columns(main_area(area)[2]).0, &app);
        let first = build_offset(&app, panels[0]);
        let screen = render(&app, width, 30);
        assert!(
            screen
                .lines()
                .nth((panels[0].y + 2) as usize)
                .unwrap()
                .contains(&app.sessions().nth(first).unwrap().title())
        );
        handle_mouse(
            &mut app,
            mouse(MouseEventKind::Down(MouseButton::Left), 2, panels[0].y + 2),
            area,
        );
        assert_eq!(app.selected, first);
        handle_mouse(
            &mut app,
            mouse(MouseEventKind::ScrollUp, 2, panels[1].y + 2),
            area,
        );
        assert_eq!(app.action_scroll, 3);
        assert_eq!(app.selected, first);
        handle_mouse(
            &mut app,
            mouse(MouseEventKind::ScrollDown, 2, panels[0].y + 2),
            area,
        );
        assert_eq!(app.selected, first + 1);
        assert_eq!(app.action_scroll, 0);
        app.select_tab(Tab::Sessions);
        app.scroll = 4;
        handle_mouse(
            &mut app,
            mouse(
                MouseEventKind::Down(MouseButton::Left),
                2,
                main_area(area)[2].y + 3,
            ),
            area,
        );
        assert_eq!(app.tab, Tab::Live);
        assert_eq!(app.selected, 5);
    }
}

#[test]
fn wheel_scrolls_store_and_insights() {
    let store = tempfile::tempdir().unwrap();
    let _build = build(store.path(), "build", 40);
    let mut app = App::new(store.path(), 50);
    app.tick(50);
    let area = Rect::new(0, 0, 48, 22);
    for tab in [Tab::Store, Tab::Insights] {
        app.select_tab(tab);
        handle_mouse(&mut app, mouse(MouseEventKind::ScrollDown, 2, 10), area);
        assert!(
            if tab == Tab::Store {
                app.store_scroll
            } else {
                app.insight_scroll
            } > 0
        );
        handle_mouse(&mut app, mouse(MouseEventKind::ScrollUp, 2, 10), area);
        assert_eq!(
            if tab == Tab::Store {
                app.store_scroll
            } else {
                app.insight_scroll
            },
            0
        );
    }
}
