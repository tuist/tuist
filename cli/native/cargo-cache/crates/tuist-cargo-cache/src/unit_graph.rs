//! Identify the build unit a wrapper invocation produced and the units it
//! consumed, so a recorded build can be read as a dependency graph.
//!
//! Cargo gives every unit a hash and passes it to rustc as
//! `-C extra-filename=-<hash>`. The files the unit writes, and the `--extern`
//! paths its dependents receive, carry the same hash. A build script's run has
//! its own directory, which the crates that read it receive as `OUT_DIR`,
//! while the script binary lives in the directory of its compilation. Those
//! names are all this needs; Cargo's own unit graph is unstable and is not
//! consulted.
//!
//! Two layouts name those directories. Through Cargo 1.99 they are
//! `build/<package>-<hash>`, with `OUT_DIR` at `build/<package>-<hash>/out`.
//! From Cargo 1.100 every unit has `build/<package>/<hash>/out`, which holds
//! its outputs, and a build script compiled there is passed no
//! `extra-filename` at all, so its `--out-dir` is what names it.
//!
//! An identity is a hint for analysis, never a cache input: a name this cannot
//! read yields no identity rather than a guess.

use std::ffi::OsString;
use std::path::Path;

/// The unit a rustc invocation produces and the units whose outputs it reads.
pub(crate) fn rustc_unit(
    arguments: &[OsString],
    out_dir: Option<&Path>,
) -> (Option<String>, Vec<String>) {
    let mut unit = None;
    let mut out_directory = None;
    let mut dependencies = Vec::new();
    let mut arguments = arguments.iter().filter_map(|argument| argument.to_str());
    while let Some(argument) = arguments.next() {
        let output = match argument {
            "--out-dir" => arguments.next(),
            _ => argument.strip_prefix("--out-dir="),
        };
        if let Some(output) = output {
            out_directory = unit_directory_hash(Path::new(output));
            continue;
        }
        let codegen = match argument {
            "-C" | "--codegen" => arguments.next(),
            _ => argument
                .strip_prefix("-C")
                .or_else(|| argument.strip_prefix("--codegen="))
                .filter(|option| !option.is_empty()),
        };
        if let Some(hash) = codegen
            .and_then(|option| option.strip_prefix("extra-filename="))
            .map(|value| value.trim_start_matches('-'))
            .filter(|hash| is_hash(hash))
        {
            unit = Some(hash.to_string());
            continue;
        }
        let external = match argument {
            "--extern" => arguments.next(),
            _ => argument.strip_prefix("--extern="),
        };
        if let Some(hash) = external
            .and_then(|value| value.split_once('=').map(|(_, path)| path))
            .and_then(|path| artifact_hash(Path::new(path)))
        {
            dependencies.push(hash);
        }
    }
    dependencies.extend(out_dir.and_then(build_script_run));
    dependencies.sort();
    dependencies.dedup();
    (unit.or(out_directory), dependencies)
}

/// The unit a build-script run produces, and the compilation it runs.
pub(crate) fn build_script_run_unit(
    out_dir: Option<&Path>,
    script: &Path,
) -> (Option<String>, Vec<String>) {
    let unit = out_dir.and_then(build_script_run);
    let compilation = script.parent().and_then(unit_directory_hash);
    (unit, compilation.into_iter().collect())
}

/// The run a build script's `OUT_DIR` belongs to.
fn build_script_run(out_dir: &Path) -> Option<String> {
    if out_dir.file_name()? != "out" {
        return None;
    }
    unit_directory_hash(out_dir).map(|hash| format!("run-{hash}"))
}

/// The hash naming a unit's directory, in either layout: `<package>-<hash>`,
/// or `<package>/<hash>` with its outputs in `out`.
fn unit_directory_hash(directory: &Path) -> Option<String> {
    let directory = if directory.file_name()? == "out" {
        directory.parent()?
    } else {
        directory
    };
    let name = directory.file_name()?.to_str()?;
    // A bare hash only names a unit under its package's directory in `build`;
    // anywhere else a hex-looking name is a coincidence.
    if is_hash(name)
        && directory
            .parent()
            .and_then(Path::parent)
            .and_then(Path::file_name)
            .is_some_and(|build| build == "build")
    {
        return Some(name.to_string());
    }
    directory_hash(name)
}

/// The hash in a `<package>-<hash>` name.
fn directory_hash(name: &str) -> Option<String> {
    let (_, hash) = name.rsplit_once('-')?;
    is_hash(hash).then(|| hash.to_string())
}

