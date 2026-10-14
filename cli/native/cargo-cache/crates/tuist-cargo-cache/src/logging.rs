//! Coordinate background diagnostics with the inline terminal renderer.
use std::io::{self, Write};
use std::sync::Mutex;

static CAPTURE: Mutex<Option<Vec<u8>>> = Mutex::new(None);

struct Stderr;

impl Write for Stderr {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        let mut capture = CAPTURE.lock().unwrap_or_else(|error| error.into_inner());
        if let Some(buffer) = capture.as_mut() {
            buffer.extend_from_slice(bytes);
            Ok(bytes.len())
        } else {
            io::stderr().write(bytes)
        }
    }

    fn flush(&mut self) -> io::Result<()> {
        io::stderr().flush()
    }
}

/// portable-pty reports a pty it could not open or spawn into at error level
/// before returning that failure to its caller, and tuist_cargo_cache is the caller that
/// decides what the failure means: an inline view that cannot start is not a
/// build problem, because the build continues under plain Cargo. Keep the
/// library quiet by default so its copy of the message does not reach a user
/// whose build then succeeds. `TUIST_CARGO_CACHE_LOG` replaces this filter outright, so
/// `TUIST_CARGO_CACHE_LOG=debug` still shows the reason the view stood down.
pub(crate) const DEFAULT_FILTER: &str = "info,portable_pty=off";

/// The logger `init` installs, built but not registered, so a test can ask
/// what a run actually filters rather than what the default filter says.
fn builder() -> env_logger::Builder {
    let mut builder = env_logger::Builder::from_env(
        env_logger::Env::default().filter_or("TUIST_CARGO_CACHE_LOG", DEFAULT_FILTER),
    );
    builder
        .format_target(false)
        .format_timestamp(None)
        .target(env_logger::Target::Pipe(Box::new(Stderr)));
    builder
}

/// Initialize the command logger while retaining its existing filter settings.
pub fn init() {
    builder().init();
}

pub(crate) fn note(message: &str) {
    if std::env::var_os("TUIST_CARGO_NATIVE").is_some() {
        if let Some(suffix) = message.strip_prefix("tuist_cargo_cache[") {
            let _ = writeln!(Stderr, "Tuist Cargo cache[{suffix}");
            return;
        }
    }
    let _ = writeln!(Stderr, "{message}");
}

/// The screen owns this guard; its destructor restores terminal mode before
/// this field is dropped, so even diagnostics arriving during shutdown survive.
pub(crate) struct Capture;

impl Capture {
    pub(crate) fn start() -> Self {
        *CAPTURE.lock().unwrap_or_else(|error| error.into_inner()) = Some(Vec::new());
        Self
    }

    pub(crate) fn drain(&self) -> Vec<u8> {
        CAPTURE
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .as_mut()
            .map(std::mem::take)
            .unwrap_or_default()
    }
}

impl Drop for Capture {
    fn drop(&mut self) {
        let mut capture = CAPTURE.lock().unwrap_or_else(|error| error.into_inner());
        if let Some(bytes) = capture.take() {
            let _ = io::stderr().write_all(&bytes);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use log::Log;

    fn enabled(logger: &env_logger::Logger, target: &str, level: log::Level) -> bool {
        logger.enabled(&log::Metadata::builder().target(target).level(level).build())
    }

    #[test]
    fn a_pty_failure_cargo_cache_recovers_from_is_not_announced_to_the_user() {
        // The assertion is about what a run without `TUIST_CARGO_CACHE_LOG` filters, so a
        // developer who exports one is testing their own filter instead.
        if std::env::var_os("TUIST_CARGO_CACHE_LOG").is_some() {
            return;
        }
        let logger = builder().build();
        assert!(!enabled(&logger, "portable_pty", log::Level::Error));
        assert!(enabled(
            &logger,
            "tuist_cargo_cache::cli::cargo",
            log::Level::Info
        ));
        assert!(!enabled(
            &logger,
            "tuist_cargo_cache::cli::cargo",
            log::Level::Debug
        ));
    }

    #[test]
    fn an_explicit_filter_can_ask_for_the_pty_report() {
        let logger = env_logger::Builder::new().parse_filters("debug").build();
        assert!(enabled(&logger, "portable_pty", log::Level::Error));
    }

    #[test]
    fn background_notes_and_logger_writes_share_the_screen_queue() {
        let capture = Capture::start();
        std::thread::spawn(|| {
            note("background warning");
            Stderr.write_all(b"logger warning\n").unwrap();
        })
        .join()
        .unwrap();
        let output = String::from_utf8(capture.drain()).unwrap();
        assert!(output.contains("background warning"));
        assert!(output.contains("logger warning"));
    }
}
