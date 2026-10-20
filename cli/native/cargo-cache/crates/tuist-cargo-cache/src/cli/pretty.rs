//! Cargo-pretty's inline view, with session-local tuist_cargo_cache cache information.
//!
//! Cargo remains the only orchestrator: the original command runs once in a
//! terminal, including runners and doctests. Only its presentation is adapted.
mod model;
mod norimel;
#[cfg(test)]
mod tests;
mod upstream;
mod view;

use eyre::{Context, Result};
use model::{Model, strip_ansi};
use portable_pty::{CommandBuilder, NativePtySystem, PtySize, PtySystem};
use ratatui::crossterm::{
    SynchronizedUpdate, cursor,
    event::{self, Event, KeyCode, KeyModifiers},
    execute, terminal,
};
use std::{
    collections::BTreeMap,
    ffi::{OsStr, OsString},
    io::{self, IsTerminal, Read, Write},
    process::ExitCode,
    sync::mpsc,
    time::{Duration, Instant},
};
use tuist_cargo_cache_core::AgentStats;

pub(super) fn enabled(arguments: &[String]) -> bool {
    eligible(arguments)
        && log::max_level() < log::LevelFilter::Debug
        && io::stdin().is_terminal()
        && io::stdout().is_terminal()
        && io::stderr().is_terminal()
        && !crate::policy::is_ci()
        && std::env::var("TERM").as_deref() != Ok("dumb")
        && std::env::var_os("NO_COLOR").is_none()
        && std::env::var("CARGO_TERM_COLOR").as_deref() != Ok("never")
        && std::env::var("CARGO_TERM_PROGRESS_WHEN").as_deref() != Ok("never")
        && terminal::size().is_ok_and(|(cols, rows)| cols >= 50 && rows >= 16)
}

/// Identify the command used by the terminal display, skipping Cargo globals
/// such as the invocation-local target configuration added by tuist_cargo_cache.
fn cargo_verb(arguments: &[String]) -> Option<&str> {
    super::launch::cargo_subcommand(arguments)
}

fn eligible(arguments: &[String]) -> bool {
    matches!(
        cargo_verb(arguments),
        Some("build" | "b" | "check" | "c" | "clippy" | "run" | "r" | "test" | "t")
    ) && !arguments
        .iter()
        .take_while(|a| a.as_str() != "--")
        .any(|arg| {
            matches!(
                arg.as_str(),
                "--quiet"
                    | "--verbose"
                    | "--help"
                    | "--version"
                    | "--message-format"
                    | "--color"
                    | "--config"
            ) || arg.starts_with("--message-format=")
                || arg.starts_with("--color=")
                || arg.starts_with("--config=")
                || (arg.starts_with('-')
                    && !arg.starts_with("--")
                    && arg[1..].contains(['q', 'v', 'h', 'V']))
        })
}

fn cargo_arguments(arguments: &[String]) -> Vec<String> {
    let mut result = arguments.to_vec();
    let index = result
        .iter()
        .position(|arg| arg == "--")
        .unwrap_or(result.len());
    result.insert(
        index,
        "--message-format=json,json-diagnostic-rendered-ansi".into(),
    );
    result
}

pub(super) fn run(
    cargo: &OsStr,
    arguments: &[String],
    environment: &BTreeMap<String, String>,
    inspect_warnings: bool,
    stats: impl Fn() -> AgentStats,
) -> Result<Option<ExitCode>> {
    let mut started = false;
    match run_inner(
        cargo,
        arguments,
        environment,
        inspect_warnings,
        &mut started,
        stats,
    ) {
        Ok(status) => Ok(Some(status)),
        Err(error) if !started => {
            log::debug!("pretty terminal unavailable; using plain Cargo: {error}");
            Ok(None)
        }
        Err(error) => Err(error),
    }
}

/// Replaces the builder's base environment with the caller's.
///
/// On Windows, `portable-pty` overlays the registry's machine and user
/// environments onto the process environment when it constructs a builder. That
/// drops `PATH` entries added in the calling shell, overwrites overridden
/// variables, and restores variables the shell removed, so the pretty display
/// would change what Cargo inherits compared with the plain launch.
fn seed_process_environment(
    command: &mut CommandBuilder,
    process: impl IntoIterator<Item = (OsString, OsString)>,
) {
    command.env_clear();
    for (key, value) in process {
        command.env(key, value);
    }
}

