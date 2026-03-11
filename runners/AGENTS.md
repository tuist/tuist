# GitHub Runners (macOS + nix-darwin)

This directory configures Tuist's macOS GitHub Actions runners and their host bootstrap.

## Responsibilities
- nix-darwin configuration for dedicated runner hosts.
- GitHub runner service management and labels.
- Runner host package bootstrap, including Homebrew where needed.
- Bootstrap helpers for Scaleway Apple Silicon hosts.

## Out of Scope
- Cache service application code.
- Cache node NixOS configuration in `cache/platform/`.
- GitHub workflow logic outside runner-specific label and environment changes.

## Related Context
- Cache platform: `cache/platform/AGENTS.md`
- Root intent: `AGENTS.md`
