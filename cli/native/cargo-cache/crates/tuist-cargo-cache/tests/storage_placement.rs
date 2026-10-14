//! Exercise startup rejection without requiring an NFS mount or mount privileges.
#![cfg(all(target_os = "linux", target_env = "gnu"))]

use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::OnceLock;

/// Only the test process tree sees this statfs interposer. Actual file I/O
/// remains local; the designated directory reports the NFS filesystem type.
fn interposer() -> &'static Path {
    static LIBRARY: OnceLock<(tempfile::TempDir, PathBuf)> = OnceLock::new();
    &LIBRARY
        .get_or_init(|| {
            let directory = tempfile::tempdir().unwrap();
            let source = directory.path().join("statfs.c");
            let library = directory.path().join("statfs.so");
            std::fs::write(
                &source,
                r#"
#define _GNU_SOURCE
#include <sys/vfs.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
int statfs(const char *path, struct statfs *buf) {
    int (*real_statfs)(const char *, struct statfs *) = dlsym(RTLD_NEXT, "statfs");
    int result = real_statfs(path, buf);
    const char *root = getenv("TEST_NFS_ROOT");
    if (result == 0 && root && strncmp(path, root, strlen(root)) == 0
        && (path[strlen(root)] == '/' || path[strlen(root)] == '\0')) {
        buf->f_type = 0x6969;
    }
    return result;
}
"#,
            )
            .unwrap();
            let output = Command::new("cc")
                .args(["-shared", "-fPIC"])
                .arg(&source)
                .arg("-o")
                .arg(&library)
                .arg("-ldl")
                .output()
                .unwrap();
            assert!(
                output.status.success(),
                "{}",
                String::from_utf8_lossy(&output.stderr)
            );
            (directory, library)
        })
        .1
}

struct Fixture {
    _directory: tempfile::TempDir,
    root: PathBuf,
    nfs: PathBuf,
    project: PathBuf,
}

impl Fixture {
    fn new() -> Self {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path().canonicalize().unwrap();
        let nfs = root.join("nfs");
        let project = root.join("project");
        std::fs::create_dir(&nfs).unwrap();
        write_project(&project);
        Self {
            _directory: directory,
            root,
            nfs,
            project,
        }
    }

    fn command(&self) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_tuist-cargo-cache-model"));
        command
            .current_dir(&self.project)
            .env("LD_PRELOAD", interposer())
            .env("TEST_NFS_ROOT", &self.nfs)
            .env("TUIST_CARGO_CACHE_DIR", self.root.join("cache"))
            .env("TUIST_CARGO_CACHE_TARGET_ROOT", self.root.join("targets"))
            .env("TUIST_CARGO_CACHE_TARGET_VIEWS", "1")
            .env("TUIST_CARGO_CACHE_GC_AUTO", "0")
            .env("TUIST_CARGO_CACHE_INCREMENTAL", "0")
            .env("TUIST_CARGO_CACHE_SUMMARY", "off")
            .env_remove("CARGO_TARGET_DIR")
            .env_remove("CARGO_BUILD_TARGET_DIR")
            .env_remove("CARGO_BUILD_BUILD_DIR")
            .env_remove("TUIST_CARGO_CACHE_DISABLE")
            .env_remove("TUIST_CARGO_CACHE_SOCKET")
            .stdin(Stdio::null());
        command
    }
}

fn write_project(project: &Path) {
    std::fs::create_dir_all(project.join("src")).unwrap();
    std::fs::write(
        project.join("Cargo.toml"),
        "[package]\nname = \"storage-fixture\"\nversion = \"0.0.0\"\nedition = \"2021\"\n",
    )
    .unwrap();
    std::fs::write(
        project.join("src/lib.rs"),
        "pub fn answer() -> u32 { 42 }\n",
    )
    .unwrap();
}