fn run_inner(
    cargo: &OsStr,
    arguments: &[String],
    environment: &BTreeMap<String, String>,
    inspect_warnings: bool,
    started: &mut bool,
    stats: impl Fn() -> AgentStats,
) -> Result<ExitCode> {
    let (cols, rows) = terminal::size()?;
    let pair = NativePtySystem::default()
        .openpty(pty_size(cols, rows))
        .map_err(|e| eyre::eyre!(e))?;
    let mut command = CommandBuilder::new(cargo);
    if cfg!(windows) {
        seed_process_environment(&mut command, std::env::vars_os());
    }
    command.args(cargo_arguments(arguments));
    // Cargo supplies the denominator itself, without an unstable unit-graph
    // probe. Include presentation overrides in the launch overlay so native
    // applications receive the caller's environment after the build ends.
    let mut environment = environment.clone();
    environment.insert("CARGO_TERM_PROGRESS_WHEN".into(), "always".into());
    environment.insert("CARGO_TERM_PROGRESS_WIDTH".into(), cols.to_string());
    super::launch::record_overlay(&mut environment)?;
    for (key, value) in &environment {
        command.env(key, value);
    }
    command.cwd(std::env::current_dir()?);
    let mut reader = pair.master.try_clone_reader().map_err(|e| eyre::eyre!(e))?;
    let mut input = pair.master.take_writer().map_err(|e| eyre::eyre!(e))?;
    let mut screen = Screen::new()?;
    let mut child = pair
        .slave
        .spawn_command(command)
        .map_err(|e| eyre::eyre!(e))?;
    *started = true;
    drop(pair.slave);
    let (send, receive) = mpsc::sync_channel(32);
    std::thread::spawn(move || {
        let mut bytes = [0; 8192];
        loop {
            match reader.read(&mut bytes) {
                Ok(0) => break,
                Ok(n) => {
                    if send.send(Ok(bytes[..n].to_vec())).is_err() {
                        break;
                    }
                }
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                Err(error) => {
                    let _ = send.send(Err(error));
                    break;
                }
            }
        }
    });
    let mut model = Model::new(arguments);
    let mode = match cargo_verb(arguments) {
        Some("run" | "r") => Mode::Run,
        Some("test" | "t") => Mode::Test,
        _ => Mode::Build,
    };
    let mut decoder = Decoder::default();
    let mut proxy = false;
    let mut last_frame = Instant::now() - Duration::from_secs(1);
    let result = (|| -> Result<portable_pty::ExitStatus> {
        let mut exit_seen = false;
        let mut last_output = Instant::now();
        loop {
            if !exit_seen && child.try_wait().map_err(|e| eyre::eyre!(e))?.is_some() {
                exit_seen = true;
                last_output = Instant::now();
            }
            match receive.recv_timeout(Duration::from_millis(20)) {
                Ok(Ok(bytes)) => {
                    last_output = Instant::now();
                    decoder.feed(&bytes, &mut model, &mut screen, mode, &mut proxy, &stats)?
                }
                Ok(Err(error)) => return Err(error.into()),
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    // Drain every available chunk, regardless of burst size. Only
                    // an idle reader after Cargo exits ends a retained-slave stream.
                    if exit_seen && last_output.elapsed() >= Duration::from_secs(1) {
                        break;
                    }
                    decoder.flush_partial(&mut screen, model.build_finished)?;
                }
            }
            forward_input(&mut input)?;
            if let Ok((cols, rows)) = terminal::size() {
                let size = pty_size(cols, rows);
                if pair.master.get_size().map_err(|e| eyre::eyre!(e))? != size {
                    pair.master.resize(size).map_err(|e| eyre::eyre!(e))?;
                    screen.clear()?;
                }
            }
            let awaiting_lf = screen.awaiting_lf();
            if !proxy
                && decoder.pending.is_empty()
                && !decoder.partial
                && !awaiting_lf
                && last_frame.elapsed() >= Duration::from_millis(80)
            {
                model.update_stats(stats());
                screen.draw(view::render(
                    &mut model,
                    None,
                    screen.width(),
                    screen.height(),
                ))?;
                last_frame = Instant::now();
            } else {
                screen.repaint()?;
            }
        }
        decoder.finish(&mut screen)?;
        child.wait().map_err(|e| eyre::eyre!(e))
    })();
    if result.is_err() {
        let _ = child.kill();
        let _ = child.wait();
    }
    let status = result.wrap_err("running Cargo with the pretty display")?;
    model.update_stats(stats());
    model.finished = Some((status.success(), model.started.elapsed()));
    if !proxy {
        screen.draw(view::render(
            &mut model,
            None,
            screen.width(),
            screen.height(),
        ))?;
        // Full diagnostic text remains in scrollback even if the user dismisses
        // the optional browser, and the child's failure status stays authoritative.
        screen.commit();
        for error in &model.errors {
            screen.diagnostic(error)?;
            screen.write(b"\r\n")?;
        }
        let count = model.warnings.len() + model.failures.len();
        if count > 0 && (!status.success() || inspect_warnings) {
            let mut browser = view::Browser::default();
            loop {
                screen.draw(view::render(
                    &mut model,
                    Some(&mut browser),
                    screen.width(),
                    screen.height(),
                ))?;
                if let Event::Key(key) = event::read()?
                    && key.kind != event::KeyEventKind::Release
                {
                    match key.code {
                        KeyCode::Esc | KeyCode::Char('q') => break,
                        KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                            break;
                        }
                        KeyCode::Up if browser.inspecting => {
                            browser.scroll = browser.scroll.saturating_sub(1)
                        }
                        KeyCode::Down if browser.inspecting => {
                            browser.scroll = browser.scroll.saturating_add(1)
                        }
                        KeyCode::Up => {
                            browser.selected = browser.selected.saturating_sub(1);
                            browser.scroll = 0;
                        }
                        KeyCode::Down => {
                            browser.selected = (browser.selected + 1).min(count - 1);
                            browser.scroll = 0;
                        }
                        KeyCode::Enter => {
                            browser.inspecting = !browser.inspecting;
                            browser.scroll = 0;
                        }
                        KeyCode::PageUp => browser.scroll = browser.scroll.saturating_sub(10),
                        KeyCode::PageDown => browser.scroll = browser.scroll.saturating_add(10),
                        _ => {}
                    }
                }
            }
            screen.clear()?;
        }
        for warning in &model.warnings {
            screen.diagnostic(&warning.rendered)?;
            screen.write(b"\r\n")?;
        }
        screen.commit();
    }
    Ok(ExitCode::from(status_code(&status)))
}

