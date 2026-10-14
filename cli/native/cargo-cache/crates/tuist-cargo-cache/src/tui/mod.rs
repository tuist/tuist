//! `tuist_cargo_cache tui`: watch builds as they happen.
//!
//! tuist_cargo_cache has no daemon, so there is nothing to ask what a build is doing. Instead
//! every build appends its decisions to a stream under the store (see
//! [`crate::events`]), and this reads them: any number of builds, in any number
//! of terminals, including ones that started before this did.
//!
//! Polling rather than filesystem notifications. A stream is an append-only
//! file read by offset, so a tick is a handful of `stat`s and a short read; that
//! is cheaper than the platform watcher it would take to avoid it, and it works
//! the same on every platform tuist_cargo_cache supports.

mod app;
mod dashboard;
mod health;
mod insights;
mod theme;
mod ui;

use crate::config::Config;
use app::{App, Tab};
use eyre::{Context, Result};
use ratatui::crossterm::{
    event::{
        self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEvent, KeyEventKind,
        KeyModifiers,
    },
    execute,
    terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode},
};
use ratatui::prelude::*;
use std::io::{self, IsTerminal};
use std::path::Path;
use std::process::ExitCode;
use std::time::{Duration, Instant};

/// How often the streams are re-read.
///
/// Fast enough that a build looks live, slow enough that watching one costs
/// nothing measurable.
const TICK: Duration = Duration::from_millis(250);

/// How often the store's own totals are re-read.
///
/// These change when a sweep runs, not when a crate compiles, so they do not
/// need a tick of their own.
const STORE_REFRESH: Duration = Duration::from_secs(2);

/// The most streams to follow at once.
///
/// The store keeps more than this; following every one would spend the tick on
/// history nobody is looking at.
const MAX_FOLLOWED: usize = 50;

/// Watch this machine's builds.
pub fn run(config: &Config, once: bool, cheeky: bool) -> Result<ExitCode> {
    let store = config.store_dir();
    if once {
        snapshot(&store);
        return Ok(ExitCode::SUCCESS);
    }
    if !io::stdout().is_terminal() {
        eyre::bail!(
            "tuist_cargo_cache tui needs a terminal; use `tuist_cargo_cache tui --once` for a snapshot that can be redirected"
        );
    }
    if !config.events {
        // Worth saying plainly: the dashboard would otherwise sit empty through
        // a perfectly good build and look broken. The fix depends on where the
        // setting came from: the environment outranks the file, and the file
        // may turn recording off too, underneath it.
        let from_environment = crate::config::resolve_settings().is_ok_and(|resolved| {
            resolved
                .origin_key("events")
                .is_some_and(|origin| origin.kind == usage_config::SourceKind::ENV)
        });
        let off_in_file = crate::config::resolve_file_settings().is_ok_and(|resolved| {
            resolved.get_key("events") == Some(&usage_config::Value::Bool(false))
        });
        let fix = match (from_environment, off_in_file) {
            (true, true) => {
                "Unset TUIST_CARGO_CACHE_EVENTS and run `tuist_cargo_cache settings set events true` to record them."
            }
            (true, false) => "Unset TUIST_CARGO_CACHE_EVENTS to record them.",
            (false, _) => "`tuist_cargo_cache settings set events true` records them.",
        };
        eprintln!(
            "tuist_cargo_cache[warning]: event recording is off, so builds will not appear here. {fix}"
        );
    }
    watch(config, cheeky)
}

fn watch(config: &Config, cheeky: bool) -> Result<ExitCode> {
    let mut terminal = enter()?;
    let result = event_loop(&mut terminal, config, cheeky);
    // Restored before the error is reported, so a failure cannot leave the
    // terminal in raw mode with no echo.
    leave(&mut terminal)?;
    result
}

type Terminal = ratatui::Terminal<CrosstermBackend<io::Stdout>>;

fn enter() -> Result<Terminal> {
    enable_raw_mode().wrap_err("failed to put the terminal in raw mode")?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)
        .wrap_err("failed to switch screens")?;
    // A panic in drawing would otherwise leave the alternate screen up and raw
    // mode on, with the backtrace invisible.
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let _ = disable_raw_mode();
        let _ = execute!(io::stdout(), DisableMouseCapture, LeaveAlternateScreen);
        previous(info);
    }));
    ratatui::Terminal::new(CrosstermBackend::new(stdout)).wrap_err("failed to start the terminal")
}

fn leave(terminal: &mut Terminal) -> Result<()> {
    disable_raw_mode().wrap_err("failed to restore the terminal")?;
    execute!(
        terminal.backend_mut(),
        DisableMouseCapture,
        LeaveAlternateScreen
    )
    .wrap_err("failed to restore the screen")?;
    terminal
        .show_cursor()
        .wrap_err("failed to show the cursor")?;
    Ok(())
}

fn event_loop(terminal: &mut Terminal, config: &Config, cheeky: bool) -> Result<ExitCode> {
    let mut app = App::new(&config.store_dir(), MAX_FOLLOWED);
    app.cheeky = cheeky;
    app.store_budget = Some(config.gc.max_bytes);
    app.gc_auto = config.gc.auto;
    let mut last_store_refresh = Instant::now();
    loop {
        app.tick(MAX_FOLLOWED);
        if last_store_refresh.elapsed() >= STORE_REFRESH {
            app.refresh_store();
            last_store_refresh = Instant::now();
        }
        terminal.draw(|frame| ui::draw(frame, &app))?;

        // The keyboard poll is also the clock: it returns as soon as a key
        // arrives, so the dashboard stays responsive between ticks.
        if !event::poll(TICK)? {
            continue;
        }
        let area = terminal.size()?.into();
        match event::read()? {
            Event::Key(key) if handle_key(&mut app, key, area) => {
                return Ok(ExitCode::SUCCESS);
            }
            Event::Mouse(mouse) => ui::handle_mouse(&mut app, mouse, area),
            _ => {}
        }
    }
}

