//! Cache CMake's C and C++ compiles through `CMAKE_<LANG>_COMPILER_LAUNCHER`.
//!
//! Under `tuist_cargo_cache build`, cmake-rs inherits tuist_cargo_cache's CC shims, and CMake discards
//! configuration options when CMAKE_<LANG>_COMPILER changes. Translate our
//! compiler paths to their real drivers before configuration, and cache C/C++
//! through launchers instead. ASM keeps its real driver too, but CMake does not
//! support an ASM compiler launcher.
//!
//! `tuist_cargo_cache exec cmake` adds the same launchers to the configure it runs, so
//! whichever compiler CMake settles on is cached: one an existing build
//! directory recorded without tuist_cargo_cache, or one the build named itself.

use super::shims::{CcShims, is_target_triple, link_path_shim, resolve_on_path};
use super::{
    pin_names_a_compiler, record_cc_bypass, reserve_stderr_for_compiler, run_transparent_cc,
    session_socket,
};
use eyre::Result;
use std::collections::BTreeMap;
use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};
use tuist_cargo_cache_cc::CcLanguage;

const PROGRAMS: &str = "TUIST_CARGO_CACHE_CMAKE_PROGRAMS";
const COMPILERS: &str = "TUIST_CARGO_CACHE_CMAKE_COMPILERS";
const SHIM: &str = "tuist_cargo_cache-cmake";
const C_LAUNCHER: &str = "tuist_cargo_cache-cmake-launch-c";
const CXX_LAUNCHER: &str = "tuist_cargo_cache-cmake-launch-cxx";
const LAUNCHERS: [(&str, &str); 2] = [
    ("CMAKE_C_COMPILER_LAUNCHER", C_LAUNCHER),
    ("CMAKE_CXX_COMPILER_LAUNCHER", CXX_LAUNCHER),
];

pub(super) fn environment(
    directory: &Path,
    compilers: &CcShims,
    build_environment: &BTreeMap<String, String>,
) -> Result<BTreeMap<String, String>> {
    let executable = std::env::current_exe()?;
    let mut environment = BTreeMap::new();
    let mut programs = BTreeMap::new();
    let mut choices: BTreeMap<_, _> = std::env::vars()
        .chain(
            build_environment
                .iter()
                .map(|(key, value)| (key.clone(), value.clone())),
        )
        .filter(|(name, _)| {
            matches!(name.as_str(), "CMAKE" | "HOST_CMAKE" | "TARGET_CMAKE")
                || name.strip_prefix("CMAKE_").is_some_and(is_target_triple)
        })
        .collect();
    if !choices.contains_key("CMAKE")
        && let Some(program) = resolve_on_path(&super::shim_file_name("cmake"))
    {
        choices.insert("CMAKE".into(), program.to_string_lossy().into_owned());
    }
    for (variable, program) in choices {
        let name = format!("{SHIM}-{}", variable.to_ascii_lowercase().replace('.', "_"));
        let shim = directory.join(super::shim_file_name(&name));
        // Nested sessions must keep the outer shim's original program.
        let program = build_environment
            .get(PROGRAMS)
            .and_then(|encoded| serde_json::from_str::<BTreeMap<String, PathBuf>>(encoded).ok())
            .unwrap_or_else(|| read_map(PROGRAMS))
            .remove(
                Path::new(&program)
                    .file_stem()
                    .and_then(OsStr::to_str)
                    .unwrap_or_default(),
            )
            .unwrap_or_else(|| PathBuf::from(program));
        link_path_shim(&executable, &shim)?;
        programs.insert(name, program);
        environment.insert(variable, shim.to_string_lossy().into_owned());
    }
    if programs.is_empty() {
        return Ok(environment);
    }
    let mut pins = BTreeMap::new();
    for (shim, real) in compilers.cc.iter().chain(compilers.cxx.iter()) {
        pins.insert(cmake_path(shim), real.clone());
    }
    for compiler in &compilers.targeted {
        pins.insert(cmake_path(&compiler.shim), compiler.real.clone());
    }
    install_launchers(directory, &executable)?;
    environment.insert(PROGRAMS.into(), serde_json::to_string(&programs)?);
    environment.insert(COMPILERS.into(), serde_json::to_string(&pins)?);
    Ok(environment)
}