fn pty_size(cols: u16, rows: u16) -> PtySize {
    PtySize {
        rows: rows.max(1),
        cols: cols.max(1),
        pixel_width: 0,
        pixel_height: 0,
    }
}

fn status_code(status: &portable_pty::ExitStatus) -> u8 {
    #[cfg(unix)]
    if let Some(name) = status.signal() {
        // portable-pty retains the signal's platform name rather than number.
        for signal in 1..=127 {
            let description = unsafe { libc::strsignal(signal) };
            if !description.is_null()
                && unsafe { std::ffi::CStr::from_ptr(description) }.to_string_lossy() == name
            {
                return 128 + signal as u8;
            }
        }
    }
    u8::try_from(status.exit_code()).unwrap_or(1)
}

// Unix input remains byte-for-byte terminal input, including function keys,
// paste sequences, control characters and application-specific escape codes.
#[cfg(unix)]
fn forward_input(input: &mut impl Write) -> io::Result<()> {
    let mut poll = libc::pollfd {
        fd: libc::STDIN_FILENO,
        events: libc::POLLIN,
        revents: 0,
    };
    if unsafe { libc::poll(&mut poll, 1, 0) } > 0 && poll.revents & libc::POLLIN != 0 {
        let mut bytes = [0u8; 8192];
        let size =
            unsafe { libc::read(libc::STDIN_FILENO, bytes.as_mut_ptr().cast(), bytes.len()) };
        if size > 0 {
            input.write_all(&bytes[..size as usize])?;
            input.flush()?;
        } else if size < 0 {
            let error = io::Error::last_os_error();
            if error.kind() != io::ErrorKind::Interrupted {
                return Err(error);
            }
        }
    }
    Ok(())
}

#[cfg(windows)]
fn forward_input(input: &mut impl Write) -> io::Result<()> {
    while event::poll(Duration::ZERO)? {
        match event::read()? {
            Event::Key(key) if key.kind != event::KeyEventKind::Release => {
                input.write_all(&key_bytes(key))?
            }
            Event::Paste(text) => input.write_all(text.as_bytes())?,
            _ => {}
        }
    }
    input.flush()
}