#[test]
fn rejects_tools_symlink_before_initializing_storage() {
    let fixture = Fixture::new();
    let cache = fixture.root.join("cache");
    std::fs::create_dir(&cache).unwrap();
    std::os::unix::fs::symlink(&fixture.nfs, cache.join("tools")).unwrap();
    rejected(
        fixture
            .command()
            .args(["build", "--offline"])
            .output()
            .unwrap(),
        &cache.join("tools"),
        "TUIST_CARGO_CACHE_DIR",
    );
    assert!(!cache.join("actions").exists());
}

#[test]
fn rejects_existing_nfs_target_without_mutating_it() {
    let fixture = Fixture::new();
    let project = fixture.nfs.join("source");
    write_project(&project);
    let target = project.join("target");
    std::fs::create_dir(&target).unwrap();
    std::fs::write(target.join("keep"), "existing outputs").unwrap();
    rejected(
        fixture
            .command()
            .current_dir(&project)
            .args(["build", "--offline"])
            .output()
            .unwrap(),
        &target,
        "CARGO_TARGET_DIR",
    );
    assert_eq!(
        std::fs::read_to_string(target.join("keep")).unwrap(),
        "existing outputs"
    );
    assert!(!fixture.root.join("targets").exists());
}

#[test]
fn rejects_nested_managed_linker_storage() {
    for (selector, child) in [("mold@2.42.0", "mold"), ("rust-lld", "rust-lld")] {
        let fixture = Fixture::new();
        let tools = fixture.root.join("cache/tools");
        std::fs::create_dir_all(&tools).unwrap();
        std::os::unix::fs::symlink(&fixture.nfs, tools.join(child)).unwrap();
        let output = fixture
            .command()
            .env("TUIST_CARGO_CACHE_LINKER", selector)
            .args(["build", "--offline"])
            .output()
            .unwrap();
        rejected(output, &tools.join(child), "TUIST_CARGO_CACHE_DIR");
        assert_eq!(std::fs::read_dir(&fixture.nfs).unwrap().count(), 0);
    }
}

#[test]
fn failed_metadata_never_launches_a_build() {
    use std::os::unix::fs::PermissionsExt;
    for shim in [false, true] {
        for configured in [false, true] {
            for subcommand in ["build", "build-alias"] {
                let fixture = Fixture::new();
                let bin = fixture.root.join("bin");
                std::fs::create_dir(&bin).unwrap();
                let cargo = bin.join("cargo");
                std::fs::write(&cargo, "#!/bin/sh\ncase \" $* \" in *' metadata '*) exit 1;; *' --list '*) printf 'Installed Commands:\\n    build\\n    build-alias    alias: build\\n'; exit 0;; esac\ntouch \"$TEST_BUILD_MARKER\"\n").unwrap();
                std::fs::set_permissions(&cargo, std::fs::Permissions::from_mode(0o755)).unwrap();
                let marker = fixture.root.join("build-ran");
                let mut command = fixture.command();
                command.arg(subcommand);
                let inherited_path = std::env::var_os("PATH").unwrap();
                let paths = std::iter::once(bin).chain(std::env::split_paths(&inherited_path));
                command
                    .env("PATH", std::env::join_paths(paths).unwrap())
                    .env("CARGO", &cargo)
                    .env("TEST_BUILD_MARKER", &marker);
                if shim {
                    command.env("TUIST_CARGO_CACHE_CARGO_SHIM_MODE", "1");
                }
                if configured {
                    command.args([
                        "--config",
                        &format!("build.build-dir={:?}", fixture.nfs.join("intermediates")),
                    ]);
                } else {
                    command.env("CARGO_BUILD_BUILD_DIR", fixture.nfs.join("intermediates"));
                }
                let output = command.output().unwrap();
                let stderr = String::from_utf8_lossy(&output.stderr);
                assert!(!output.status.success(), "{stderr}");
                assert!(
                    stderr.contains("could not verify Cargo build storage"),
                    "{stderr}"
                );
                assert!(!marker.exists());
                assert!(!fixture.project.join("target").exists());
                assert!(!fixture.root.join("cache/tools").exists());
            }
        }
    }
}

