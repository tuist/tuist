//! Real Cargo is the oracle for alias expansion. A wrapper can fail metadata
//! without changing Cargo's configuration loading, listing, or execution.
#![cfg(unix)]

use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

struct Fixture {
    _temp: tempfile::TempDir,
    root: PathBuf,
    outside: PathBuf,
    cargo: PathBuf,
}

impl Fixture {
    fn new() -> Self {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().canonicalize().unwrap();
        let outside = root.join("outside");
        std::fs::create_dir_all(outside.join(".cargo")).unwrap();
        std::fs::create_dir_all(root.join("bin")).unwrap();
        let cargo = root.join("bin/cargo");
        executable(
            &cargo,
            r#"#!/bin/sh
for arg do
  if [ "$arg" = metadata ] && [ "$REJECT_METADATA" = 1 ]; then exit 1; fi
done
exec "$REAL_CARGO" "$@"
"#,
        );
        executable(
            &root.join("bin/cargo-probe"),
            r#"#!/bin/sh
printf '%s\n' "$@"
touch "$EXTERNAL_MARKER"
"#,
        );
        Self {
            _temp: temp,
            root,
            outside,
            cargo,
        }
    }

    fn config(&self, text: &str) {
        std::fs::write(self.outside.join(".cargo/config.toml"), text).unwrap();
    }

    fn project(&self, name: &str) -> PathBuf {
        let project = self.root.join(name);
        std::fs::create_dir_all(project.join("src")).unwrap();
        std::fs::write(
            project.join("Cargo.toml"),
            "[package]\nname='alias-fixture'\nversion='0.0.0'\nedition='2021'\n",
        )
        .unwrap();
        std::fs::write(project.join("src/main.rs"), "fn main() {}\n").unwrap();
        // Successful recovery must actually manage the build.
        std::fs::write(
            project.join("build.rs"),
            r#"fn main() {
    assert!(std::env::var_os("TUIST_CARGO_CACHE_SOCKET").is_some(), "unmanaged build");
}
"#,
        )
        .unwrap();
        project
    }

    fn command(&self, shim: bool) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_tuist-cargo-cache-model"));
        let real = std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into());
        let real = which::which(real).unwrap();
        let path = std::env::join_paths(
            std::iter::once(self.root.join("bin"))
                .chain(std::env::split_paths(&std::env::var_os("PATH").unwrap())),
        )
        .unwrap();
        for (key, _) in std::env::vars_os() {
            let name = key.to_string_lossy();
            if name.starts_with("TUIST_CARGO_CACHE_")
                || name.starts_with("CARGO_")
                || name.starts_with("RUSTC_")
            {
                command.env_remove(key);
            }
        }
        command
            .current_dir(&self.outside)
            .env("PATH", path)
            .env("REAL_CARGO", real)
            .env("CARGO", &self.cargo)
            .env("CARGO_HOME", self.root.join("cargo-home"))
            .env("TUIST_CARGO_CACHE_DIR", self.root.join("cache"))
            .env("TUIST_CARGO_CACHE_TARGET_ROOT", self.root.join("targets"))
            .env("TUIST_CARGO_CACHE_GC_AUTO", "0")
            .env("TUIST_CARGO_CACHE_INCREMENTAL", "0")
            .env("TUIST_CARGO_CACHE_LINKER", "system")
            .env("TUIST_CARGO_CACHE_SUMMARY", "off")
            .env("EXTERNAL_MARKER", self.root.join("external-ran"));
        if shim {
            command.env("TUIST_CARGO_CACHE_CARGO_SHIM_MODE", "1");
        }
        command
    }
}

fn executable(path: &Path, text: &str) {
    std::fs::write(path, text).unwrap();
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
}

fn rejected(output: Output) {
    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("could not verify Cargo build storage"),
        "{stderr}"
    );
    assert!(!stderr.contains("Compiling"), "{stderr}");
}

fn succeeded(output: Output) -> String {
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(output.status.success(), "{stderr}");
    String::from_utf8(output.stdout).unwrap()
}

fn array(words: &[&str]) -> String {
    toml::Value::Array(
        words
            .iter()
            .map(|word| toml::Value::String((*word).into()))
            .collect(),
    )
    .to_string()
}

#[test]
fn path_aliases_preserve_boundaries_and_fail_closed() {
    let f = Fixture::new();
    for name in [
        "ordinary",
        "space suffix",
        "space -suffix",
        "space --help",
        "tab\tsuffix",
    ] {
        let project = f.project(name);
        let path = project.to_str().unwrap();
        for attached in [false, true] {
            let attached_path = format!("--path={path}");
            let words = if attached {
                vec!["install", &attached_path]
            } else {
                vec!["install", "--path", path]
            };
            f.config(&format!("[alias]\ni={}\nchain='i'\n", array(&words)));
            for shim in [false, true] {
                rejected(
                    f.command(shim)
                        .args(["chain", "--offline"])
                        .env("REJECT_METADATA", "1")
                        .output()
                        .unwrap(),
                );
            }
        }
        assert!(!project.join("target").exists());
    }
}