#[cfg(windows)]
fn key_bytes(key: event::KeyEvent) -> Vec<u8> {
    let mut bytes = match key.code {
        KeyCode::Char(c) if key.modifiers.contains(KeyModifiers::CONTROL) && c.is_ascii() => {
            vec![(c as u8) & 0x1f]
        }
        KeyCode::Char(c) => c.to_string().into_bytes(),
        KeyCode::Enter => vec![b'\r'],
        KeyCode::Backspace => vec![127],
        KeyCode::Tab => vec![b'\t'],
        KeyCode::BackTab => b"\x1b[Z".to_vec(),
        KeyCode::Esc => vec![27],
        KeyCode::Up => b"\x1b[A".to_vec(),
        KeyCode::Down => b"\x1b[B".to_vec(),
        KeyCode::Right => b"\x1b[C".to_vec(),
        KeyCode::Left => b"\x1b[D".to_vec(),
        KeyCode::Home => b"\x1b[H".to_vec(),
        KeyCode::End => b"\x1b[F".to_vec(),
        KeyCode::Delete => b"\x1b[3~".to_vec(),
        KeyCode::Insert => b"\x1b[2~".to_vec(),
        KeyCode::PageUp => b"\x1b[5~".to_vec(),
        KeyCode::PageDown => b"\x1b[6~".to_vec(),
        KeyCode::F(n @ 1..=4) => vec![27, b'O', b'P' + n - 1],
        KeyCode::F(n @ 5..=12) => format!(
            "\x1b[{}~",
            [15, 17, 18, 19, 20, 21, 23, 24][usize::from(n - 5)]
        )
        .into_bytes(),
        _ => Vec::new(),
    };
    if key.modifiers.contains(KeyModifiers::ALT) {
        bytes.insert(0, 27);
    }
    bytes
}

#[derive(Clone, Copy)]
enum Mode {
    Build,
    Run,
    Test,
}

#[derive(Default)]
struct Decoder {
    pending: Vec<u8>,
    partial: bool,
    swallow_lf: bool,
}

impl Decoder {
    fn feed(
        &mut self,
        bytes: &[u8],
        model: &mut Model,
        screen: &mut Screen,
        mode: Mode,
        proxy: &mut bool,
        stats: &impl Fn() -> AgentStats,
    ) -> io::Result<()> {
        if *proxy {
            return screen.write(bytes);
        }
        for chunk in bytes.split_inclusive(|byte| matches!(byte, b'\n' | b'\r')) {
            if *proxy {
                screen.write(chunk)?;
                continue;
            }
            if self.swallow_lf && chunk == b"\n" {
                self.swallow_lf = false;
                continue;
            }
            self.swallow_lf = false;
            self.pending.extend_from_slice(chunk);
            if chunk.ends_with(b"\n") || chunk.ends_with(b"\r") {
                let clean = std::str::from_utf8(&self.pending).ok().map(strip_ansi);
                let line = clean
                    .as_deref()
                    .unwrap_or("")
                    .trim_end_matches(['\n', '\r']);
                let handled = !self.partial
                    && ((!model.build_finished && (model.cargo(line) || model.status(line)))
                        || (matches!(mode, Mode::Test) && model.test_line(line)));
                self.swallow_lf = handled && chunk.ends_with(b"\r");
                if !handled {
                    screen.write(&self.pending)?;
                }
                self.pending.clear();
                self.partial = false;
                if matches!(mode, Mode::Run) && model.build_finished && model.build_ok == Some(true)
                {
                    model.update_stats(stats());
                    model.finished = Some((true, model.started.elapsed()));
                    screen.draw(view::summary(model))?;
                    screen.commit();
                    for warning in &model.warnings {
                        screen.diagnostic(&warning.rendered)?;
                        screen.write(b"\r\n")?;
                    }
                    *proxy = true;
                    execute!(io::stderr(), cursor::Show)?;
                }
            } else if self.pending.len() >= 1024 * 1024 {
                self.partial = true;
                self.flush_partial(screen, true)?;
            }
        }
        Ok(())
    }

    fn flush_partial(&mut self, screen: &mut Screen, native_output: bool) -> io::Result<()> {
        // Compiler JSON may be emitted in many writes; retain a bounded record.
        // Ordinary partial output (prompts, custom harnesses) is forwarded now.
        if !self.pending.is_empty()
            && (native_output || self.partial || !self.pending.starts_with(b"{"))
        {
            screen.write(&self.pending)?;
            self.pending.clear();
            self.partial = true;
        }
        Ok(())
    }