/// Outside a project there is no package to compile and no target directory to
/// place, so a failed metadata probe reports only that Cargo has nothing to do
/// here. `cargo binstall` and friends must still reach Cargo, while the same
/// invocation inside a project stays behind the storage check.
#[test]
fn an_invocation_outside_a_project_still_reaches_cargo() {
    use std::os::unix::fs::PermissionsExt;
    let fixture = Fixture::new();
    let bin = fixture.root.join("bin");
    std::fs::create_dir(&bin).unwrap();
    let cargo = bin.join("cargo");
    std::fs::write(&cargo, "#!/bin/sh\ncase \" $* \" in *' metadata '*) exit 1;; *' --list '*) printf 'Installed Commands:\\n    binstall    Install a Rust binary\\n    build    Compile\\n'; exit 0;; esac\ntouch \"$TEST_PASSTHROUGH_MARKER\"\n").unwrap();
    std::fs::set_permissions(&cargo, std::fs::Permissions::from_mode(0o755)).unwrap();
    let outside = fixture.root.join("outside");
    std::fs::create_dir(&outside).unwrap();
    // A subcommand external to Cargo spends `--path` on its own argument, as
    // `cargo generate --path` does on a local template. That the template is
    // itself a package must not read as a path install and cost the
    // passthrough, since only a real install compiles what `--path` names.
    let template = fixture.root.join("template");
    std::fs::create_dir(&template).unwrap();
    write_project(&template);
    let template = template.to_string_lossy().into_owned();
    // A toolchain selector and a configuration override reach a different
    // Cargo and a different configuration, but neither can put a manifest
    // where the filesystem has none, so they do not cost the passthrough.
    // Only the shim forwards a bare `--config`; tuist_cargo_cache's own CLI rejects it.
    for shim in [false, true] {
        let mut globals: Vec<&[&str]> = vec![&[], &["+stable"]];
        if shim {
            globals.push(&["--config", "term.quiet=false"]);
        }
        for (index, global) in globals.iter().enumerate() {
            for (directory, reaches_cargo) in [(&outside, true), (&fixture.project, false)] {
                let marker = fixture
                    .root
                    .join(format!("passthrough-{shim}-{index}-{reaches_cargo}"));
                let mut command = fixture.command();
                let inherited_path = std::env::var_os("PATH").unwrap();
                let paths =
                    std::iter::once(bin.clone()).chain(std::env::split_paths(&inherited_path));
                command
                    .args(*global)
                    .args(["binstall", "--path", &template])
                    .current_dir(directory)
                    .env("PATH", std::env::join_paths(paths).unwrap())
                    .env("CARGO", &cargo)
                    .env("TEST_PASSTHROUGH_MARKER", &marker);
                if shim {
                    command.env("TUIST_CARGO_CACHE_CARGO_SHIM_MODE", "1");
                }
                let output = command.output().unwrap();
                let stderr = String::from_utf8_lossy(&output.stderr);
                let where_ = format!("{global:?} in {}", directory.display());
                assert_eq!(output.status.success(), reaches_cargo, "{where_}: {stderr}");
                assert_eq!(
                    !stderr.contains("could not verify Cargo build storage"),
                    reaches_cargo,
                    "{where_}: {stderr}"
                );
                assert_eq!(marker.exists(), reaches_cargo, "{where_}: {stderr}");
            }
        }
    }
}

