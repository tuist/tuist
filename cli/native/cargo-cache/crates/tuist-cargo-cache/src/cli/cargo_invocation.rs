//! Resolve aliases only from configuration that preserves argument boundaries.
//!
//! `cargo --list` is a command inventory, not an argument serialization format.
//! Never parse its alias descriptions: an array element containing whitespace
//! is indistinguishable there from several elements. Unsupported configuration
//! leaves the invocation unresolved, so failed metadata cannot authorize a build.

use std::collections::{BTreeMap, BTreeSet};
use std::ffi::{OsStr, OsString};
use std::path::Path;
use std::process::Command;

pub(super) enum Kind {
    Unknown,
    Proxy,
    Build,
    External,
}

pub(super) struct Invocation {
    pub arguments: Vec<OsString>,
    pub kind: Kind,
}

#[derive(serde::Deserialize)]
#[serde(untagged)]
enum Alias {
    String(String),
    Array(Vec<String>),
}

impl Alias {
    fn arguments(self) -> Vec<OsString> {
        match self {
            Self::String(value) => value.split_whitespace().map(OsString::from).collect(),
            Self::Array(value) => value.into_iter().map(OsString::from).collect(),
        }
    }
}

// cargo-config2 implements Cargo's hierarchy, legacy config-file precedence,
// and array merging. Its unresolved representation retains string vs array,
// allowing Cargo's alias-specific whitespace rule to be applied to strings.
// It does not implement includes; never silently ignore those.
//
// Nothing where the configuration cannot be read in full. An `include` can
// define an alias or redefine one, so an alias read past it could name a
// different package, and the shorthand names are configuration that an
// include can redefine too. The caller reads nothing from configuration in
// that case and lets the listing answer, which refuses whatever Cargo calls
// an alias. A command that is no alias at all is unaffected: no include turns
// `cargo binstall` into something else.
fn aliases(cwd: &Path) -> Option<BTreeMap<String, Alias>> {
    for path in cargo_config2::Walk::new(cwd) {
        let value: toml::Value = toml::from_str(&std::fs::read_to_string(path).ok()?).ok()?;
        if value.get("include").is_some() {
            return None;
        }
    }
    let config = cargo_config2::de::Config::load_with_cwd(cwd).ok()?;
    serde_json::from_value(serde_json::to_value(config.alias).ok()?).ok()
}

fn builtin(command: &str) -> bool {
    matches!(
        command,
        "build"
            | "check"
            | "test"
            | "run"
            | "bench"
            | "doc"
            | "rustc"
            | "rustdoc"
            | "fix"
            | "install"
            | "help"
            | "new"
            | "init"
            | "add"
            | "remove"
            | "update"
            | "fetch"
            | "clean"
            | "config"
            | "tree"
            | "search"
            | "info"
            | "login"
            | "logout"
            | "owner"
            | "package"
            | "publish"
            | "uninstall"
            | "yank"
            | "locate-project"
            | "metadata"
            | "generate-lockfile"
            | "pkgid"
            | "read-manifest"
            | "report"
            | "vendor"
            | "verify-project"
            | "version"
            | "git-checkout"
    )
}

fn default_alias(command: &str) -> Option<&'static str> {
    match command {
        "b" => Some("build"),
        "c" => Some("check"),
        "d" => Some("doc"),
        "r" => Some("run"),
        "t" => Some("test"),
        "rm" => Some("remove"),
        _ => None,
    }
}

fn unsupported(arguments: &[OsString]) -> bool {
    arguments.iter().take_while(|arg| *arg != "--").any(|arg| {
        let arg = arg.to_string_lossy();
        // Directory changes and single-file scripts need different probing.
        arg.starts_with("-Z") || arg.starts_with("-C") || arg.starts_with("--directory")
    })
}

fn config_override(arguments: &[OsString]) -> bool {
    arguments
        .iter()
        .take_while(|arg| *arg != "--")
        .any(|arg| arg == "--config" || arg.to_string_lossy().starts_with("--config="))
}

