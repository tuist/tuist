# TuistXcodeProjectOrWorkspacePathLocator (CLI Module)

This module provides helpers for resolving Xcode project/workspace paths.

## Responsibilities
- Locate `.xcworkspace` or `.xcodeproj` under a given path.
- Honor `TUIST_WORKSPACE_PATH` (via `Environment.current.workspacePath`) when set.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistGenerator/AGENTS.md
- cli/Sources/TuistLoader/AGENTS.md

## Invariants
- Workspace has precedence over project; falls back to project if workspace is missing.