/// A path install compiles a local package, so it stays behind the storage
/// check however its subcommand is spelled and wherever its `--path` sits.
/// Only Cargo can expand a user's alias, so neither the manifest-less
/// passthrough nor the alias table may read one as the registry install that
/// a bare `install` would be. The third case puts `--path` inside the alias
/// body, where the command line alone does not show it at all.
#[test]
fn an_aliased_path_install_is_still_checked() {
    use std::os::unix::fs::PermissionsExt;
    let fixture = Fixture::new();
    let bin = fixture.root.join("bin");
    std::fs::create_dir(&bin).unwrap();
    let cargo = bin.join("cargo");
    std::fs::write(&cargo, "#!/bin/sh\ncase \" $* \" in *' metadata '*) exit 1;; *' --list '*) printf 'Installed Commands:\\n    i    alias: %s\\n    install    Install a Rust binary\\n' \"$TEST_ALIAS_BODY\"; exit 0;; esac\ntouch \"$TEST_INSTALL_MARKER\"\n").unwrap();
    std::fs::set_permissions(&cargo, std::fs::Permissions::from_mode(0o755)).unwrap();
    let outside = fixture.root.join("outside-install");
    std::fs::create_dir(&outside).unwrap();
    let project = fixture.project.to_string_lossy().into_owned();
    let embedded = format!("install --path {project}");
    // Array values retain their boundaries even when a space is followed
    // by a dash. Failed metadata must never turn either path into passthrough.
    let spaced_root = fixture.root.join("spaced project");
    std::fs::create_dir(&spaced_root).unwrap();
    write_project(&spaced_root);
    let spaced = format!("install --path {}", spaced_root.display());
    // An alias body may lead with global options. Those name no command and
    // appear in no listing, so reading the body's first word would call the
    // whole invocation unknown and wave through the install behind it.
    let prefixed = format!("--offline install --path {project}");
    // A directory option decides where the manifest search starts, so a value
    // the listing split is as unreadable there as in a path option.
    let directed = format!("build -C {} --offline", spaced_root.display());
    let dashed_root = fixture.root.join("project -suffix");
    std::fs::create_dir(&dashed_root).unwrap();
    write_project(&dashed_root);
    let dashed = format!("install --path {}", dashed_root.display());
    let cases: [(&str, Vec<&str>, &str); 7] = [
        ("literal", vec!["install", "--path", &project], "install"),
        ("aliased", vec!["i", "--path", &project], "install"),
        ("embedded", vec!["i"], &embedded),
        ("spaced", vec!["i"], &spaced),
        ("prefixed", vec!["i"], &prefixed),
        ("directed", vec!["i"], &directed),
        ("dashed", vec!["i"], &dashed),
    ];
    for shim in [false, true] {
        for (name, arguments, alias) in &cases {
            let expansion = match *name {
                "spaced" => vec![
                    "install".to_owned(),
                    "--path".into(),
                    spaced_root.to_string_lossy().into_owned(),
                ],
                "dashed" => vec![
                    "install".to_owned(),
                    "--path".into(),
                    dashed_root.to_string_lossy().into_owned(),
                ],
                "directed" => vec![
                    "build".into(),
                    "-C".into(),
                    spaced_root.to_string_lossy().into_owned(),
                    "--offline".into(),
                ],
                _ => alias.split_whitespace().map(str::to_owned).collect(),
            };
            std::fs::create_dir_all(outside.join(".cargo")).unwrap();
            std::fs::write(
                outside.join(".cargo/config.toml"),
                format!(
                    "[alias]\ni = {}\n",
                    toml::Value::Array(expansion.into_iter().map(toml::Value::String).collect())
                ),
            )
            .unwrap();
            let marker = fixture.root.join(format!("install-{shim}-{name}"));
            let mut command = fixture.command();
            let inherited_path = std::env::var_os("PATH").unwrap();
            let paths = std::iter::once(bin.clone()).chain(std::env::split_paths(&inherited_path));
            command
                .args(arguments)
                .current_dir(&outside)
                .env("PATH", std::env::join_paths(paths).unwrap())
                .env("CARGO", &cargo)
                .env("CARGO_BUILD_BUILD_DIR", fixture.nfs.join("intermediates"))
                .env("TEST_ALIAS_BODY", alias)
                .env("TEST_INSTALL_MARKER", &marker);
            if shim {
                command.env("TUIST_CARGO_CACHE_CARGO_SHIM_MODE", "1");
            }
            let output = command.output().unwrap();
            let stderr = String::from_utf8_lossy(&output.stderr);
            assert!(!output.status.success(), "{name}: {stderr}");
            assert!(
                stderr.contains("could not verify Cargo build storage"),
                "{name}: {stderr}"
            );
            assert!(!marker.exists(), "{name} reached Cargo: {stderr}");
        }
    }
}

