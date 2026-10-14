//! Keep the developer's own tuist_cargo_cache setup out of the integration tests.

use std::process::Command;

/// Hide the developer's own tuist_cargo_cache setup from the child: the settings it reads
/// from the environment, and on Unix the directories it reads a global
/// `config.toml` from. `test/test_helper/common_setup.bash` does the same for
/// the Bats suites. Cargo and rustup keep their real homes so the toolchain
/// still resolves.
///
/// Every test names the settings it needs after this, so a scrubbed variable
/// that a test cares about comes back with the test's own value.
pub fn isolate_host(command: &mut Command) -> &mut Command {
    scrub_settings(command);
    #[cfg(unix)]
    {
        let real_home = std::env::var_os("HOME").map(std::path::PathBuf::from);
        for (name, default) in [("CARGO_HOME", ".cargo"), ("RUSTUP_HOME", ".rustup")] {
            let value = std::env::var_os(name)
                .map(std::path::PathBuf::from)
                .or_else(|| real_home.as_ref().map(|home| home.join(default)));
            if let Some(value) = value {
                command.env(name, value);
            }
        }
        let home = isolated_home();
        command
            .env("HOME", home)
            .env("XDG_CACHE_HOME", home.join(".cache"))
            .env("XDG_CONFIG_HOME", home.join(".config"))
            .env("XDG_DATA_HOME", home.join(".local/share"));
    }
    command
}

/// A setting in the environment outranks the same setting in a configuration
/// file, so hiding the file is not enough on its own: an exported
/// `TUIST_CARGO_CACHE_TARGET_ROOT` moves managed targets out of a test's store exactly as
/// `[target] root` does. Drop the whole namespace rather than name the
/// settings that bite today, since the next one to bite would arrive silently.
///
/// `TUIST_CARGO_CACHE_LOG` stays. It only raises tuist_cargo_cache's own diagnostics, and running one of
/// these tests under it is how a developer sees what tuist_cargo_cache did. The extra stderr
/// it produces can fail a test that asserts on stderr, which is a deliberate
/// act rather than something the machine decides.
///
/// This applies on every platform. Windows resolves the configuration
/// directory through known-folder APIs rather than the environment, so a
/// global `config.toml` on a Windows developer's machine is still visible
/// here; isolating it needs a way to point tuist_cargo_cache at a different file.
fn scrub_settings(command: &mut Command) {
    for (name, _) in std::env::vars_os() {
        let key = name.to_string_lossy().to_ascii_uppercase();
        if key.starts_with("TUIST_CARGO_CACHE_") && key != "TUIST_CARGO_CACHE_LOG" {
            command.env_remove(&name);
        }
    }
}

/// Shared by every test in the run, as the real home was. No test writes tuist_cargo_cache
/// configuration, so a global configuration file never exists here.
#[cfg(unix)]
fn isolated_home() -> &'static std::path::Path {
    static HOME: std::sync::OnceLock<std::path::PathBuf> = std::sync::OnceLock::new();
    HOME.get_or_init(|| {
        let home = std::path::Path::new(env!("CARGO_TARGET_TMPDIR")).join("isolated-home");
        std::fs::create_dir_all(&home).unwrap();
        home
    })
}