#[test]
fn real_path_installs_are_managed_even_with_spaces_and_dashes() {
    let f = Fixture::new();
    let project = f.project("package -suffix");
    f.config(&format!(
        "[alias]\ni={}\n",
        array(&["install", "--path", project.to_str().unwrap()])
    ));
    for shim in [false, true] {
        succeeded(
            f.command(shim)
                .args(["i", "--offline", "--root"])
                .arg(f.root.join(format!("installed-{shim}")))
                .output()
                .unwrap(),
        );
        assert!(
            f.root
                .join(format!("installed-{shim}/bin/alias-fixture"))
                .is_file()
        );
    }
}

#[test]
fn outside_commands_and_external_aliases_reach_real_cargo() {
    let f = Fixture::new();
    let template = f.project("template -suffix");
    f.config(&format!(
        "[alias]\nexternal={}\nchain='external'\n",
        array(&["probe", "--path", template.to_str().unwrap(), "ripgrep"])
    ));
    for shim in [false, true] {
        succeeded(
            f.command(shim)
                .args(["probe", "--manifest-path"])
                .arg(template.join("Cargo.toml"))
                .output()
                .unwrap(),
        );
        for command in ["probe", "chain"] {
            let stdout = succeeded(f.command(shim).arg(command).output().unwrap());
            assert!(stdout.starts_with("probe\n"));
            if command == "chain" {
                assert!(stdout.contains(template.to_str().unwrap()));
                assert!(stdout.ends_with("ripgrep\n"));
            }
        }
        let output = f.command(shim).arg("build").output().unwrap();
        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(stderr.contains("could not find `Cargo.toml`"), "{stderr}");
        assert!(!stderr.contains("could not verify"), "{stderr}");
        assert!(!stderr.contains("without the cache"), "{stderr}");
    }
}

#[test]
fn external_command_without_a_manifest_says_it_runs_uncached() {
    let f = Fixture::new();
    for shim in [false, true] {
        let output = f.command(shim).arg("probe").output().unwrap();
        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(output.status.success(), "{stderr}");
        assert!(
            stderr.contains("no Cargo manifest in scope; running `cargo probe` without the cache"),
            "{stderr}"
        );
        // Cargo's global options precede the subcommand only through the shim.
        if shim {
            // The note names the subcommand, not the value of a global option.
            let output = f
                .command(shim)
                .args(["--config", "build.jobs=1", "probe"])
                .output()
                .unwrap();
            let stderr = String::from_utf8_lossy(&output.stderr);
            assert!(output.status.success(), "{stderr}");
            assert!(stderr.contains("running `cargo probe` without"), "{stderr}");
            // A quiet run stays quiet.
            let output = f.command(shim).args(["--quiet", "probe"]).output().unwrap();
            let stderr = String::from_utf8_lossy(&output.stderr);
            assert!(output.status.success(), "{stderr}");
            assert!(!stderr.contains("without the cache"), "{stderr}");
        }
        let output = f.command(shim).args(["--version"]).output().unwrap();
        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(!stderr.contains("without the cache"), "{stderr}");
    }
}

#[test]
fn environment_and_hierarchical_aliases_keep_cargo_precedence() {
    let f = Fixture::new();
    let project = f.project("package -suffix");
    let install = array(&["install", "--path", project.to_str().unwrap()]);
    // The lower-priority array contributes its command, the local one its path.
    std::fs::create_dir_all(f.root.join(".cargo")).unwrap();
    std::fs::write(
        f.root.join(".cargo/config.toml"),
        "[alias]\ni=['install']\n",
    )
    .unwrap();
    f.config(&format!(
        "[alias]\ni={}\n",
        array(&["--path", project.to_str().unwrap()])
    ));
    for shim in [false, true] {
        rejected(
            f.command(shim)
                .arg("i")
                .env("REJECT_METADATA", "1")
                .output()
                .unwrap(),
        );
        rejected(
            f.command(shim)
                .env("REJECT_METADATA", "1")
                .arg("i")
                .env("CARGO_ALIAS_I", "probe")
                .output()
                .unwrap(),
        );
        rejected(
            f.command(shim)
                .args(["env-install", "--path"])
                .arg(&project)
                .env("CARGO_ALIAS_ENV_INSTALL", "install")
                .env("REJECT_METADATA", "1")
                .output()
                .unwrap(),
        );
    }
    // Legacy config wins over config.toml, including for built-in shorthand.
    std::fs::write(
        f.outside.join(".cargo/config"),
        format!("[alias]\nb={install}\n"),
    )
    .unwrap();
    for shim in [false, true] {
        rejected(
            f.command(shim)
                .arg("b")
                .env("REJECT_METADATA", "1")
                .output()
                .unwrap(),
        );
    }
}

