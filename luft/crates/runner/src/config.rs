//! The runner's settings, which the app edits and the daemon reads. One file,
//! `config.json` in the state directory, written atomically by whoever changes it.
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

use crate::paths;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    /// The name threads and the server show for this machine.
    pub name: String,
    /// Folders threads may work in, stored with `~` for the home folder.
    pub folders: Vec<String>,
    /// Where a thread creates a project that has no folder yet.
    pub new_project_folder: String,
    pub share_display: bool,
    pub allow_terminal: bool,
    pub allow_portals: bool,
    /// Keep the machine from sleeping while it is on power and the runner runs.
    pub keep_awake: bool,
}

/// A fresh runner shares one projects folder and nothing else: no terminal,
/// display or portals until the person turns them on.
impl Default for Config {
    fn default() -> Self {
        let projects = if cfg!(target_os = "macos") {
            "~/Developer"
        } else {
            "~/projects"
        };
        Self {
            name: default_name(),
            folders: vec![projects.into()],
            new_project_folder: projects.into(),
            share_display: false,
            allow_terminal: false,
            allow_portals: false,
            keep_awake: false,
        }
    }
}

fn default_name() -> String {
    let name = if cfg!(target_os = "macos") {
        command_output("scutil", &["--get", "LocalHostName"])
    } else {
        None
    }
    .or_else(|| std::env::var("COMPUTERNAME").ok())
    .or_else(|| std::env::var("HOSTNAME").ok())
    .or_else(|| command_output("hostname", &[]))
    .unwrap_or_default();
    let name = sanitize_name(&name);
    if name.is_empty() {
        "runner".into()
    } else {
        name
    }
}

fn command_output(program: &str, args: &[&str]) -> Option<String> {
    let output = std::process::Command::new(program)
        .args(args)
        .output()
        .ok()?;
    output
        .status
        .success()
        .then(|| String::from_utf8_lossy(&output.stdout).trim().to_string())
}

/// Runner names are lowercase letters, digits and hyphens, at most 63 bytes,
/// like a host name, so they read the same in a URL, a list and a log.
pub fn sanitize_name(name: &str) -> String {
    let mut out = String::new();
    for character in name.trim().chars().flat_map(char::to_lowercase) {
        if character.is_ascii_alphanumeric() {
            out.push(character);
        } else if !out.is_empty() && !out.ends_with('-') {
            out.push('-');
        }
    }
    let mut out: String = out.trim_end_matches('-').chars().take(63).collect();
    while out.ends_with('-') {
        out.pop();
    }
    out
}

impl Config {
    pub fn load(state: &Path) -> Result<Self, String> {
        match std::fs::read(paths::config_file(state)) {
            Ok(bytes) => serde_json::from_slice(&bytes)
                .map_err(|error| format!("Invalid runner config: {error}")),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(Self::default()),
            Err(error) => Err(format!("Could not read the runner config: {error}")),
        }
    }

    /// The settings the daemon serves with: the file when it reads, otherwise
    /// the last settings it read, otherwise `locked()`. Never the defaults,
    /// which share more than a person who narrowed them meant to.
    pub fn load_for_serving(state: &Path) -> Self {
        static LAST: std::sync::Mutex<Option<Config>> = std::sync::Mutex::new(None);
        let mut last = LAST.lock().unwrap_or_else(|poison| poison.into_inner());
        // A file that disappears after one loaded keeps the last settings too:
        // only a runner that never had a file starts from the defaults.
        if last.is_some() && !paths::config_file(state).exists() {
            eprintln!("The runner config is missing; serving the last settings that loaded");
            return last.clone().unwrap_or_else(Self::locked);
        }
        match Self::load(state) {
            Ok(config) => {
                *last = Some(config.clone());
                config
            }
            Err(error) => {
                eprintln!("{error}; serving the last settings that loaded");
                last.clone().unwrap_or_else(Self::locked)
            }
        }
    }

    /// What the daemon serves when it can't read the settings and has none
    /// it read before: nothing at all, so a damaged or newer file never widens
    /// what threads reach.
    pub fn locked() -> Self {
        Self {
            folders: vec![],
            share_display: false,
            allow_terminal: false,
            allow_portals: false,
            ..Self::default()
        }
    }

    pub fn save(&self, state: &Path) -> Result<(), String> {
        let bytes = serde_json::to_vec_pretty(self).map_err(|error| error.to_string())?;
        paths::write_atomically(&paths::config_file(state), &bytes)
            .map_err(|error| format!("Could not write the runner config: {error}"))
    }

