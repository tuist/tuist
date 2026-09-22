use std::collections::BTreeSet;

use anyhow::{Context, Result};
use clap::{Arg, Command, CommandFactory};
use serde::Serialize;

use crate::cli::Cli;

#[derive(Clone, Debug, Serialize)]
pub(super) struct CommandSurface {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub about: Option<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub aliases: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub args: Vec<ArgSurface>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub subcommands: Vec<CommandSurface>,
}

#[derive(Clone, Copy, Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub(super) enum ArgKind {
    Flag,
    Option,
    Positional,
}

#[derive(Clone, Debug, Serialize)]
pub(super) struct ArgSurface {
    pub id: String,
    pub syntax: String,
    pub kind: ArgKind,
    pub required: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub help: Option<String>,
}

pub(super) fn load(path: &[&str]) -> Result<CommandSurface> {
    let mut command = Cli::command();
    let selected = select_command(&mut command, path).context("selecting command surface")?;
    Ok(build_command_surface(selected, &BTreeSet::new()))
}

fn select_command<'a>(command: &'a mut Command, path: &[&str]) -> Result<&'a mut Command> {
    if let Some((head, tail)) = path.split_first() {
        let next = command
            .get_subcommands_mut()
            .find(|subcommand| subcommand.get_name() == *head)
            .with_context(|| format!("unknown command path segment `{head}`"))?;
        return select_command(next, tail);
    }
    Ok(command)
}

fn build_command_surface(
    command: &Command,
    inherited_globals: &BTreeSet<String>,
) -> CommandSurface {
    let mut globals = inherited_globals.clone();
    let args = command
        .get_arguments()
        .filter(|arg| !arg.is_hide_set())
        .filter(|arg| !arg.is_global_set() || !inherited_globals.contains(arg.get_id().as_str()))
        .map(|arg| {
            if arg.is_global_set() {
                globals.insert(arg.get_id().as_str().to_string());
            }
            build_arg_surface(arg)
        })
        .collect::<Vec<_>>();
    let subcommands = command
        .get_subcommands()
        .filter(|subcommand| !subcommand.is_hide_set())
        .map(|subcommand| build_command_surface(subcommand, &globals))
        .collect::<Vec<_>>();
    CommandSurface {
        name: command.get_name().to_string(),
        about: command.get_about().map(ToString::to_string),
        aliases: command
            .get_all_aliases()
            .map(ToString::to_string)
            .collect::<Vec<_>>(),
        args,
        subcommands,
    }
}

fn build_arg_surface(arg: &Arg) -> ArgSurface {
    let kind = if arg.is_positional() {
        ArgKind::Positional
    } else if arg.get_action().takes_values() {
        ArgKind::Option
    } else {
        ArgKind::Flag
    };
    ArgSurface {
        id: arg.get_id().as_str().to_string(),
        syntax: arg_syntax(arg),
        kind,
        required: arg.is_required_set(),
        help: arg.get_help().map(ToString::to_string),
    }
}

fn arg_syntax(arg: &Arg) -> String {
    if arg.is_positional() {
        let value = arg
            .get_value_names()
            .and_then(|names| names.first())
            .map_or_else(|| arg.get_id().as_str().to_uppercase(), ToString::to_string);
        return if arg.is_required_set() {
            format!("<{value}>")
        } else {
            format!("[{value}]")
        };
    }

    let mut parts = Vec::new();
    if let Some(short) = arg.get_short() {
        parts.push(format!("-{short}"));
    }
    if let Some(long) = arg.get_long() {
        parts.push(format!("--{long}"));
    }
    let mut syntax = parts.join(", ");
    if arg.get_action().takes_values() {
        let value = arg
            .get_value_names()
            .and_then(|names| names.first())
            .map_or("VALUE".to_string(), ToString::to_string);
        syntax.push(' ');
        syntax.push('<');
        syntax.push_str(&value);
        syntax.push('>');
    }
    syntax
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn root_surface_includes_run_and_global_list_flag() {
        let surface = load(&[]).unwrap();
        assert!(surface
            .subcommands
            .iter()
            .any(|command| command.name == "run"));
        assert!(surface.args.iter().any(|arg| arg.syntax.contains("--list")));
    }

    #[test]
    fn cache_subtree_resolves_to_blob_command() {
        let surface = load(&["cache"]).unwrap();
        assert_eq!(surface.name, "cache");
        assert!(surface
            .subcommands
            .iter()
            .any(|command| command.name == "blob"));
    }

    #[test]
    fn unknown_path_returns_error() {
        let err = load(&["does-not-exist"]).unwrap_err();
        assert!(format!("{err:#}").contains("unknown command path segment `does-not-exist`"));
    }

    #[test]
    fn every_subcommand_surface_path_resolves() {
        use clap::Parser;

        // Guards against drift between `Cmd::surface_path` and the
        // clap `#[command(name = ...)]` strings. A mismatch otherwise
        // only surfaces at runtime as "unknown command path segment"
        // when `<subcommand> --list` is invoked.
        let invocations: &[&[&str]] = &[
            &["once", "run", "t"],
            &["once", "exec", "true"],
            &["once", "cache", "stats"],
            &["once", "cache", "blob", "put", "-"],
            &[
                "once",
                "cache",
                "blob",
                "get",
                "0000000000000000000000000000000000000000000000000000000000000000",
            ],
            &[
                "once",
                "cache",
                "blob",
                "exists",
                "0000000000000000000000000000000000000000000000000000000000000000",
            ],
            &[
                "once",
                "cache",
                "action",
                "get",
                "0000000000000000000000000000000000000000000000000000000000000000",
            ],
            &["once", "toolchain", "inspect"],
            &["once", "runtime", "rpc", "/tmp/session"],
        ];
        for argv in invocations {
            let cli = crate::cli::Cli::try_parse_from(*argv)
                .unwrap_or_else(|e| panic!("parsing {argv:?}: {e}"));
            let path = cli.surface_path();
            let surface = load(&path).unwrap_or_else(|e| {
                panic!("resolving surface for {argv:?} (path {path:?}): {e:#}")
            });
            let expected = path.last().copied().unwrap_or("once");
            assert_eq!(surface.name, expected, "argv {argv:?} path {path:?}");
        }
    }
}
