# TuistCI (CLI Module)

This module provides CI detection and metadata extraction for CLI workflows.

## Responsibilities
- Detect CI providers (GitHub Actions, GitLab, Bitrise, CircleCI, Buildkite, Codemagic).
- Produce `CIInfo` with provider, run ID, and project handle.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistSupport/AGENTS.md

## Invariants
- CI detection is purely environment-variable based.