/// Point a configure that `tuist_cargo_cache exec` runs itself at the compiler launchers.
///
/// The compiler shims on `PATH` reach only a build that finds its compiler by
/// one of their names, on a fresh configure. A launcher reaches the compiler
/// CMake already recorded, and one the build chose by path or by a versioned
/// name, without changing CMAKE_<LANG>_COMPILER and so without discarding the
/// build directory's configuration.
///
/// Only the command `tuist_cargo_cache exec` was given, not a `cmake` on `PATH`: a version
/// manager's `cmake` shim may itself search `PATH` for the next `cmake`, and a
/// wrapper there would be handed back to itself indefinitely.
pub(super) fn exec_arguments(
    directory: &Path,
    program: &OsStr,
    arguments: &mut Vec<OsString>,
    environment: &mut BTreeMap<String, String>,
) -> Result<()> {
    if !is_cmake(program) || !configures(arguments) {
        return Ok(());
    }
    install_launchers(directory, &std::env::current_exe()?)?;
    environment.extend(add_launchers(arguments, directory, &LAUNCHERS));
    Ok(())
}

/// Whether `tuist_cargo_cache exec` was handed CMake to run.
pub fn is_cmake(program: &OsStr) -> bool {
    Path::new(program)
        .file_stem()
        .and_then(OsStr::to_str)
        .is_some_and(|stem| stem.eq_ignore_ascii_case("cmake"))
}

/// Install the C and C++ launchers, and the scripts that point a cache at them.
fn install_launchers(directory: &Path, executable: &Path) -> Result<()> {
    for (variable, launcher) in LAUNCHERS {
        let installed = directory.join(super::shim_file_name(launcher));
        link_path_shim(executable, &installed)?;
        write_launcher_script(directory, variable, launcher, &installed)?;
    }
    Ok(())
}

fn read_map(name: &str) -> BTreeMap<String, PathBuf> {
    std::env::var(name)
        .ok()
        .and_then(|value| serde_json::from_str(&value).ok())
        .unwrap_or_default()
}

fn cmake_path(path: &Path) -> String {
    let path = path.to_string_lossy().into_owned();
    // cmake-rs writes forward slashes even when cc-rs returned a Windows path.
    if cfg!(windows) {
        path.replace('\\', "/")
    } else {
        path
    }
}

/// Dispatch before tuist_cargo_cache's CLI: CMake launchers also survive outside a session.
pub fn dispatch() -> Option<ExitCode> {
    let invoked = PathBuf::from(std::env::args_os().next()?);
    let name = invoked.file_stem()?.to_str()?;
    if matches!(name, C_LAUNCHER | CXX_LAUNCHER) {
        let language = if name == C_LAUNCHER {
            CcLanguage::C
        } else {
            CcLanguage::Cxx
        };
        reserve_stderr_for_compiler();
        let mut arguments = std::env::args_os().skip(1);
        let Some(compiler) = arguments.next() else {
            eprintln!("tuist_cargo_cache[error]: CMake launcher requires a compiler");
            return Some(ExitCode::FAILURE);
        };
        let arguments: Vec<_> = arguments.collect();
        // A build configured under `tuist_cargo_cache exec` records the compiler shim it
        // found on `PATH`, and that shim caches the compile itself.
        let current = std::env::current_exe().ok();
        if !pin_names_a_compiler(Path::new(&compiler), current.as_deref()) {
            return Some(run_transparent_cc(compiler, arguments));
        }
        if session_socket().is_some() {
            match crate::cc::compile(&compiler, &arguments, language) {
                Ok(code) => return Some(code),
                Err(error) => record_cc_bypass(&error),
            }
        }
        return Some(run_transparent_cc(compiler, arguments));
    }
    if !name.starts_with(&format!("{SHIM}-")) {
        return None;
    }
    let program = read_map(PROGRAMS)
        .remove(name)
        .unwrap_or_else(|| "cmake".into());
    let mut arguments: Vec<_> = std::env::args_os().skip(1).collect();
    let mut command = Command::new(program);
    if configures(&arguments) {
        let launchers = rewrite_compilers(&mut arguments, &read_map(COMPILERS));
        command.envs(add_launchers(
            &mut arguments,
            invoked.parent().unwrap(),
            &launchers,
        ));
    }
    Some(run_cmake(command, arguments))
}

