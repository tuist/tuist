use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Platform {
    MacOS,
    Linux,
    Windows,
}

impl Platform {
    pub fn current() -> Self {
        if cfg!(target_os = "macos") {
            Self::MacOS
        } else if cfg!(windows) {
            Self::Windows
        } else {
            Self::Linux
        }
    }
}

/// Tuist's configuration (credentials) and state (locks) directories.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Directories {
    pub config: PathBuf,
    pub state: PathBuf,
    pub data: PathBuf,
}

impl Directories {
    pub fn from_env() -> Self {
        Self::resolve(Platform::current(), |name| std::env::var(name).ok())
    }

    /// Mirrors `Environment.configDirectory`/`stateDirectory` and the Linux
    /// credential store. Windows has no Swift client, so it uses the
    /// platform's local application data, never roaming credentials.
    pub fn resolve(platform: Platform, env: impl Fn(&str) -> Option<String>) -> Self {
        // `Environment.variable` prefers the `TUIST_`-prefixed name and only
        // accepts absolute paths.
        let xdg = |name: &str| {
            env(&format!("TUIST_{name}"))
                .or_else(|| env(name))
                .map(PathBuf::from)
                .filter(|path| path.is_absolute())
                .map(|path| normalized(&path))
        };
        // NSHomeDirectory() reads HOME; the Linux store falls back to /tmp.
        let home = || {
            env("HOME")
                .map(PathBuf::from)
                .or_else(std::env::home_dir)
                .unwrap_or_else(|| PathBuf::from("/tmp"))
        };
        let tuist = |base: PathBuf| base.join("tuist");

        match platform {
            Platform::MacOS => Self {
                config: tuist(xdg("XDG_CONFIG_HOME").unwrap_or_else(|| home().join(".config"))),
                state: tuist(xdg("XDG_STATE_HOME").unwrap_or_else(|| home().join(".local/state"))),
                data: tuist(xdg("XDG_CONFIG_HOME").unwrap_or_else(|| home().join(".config"))),
            },
            // The Linux CLI keeps credentials under $HOME/.config/tuist
            // regardless of XDG_CONFIG_HOME, while locks follow XDG_STATE_HOME.
            Platform::Linux => Self {
                config: tuist(home().join(".config")),
                state: tuist(xdg("XDG_STATE_HOME").unwrap_or_else(|| home().join(".local/state"))),
                data: tuist(xdg("XDG_DATA_HOME").unwrap_or_else(|| home().join(".local/share"))),
            },
            Platform::Windows => {
                let local = || {
                    env("LOCALAPPDATA")
                        .map(PathBuf::from)
                        .filter(|path| path.is_absolute())
                        .unwrap_or_else(|| home().join("AppData/Local"))
                };
                Self {
                    config: tuist(xdg("XDG_CONFIG_HOME").unwrap_or_else(local)),
                    state: tuist(xdg("XDG_STATE_HOME").unwrap_or_else(local)),
                    data: tuist(xdg("XDG_DATA_HOME").unwrap_or_else(local)),
                }
            }
        }
    }
}

/// `AbsolutePath` drops trailing separators; lock names hash the path string.
fn normalized(path: &Path) -> PathBuf {
    path.components().collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn env(pairs: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> {
        let pairs: Vec<(String, String)> = pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect();
        move |name| {
            pairs
                .iter()
                .find(|(k, _)| k == name)
                .map(|(_, v)| v.clone())
        }
    }

    // The macOS and Linux layouts only resolve on those hosts; Unix paths such
    // as `/cfg` are not absolute on Windows.
    #[cfg(unix)]
    #[test]
    fn macos_prefers_tuist_prefixed_xdg_and_ignores_relative_paths() {
        let dirs = Directories::resolve(
            Platform::MacOS,
            env(&[
                ("HOME", "/Users/ana"),
                ("TUIST_XDG_CONFIG_HOME", "/cfg/"),
                ("XDG_CONFIG_HOME", "/other"),
                ("XDG_STATE_HOME", "relative"),
            ]),
        );
        assert_eq!(dirs.config, PathBuf::from("/cfg/tuist"));
        assert_eq!(dirs.data, dirs.config);
        assert_eq!(dirs.state, PathBuf::from("/Users/ana/.local/state/tuist"));
    }

    #[cfg(unix)]
    #[test]
    fn linux_keeps_credentials_under_home_but_locks_follow_xdg_state() {
        let dirs = Directories::resolve(
            Platform::Linux,
            env(&[
                ("HOME", "/home/ana"),
                ("XDG_CONFIG_HOME", "/xdg/config"),
                ("XDG_STATE_HOME", "/xdg/state"),
                ("XDG_DATA_HOME", "/xdg/data"),
                ("TUIST_XDG_DATA_HOME", "/tuist/data"),
            ]),
        );
        assert_eq!(dirs.config, PathBuf::from("/home/ana/.config/tuist"));
        assert_eq!(dirs.state, PathBuf::from("/xdg/state/tuist"));
        assert_eq!(dirs.data, PathBuf::from("/tuist/data/tuist"));
    }

    #[test]
    fn windows_uses_local_not_roaming_and_respects_absolute_overrides() {
        // Native absolute paths, not C:\\... interpreted as relative on macOS.
        let base = std::env::temp_dir();
        let local = base.join("local");
        let roaming = base.join("roaming");
        let override_path = base.join("override");
        let dirs = Directories::resolve(
            Platform::Windows,
            env(&[
                ("LOCALAPPDATA", local.to_str().unwrap()),
                ("APPDATA", roaming.to_str().unwrap()),
            ]),
        );
        assert_eq!(dirs.config, local.join("tuist"));
        assert_eq!(dirs.data, dirs.config);
        assert_eq!(dirs.state, dirs.config);
        let dirs = Directories::resolve(
            Platform::Windows,
            env(&[
                ("LOCALAPPDATA", local.to_str().unwrap()),
                ("TUIST_XDG_DATA_HOME", override_path.to_str().unwrap()),
                ("TUIST_XDG_CONFIG_HOME", "relative"),
            ]),
        );
        assert_eq!(dirs.data, override_path.join("tuist"));
        assert_eq!(dirs.config, local.join("tuist"));
    }
}