/// An alias the first probe could not read still names a package, so asking
/// again as Cargo will expand it recovers that package's roots and the build
/// is managed rather than refused. The roots are the expansion's; the child
/// keeps the command line as typed, because Cargo expands the alias itself.
#[test]
fn an_aliased_path_install_recovers_its_roots() {
    use std::os::unix::fs::PermissionsExt;
    let fixture = Fixture::new();
    let bin = fixture.root.join("bin");
    std::fs::create_dir(&bin).unwrap();
    let cargo = bin.join("cargo");
    std::fs::write(&cargo, "#!/bin/sh\ncase \" $* \" in\n  *' metadata '*)\n    [ \"$(pwd)\" = \"$TEST_PACKAGE\" ] || exit 1\n    build=\n    [ -n \"$CARGO_BUILD_BUILD_DIR\" ] && build=\",\\\"build_directory\\\":\\\"$CARGO_BUILD_BUILD_DIR\\\"\"\n    printf '{\"workspace_root\":\"%s\",\"target_directory\":\"%s/target\"%s}\\n' \"$TEST_PACKAGE\" \"$TEST_PACKAGE\" \"$build\"\n    exit 0;;\n  *' --list '*) printf 'Installed Commands:\\n    i    alias: install --path %s\\n    install    Install a Rust binary\\n' \"$TEST_PACKAGE\"; exit 0;;\nesac\ntouch \"$TEST_INSTALL_MARKER\"\n").unwrap();
    std::fs::set_permissions(&cargo, std::fs::Permissions::from_mode(0o755)).unwrap();
    let outside = fixture.root.join("outside-recovery");
    std::fs::create_dir(&outside).unwrap();
    std::fs::create_dir_all(outside.join(".cargo")).unwrap();
    std::fs::write(
        outside.join(".cargo/config.toml"),
        format!(
            "[alias]\ni = [\"install\", \"--path\", {}]\n",
            toml::Value::String(fixture.project.to_string_lossy().into_owned())
        ),
    )
    .unwrap();
    for shim in [false, true] {
        for nfs in [false, true] {
            let marker = fixture.root.join(format!("recovered-{shim}-{nfs}"));
            let mut command = fixture.command();
            let inherited_path = std::env::var_os("PATH").unwrap();
            let paths = std::iter::once(bin.clone()).chain(std::env::split_paths(&inherited_path));
            command
                .arg("i")
                .current_dir(&outside)
                .env("PATH", std::env::join_paths(paths).unwrap())
                .env("CARGO", &cargo)
                .env("TEST_PACKAGE", &fixture.project)
                .env("TEST_INSTALL_MARKER", &marker);
            if shim {
                command.env("TUIST_CARGO_CACHE_CARGO_SHIM_MODE", "1");
            }
            if nfs {
                command.env("CARGO_BUILD_BUILD_DIR", fixture.nfs.join("intermediates"));
            }
            let output = command.output().unwrap();
            let stderr = String::from_utf8_lossy(&output.stderr);
            // Whichever way it goes, the roots were read: the metadata failure
            // this used to report is gone.
            assert!(
                !stderr.contains("could not verify Cargo build storage"),
                "shim={shim} nfs={nfs}: {stderr}"
            );
            if nfs {
                // Storage the recovered roots name is checked like any other,
                // which is the point of recovering them.
                assert!(!output.status.success(), "shim={shim}: {stderr}");
                assert!(stderr.contains("is on NFS"), "shim={shim}: {stderr}");
                assert!(!marker.exists(), "shim={shim}: {stderr}");
            } else {
                assert!(output.status.success(), "shim={shim}: {stderr}");
                assert!(marker.exists(), "shim={shim}: {stderr}");
            }
        }
    }
}