    /// The configured folders that exist, resolved and without duplicates or
    /// folders already inside another one.
    pub fn roots(&self) -> Vec<PathBuf> {
        let mut roots: Vec<PathBuf> = self
            .folders
            .iter()
            .filter_map(|folder| paths::expand(folder))
            .filter_map(|folder| folder.canonicalize().ok())
            .filter(|folder| folder.is_dir())
            .collect();
        roots.sort();
        roots.dedup();
        let all = roots.clone();
        roots.retain(|root| {
            !all.iter()
                .any(|other| other != root && root.starts_with(other))
        });
        roots
    }

    /// Applies one change the app asks for. Folders are added and removed by
    /// their absolute or `~` path; the new project folder must be one of them
    /// or inside one, so a thread never creates a project where it cannot work.
    pub fn apply(&mut self, change: &Change) -> Result<(), String> {
        match change {
            Change::Name(name) => {
                let name = sanitize_name(name);
                if name.is_empty() {
                    return Err("Use letters or digits in the runner name".into());
                }
                self.name = name;
            }
            Change::AddFolder(folder) => {
                let folder = normalize_folder(folder)?;
                if !self.folders.contains(&folder) {
                    self.folders.push(folder);
                }
            }
            Change::RemoveFolder(folder) => {
                let folder = normalize_folder(folder)?;
                self.folders.retain(|existing| existing != &folder);
                if !self.new_project_folder_allowed() {
                    self.new_project_folder =
                        self.folders.first().cloned().unwrap_or_else(|| "~".into());
                }
            }
            Change::NewProjectFolder(folder) => {
                let previous =
                    std::mem::replace(&mut self.new_project_folder, normalize_folder(folder)?);
                if !self.new_project_folder_allowed() {
                    self.new_project_folder = previous;
                    return Err("Choose a folder inside one of the runner's folders".into());
                }
            }
            Change::ShareDisplay(value) => self.share_display = *value,
            Change::AllowTerminal(value) => self.allow_terminal = *value,
            Change::AllowPortals(value) => self.allow_portals = *value,
            Change::KeepAwake(value) => self.keep_awake = *value,
        }
        Ok(())
    }

    fn new_project_folder_allowed(&self) -> bool {
        let Some(target) = paths::expand(&self.new_project_folder) else {
            return false;
        };
        self.folders
            .iter()
            .filter_map(|folder| paths::expand(folder))
            .any(|folder| target.starts_with(folder))
    }
}

fn normalize_folder(folder: &str) -> Result<String, String> {
    let path = paths::expand(folder.trim()).ok_or("Choose an absolute folder")?;
    if path
        .components()
        .any(|part| matches!(part, std::path::Component::ParentDir))
    {
        return Err("Choose a folder without ..".into());
    }
    Ok(paths::abbreviate(&path))
}

#[derive(Clone, Debug, PartialEq)]
pub enum Change {
    Name(String),
    AddFolder(String),
    RemoveFolder(String),
    NewProjectFolder(String),
    ShareDisplay(bool),
    AllowTerminal(bool),
    AllowPortals(bool),
    KeepAwake(bool),
}

