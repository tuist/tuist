//! Target id normalization.
//!
//! Build files declare dependency references in the local context of
//! the directory they live in. CLI arguments are project-root relative
//! unless they start with `./` or `../`, in which case they resolve
//! from the caller's current directory.

use std::path::{Path, PathBuf};

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum TargetIdError {
    #[error("target reference is empty")]
    Empty,
    #[error("target name `{0}` must be a single path segment")]
    InvalidName(String),
    #[error("target reference `{raw}` uses Bazel label syntax; use `{suggestion}`")]
    BazelSyntax { raw: String, suggestion: String },
    #[error("target reference `{0}` must not contain `:`")]
    Colon(String),
    #[error("target reference `{0}` must be relative to the project root")]
    Absolute(String),
    #[error("target reference `{0}` must not escape the project root")]
    EscapesRoot(String),
    #[error("target reference `{0}` contains an empty path segment")]
    EmptySegment(String),
    #[error("current directory `{cwd}` is outside project root `{root}`")]
    CurrentDirOutsideProject { cwd: String, root: String },
}

pub fn target_id(package: &str, name: &str) -> String {
    if package.is_empty() {
        name.to_string()
    } else {
        format!("{package}/{name}")
    }
}

pub fn validate_target_name(name: &str) -> Result<(), TargetIdError> {
    if name.is_empty() || name == "." || name == ".." || name.contains(['/', '\\', ':']) {
        return Err(TargetIdError::InvalidName(name.to_string()));
    }
    Ok(())
}

pub fn normalize_cli_target(workspace_root: &Path, raw: &str) -> Result<String, TargetIdError> {
    let current_dir = std::env::current_dir().map_err(|_| TargetIdError::Empty)?;
    normalize_cli_target_from(workspace_root, &current_dir, raw)
}

pub fn normalize_cli_target_from(
    workspace_root: &Path,
    current_dir: &Path,
    raw: &str,
) -> Result<String, TargetIdError> {
    validate_raw(raw)?;
    if raw.starts_with("./") || raw.starts_with("../") {
        let package = current_package(workspace_root, current_dir)?;
        normalize_from(&package, raw)
    } else {
        normalize_from(&[], raw)
    }
}

fn validate_raw(raw: &str) -> Result<(), TargetIdError> {
    if raw.is_empty() {
        return Err(TargetIdError::Empty);
    }
    if let Some(suggestion) = bazel_suggestion(raw) {
        return Err(TargetIdError::BazelSyntax {
            raw: raw.to_string(),
            suggestion,
        });
    }
    if raw.contains(':') {
        return Err(TargetIdError::Colon(raw.to_string()));
    }
    if raw.starts_with('/') {
        return Err(TargetIdError::Absolute(raw.to_string()));
    }
    Ok(())
}

fn bazel_suggestion(raw: &str) -> Option<String> {
    if let Some(name) = raw.strip_prefix(':') {
        return Some(name.to_string());
    }
    let rest = raw.strip_prefix("//")?;
    let (package, name) = rest.split_once(':')?;
    if package.is_empty() {
        Some(name.to_string())
    } else {
        Some(format!("{package}/{name}"))
    }
}

fn normalize_from(base: &[String], raw: &str) -> Result<String, TargetIdError> {
    let mut out = base.to_vec();
    for segment in raw.split('/') {
        match segment {
            "" => return Err(TargetIdError::EmptySegment(raw.to_string())),
            "." => {}
            ".." => {
                out.pop()
                    .ok_or_else(|| TargetIdError::EscapesRoot(raw.to_string()))?;
            }
            segment => {
                validate_segment(raw, segment)?;
                out.push(segment.to_string());
            }
        }
    }
    if out.is_empty() {
        return Err(TargetIdError::Empty);
    }
    Ok(out.join("/"))
}

fn validate_segment(raw: &str, segment: &str) -> Result<(), TargetIdError> {
    if segment.contains(['\\', ':']) {
        return Err(TargetIdError::Colon(raw.to_string()));
    }
    Ok(())
}

fn current_package(
    workspace_root: &Path,
    current_dir: &Path,
) -> Result<Vec<String>, TargetIdError> {
    let relative = current_dir.strip_prefix(workspace_root).map_err(|_| {
        TargetIdError::CurrentDirOutsideProject {
            cwd: display(current_dir),
            root: display(workspace_root),
        }
    })?;
    Ok(path_components(relative))
}

fn path_components(path: &Path) -> Vec<String> {
    path.components()
        .filter_map(|component| {
            let value = component.as_os_str().to_string_lossy();
            if value.is_empty() || value == "." {
                None
            } else {
                Some(value.replace(std::path::MAIN_SEPARATOR, "/"))
            }
        })
        .flat_map(|component| {
            component
                .split('/')
                .filter(|part| !part.is_empty())
                .map(str::to_string)
                .collect::<Vec<_>>()
        })
        .collect()
}

fn display(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

pub fn absolutize(path: PathBuf) -> std::io::Result<PathBuf> {
    if path.is_absolute() {
        std::fs::canonicalize(path)
    } else {
        std::fs::canonicalize(std::env::current_dir()?.join(path))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn target_id_joins_package_and_name() {
        assert_eq!(target_id("", "tool"), "tool");
        assert_eq!(
            target_id("examples/macos-cli", "hello"),
            "examples/macos-cli/hello"
        );
    }

    #[test]
    fn cli_deps_are_root_relative_by_default() {
        let tmp = TempDir::new().unwrap();
        let root = tmp.path();
        let current = root.join("examples/macos-cli");
        std::fs::create_dir_all(&current).unwrap();
        assert_eq!(
            normalize_cli_target_from(root, &current, "examples/macos-cli/hello").unwrap(),
            "examples/macos-cli/hello"
        );
        assert_eq!(
            normalize_cli_target_from(root, &current, "./hello").unwrap(),
            "examples/macos-cli/hello"
        );
        assert_eq!(
            normalize_cli_target_from(root, &current, "../shared/Logging").unwrap(),
            "examples/shared/Logging"
        );
    }

    #[test]
    fn cli_current_dir_must_be_inside_project_for_dot_refs() {
        let root = TempDir::new().unwrap();
        let outside = TempDir::new().unwrap();
        assert!(matches!(
            normalize_cli_target_from(root.path(), outside.path(), "./hello"),
            Err(TargetIdError::CurrentDirOutsideProject { .. })
        ));
    }
}
