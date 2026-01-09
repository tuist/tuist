# TuistRootDirectoryLocator (CLI Module)

This module provides helpers to resolve the Tuist root directory.

## Responsibilities
- Locate the root by walking up the tree and checking for `Tuist/`, `Tuist.swift`, `Plugin.swift`, or `.git`.
- Cache discovered root directories to avoid repeated traversal.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistLoader/AGENTS.md
- cli/Sources/TuistKit/AGENTS.md

## Invariants
- Root detection is ordered: Tuist dir, Tuist manifest, Plugin manifest, .git.