impl Change {
    /// Parses `key value` from the command line, as the app passes it.
    pub fn parse(key: &str, value: &str) -> Result<Self, String> {
        let flag = || match value {
            "true" | "on" => Ok(true),
            "false" | "off" => Ok(false),
            _ => Err(format!("{key} takes true or false")),
        };
        Ok(match key {
            "name" => Self::Name(value.into()),
            "add_folder" => Self::AddFolder(value.into()),
            "remove_folder" => Self::RemoveFolder(value.into()),
            "new_project_folder" => Self::NewProjectFolder(value.into()),
            "share_display" => Self::ShareDisplay(flag()?),
            "allow_terminal" => Self::AllowTerminal(flag()?),
            "allow_portals" => Self::AllowPortals(flag()?),
            "keep_awake" => Self::KeepAwake(flag()?),
            _ => return Err(format!("Unknown setting {key}")),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// An absolute folder on this platform: Windows needs a drive.
    fn abs(path: &str) -> String {
        if cfg!(windows) {
            format!("C:{path}")
        } else {
            path.into()
        }
    }

    #[test]
    fn names_read_like_host_names() {
        assert_eq!(
            sanitize_name("The Studio's MacBook Pro"),
            "the-studio-s-macbook-pro"
        );
        assert_eq!(sanitize_name("  --Mac__mini--  "), "mac-mini");
        assert_eq!(sanitize_name("🙂"), "");
        let long = sanitize_name(&format!("{}-x", "a".repeat(62)));
        assert_eq!(long, "a".repeat(62), "a cut never leaves a trailing hyphen");
    }

    #[test]
    fn the_new_project_folder_stays_inside_a_runner_folder() {
        let mut config = Config {
            folders: vec![abs("/srv/work")],
            new_project_folder: abs("/srv/work"),
            ..Config::default()
        };
        config
            .apply(&Change::NewProjectFolder(abs("/srv/work/new")))
            .unwrap();
        assert_eq!(config.new_project_folder, abs("/srv/work/new"));
        // A sibling that only shares a string prefix is outside.
        assert!(
            config
                .apply(&Change::NewProjectFolder(abs("/srv/workshop")))
                .is_err()
        );
        assert_eq!(config.new_project_folder, abs("/srv/work/new"));

        config.apply(&Change::AddFolder(abs("/opt/code"))).unwrap();
        config
            .apply(&Change::RemoveFolder(abs("/srv/work")))
            .unwrap();
        assert_eq!(config.folders, [abs("/opt/code")]);
        assert_eq!(
            config.new_project_folder,
            abs("/opt/code"),
            "removing its folder moves it to one that remains"
        );
    }

    #[test]
    fn folders_are_absolute_and_added_once() {
        let mut config = Config {
            folders: vec![],
            ..Config::default()
        };
        assert!(
            config
                .apply(&Change::AddFolder("relative/path".into()))
                .is_err()
        );
        assert!(config.apply(&Change::AddFolder(abs("/a/../etc"))).is_err());
        config.apply(&Change::AddFolder(abs("/a"))).unwrap();
        config.apply(&Change::AddFolder(abs("/a"))).unwrap();
        assert_eq!(config.folders, [abs("/a")]);
    }

    #[test]
    fn roots_drop_missing_and_nested_folders() {
        let base = std::env::temp_dir().join(format!("runner-roots-{}", std::process::id()));
        std::fs::create_dir_all(base.join("outer/inner")).unwrap();
        std::fs::create_dir_all(base.join("other")).unwrap();
        let path = |rest: &str| base.join(rest).display().to_string();
        let config = Config {
            folders: vec![
                path("outer/inner"),
                path("outer"),
                path("missing"),
                path("other"),
            ],
            ..Config::default()
        };
        let base = base.canonicalize().unwrap();
        assert_eq!(config.roots(), [base.join("other"), base.join("outer")]);
    }

    #[test]
    fn unreadable_settings_never_widen_access() {
        let state = std::env::temp_dir().join(format!("runner-serving-{}", std::process::id()));
        std::fs::create_dir_all(&state).unwrap();
        let file = paths::config_file(&state);
        std::fs::write(&file, r#"{"setting_from_a_newer_app":true}"#).unwrap();
        assert_eq!(
            Config::load_for_serving(&state),
            Config::locked(),
            "with nothing read before, nothing is shared"
        );
        assert!(Config::locked().folders.is_empty() && !Config::locked().allow_terminal);

        let narrowed = Config {
            folders: vec!["/srv/one".into()],
            new_project_folder: "/srv/one".into(),
            ..Config::default()
        };
        narrowed.save(&state).unwrap();
        assert_eq!(Config::load_for_serving(&state), narrowed);
        std::fs::write(&file, "{\"folders\": [").unwrap();
        assert_eq!(
            Config::load_for_serving(&state),
            narrowed,
            "a half-written file keeps the last settings"
        );
        std::fs::remove_file(&file).unwrap();
        assert_eq!(
            Config::load_for_serving(&state),
            narrowed,
            "a deleted file keeps the last settings too"
        );
    }

    #[test]
    fn a_fresh_runner_shares_only_a_projects_folder() {
        let config = Config::default();
        assert_eq!(
            config.folders,
            std::slice::from_ref(&config.new_project_folder)
        );
        assert_ne!(config.new_project_folder, "~");
        assert!(!config.allow_terminal && !config.share_display && !config.allow_portals);
    }

    #[test]
    fn command_line_changes() {
        assert_eq!(
            Change::parse("keep_awake", "on").unwrap(),
            Change::KeepAwake(true)
        );
        assert!(Change::parse("keep_awake", "yes").is_err());
        assert!(Change::parse("share_network", "true").is_err());
    }
}