    fn finish(&mut self, screen: &mut Screen) -> io::Result<()> {
        if !self.pending.is_empty() {
            screen.write(&self.pending)?;
            self.pending.clear();
        }
        Ok(())
    }
}

/// The progress block on screen and the child output waiting to be shown with it.
///
/// Every method returns the bytes to write instead of writing them, so a caller
/// can present each change in one synchronized update and tests can inspect it.
#[derive(Default)]
struct Frame {
    /// Rows of the block above the cursor, zero once it is erased or committed.
    drawn: u16,
    /// The last block drawn, repainted below output that arrives between frames.
    block: String,
    rows: u16,
    /// Complete lines of child output not yet shown, in arrival order.
    held: Vec<u8>,
    /// A held CR was ended with an LF of our own, so the child's LF, if it
    /// arrives, must not end the line a second time.
    lf_owed: bool,
    /// When a frame first found the held CR waiting. Cleared when held output is
    /// shown, so the next CR gets a full grace period of its own.
    cr_since: Option<Instant>,
}

impl Frame {
    fn erase(&mut self, out: &mut Vec<u8>) {
        if self.drawn > 0 {
            out.extend_from_slice(format!("\r\x1b[{}A\x1b[J", self.drawn).as_bytes());
            self.drawn = 0;
        }
    }

    /// Output that ends a line waits while a block is showing, so that
    /// [`Frame::present`] or [`Frame::draw`] can erase, print and repaint it
    /// in one update. A CR waits too: the PTY's CRLF arrives as two chunks, and
    /// nothing may be written between them. Anything else (a prompt, a partial
    /// line) is shown at once, without the block, which stays away until the
    /// line is complete.
    fn write(&mut self, bytes: &[u8]) -> Vec<u8> {
        let bytes = match bytes {
            [b'\n', rest @ ..] if self.lf_owed => rest,
            _ => bytes,
        };
        self.lf_owed = false;
        if bytes.is_empty() {
            return Vec::new();
        }
        self.held.extend_from_slice(bytes);
        if self.drawn > 0 && matches!(bytes.last(), Some(b'\n' | b'\r')) {
            Vec::new()
        } else {
            self.present(false)
        }
    }

    /// Show held output, and put the last block back below it if `repaint`.
    /// Output that ends in a CR keeps waiting for a repaint: its LF may be in
    /// the next read, and a bare CR would have the block overwrite the line it
    /// returned to. The next [`Frame::draw`] shows it, on a line of its own.
    fn present(&mut self, repaint: bool) -> Vec<u8> {
        let repaint = repaint && self.drawn > 0;
        if repaint && (self.held.is_empty() || self.trailing_cr()) {
            return Vec::new();
        }
        let mut out = Vec::with_capacity(self.held.len());
        self.erase(&mut out);
        out.append(&mut self.held);
        self.cr_since = None;
        if repaint {
            out.extend_from_slice(self.block.as_bytes());
            self.drawn = self.rows;
        }
        out
    }

    /// Move held output to `out`. A line that ends in a bare CR is ended with an
    /// LF, or the block drawn next would print over it.
    fn flush_held(&mut self, out: &mut Vec<u8>) {
        let unterminated = self.trailing_cr();
        out.append(&mut self.held);
        self.cr_since = None;
        if unterminated {
            out.push(b'\n');
            self.lf_owed = true;
        }
    }

    /// Erase the block and show what was held, for a block about to be redrawn
    /// from scratch.
    fn clear(&mut self) -> Vec<u8> {
        let mut out = Vec::with_capacity(self.held.len());
        self.erase(&mut out);
        self.flush_held(&mut out);
        out
    }

    /// Whether a frame should wait for what follows a trailing CR. Drawing now
    /// would put a newline after half a CRLF and leave a blank row when the LF
    /// arrives. The wait ends [`CR_GRACE`] after it was first seen.
    fn awaiting_lf(&mut self, now: Instant) -> bool {
        if !self.trailing_cr() {
            self.cr_since = None;
            return false;
        }
        let since = *self.cr_since.get_or_insert(now);
        now.saturating_duration_since(since) < CR_GRACE
    }

    /// Held output ends in a CR: either half a CRLF or a line that rewrites itself.
    fn trailing_cr(&self) -> bool {
        self.held.ends_with(b"\r")
    }