/// Whether a CMake command line configures a build tree.
///
/// Building, installing, scripting, and informational modes must pass through
/// verbatim: several of them reject `-C`.
fn configures(arguments: &[OsString]) -> bool {
    !arguments.iter().any(|argument| {
        let argument = argument.to_str().unwrap_or_default();
        matches!(
            argument,
            "--build"
                | "--install"
                | "--open"
                | "--workflow"
                | "--list-presets"
                | "--find-package"
                | "--system-information"
                | "-E"
                | "-P"
                | "-N"
                | "--version"
                | "-version"
                | "--help"
                | "-help"
                | "-h"
                | "/?"
        ) || argument.starts_with("--help-")
            || argument.starts_with("--list-presets=")
    })
}

/// Point a configure at the launchers in `directory`, returning any
/// environment CMake needs for it.
fn add_launchers(
    arguments: &mut Vec<OsString>,
    directory: &Path,
    launchers: &[(&str, &str)],
) -> Vec<(String, String)> {
    let mut scripts = Vec::new();
    let mut environment = Vec::new();
    for &(variable, launcher) in launchers {
        // A launcher chosen on the command line is left to the caller.
        // One exported in the environment still runs the script, which
        // installs it in place of a stale tuist_cargo_cache launcher: CMake itself would
        // only have read it into a fresh cache.
        if defines(arguments, variable) {
            continue;
        }
        let script = directory.join(launcher_script_name(launcher));
        if script.is_file() {
            scripts.extend([OsString::from("-C"), script.into_os_string()]);
        } else if std::env::var_os(variable).is_none() {
            let launcher = directory.join(super::shim_file_name(launcher));
            environment.push((variable.into(), launcher.to_string_lossy().into_owned()));
        }
    }
    // After the caller's own initial-cache scripts: one that seeds a
    // launcher without FORCE must find the entry still empty.
    let position = after_initial_cache_scripts(arguments);
    arguments.splice(position..position, scripts);
    environment
}

fn run_cmake(mut command: Command, arguments: Vec<OsString>) -> ExitCode {
    match command.args(arguments).status() {
        Ok(status) => crate::materialize::exit_code(status),
        Err(error) => {
            eprintln!("tuist_cargo_cache[error]: failed to execute CMake: {error}");
            ExitCode::FAILURE
        }
    }
}

/// File name of the initial-cache script that installs `launcher`.
fn launcher_script_name(launcher: &str) -> String {
    format!("{launcher}.cmake")
}

/// Write the `-C` script that points a CMake cache at this binary's launcher.
///
/// The launcher cannot simply be offered through the environment: CMake reads
/// `CMAKE_<LANG>_COMPILER_LAUNCHER` from there only for a fresh cache. Shims
/// live per tuist_cargo_cache binary, so a build tree configured before an upgrade would
/// otherwise keep the previous binary's launcher, and fail every compile once
/// that binary was removed. The script runs against whichever cache CMake
/// loads -- `-B`, the working directory, or a preset's `binaryDir` alike --
/// and replaces only an empty entry or another tuist_cargo_cache launcher, never one the
/// build chose for itself. A launcher the caller exports takes the place of
/// ours, just as CMake would have seeded a fresh cache with it.
fn write_launcher_script(
    directory: &Path,
    variable: &str,
    launcher: &str,
    installed: &Path,
) -> Result<()> {
    let quoted = cmake_path(installed)
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('$', "\\$");
    // Either separator: a launcher CMake seeded from the environment, or one
    // an older tuist_cargo_cache recorded, keeps Windows backslashes.
    let separator = "[/\\\\]";
    let suffix = if cfg!(windows) {
        "\\\\.[Ee][Xx][Ee]"
    } else {
        ""
    };
    let script = format!(
        "# Written by tuist_cargo_cache: point this build at the running tuist_cargo_cache's compiler launcher.\n\
         get_property(cargo_cache_launcher CACHE {variable} PROPERTY VALUE)\n\
         if(NOT cargo_cache_launcher OR cargo_cache_launcher MATCHES \"{separator}{launcher}{suffix}$\")\n  \
         if(NOT \"$ENV{{{variable}}}\" STREQUAL \"\")\n    \
         set({variable} \"$ENV{{{variable}}}\" CACHE STRING \"Compiler launcher\" FORCE)\n  \
         else()\n    \
         set({variable} \"{quoted}\" CACHE STRING \"Compiler launcher installed by tuist_cargo_cache\" FORCE)\n  \
         endif()\n\
         endif()\n\
         unset(cargo_cache_launcher)\n"
    );
    let destination = directory.join(launcher_script_name(launcher));
    if std::fs::read_to_string(&destination).is_ok_and(|existing| existing == script) {
        return Ok(());
    }
    // Staged and renamed: a concurrent CMake run may be reading it.
    let staging = directory.join(format!(
        ".{}.{}",
        launcher_script_name(launcher),
        std::process::id()
    ));
    std::fs::write(&staging, script)?;
    std::fs::rename(&staging, &destination)?;
    Ok(())
}