/// The command line Cargo runs once aliases are expanded, for a caller that
/// needs to look inside it.
///
/// Commands Cargo will not let configuration redefine are answered from the
/// command line alone. `clippy` is one of them here: it is an external command,
/// and a lane is chosen on every run, so reading configuration for it would
/// cost a lookup on the path this exists to keep short. Only a shorthand such
/// as `c` or a configured alias reads configuration.
pub(super) fn expanded_arguments(cargo: &OsStr, arguments: &[String]) -> Option<Vec<String>> {
    let typed = super::launch::cargo_subcommand(arguments)?;
    if builtin(typed) || typed == "clippy" {
        return Some(arguments.to_vec());
    }
    let typed_arguments = arguments.iter().map(OsString::from).collect::<Vec<_>>();
    let resolved = super::strings(&resolve(cargo, &typed_arguments)?.arguments).ok()?;
    // An expansion that brings its own `--` would hand a flag added after the
    // alias to the compiler rather than to Cargo.
    let separator = |arguments: &[String]| arguments.iter().any(|argument| argument == "--");
    if separator(&resolved) && !separator(arguments) {
        return None;
    }
    Some(resolved)
}

pub(super) fn resolve(cargo: &OsStr, arguments: &[OsString]) -> Option<Invocation> {
    let mut arguments = arguments.to_vec();
    let mut aliases = None;
    let mut expanded = BTreeSet::new();
    loop {
        if unsupported(&arguments) {
            return None;
        }
        let (index, command) = super::launch::cargo_subcommand_at(&arguments)?;
        // Real builtins shadow user aliases; the shorthand names do not.
        if builtin(command) {
            let kind = if super::shim::cargo_proxy_passthrough(&arguments) {
                Kind::Proxy
            } else {
                Kind::Build
            };
            return Some(Invocation { arguments, kind });
        }
        if aliases.is_none() {
            aliases = Some(self::aliases(&std::env::current_dir().ok()?));
        }
        // Configuration that could not be read in full supplies no alias, not
        // even a shorthand: the environment merges onto what a file declared,
        // and an unread file leaves nothing to merge onto. The listing below
        // then classifies the command and refuses any alias among them.
        let alias = match aliases.as_mut()?.as_mut() {
            None => None,
            Some(aliases) => {
                // Cargo looks up the environment by normalized key, including
                // aliases not present in any file. Do not enumerate uppercase
                // names as commands.
                let key = format!("CARGO_ALIAS_{}", command.replace('-', "_").to_uppercase());
                let configured = aliases.remove(command);
                match (configured, std::env::var_os(key)) {
                    (Some(Alias::Array(mut words)), Some(value)) => {
                        // Cargo concatenates environment values onto configured
                        // arrays, whereas strings are replaced by the environment.
                        words.extend(
                            value
                                .into_string()
                                .ok()?
                                .split_whitespace()
                                .map(str::to_owned),
                        );
                        Some(Alias::Array(words))
                    }
                    (_, Some(value)) => Some(Alias::String(value.into_string().ok()?)),
                    (value, None) => value.or_else(|| {
                        default_alias(command).map(|value| Alias::String(value.to_owned()))
                    }),
                }
            }
        };
        if let Some(alias) = alias {
            // Cargo applies CLI overrides at a different stage from alias
            // expansion. Until that ordering is modeled, do not recover roots
            // or authorize passthrough for aliases carrying overrides.
            if config_override(&arguments)
                || expanded.len() == 32
                || !expanded.insert(command.to_owned())
            {
                return None;
            }
            let expansion = alias.arguments();
            if expansion.is_empty() || config_override(&expansion) {
                return None;
            }
            arguments.splice(index..index + 1, expansion);
            continue;
        }
        if expanded.contains(command) {
            return None;
        }
        // Only classification comes from the listing. If Cargo sees an alias
        // our supported configuration did not, refuse rather than interpreting
        // the human-readable body. Carry the selected toolchain/global flags.
        let output = Command::new(cargo)
            .args(&arguments[..index])
            .args(["--color=never", "--list"])
            .output()
            .ok()?;
        let listing = std::str::from_utf8(&output.stdout).ok()?;
        if !output.status.success()
            || listing
                .lines()
                .next()
                .is_none_or(|line| line != "Installed Commands:")
        {
            return None;
        }
        let entry = listing.lines().skip(1).find_map(|line| {
            let line = line.trim();
            let end = line.find(char::is_whitespace).unwrap_or(line.len());
            (&line[..end] == command).then(|| line[end..].trim())
        });
        let kind = match entry {
            Some(description) if description.starts_with("alias:") => return None,
            Some(_) if super::shim::cargo_proxy_passthrough(&arguments) => Kind::Proxy,
            Some(_) => Kind::External,
            None => Kind::Unknown,
        };
        return Some(Invocation { arguments, kind });
    }
}