/// Return true when the user asks to quit. Keep navigation testable without a PTY.
fn handle_key(app: &mut App, key: KeyEvent, area: Rect) -> bool {
    if key.kind == KeyEventKind::Release {
        return false;
    }
    match key.code {
        KeyCode::Char('q') | KeyCode::Esc => return true,
        KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => return true,
        KeyCode::Tab | KeyCode::Right => app.next_tab(),
        KeyCode::BackTab | KeyCode::Left => app.previous_tab(),
        KeyCode::Char('1') => app.select_tab(Tab::Live),
        KeyCode::Char('2') => app.select_tab(Tab::Sessions),
        KeyCode::Char('3') => app.select_tab(Tab::Store),
        KeyCode::Char('4') => app.select_tab(Tab::Insights),
        KeyCode::Char('j') | KeyCode::Down => ui::move_vertical(app, area, true),
        KeyCode::Char('k') | KeyCode::Up => ui::move_vertical(app, area, false),
        KeyCode::PageUp => ui::scroll_page(app, area, false),
        KeyCode::PageDown => ui::scroll_page(app, area, true),
        KeyCode::End => app.follow_actions(),
        KeyCode::Char('p') if key.kind == KeyEventKind::Press => app.toggle_pause(),
        _ => {}
    }
    false
}

/// Print what the dashboard would show, once, as plain text.
///
/// For a pipe, a CI log, or a quick look without taking over the terminal.
fn snapshot(store: &Path) {
    let mut app = App::new(store, MAX_FOLLOWED);
    app.tick(MAX_FOLLOWED);
    println!("store: {}", store.display());
    if let Some(stats) = &app.store_stats {
        println!(
            "objects: {} ({}); action results: {} ({})",
            stats.objects,
            bytesize::ByteSize::b(stats.object_bytes).display().iec(),
            stats.action_results,
            bytesize::ByteSize::b(stats.action_result_bytes)
                .display()
                .iec(),
        );
    }
    if app.is_empty() {
        println!("no builds recorded");
        return;
    }
    println!();
    println!(
        "{:<34}  {:<10}  {:>5}  {:>5}  {:>11}  {:>6}",
        "command", "state", "hit", "miss", "unconsulted", "bypass"
    );
    for session in app.sessions() {
        println!(
            "{:<34}  {:<10}  {:>5}  {:>5}  {:>11}  {:>6}",
            truncate(&session.title(), 34),
            session.state.label(),
            session.count("hit"),
            session.count("miss"),
            session.count("unconsulted"),
            session
                .bypasses()
                .iter()
                .map(|(_, count)| count)
                .sum::<u64>(),
        );
    }
}

fn truncate(value: &str, width: usize) -> String {
    if value.chars().count() <= width {
        return value.to_string();
    }
    let kept: String = value.chars().take(width.saturating_sub(1)).collect();
    format!("{kept}…")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn arrows_switch_tabs_and_scroll_store_with_key_repeats() {
        let store = tempfile::tempdir().unwrap();
        let mut app = App::new(store.path(), 50);
        let area = Rect::new(0, 0, 80, 24);
        let key = |code| KeyEvent::new(code, KeyModifiers::NONE);
        handle_key(&mut app, key(KeyCode::Left), area);
        assert_eq!(app.tab, Tab::Insights);
        handle_key(&mut app, key(KeyCode::Right), area);
        assert_eq!(app.tab, Tab::Live);
        handle_key(&mut app, key(KeyCode::BackTab), area);
        assert_eq!(app.tab, Tab::Insights);
        handle_key(&mut app, key(KeyCode::Left), area);
        assert_eq!(app.tab, Tab::Store);
        handle_key(&mut app, key(KeyCode::Down), area);
        assert_eq!(app.store_scroll, 1);
        handle_key(
            &mut app,
            KeyEvent::new_with_kind(KeyCode::Down, KeyModifiers::NONE, KeyEventKind::Repeat),
            area,
        );
        assert_eq!(app.store_scroll, 2);
        handle_key(
            &mut app,
            KeyEvent::new_with_kind(KeyCode::Down, KeyModifiers::NONE, KeyEventKind::Release),
            area,
        );
        assert_eq!(app.store_scroll, 2);
        handle_key(&mut app, key(KeyCode::Up), area);
        assert_eq!(app.store_scroll, 1);
    }

    #[test]
    fn up_and_down_select_builds() {
        let store = tempfile::tempdir().unwrap();
        let writers = (0..2)
            .map(|_| {
                let writer = crate::events::EventWriter::with_limit(
                    store.path(),
                    Some(crate::config::DEFAULT_EVENTS_MAX_SIZE),
                );
                writer.started(Path::new("/fixture"), &["build".into()], None);
                writer
            })
            .collect::<Vec<_>>();
        let mut app = App::new(store.path(), 50);
        app.tick(50);
        let area = Rect::new(0, 0, 80, 24);
        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Down, KeyModifiers::NONE),
            area,
        );
        assert_eq!(app.selected, 1);
        handle_key(
            &mut app,
            KeyEvent::new(KeyCode::Up, KeyModifiers::NONE),
            area,
        );
        assert_eq!(app.selected, 0);
        drop(writers);
    }
}