/// Where a `-C` script goes so it runs after every one the caller passed.
fn after_initial_cache_scripts(arguments: &[OsString]) -> usize {
    let mut position = 0;
    let mut index = 0;
    while index < arguments.len() {
        let argument = arguments[index].to_str().unwrap_or_default();
        if argument == "--" {
            break;
        }
        if argument == "-C" {
            index += 2;
            position = index.min(arguments.len());
            continue;
        }
        index += 1;
        if argument.starts_with("-C") {
            position = index;
        }
    }
    position
}

/// Whether the command line sets `variable` itself.
fn defines(arguments: &[OsString], variable: &str) -> bool {
    let mut after_define = false;
    arguments.iter().any(|argument| {
        let text = argument.to_str().unwrap_or_default();
        let definition = text.strip_prefix("-D").or(after_define.then_some(text));
        after_define = text == "-D";
        definition.is_some_and(|definition| {
            definition
                .split(['=', ':'])
                .next()
                .is_some_and(|name| name == variable)
        })
    })
}

fn rewrite_compilers(
    arguments: &mut [OsString],
    pins: &BTreeMap<String, PathBuf>,
) -> Vec<(&'static str, &'static str)> {
    let mut launchers = Vec::new();
    // Both -DNAME[:TYPE]=value and -D NAME[:TYPE]=value are accepted by CMake.
    // Only exact paths installed by this session are ours to replace.
    let mut after_define = false;
    for argument in arguments {
        let Some(text) = argument.to_str() else {
            after_define = false;
            continue;
        };
        let definition = if let Some(value) = text.strip_prefix("-D") {
            value
        } else if after_define {
            text
        } else {
            continue;
        };
        after_define = text == "-D";
        let Some((key, value)) = definition.split_once('=') else {
            continue;
        };
        let variable = key.split(':').next().unwrap();
        if !matches!(
            variable,
            "CMAKE_C_COMPILER" | "CMAKE_CXX_COMPILER" | "CMAKE_ASM_COMPILER"
        ) {
            continue;
        }
        let Some(real) = pins.get(&cmake_path(Path::new(value))) else {
            continue;
        };
        match variable {
            "CMAKE_C_COMPILER" => launchers.push(("CMAKE_C_COMPILER_LAUNCHER", C_LAUNCHER)),
            "CMAKE_CXX_COMPILER" => launchers.push(("CMAKE_CXX_COMPILER_LAUNCHER", CXX_LAUNCHER)),
            _ => {}
        }
        let prefix = if text.starts_with("-D") { "-D" } else { "" };
        *argument = format!("{prefix}{key}={}", cmake_path(real)).into();
    }
    launchers
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compiler_definitions_keep_types_spaces_and_unrelated_options() {
        let mut arguments: Vec<OsString> = [
            "-S",
            "source tree",
            "-D",
            "CMAKE_C_COMPILER:FILEPATH=/cache dir/tuist_cargo_cache-c",
            "-DCMAKE_CXX_COMPILER=/cache dir/tuist_cargo_cache-cxx",
            "-DCMAKE_ASM_COMPILER=/cache dir/tuist_cargo_cache-c",
            "-DCMAKE_C_COMPILER_LAUNCHER=user-launcher",
            "-DBUILD_TESTING=OFF",
            "-DSOME_COMPILER=/cache dir/tuist_cargo_cache-c",
        ]
        .into_iter()
        .map(Into::into)
        .collect();
        let pins = BTreeMap::from([
            (
                "/cache dir/tuist_cargo_cache-c".into(),
                "/tool chain/cc".into(),
            ),
            (
                "/cache dir/tuist_cargo_cache-cxx".into(),
                "/tool chain/c++".into(),
            ),
        ]);
        let launchers = rewrite_compilers(&mut arguments, &pins);
        assert_eq!(
            arguments,
            [
                "-S",
                "source tree",
                "-D",
                "CMAKE_C_COMPILER:FILEPATH=/tool chain/cc",
                "-DCMAKE_CXX_COMPILER=/tool chain/c++",
                "-DCMAKE_ASM_COMPILER=/tool chain/cc",
                "-DCMAKE_C_COMPILER_LAUNCHER=user-launcher",
                "-DBUILD_TESTING=OFF",
                "-DSOME_COMPILER=/cache dir/tuist_cargo_cache-c",
            ]
            .map(OsString::from)
        );
        assert_eq!(
            launchers,
            vec![
                ("CMAKE_C_COMPILER_LAUNCHER", C_LAUNCHER),
                ("CMAKE_CXX_COMPILER_LAUNCHER", CXX_LAUNCHER),
            ]
        );
    }

    /// Run the generated script against a real cache holding `cached`, and
    /// return what the cache holds afterwards.
    fn launcher_after_script(cached: &str) -> Option<String> {
        launcher_after_configure(Some(cached), &[])
    }

    /// Configure a real cache, seeded with `cached` when given, through the
    /// arguments dispatch would hand CMake along with `caller` scripts, and
    /// return the launcher it records.
    fn launcher_after_configure(cached: Option<&str>, caller: &[&str]) -> Option<String> {
        let cmake = resolve_on_path(&super::super::shim_file_name("cmake"))?;
        let directory = tempfile::tempdir().unwrap();
        let source = directory.path().join("source");
        let build = directory.path().join("build");
        std::fs::create_dir_all(&source).unwrap();
        std::fs::write(
            source.join("CMakeLists.txt"),
            "cmake_minimum_required(VERSION 3.10)\nproject(probe NONE)\n",
        )
        .unwrap();
        let installed = directory
            .path()
            .join(super::super::shim_file_name(C_LAUNCHER));
        write_launcher_script(
            directory.path(),
            "CMAKE_C_COMPILER_LAUNCHER",
            C_LAUNCHER,
            &installed,
        )
        .unwrap();
        let configure = |arguments: &[OsString]| {
            let status = Command::new(&cmake)
                .args(arguments)
                .arg("-S")
                .arg(&source)
                .arg("-B")
                .arg(&build)
                .env_remove("CMAKE_C_COMPILER_LAUNCHER")
                .stdout(std::process::Stdio::null())
                .status()
                .unwrap();
            assert!(status.success());
        };
        if let Some(cached) = cached {
            configure(&[format!("-DCMAKE_C_COMPILER_LAUNCHER:STRING={cached}").into()]);
        }
        let mut arguments = Vec::new();
        for (index, script) in caller.iter().enumerate() {
            let path = directory.path().join(format!("caller-{index}.cmake"));
            std::fs::write(&path, script).unwrap();
            arguments.extend([OsString::from("-C"), path.into_os_string()]);
        }
        let position = after_initial_cache_scripts(&arguments);
        arguments.splice(
            position..position,
            [
                OsString::from("-C"),
                directory
                    .path()
                    .join(launcher_script_name(C_LAUNCHER))
                    .into_os_string(),
            ],
        );
        configure(&arguments);
        let cache = std::fs::read_to_string(build.join("CMakeCache.txt")).unwrap();
        let value = cache
            .lines()
            .find_map(|line| line.strip_prefix("CMAKE_C_COMPILER_LAUNCHER:STRING="))
            .map(ToOwned::to_owned);
        assert!(value.is_some(), "{cache}");
        let ours = cmake_path(&installed);
        value.map(|value| if value == ours { "ours".into() } else { value })
    }

    #[test]
    fn a_stale_cargo_cache_launcher_is_replaced_whichever_separator_it_uses() {
        let name = super::super::shim_file_name(C_LAUNCHER);
        for cached in [
            format!("/old/shims/native/id/{name}"),
            format!("C:\\old\\shims\\native\\id\\{name}"),
        ] {
            let Some(after) = launcher_after_script(&cached) else {
                return;
            };
            assert_eq!(after, "ours", "{cached} should be replaced");
        }
        let Some(after) = launcher_after_script("/usr/bin/ccache") else {
            return;
        };
        assert_eq!(after, "/usr/bin/ccache", "a user's launcher must stay");
    }

    #[test]
    fn a_callers_initial_cache_script_chooses_the_launcher_first() {
        let Some(after) = launcher_after_configure(
            None,
            &["set(CMAKE_C_COMPILER_LAUNCHER \"/usr/bin/ccache\" CACHE STRING \"\")\n"],
        ) else {
            return;
        };
        assert_eq!(after, "/usr/bin/ccache");
        let Some(after) = launcher_after_configure(None, &[]) else {
            return;
        };
        assert_eq!(after, "ours", "a fresh cache gets this binary's launcher");
    }

    #[test]
    fn cargo_cache_scripts_follow_the_callers_and_precede_a_separator() {
        let arguments =
            |items: &[&str]| -> Vec<OsString> { items.iter().map(OsString::from).collect() };
        assert_eq!(after_initial_cache_scripts(&arguments(&["-S", "src"])), 0);
        assert_eq!(
            after_initial_cache_scripts(&arguments(&["-C", "a.cmake", "-S", "src", "-Cb.cmake"])),
            5
        );
        assert_eq!(
            after_initial_cache_scripts(&arguments(&["-C", "a.cmake", "--", "-C", "x"])),
            2
        );
        assert_eq!(after_initial_cache_scripts(&arguments(&["-C"])), 1);
    }

    #[test]
    fn launchers_set_on_the_command_line_are_recognized() {
        let arguments: Vec<OsString> = [
            "-D",
            "CMAKE_C_COMPILER_LAUNCHER=user",
            "-DCMAKE_CXX_COMPILER_LAUNCHER:STRING=user",
            "-DCMAKE_C_COMPILER_LAUNCHER_EXTRA=unrelated",
        ]
        .into_iter()
        .map(Into::into)
        .collect();
        assert!(defines(&arguments, "CMAKE_C_COMPILER_LAUNCHER"));
        assert!(defines(&arguments, "CMAKE_CXX_COMPILER_LAUNCHER"));
        assert!(!defines(&arguments[3..], "CMAKE_C_COMPILER_LAUNCHER"));
    }

    #[test]
    fn only_configures_receive_launcher_scripts() {
        let configures =
            |items: &[&str]| configures(&items.iter().map(OsString::from).collect::<Vec<_>>());
        assert!(configures(&["-S", ".", "-B", "build"]));
        assert!(configures(&["--preset", "default"]));
        assert!(configures(&["."]));
        for passthrough in [
            &["--build", "build"][..],
            &["--install", "build"],
            &["--workflow", "--preset", "default"],
            &["--list-presets=all"],
            &["--help-command", "project"],
            &["-E", "echo", "hi"],
            &["-P", "script.cmake"],
            &["--version"],
            &["--find-package", "-DNAME=ZLIB", "-DMODE=EXIST"],
            &["--system-information", "info.txt"],
        ] {
            assert!(!configures(passthrough), "{passthrough:?}");
        }
    }

    #[test]
    fn exec_adds_launchers_only_to_a_cmake_configure() {
        let directory = tempfile::tempdir().unwrap();
        let run = |program: &str, items: &[&str]| {
            let mut arguments: Vec<OsString> = items.iter().map(OsString::from).collect();
            let mut environment = BTreeMap::new();
            exec_arguments(
                directory.path(),
                OsStr::new(program),
                &mut arguments,
                &mut environment,
            )
            .unwrap();
            arguments
        };
        let script = |launcher| {
            directory
                .path()
                .join(launcher_script_name(launcher))
                .into_os_string()
        };
        assert_eq!(
            run("/opt/bin/cmake", &["-C", "mine.cmake", "-S", "."]),
            [
                "-C".into(),
                "mine.cmake".into(),
                "-C".into(),
                script(C_LAUNCHER),
                "-C".into(),
                script(CXX_LAUNCHER),
                "-S".into(),
                ".".into(),
            ]
        );
        assert!(
            directory
                .path()
                .join(launcher_script_name(C_LAUNCHER))
                .is_file()
        );
        assert_eq!(run("cmake", &["--build", "build"]), ["--build", "build"]);
        assert_eq!(run("make", &["-C", "build"]), ["-C", "build"]);
        assert_eq!(
            run("cmake", &["-S", ".", "-DCMAKE_C_COMPILER_LAUNCHER=ccache"]),
            [
                "-C".into(),
                script(CXX_LAUNCHER),
                "-S".into(),
                ".".into(),
                "-DCMAKE_C_COMPILER_LAUNCHER=ccache".into(),
            ]
        );
    }

    #[test]
    fn compiler_overrides_are_not_rewritten_or_wrapped() {
        let mut arguments = [OsString::from(
            "-DCMAKE_C_COMPILER=/custom/tuist_cargo_cache-c",
        )];
        let original = arguments.clone();
        let pins = BTreeMap::from([("/cache/tuist_cargo_cache-c".into(), "/usr/bin/cc".into())]);
        assert!(rewrite_compilers(&mut arguments, &pins).is_empty());
        assert_eq!(arguments, original);
    }
}