/// The hash in a compiler artifact's file name, as Cargo spells one:
/// `lib<crate>-<hash>.rlib`, `.rmeta`, or a dynamic library.
fn artifact_hash(path: &Path) -> Option<String> {
    let extension = path.extension()?.to_str()?;
    if !matches!(extension, "rlib" | "rmeta" | "so" | "dylib" | "dll") {
        return None;
    }
    directory_hash(path.file_stem()?.to_str()?)
}

fn is_hash(value: &str) -> bool {
    !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_hexdigit())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn arguments(values: &[&str]) -> Vec<OsString> {
        values.iter().map(OsString::from).collect()
    }

    #[test]
    fn a_rustc_unit_is_named_by_its_extra_filename_and_reads_its_externs() {
        let (unit, dependencies) = rustc_unit(
            &arguments(&[
                "--crate-name",
                "app",
                "-C",
                "metadata=0123",
                "-C",
                "extra-filename=-5d4c3b2a",
                "--extern",
                "engine=/t/debug/deps/libengine-aa11.rmeta",
                "--extern=serde_derive=/t/debug/deps/libserde_derive-bb22.so",
                "--extern",
                "noprelude:alloc=/t/debug/deps/liballoc-cc33.rlib",
                // A sysroot crate named without a path has no unit here.
                "--extern",
                "proc_macro",
            ]),
            Some(Path::new("/t/debug/build/app-dd44/out")),
        );

        assert_eq!(unit.as_deref(), Some("5d4c3b2a"));
        assert_eq!(dependencies, ["aa11", "bb22", "cc33", "run-dd44"]);
    }

    #[test]
    fn joined_codegen_spellings_are_read_too() {
        assert_eq!(
            rustc_unit(&arguments(&["-Cextra-filename=-ab12"]), None).0,
            Some("ab12".into())
        );
        assert_eq!(
            rustc_unit(&arguments(&["--codegen=extra-filename=-cd34"]), None).0,
            Some("cd34".into())
        );
    }

    #[test]
    fn a_name_that_is_not_cargo_s_yields_no_identity() {
        let (unit, dependencies) = rustc_unit(
            &arguments(&[
                "-C",
                "extra-filename=custom",
                "--extern",
                "engine=/elsewhere/engine.rlib",
            ]),
            Some(Path::new("/generated")),
        );

        assert_eq!(unit, None);
        assert!(dependencies.is_empty());
    }

    /// Cargo 1.100 gives every unit `build/<package>/<hash>/out`, and passes a
    /// build script's compilation no `extra-filename`.
    #[test]
    fn the_cargo_1_100_layout_is_read_too() {
        let (unit, dependencies) = rustc_unit(
            &arguments(&[
                "--crate-name",
                "build_script_build",
                "--out-dir",
                "/t/debug/build/api/b08ebe71fd39a343/out",
            ]),
            None,
        );
        assert_eq!(unit.as_deref(), Some("b08ebe71fd39a343"));
        assert!(dependencies.is_empty());

        let (unit, dependencies) = rustc_unit(
            &arguments(&[
                "-C",
                "extra-filename=-9d3b46aad32ac5c9",
                "--out-dir",
                "/t/debug/build/api/9d3b46aad32ac5c9/out",
                "--extern",
                "engine=/t/debug/build/engine/4bf0fb4dd59f0179/out/libengine-4bf0fb4dd59f0179.rmeta",
            ]),
            Some(Path::new("/t/debug/build/api/ba26dbedf7b267d9/out")),
        );
        assert_eq!(unit.as_deref(), Some("9d3b46aad32ac5c9"));
        assert_eq!(dependencies, ["4bf0fb4dd59f0179", "run-ba26dbedf7b267d9"]);

        let (unit, dependencies) = build_script_run_unit(
            Some(Path::new("/t/debug/build/api/ba26dbedf7b267d9/out")),
            Path::new("/t/debug/build/api/b08ebe71fd39a343/out/build-script-build"),
        );
        assert_eq!(unit.as_deref(), Some("run-ba26dbedf7b267d9"));
        assert_eq!(dependencies, ["b08ebe71fd39a343"]);
    }

    #[test]
    fn a_shared_deps_directory_names_no_unit() {
        assert_eq!(
            rustc_unit(&arguments(&["--out-dir", "/t/debug/deps"]), None).0,
            None
        );
    }

    #[test]
    fn a_build_script_run_depends_on_its_compilation() {
        let (unit, dependencies) = build_script_run_unit(
            Some(Path::new("/t/debug/build/ring-77ee/out")),
            Path::new("/t/debug/build/ring-66ff/build-script-build"),
        );

        assert_eq!(unit.as_deref(), Some("run-77ee"));
        assert_eq!(dependencies, ["66ff"]);
    }
}