/// A colored `cargo --list` must not cost an alias its passthrough. Cargo
/// colors the listing whenever `CARGO_TERM_COLOR` or `term.color` says
/// `always`, and the parser reads the listing as plain text, so both the
/// header check and the alias table fail and a harmless `fmt` alias is
/// rejected as unverified build storage. This stub colors on the same
/// condition the real Cargo does, and honors the `--color=never` that
/// overrides it.
#[test]
fn a_colored_listing_still_preserves_a_non_build_alias() {
    use std::os::unix::fs::PermissionsExt;
    let fixture = Fixture::new();
    let bin = fixture.root.join("bin");
    std::fs::create_dir(&bin).unwrap();
    let cargo = bin.join("cargo");
    std::fs::write(&cargo, CARGO_ALIAS_STUB).unwrap();
    std::fs::create_dir_all(fixture.project.join(".cargo")).unwrap();
    std::fs::write(
        fixture.project.join(".cargo/config.toml"),
        "[alias]\nfmt-alias = \"fmt\"\n",
    )
    .unwrap();
    std::fs::set_permissions(&cargo, std::fs::Permissions::from_mode(0o755)).unwrap();
    for shim in [false, true] {
        let marker = fixture.root.join(format!("fmt-ran-{shim}"));
        let mut command = fixture.command();
        let inherited_path = std::env::var_os("PATH").unwrap();
        let paths = std::iter::once(bin.clone()).chain(std::env::split_paths(&inherited_path));
        command
            .arg("fmt-alias")
            .env("PATH", std::env::join_paths(paths).unwrap())
            .env("CARGO", &cargo)
            .env("CARGO_TERM_COLOR", "always")
            .env("TEST_ALIAS_MARKER", &marker);
        if shim {
            command.env("TUIST_CARGO_CACHE_CARGO_SHIM_MODE", "1");
        }
        let output = command.output().unwrap();
        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(output.status.success(), "{stderr}");
        assert!(
            !stderr.contains("could not verify Cargo build storage"),
            "{stderr}"
        );
        assert!(marker.exists(), "the alias should reach Cargo: {stderr}");
    }
}

const CARGO_ALIAS_STUB: &str = r#"#!/bin/sh
plain='Installed Commands:\n    fmt\n    fmt-alias    alias: fmt\n'
color='\033[92m\033[1mInstalled Commands:\033[0m\n    \033[1mfmt\033[0m\n    \033[1mfmt-alias\033[0m    alias: fmt\n'
case " $* " in
  *' metadata '*) exit 1 ;;
  *' --list '*)
    case " $* " in
      *' --color=never '*) printf "$plain" ;;
      *) if [ "$CARGO_TERM_COLOR" = always ]; then printf "$color"; else printf "$plain"; fi ;;
    esac
    exit 0 ;;
esac
touch "$TEST_ALIAS_MARKER"
"#;

fn rejected(output: Output, path: &Path, setting: &str) {
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(!output.status.success(), "{stderr}");
    assert!(stderr.contains("is on NFS"), "{stderr}");
    assert!(stderr.contains(&path.display().to_string()), "{stderr}");
    assert!(stderr.contains(setting), "{stderr}");
    assert!(!stderr.contains("Compiling storage-fixture"), "{stderr}");
}