#[test]
fn unsupported_configuration_and_recursive_aliases_are_not_guessed() {
    let f = Fixture::new();
    for config in [
        "[alias]\nx='y'\ny='x'\n",
        "[alias]\nx=['-Zscript','example.rs']\n",
        "[alias]\nx=['build','-C','somewhere']\n",
        "[alias]\nx=['--config','alias.y=\"probe\"','y']\n",
    ] {
        f.config(config);
        for shim in [false, true] {
            rejected(
                f.command(shim)
                    .arg("x")
                    .env("REJECT_METADATA", "1")
                    .output()
                    .unwrap(),
            );
        }
    }
    f.config("[alias]\nx='probe'\n");
    rejected(
        f.command(true)
            .args(["--config", "term.quiet=true", "x"])
            .env("REJECT_METADATA", "1")
            .output()
            .unwrap(),
    );
    assert!(!f.root.join("external-ran").exists());
}

/// An `include` is configuration this cannot read, but only aliases can come
/// out of one, and Cargo's own listing reports the aliases it honours. So a
/// command Cargo knows as an alias is refused rather than guessed, while a
/// command that is no alias at all is untouched: an include cannot turn
/// `cargo probe` into something else, and refusing it would put back the very
/// failure outside a project that this change exists to remove.
#[test]
fn configuration_includes_refuse_aliases_without_refusing_everything() {
    let f = Fixture::new();
    let include = |text: &str| {
        std::fs::write(f.outside.join(".cargo/extra.toml"), text).unwrap();
        f.config("include=['extra.toml']\n");
    };
    for shim in [false, true] {
        // Cargo honours the alias and says so in its listing, so it is refused
        // rather than read from configuration this cannot follow.
        include("[alias]\nx='probe'\n");
        rejected(
            f.command(shim)
                .arg("x")
                .env("REJECT_METADATA", "1")
                .output()
                .unwrap(),
        );
        assert!(!f.root.join("external-ran").exists());
        // The same configuration must not cost an ordinary external command
        // its passthrough.
        let stdout = succeeded(
            f.command(shim)
                .arg("probe")
                .env("REJECT_METADATA", "1")
                .output()
                .unwrap(),
        );
        assert!(stdout.starts_with("probe\n"), "{stdout}");
        std::fs::remove_file(f.root.join("external-ran")).unwrap();
    }
    // An include Cargo cannot load leaves it honouring no alias at all, and
    // its own diagnostic is the one worth showing. Nothing is built either way.
    f.config("include=['missing.toml']\n[alias]\nx='probe'\n");
    for shim in [false, true] {
        let output = f
            .command(shim)
            .arg("x")
            .env("REJECT_METADATA", "1")
            .output()
            .unwrap();
        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(!stderr.contains("could not verify"), "{stderr}");
        assert!(!stderr.contains("Compiling"), "{stderr}");
        assert!(!f.root.join("external-ran").exists(), "{stderr}");
    }
}

#[test]
fn manifest_aliases_global_flags_and_builtin_shadowing_are_checked() {
    let f = Fixture::new();
    let project = f.project("manifest --help");
    let manifest = project.join("Cargo.toml");
    for expansion in [
        array(&["build", "--manifest-path", manifest.to_str().unwrap()]),
        array(&[
            "--offline",
            "build",
            "--manifest-path",
            manifest.to_str().unwrap(),
        ]),
        array(&["build", &format!("--manifest-path={}", manifest.display())]),
    ] {
        f.config(&format!("[alias]\nx={expansion}\nbuild='probe'\n"));
        for shim in [false, true] {
            rejected(
                f.command(shim)
                    .arg("x")
                    .env("REJECT_METADATA", "1")
                    .output()
                    .unwrap(),
            );
        }
    }
    assert!(!f.root.join("external-ran").exists());
    assert!(!project.join("target").exists());
}

#[test]
fn cargo_home_and_environment_string_aliases_are_resolved() {
    let f = Fixture::new();
    std::fs::create_dir_all(f.root.join("cargo-home")).unwrap();
    std::fs::write(
        f.root.join("cargo-home/config.toml"),
        "[alias]\nx='build'\n",
    )
    .unwrap();
    for shim in [false, true] {
        // An environment string replaces a file string (but appends to an
        // array, covered separately). Whitespace splitting matches Cargo.
        succeeded(
            f.command(shim)
                .arg("x")
                .env("CARGO_ALIAS_X", "probe\t--example")
                .output()
                .unwrap(),
        );
    }
    let project = f.project("project");
    std::fs::write(
        f.root.join("cargo-home/config.toml"),
        format!(
            "[alias]\nx={}\n",
            array(&["install", "--path", project.to_str().unwrap()])
        ),
    )
    .unwrap();
    for shim in [false, true] {
        rejected(
            f.command(shim)
                .arg("x")
                .env("REJECT_METADATA", "1")
                .output()
                .unwrap(),
        );
    }
}

#[test]
fn external_flags_cannot_hide_a_project_after_failed_metadata() {
    let f = Fixture::new();
    let project = f.project("project");
    for shim in [false, true] {
        rejected(
            f.command(shim)
                .current_dir(&project)
                .args(["probe", "--manifest-path", "missing/Cargo.toml"])
                .env("REJECT_METADATA", "1")
                .output()
                .unwrap(),
        );
    }
    assert!(!f.root.join("external-ran").exists());
}
