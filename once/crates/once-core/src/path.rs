//! Workspace-relative paths.
//!
//! Action working directories must be expressed as paths relative to the
//! workspace root, not absolute filesystem paths. This is what lets two
//! developers (or CI and a developer) share cache entries: their
//! workspaces live at different absolute paths but the relative
//! structure is the same.

use std::fmt;
use std::path::{Component, Path, PathBuf};

use serde::{Deserialize, Serialize};

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum WorkspacePathError {
    #[error("workspace path must be relative, got `{0}`")]
    Absolute(String),
    #[error("workspace path must not escape the workspace, got `{0}`")]
    Escape(String),
    #[error("workspace path component is not valid utf-8: `{0}`")]
    NonUtf8(String),
}

/// A normalized, workspace-relative logical path.
///
/// Stored as a forward-slash-joined `String` regardless of host OS so
/// that the on-the-wire form (and therefore the action digest) is
/// portable across Linux, macOS, and Windows.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct WorkspacePath(String);

impl WorkspacePath {
    /// The empty path - equivalent to "the workspace root".
    pub fn root() -> Self {
        Self(String::new())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// Resolve against an absolute workspace root.
    pub fn resolve(&self, workspace: &Path) -> PathBuf {
        if self.0.is_empty() {
            workspace.to_path_buf()
        } else {
            workspace.join(&self.0)
        }
    }

    /// Build a workspace path from a package directory and a
    /// package-relative source path. Mirrors the ad-hoc string joins
    /// every plugin used to do by hand and routes the result through
    /// the same validation as [`WorkspacePath::try_from`], so a `..`
    /// in the declared source still surfaces as a structured error.
    pub fn from_package_relative(
        package: &str,
        src: &str,
    ) -> std::result::Result<Self, WorkspacePathError> {
        let joined = if package.is_empty() {
            src.to_string()
        } else {
            format!("{package}/{src}")
        };
        Self::try_from(joined)
    }
}

impl TryFrom<String> for WorkspacePath {
    type Error = WorkspacePathError;

    fn try_from(raw: String) -> Result<Self, Self::Error> {
        let path = Path::new(&raw);
        if path.is_absolute() {
            return Err(WorkspacePathError::Absolute(raw));
        }
        let mut parts: Vec<&str> = Vec::new();
        for comp in path.components() {
            match comp {
                Component::Normal(s) => match s.to_str() {
                    Some(s) => parts.push(s),
                    None => return Err(WorkspacePathError::NonUtf8(raw)),
                },
                Component::CurDir => {}
                Component::ParentDir | Component::Prefix(_) | Component::RootDir => {
                    return Err(WorkspacePathError::Escape(raw));
                }
            }
        }
        Ok(Self(parts.join("/")))
    }
}

impl TryFrom<&str> for WorkspacePath {
    type Error = WorkspacePathError;
    fn try_from(value: &str) -> Result<Self, Self::Error> {
        Self::try_from(value.to_string())
    }
}

impl From<WorkspacePath> for String {
    fn from(p: WorkspacePath) -> String {
        p.0
    }
}

impl fmt::Display for WorkspacePath {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl AsRef<str> for WorkspacePath {
    fn as_ref(&self) -> &str {
        &self.0
    }
}

impl AsRef<Path> for WorkspacePath {
    fn as_ref(&self) -> &Path {
        Path::new(&self.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_relative_path() {
        let p = WorkspacePath::try_from("crates/once-cli").unwrap();
        assert_eq!(p.as_str(), "crates/once-cli");
    }

    #[test]
    fn normalizes_dot_components() {
        let p = WorkspacePath::try_from("./crates/./once-cli").unwrap();
        assert_eq!(p.as_str(), "crates/once-cli");
    }

    #[test]
    fn rejects_absolute_paths() {
        assert!(matches!(
            WorkspacePath::try_from("/tmp/foo"),
            Err(WorkspacePathError::Absolute(_))
        ));
    }

    #[test]
    fn rejects_parent_escapes() {
        assert!(matches!(
            WorkspacePath::try_from("../sibling"),
            Err(WorkspacePathError::Escape(_))
        ));
        assert!(matches!(
            WorkspacePath::try_from("crates/../../escape"),
            Err(WorkspacePathError::Escape(_))
        ));
    }

    #[test]
    fn empty_is_root() {
        let p = WorkspacePath::try_from("").unwrap();
        assert!(p.as_str().is_empty());
        assert_eq!(p.resolve(Path::new("/ws")), Path::new("/ws"));
    }

    #[test]
    fn resolves_against_workspace() {
        let p = WorkspacePath::try_from("crates/once-cli").unwrap();
        assert_eq!(
            p.resolve(Path::new("/ws")),
            Path::new("/ws/crates/once-cli")
        );
    }

    #[test]
    fn from_package_relative_joins_and_validates() {
        let inside = WorkspacePath::from_package_relative("crates/foo", "src/main.rs").unwrap();
        assert_eq!(inside.as_str(), "crates/foo/src/main.rs");
        let root = WorkspacePath::from_package_relative("", "main.rs").unwrap();
        assert_eq!(root.as_str(), "main.rs");
    }

    #[test]
    fn from_package_relative_rejects_escapes() {
        // The frontend collects whatever the user wrote in a `srcs`
        // entry; preventing the join from escaping the package is a
        // workspace-path concern, not a per-plugin one.
        let err = WorkspacePath::from_package_relative("pkg", "../escape.rs").unwrap_err();
        assert!(matches!(err, WorkspacePathError::Escape(_)));
    }
}