#[test]
fn rejects_cache_before_cargo_or_exec_initializes_it() {
    let fixture = Fixture::new();
    let cache = fixture.nfs.join("new-cache");
    rejected(
        fixture
            .command()
            .env("TUIST_CARGO_CACHE_DIR", &cache)
            .args(["build", "--offline"])
            .output()
            .unwrap(),
        &cache,
        "TUIST_CARGO_CACHE_DIR",
    );
    let marker = fixture.root.join("child-ran");
    rejected(
        fixture
            .command()
            .env("TUIST_CARGO_CACHE_DIR", &cache)
            .args(["exec", "touch"])
            .arg(&marker)
            .output()
            .unwrap(),
        &cache,
        "TUIST_CARGO_CACHE_DIR",
    );
    assert!(!cache.exists());
    assert!(!marker.exists());
    assert!(!fixture.project.join("target").exists());
}

#[test]
fn rejects_explicit_cargo_target_overrides() {
    let fixture = Fixture::new();
    let target = fixture.nfs.join("target");
    for mode in ["flag", "environment", "config"] {
        let mut command = fixture.command();
        command.args(["build", "--offline"]);
        match mode {
            "flag" => {
                command.arg("--target-dir").arg(&target);
            }
            "environment" => {
                command.env("CARGO_TARGET_DIR", &target);
            }
            _ => {
                command
                    .arg("--config")
                    .arg(format!("build.target-dir='{}'", target.display()));
            }
        }
        rejected(command.output().unwrap(), &target, "CARGO_TARGET_DIR");
    }
    assert!(!target.exists());
}

#[test]
fn rejects_managed_destination_and_placement_fallback() {
    let fixture = Fixture::new();
    rejected(
        fixture
            .command()
            .env("TUIST_CARGO_CACHE_TARGET_ROOT", fixture.nfs.join("views"))
            .args(["build", "--offline"])
            .output()
            .unwrap(),
        &fixture.nfs,
        "TUIST_CARGO_CACHE_TARGET_ROOT",
    );
    assert!(!fixture.project.join("target").exists());
    assert!(!fixture.nfs.join("views").exists());

    let project = fixture.nfs.join("source");
    write_project(&project);
    // An existing real target makes managed placement decline.
    std::fs::create_dir(project.join("target")).unwrap();
    rejected(
        fixture
            .command()
            .current_dir(&project)
            .args(["build", "--offline"])
            .output()
            .unwrap(),
        &project.join("target"),
        "CARGO_TARGET_DIR",
    );
}

#[test]
fn rejects_separate_intermediates_and_invalidates_cached_probe() {
    let fixture = Fixture::new();
    let intermediate = fixture.nfs.join("intermediate");
    let local = fixture.root.join("intermediate");
    // First populate the probe using a local intermediate directory. Changing
    // the environment must not reuse that answer on the following invocation.
    let first = fixture
        .command()
        .env("CARGO_BUILD_BUILD_DIR", &local)
        .args(["build", "--offline"])
        .output()
        .unwrap();
    assert!(
        first.status.success(),
        "{}",
        String::from_utf8_lossy(&first.stderr)
    );
    rejected(
        fixture
            .command()
            .env("CARGO_BUILD_BUILD_DIR", &intermediate)
            .args(["build", "--offline"])
            .output()
            .unwrap(),
        &intermediate,
        "CARGO_BUILD_BUILD_DIR",
    );
    rejected(
        fixture
            .command()
            .args(["build", "--offline", "--config"])
            .arg(format!("build.build-dir='{}'", intermediate.display()))
            .output()
            .unwrap(),
        &intermediate,
        "CARGO_BUILD_BUILD_DIR",
    );
    assert!(!intermediate.exists());
}

#[test]
fn rejects_separate_intermediates_before_placing_the_target() {
    let fixture = Fixture::new();
    let intermediate = fixture.nfs.join("intermediate");
    rejected(
        fixture
            .command()
            .env("CARGO_BUILD_BUILD_DIR", &intermediate)
            .args(["build", "--offline"])
            .output()
            .unwrap(),
        &intermediate,
        "CARGO_BUILD_BUILD_DIR",
    );
    assert!(std::fs::symlink_metadata(fixture.project.join("target")).is_err());

    // An intermediate directory nested in the target follows it to the
    // managed destination, even from an NFS checkout.
    let project = fixture.nfs.join("source");
    write_project(&project);
    let nested = project.join("target/intermediate");
    let output = fixture
        .command()
        .current_dir(&project)
        .env("CARGO_BUILD_BUILD_DIR", &nested)
        .args(["build", "--offline"])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        nested
            .canonicalize()
            .unwrap()
            .starts_with(fixture.root.join("targets"))
    );
}

