//! Installs the daemon as the signed-in user's background service: a launchd
//! agent on macOS, a systemd user unit on Linux and a logon task on Windows.
//! Each starts the daemon at login and again if it exits.
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::paths;

pub const LABEL: &str = "dev.tuist.guild.runner";

#[derive(Debug, PartialEq)]
pub struct Installation {
    /// The service definition exists.
    pub installed: bool,
    /// The service manager has it loaded (macOS, Linux) or scheduled (Windows).
    pub loaded: bool,
    /// The executable the installed service starts.
    pub program: Option<PathBuf>,
}

pub fn definition_path() -> Option<PathBuf> {
    let home = paths::home()?;
    if cfg!(target_os = "macos") {
        Some(home.join(format!("Library/LaunchAgents/{LABEL}.plist")))
    } else if cfg!(windows) {
        None
    } else {
        Some(
            std::env::var_os("XDG_CONFIG_HOME")
                .map(PathBuf::from)
                .filter(|path| path.is_absolute())
                .unwrap_or_else(|| home.join(".config"))
                .join("systemd/user/luft-runner.service"),
        )
    }
}

fn xml_escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

/// The launchd agent: started at login, restarted when it exits, with its
/// output in the runner log. `ProcessType` `Interactive` keeps it from being
/// throttled like a background job, since threads wait on it.
pub fn launchd_plist(program: &Path, log: &Path) -> String {
    let program = xml_escape(&program.display().to_string());
    let log = xml_escape(&log.display().to_string());
    format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>{LABEL}</string>
    <key>ProgramArguments</key><array><string>{program}</string><string>run</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>ProcessType</key><string>Interactive</string>
    <key>StandardOutPath</key><string>{log}</string>
    <key>StandardErrorPath</key><string>{log}</string>
</dict>
</plist>
"#
    )
}

pub fn systemd_unit(program: &Path) -> String {
    // systemd splits ExecStart on spaces; quote the path and escape what quoting keeps.
    let program = program
        .display()
        .to_string()
        .replace('\\', "\\\\")
        .replace('"', "\\\"");
    format!(
        "[Unit]\nDescription=Luft runner\n\n[Service]\nExecStart=\"{program}\" run\nRestart=always\nRestartSec=10\n\n[Install]\nWantedBy=default.target\n"
    )
}

/// Reads the program back out of an installed definition, so the app can tell
/// whether the service still points at this copy of the app.
pub fn installed_program(definition: &str) -> Option<PathBuf> {
    if let Some(start) = definition.find("<key>ProgramArguments</key><array><string>") {
        let rest = &definition[start + "<key>ProgramArguments</key><array><string>".len()..];
        let value = &rest[..rest.find("</string>")?];
        let value = value
            .replace("&quot;", "\"")
            .replace("&gt;", ">")
            .replace("&lt;", "<")
            .replace("&amp;", "&");
        return Some(PathBuf::from(value));
    }
    let line = definition
        .lines()
        .find_map(|line| line.strip_prefix("ExecStart=\""))?;
    let end = line.rfind("\" run")?;
    Some(PathBuf::from(
        line[..end].replace("\\\"", "\"").replace("\\\\", "\\"),
    ))
}

#[cfg(unix)]
fn user_id() -> u32 {
    unsafe extern "C" {
        fn getuid() -> u32;
    }
    unsafe { getuid() }
}

fn run(program: &str, args: &[&str]) -> Result<(), String> {
    let output = Command::new(program)
        .args(args)
        .output()
        .map_err(|error| format!("Could not run {program}: {error}"))?;
    if output.status.success() {
        Ok(())
    } else {
        let message = String::from_utf8_lossy(&output.stderr);
        Err(format!(
            "{program} {} failed: {}",
            args.first().unwrap_or(&""),
            message.trim()
        ))
    }
}

fn succeeds(program: &str, args: &[&str]) -> bool {
    Command::new(program)
        .args(args)
        .output()
        .is_ok_and(|output| output.status.success())
}

const WINDOWS_TASK: &str = "Luft Runner";