    /// Replace the block: erase the old one, then held output, diagnostics
    /// and the new block.
    fn draw(&mut self, diagnostics: &[u8], block: String, rows: u16) -> Vec<u8> {
        let mut out = Vec::with_capacity(self.held.len() + block.len());
        self.erase(&mut out);
        self.flush_held(&mut out);
        out.extend_from_slice(
            String::from_utf8_lossy(diagnostics)
                .replace("\r\n", "\n")
                .replace('\n', "\r\n")
                .as_bytes(),
        );
        out.extend_from_slice(block.as_bytes());
        self.block = block;
        self.rows = rows;
        self.drawn = rows;
        out
    }

    /// Leave the block in scrollback.
    fn commit(&mut self) {
        debug_assert!(self.held.is_empty(), "held output would be lost");
        self.drawn = 0;
    }
}

/// How long a trailing CR may wait for its LF before it is taken as a line
/// that rewrites itself. A CRLF split by a read boundary completes far sooner.
const CR_GRACE: Duration = Duration::from_millis(250);

struct Screen {
    frame: Frame,
    diagnostics: crate::logging::Capture,
}
impl Screen {
    fn new() -> io::Result<Self> {
        let diagnostics = crate::logging::Capture::start();
        terminal::enable_raw_mode()?;
        let mut screen = Self {
            frame: Frame::default(),
            diagnostics,
        };
        if let Err(error) = execute!(io::stderr(), cursor::Hide) {
            let _ = terminal::disable_raw_mode();
            return Err(error);
        }
        screen.clear()?;
        Ok(screen)
    }
    fn width(&self) -> u16 {
        terminal::size()
            .map_or(80, |s| s.0.max(2))
            .saturating_sub(1)
    }
    fn height(&self) -> u16 {
        terminal::size()
            .map_or(24, |s| s.1.max(3))
            .saturating_sub(2)
            .min(27)
    }
    /// Write one composed frame. A block that is erased or repainted goes out in
    /// a single DEC 2026 synchronized update, which unsupported terminals ignore.
    fn emit(&mut self, bytes: &[u8], synchronized: bool) -> io::Result<()> {
        if bytes.is_empty() {
            return Ok(());
        }
        let mut stderr = io::stderr().lock();
        if synchronized {
            stderr.sync_update(|output| output.write_all(bytes))??;
        } else {
            stderr.write_all(bytes)?;
            stderr.flush()?;
        }
        Ok(())
    }
    /// Whether a frame should wait for what follows a trailing CR.
    fn awaiting_lf(&mut self) -> bool {
        self.frame.awaiting_lf(Instant::now())
    }
    fn clear(&mut self) -> io::Result<()> {
        let synchronized = self.frame.drawn > 0;
        let bytes = self.frame.clear();
        self.emit(&bytes, synchronized)
    }
    fn draw(&mut self, block: norimel::Block) -> io::Result<()> {
        // Compose before touching the terminal, then present the erase, held
        // output, diagnostics and replacement together.
        let diagnostics = self.diagnostics.drain();
        let rows = block.size().1;
        let text = block.to_string().replace('\n', "\r\n") + "\r\n";
        let bytes = self.frame.draw(&diagnostics, text, rows);
        self.emit(&bytes, true)
    }
    /// Show output held since the last frame, with the block repainted below it.
    fn repaint(&mut self) -> io::Result<()> {
        let bytes = self.frame.present(true);
        self.emit(&bytes, true)
    }

    fn write(&mut self, bytes: &[u8]) -> io::Result<()> {
        let synchronized = self.frame.drawn > 0;
        let bytes = self.frame.write(bytes);
        self.emit(&bytes, synchronized)
    }
    // Cargo JSON contains LF-delimited diagnostic text, unlike bytes read
    // from the child PTY. Raw mode requires explicit carriage returns here.
    fn diagnostic(&mut self, text: &str) -> io::Result<()> {
        self.write(text.replace("\r\n", "\n").replace('\n', "\r\n").as_bytes())
    }
    fn commit(&mut self) {
        self.frame.commit();
    }
}
impl Drop for Screen {
    fn drop(&mut self) {
        let _ = self.clear();
        let _ = execute!(io::stderr(), terminal::EndSynchronizedUpdate, cursor::Show);
        let _ = terminal::disable_raw_mode();
    }
}