#[test]
fn allows_nfs_sources_with_local_outputs_and_ignores_unused_managed_root() {
    let fixture = Fixture::new();
    let project = fixture.nfs.join("source");
    write_project(&project);
    let output = fixture
        .command()
        .current_dir(&project)
        .args(["build", "--offline"])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        project
            .join("target")
            .canonicalize()
            .unwrap()
            .starts_with(fixture.root.join("targets"))
    );
    let output = fixture
        .command()
        .env("TUIST_CARGO_CACHE_TARGET_ROOT", &fixture.nfs)
        .env("CARGO_TARGET_DIR", fixture.root.join("explicit-target"))
        .args(["build", "--offline"])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    // A foreign symlink is not managed by tuist_cargo_cache; its local destination wins
    // over an unused NFS managed-root setting.
    std::os::unix::fs::symlink(
        fixture.root.join("explicit-target"),
        fixture.project.join("target"),
    )
    .unwrap();
    let output = fixture
        .command()
        .env("TUIST_CARGO_CACHE_TARGET_ROOT", &fixture.nfs)
        .args(["build", "--offline"])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn follows_dangling_cache_links_and_checks_the_persistent_shim() {
    let fixture = Fixture::new();
    let cache = fixture.root.join("linked-cache");
    std::os::unix::fs::symlink(fixture.nfs.join("not-created"), &cache).unwrap();
    rejected(
        fixture
            .command()
            .env("TUIST_CARGO_CACHE_DIR", &cache)
            .args(["build", "--offline"])
            .output()
            .unwrap(),
        &cache,
        "TUIST_CARGO_CACHE_DIR",
    );
    rejected(
        fixture
            .command()
            .env("TUIST_CARGO_CACHE_DIR", &cache)
            .env("TUIST_CARGO_CACHE_CARGO_SHIM_MODE", "1")
            .args(["build", "--offline"])
            .output()
            .unwrap(),
        &cache,
        "TUIST_CARGO_CACHE_DIR",
    );
    assert!(!fixture.nfs.join("not-created").exists());
}

#[test]
fn help_inspection_cleanup_and_disabled_shim_remain_available() {
    let fixture = Fixture::new();
    let cache = fixture.nfs.join("cache");
    for arguments in [
        vec!["build", "--help"],
        vec!["cache", "dir"],
        vec!["gc", "--dry-run"],
        vec!["clean"],
    ] {
        let output = fixture
            .command()
            .env("TUIST_CARGO_CACHE_DIR", &cache)
            .args(&arguments)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{arguments:?}: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }
    let output = fixture
        .command()
        .env("TUIST_CARGO_CACHE_DIR", &cache)
        .env("TUIST_CARGO_CACHE_CARGO_SHIM_MODE", "1")
        .env("TUIST_CARGO_CACHE_DISABLE", "1")
        .args(["build", "--offline"])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn rejects_a_private_nfs_shim_directory_before_initializing_storage() {
    for arguments in [vec!["build", "--offline"], vec!["exec", "cc", "--version"]] {
        let fixture = Fixture::new();
        let shims = fixture.nfs.join("private-shims");
        rejected(
            fixture
                .command()
                .env("TUIST_CARGO_CACHE_SHIMS_DIR", &shims)
                .args(arguments)
                .output()
                .unwrap(),
            &shims,
            "TUIST_CARGO_CACHE_SHIMS_DIR",
        );
        assert!(!shims.exists());
        assert!(!fixture.root.join("cache/actions").exists());
    }
}
