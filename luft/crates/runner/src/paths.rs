//! Where the runner keeps its configuration, status and log on each platform.
use std::path::{Path, PathBuf};

pub fn home() -> Option<PathBuf> {
    let variable = if cfg!(windows) { "USERPROFILE" } else { "HOME" };
    std::env::var_os(variable)
        .map(PathBuf::from)
        .filter(|path| path.is_absolute())
}

fn absolute(variable: &str) -> Option<PathBuf> {
    std::env::var_os(variable)
        .map(PathBuf::from)
        .filter(|path| path.is_absolute())
}

/// The directory holding `config.json` and `status.json`. `LUFT_RUNNER_HOME`
/// overrides it, so tests and a second development copy never share the real one.
pub fn state_dir() -> Option<PathBuf> {
    if let Some(path) = absolute("LUFT_RUNNER_HOME") {
        return Some(path);
    }
    if cfg!(target_os = "macos") {
        home().map(|home| home.join("Library/Application Support/dev.tuist.guild/Runner"))
    } else if cfg!(windows) {
        absolute("LOCALAPPDATA").map(|path| path.join("luft").join("runner"))
    } else {
        absolute("XDG_STATE_HOME")
            .or_else(|| home().map(|home| home.join(".local/state")))
            .map(|path| path.join("luft/runner"))
    }
}

pub fn config_file(state: &Path) -> PathBuf {
    state.join("config.json")
}

/// Asks the running daemon to request its display permissions, which only it
/// can do for itself.
pub fn permission_request_file(state: &Path) -> PathBuf {
    state.join("request-permissions")
}

pub fn status_file(state: &Path) -> PathBuf {
    state.join("status.json")
}

/// The daemon's stdout and stderr. On macOS it is under `~/Library/Logs`, where
/// Console finds it.
pub fn log_file(state: &Path) -> PathBuf {
    if cfg!(target_os = "macos")
        && absolute("LUFT_RUNNER_HOME").is_none()
        && let Some(home) = home()
    {
        return home.join("Library/Logs/Luft/runner.log");
    }
    state.join("runner.log")
}

/// `~` and `~/…` name the home folder; every other folder is absolute.
pub fn expand(path: &str) -> Option<PathBuf> {
    if path == "~" {
        return home();
    }
    if let Some(rest) = path.strip_prefix("~/") {
        return home().map(|home| home.join(rest));
    }
    let path = PathBuf::from(path);
    path.is_absolute().then_some(path)
}

/// The inverse of `expand` for display and storage: a path under the home
/// folder is written with `~`.
pub fn abbreviate(path: &Path) -> String {
    if let Some(home) = home() {
        if path == home {
            return "~".into();
        }
        if let Ok(rest) = path.strip_prefix(&home) {
            return format!("~/{}", rest.display());
        }
    }
    path.display().to_string()
}

/// Writes through a temporary file and a rename, so a reader never sees half a file.
pub fn write_atomically(path: &Path, contents: &[u8]) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let temporary = path.with_extension(format!("tmp-{}", std::process::id()));
    std::fs::write(&temporary, contents)?;
    std::fs::rename(&temporary, path)
}
