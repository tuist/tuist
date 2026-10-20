use std::fs;
use std::path::Path;

use crate::error::{Error, Result};

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ScriptAnnotations {
    pub runtime: String,
    pub runtime_args: Vec<String>,
    pub inputs: Vec<String>,
    pub outputs: Vec<String>,
    pub env_vars: Vec<String>,
    pub cwd: Option<String>,
    pub remote: Option<String>,
    pub output_symlinks: Option<String>,
}

pub fn parse_script_annotations(path: &Path, display_name: &str) -> Result<ScriptAnnotations> {
    let content = fs::read_to_string(path).map_err(|source| Error::Read {
        path: path.display().to_string(),
        source,
    })?;
    let mut lines = content.lines();
    let shebang = lines.next().ok_or_else(|| Error::Eval {
        path: display_name.to_string(),
        message: format!("script {} is empty", path.display()),
    })?;
    let (runtime, runtime_args) = parse_shebang(shebang, display_name, path)?;
    let mut annotations = ScriptAnnotations {
        runtime,
        runtime_args,
        ..Default::default()
    };

    for line in lines {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let Some(rest) = annotation_payload(trimmed) else {
            if looks_like_comment(trimmed) {
                continue;
            }
            break;
        };
        parse_annotation_line(&mut annotations, rest, display_name)?;
    }

    Ok(annotations)
}

fn parse_shebang(line: &str, display_name: &str, path: &Path) -> Result<(String, Vec<String>)> {
    let Some(raw) = line.strip_prefix("#!") else {
        return Err(Error::Eval {
            path: display_name.to_string(),
            message: format!(
                "script {} must start with a shebang so Once knows how to run it",
                path.display()
            ),
        });
    };
    let mut parts = raw.split_whitespace();
    let Some(first) = parts.next() else {
        return Err(Error::Eval {
            path: display_name.to_string(),
            message: format!("script {} has an empty shebang", path.display()),
        });
    };

    if first.ends_with("/env") || first == "env" {
        let mut runtime = None;
        let mut runtime_args = Vec::new();
        for part in parts.by_ref() {
            if runtime.is_none() && part.starts_with('-') {
                continue;
            }
            if runtime.is_none() {
                runtime = Some(part.to_string());
            } else {
                runtime_args.push(part.to_string());
            }
        }
        let Some(runtime) = runtime else {
            return Err(Error::Eval {
                path: display_name.to_string(),
                message: format!(
                    "script {} shebang must name a runtime after env",
                    path.display()
                ),
            });
        };
        return Ok(parse_once_exec_shebang(runtime, runtime_args));
    }

    Ok((first.to_string(), parts.map(ToString::to_string).collect()))
}

fn parse_once_exec_shebang(runtime: String, runtime_args: Vec<String>) -> (String, Vec<String>) {
    if (runtime == "once" || runtime.ends_with("/once"))
        && runtime_args.first().is_some_and(|arg| arg == "exec")
        && runtime_args.get(1).is_some_and(|arg| arg == "--script")
        && runtime_args.get(2).is_some()
    {
        let actual_runtime = runtime_args[2].clone();
        let actual_runtime_args = runtime_args[3..].to_vec();
        return (actual_runtime, actual_runtime_args);
    }
    if (runtime == "once" || runtime.ends_with("/once"))
        && runtime_args.first().is_some_and(|arg| arg == "exec")
        && runtime_args.get(1).is_some_and(|arg| arg == "--")
        && runtime_args.get(2).is_some()
    {
        let actual_runtime = runtime_args[2].clone();
        let actual_runtime_args = runtime_args[3..].to_vec();
        return (actual_runtime, actual_runtime_args);
    }
    (runtime, runtime_args)
}

fn annotation_payload(line: &str) -> Option<&str> {
    const COMMENT_PREFIXES: &[&str] = &["#", "//", ";", "--", "%", "'"];
    COMMENT_PREFIXES.iter().find_map(|prefix| {
        let rest = line.strip_prefix(prefix)?.trim_start();
        strip_once_marker(rest).map(str::trim_start)
    })
}

fn strip_once_marker(rest: &str) -> Option<&str> {
    let split = rest.find(char::is_whitespace).unwrap_or(rest.len());
    let marker = &rest[..split];
    if !marker.eq_ignore_ascii_case("once") {
        return None;
    }
    Some(&rest[split..])
}

fn looks_like_comment(line: &str) -> bool {
    ["#", "//", ";", "--", "%", "'"]
        .iter()
        .any(|prefix| line.starts_with(prefix))
}

fn parse_annotation_line(
    annotations: &mut ScriptAnnotations,
    line: &str,
    display_name: &str,
) -> Result<()> {
    if let Some(raw) = line.strip_prefix("input ") {
        annotations
            .inputs
            .push(parse_quoted(raw, "input", display_name)?);
        return Ok(());
    }
    if let Some(raw) = line.strip_prefix("output ") {
        annotations
            .outputs
            .push(parse_quoted(raw, "output", display_name)?);
        return Ok(());
    }
    if let Some(raw) = line.strip_prefix("env ") {
        annotations
            .env_vars
            .push(parse_quoted(raw, "env", display_name)?);
        return Ok(());
    }
    if let Some(raw) = line.strip_prefix("cwd ") {
        annotations.cwd = Some(parse_quoted(raw, "cwd", display_name)?);
        return Ok(());
    }
    if let Some(raw) = line.strip_prefix("remote ") {
        annotations.remote = Some(parse_quoted(raw, "remote", display_name)?);
        return Ok(());
    }
    if let Some(raw) = line.strip_prefix("output-symlinks ") {
        annotations.output_symlinks = Some(parse_quoted(raw, "output-symlinks", display_name)?);
        return Ok(());
    }
    Err(Error::Eval {
        path: display_name.to_string(),
        message: format!("unknown once directive `{line}`"),
    })
}