pub fn status() -> Installation {
    if cfg!(windows) {
        let loaded = succeeds("schtasks", &["/Query", "/TN", WINDOWS_TASK]);
        return Installation {
            installed: loaded,
            loaded,
            program: None,
        };
    }
    let Some(definition) = definition_path() else {
        return Installation {
            installed: false,
            loaded: false,
            program: None,
        };
    };
    let program = std::fs::read_to_string(&definition)
        .ok()
        .and_then(|contents| installed_program(&contents));
    #[cfg(unix)]
    let loaded = if cfg!(target_os = "macos") {
        succeeds(
            "launchctl",
            &["print", &format!("gui/{}/{LABEL}", user_id())],
        )
    } else {
        succeeds(
            "systemctl",
            &["--user", "is-active", "--quiet", "luft-runner.service"],
        )
    };
    #[cfg(not(unix))]
    let loaded = false;
    Installation {
        installed: definition.exists(),
        loaded,
        program,
    }
}

/// Installs or reinstalls the service for `program` and starts it now.
pub fn install(program: &Path, state: &Path) -> Result<(), String> {
    if !program.is_absolute() {
        return Err("The runner program must be an absolute path".into());
    }
    if cfg!(windows) {
        let command = format!("\"{}\" run", program.display());
        run(
            "schtasks",
            &[
                "/Create",
                "/F",
                "/SC",
                "ONLOGON",
                "/RL",
                "LIMITED",
                "/TN",
                WINDOWS_TASK,
                "/TR",
                &command,
            ],
        )?;
        return run("schtasks", &["/Run", "/TN", WINDOWS_TASK]);
    }
    let definition = definition_path().ok_or("Could not find the home folder")?;
    #[cfg(unix)]
    {
        if cfg!(target_os = "macos") {
            let log = paths::log_file(state);
            if let Some(parent) = log.parent() {
                std::fs::create_dir_all(parent).map_err(|error| error.to_string())?;
            }
            let domain = format!("gui/{}", user_id());
            // A loaded agent keeps its old definition until it is booted out.
            let _ = run("launchctl", &["bootout", &format!("{domain}/{LABEL}")]);
            paths::write_atomically(&definition, launchd_plist(program, &log).as_bytes())
                .map_err(|error| format!("Could not write the launch agent: {error}"))?;
            return run(
                "launchctl",
                &["bootstrap", &domain, &definition.display().to_string()],
            );
        }
        paths::write_atomically(&definition, systemd_unit(program).as_bytes())
            .map_err(|error| format!("Could not write the systemd unit: {error}"))?;
        run("systemctl", &["--user", "daemon-reload"])?;
        run("systemctl", &["--user", "enable", "luft-runner.service"])?;
        run("systemctl", &["--user", "restart", "luft-runner.service"])
    }
    #[cfg(not(unix))]
    {
        let _ = (definition, state);
        Err("Unsupported platform".into())
    }
}

/// Stops the service and removes its definition. Configuration stays, so
/// turning the runner on again keeps its folders and name.
pub fn uninstall() -> Result<(), String> {
    if cfg!(windows) {
        let _ = run("schtasks", &["/End", "/TN", WINDOWS_TASK]);
        return if succeeds("schtasks", &["/Query", "/TN", WINDOWS_TASK]) {
            run("schtasks", &["/Delete", "/F", "/TN", WINDOWS_TASK])
        } else {
            Ok(())
        };
    }
    let definition = definition_path().ok_or("Could not find the home folder")?;
    #[cfg(unix)]
    {
        if cfg!(target_os = "macos") {
            let _ = run(
                "launchctl",
                &["bootout", &format!("gui/{}/{LABEL}", user_id())],
            );
        } else {
            let _ = run(
                "systemctl",
                &["--user", "disable", "--now", "luft-runner.service"],
            );
        }
    }
    match std::fs::remove_file(&definition) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(format!("Could not remove the service definition: {error}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn launchd_agent_round_trips_the_program_path() {
        let program = Path::new("/Applications/Luft & Co <dev>.app/Contents/MacOS/luft-runner");
        let plist = launchd_plist(program, Path::new("/Users/me/Library/Logs/Luft/runner.log"));
        assert!(
            plist.contains("Luft &amp; Co &lt;dev&gt;.app"),
            "the path is escaped as XML"
        );
        assert!(plist.contains("<string>run</string>"));
        assert!(plist.contains("<key>KeepAlive</key><true/>"));
        assert_eq!(installed_program(&plist).as_deref(), Some(program));
    }

    #[test]
    fn systemd_unit_round_trips_a_path_with_spaces_and_quotes() {
        let program = Path::new("/opt/Tuist \"Luft\"/luft-runner");
        let unit = systemd_unit(program);
        assert!(unit.contains(r#"ExecStart="/opt/Tuist \"Luft\"/luft-runner" run"#));
        assert_eq!(installed_program(&unit).as_deref(), Some(program));
    }
}