fn parse_quoted(raw: &str, name: &str, display_name: &str) -> Result<String> {
    let raw = raw.trim();
    let Some(rest) = raw.strip_prefix('"') else {
        return Err(Error::Eval {
            path: display_name.to_string(),
            message: format!("Once {name} expects a quoted string"),
        });
    };
    let Some(end) = rest.find('"') else {
        return Err(Error::Eval {
            path: display_name.to_string(),
            message: format!("Once {name} is missing a closing quote"),
        });
    };
    if !rest[end + 1..].trim().is_empty() {
        return Err(Error::Eval {
            path: display_name.to_string(),
            message: format!("Once {name} only accepts one quoted string"),
        });
    }
    Ok(rest[..end].to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn parses_bash_script_annotations() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("build.sh");
        fs::write(
            &path,
            r#"#!/usr/bin/env bash
# once input "src/**/*.ts"
# once output "dist/"
# once env "NODE_ENV"
# once cwd "."
# once output-symlinks "preserve"

echo hi
"#,
        )
        .unwrap();

        let annotations = parse_script_annotations(&path, "build.sh").unwrap();
        assert_eq!(annotations.runtime, "bash");
        assert_eq!(annotations.inputs, vec!["src/**/*.ts".to_string()]);
        assert_eq!(annotations.outputs, vec!["dist/".to_string()]);
        assert_eq!(annotations.env_vars, vec!["NODE_ENV".to_string()]);
        assert_eq!(annotations.cwd.as_deref(), Some("."));
        assert_eq!(annotations.output_symlinks.as_deref(), Some("preserve"));
    }

    #[test]
    fn parses_remote_script_annotation() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("build.sh");
        fs::write(
            &path,
            r#"#!/usr/bin/env bash
# once remote "microsandbox"

echo hi
"#,
        )
        .unwrap();

        let annotations = parse_script_annotations(&path, "build.sh").unwrap();
        assert_eq!(annotations.remote.as_deref(), Some("microsandbox"));
    }

    #[test]
    fn accepts_legacy_uppercase_once_marker() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("build.sh");
        fs::write(
            &path,
            r#"#!/usr/bin/env bash
# ONCE input "src/**/*.ts"
# ONCE output "dist/"

echo hi
"#,
        )
        .unwrap();

        let annotations = parse_script_annotations(&path, "build.sh").unwrap();
        assert_eq!(annotations.inputs, vec!["src/**/*.ts".to_string()]);
        assert_eq!(annotations.outputs, vec!["dist/".to_string()]);
    }

    #[test]
    fn parses_env_dash_s_runtime_args() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("build.js");
        fs::write(
            &path,
            r#"#!/usr/bin/env -S node --no-warnings
console.log("hi");
"#,
        )
        .unwrap();

        let annotations = parse_script_annotations(&path, "build.js").unwrap();
        assert_eq!(annotations.runtime, "node");
        assert_eq!(annotations.runtime_args, vec!["--no-warnings".to_string()]);
    }

    #[test]
    fn parses_multiple_comment_styles_for_script_annotations() {
        let tmp = TempDir::new().unwrap();
        for (name, runtime) in [
            ("build.py", "python3"),
            ("build.rb", "ruby"),
            ("build.exs", "elixir"),
        ] {
            let path = tmp.path().join(name);
            fs::write(
                &path,
                format!(
                    r#"#!/usr/bin/env {runtime}
# once input "src/**/*"
# once output "dist/"
# once env "APP_ENV"
# once cwd "."

print("hi")
"#
                ),
            )
            .unwrap();

            let annotations = parse_script_annotations(&path, name).unwrap();
            assert_eq!(annotations.runtime, runtime);
            assert_eq!(annotations.inputs, vec!["src/**/*".to_string()]);
            assert_eq!(annotations.outputs, vec!["dist/".to_string()]);
            assert_eq!(annotations.env_vars, vec!["APP_ENV".to_string()]);
            assert_eq!(annotations.cwd.as_deref(), Some("."));
        }
    }

    #[test]
    fn parses_once_exec_script_shebang() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("build.py");
        fs::write(
            &path,
            r#"#!/usr/bin/env -S once exec --script python3
# once input "src/**/*.py"
print("hi")
"#,
        )
        .unwrap();

        let annotations = parse_script_annotations(&path, "build.py").unwrap();
        assert_eq!(annotations.runtime, "python3");
        assert_eq!(annotations.inputs, vec!["src/**/*.py".to_string()]);
    }

    #[test]
    fn parses_once_exec_separator_shebang() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("build.py");
        fs::write(
            &path,
            r#"#!/usr/bin/env -S once exec -- python3
# once input "src/**/*.py"
print("hi")
"#,
        )
        .unwrap();

        let annotations = parse_script_annotations(&path, "build.py").unwrap();
        assert_eq!(annotations.runtime, "python3");
        assert_eq!(annotations.inputs, vec!["src/**/*.py".to_string()]);
    }

    #[test]
    fn rejects_unknown_directive() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("bad.sh");
        fs::write(
            &path,
            r#"#!/bin/sh
# once unknown "thing"
echo hi
"#,
        )
        .unwrap();

        let err = parse_script_annotations(&path, "bad.sh").unwrap_err();
        assert!(err.to_string().contains("unknown once directive"));
    }
}
