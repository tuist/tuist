# Working on Once

Conventions for humans and AI agents contributing to Once. Once lives in the `once/`
directory of the `tuist/tuist` monorepo. Every command below is run from that
directory unless stated otherwise; `mise` picks up `once/mise.toml` from there.

Releases and CI/CD are wired at the monorepo root:

- `.github/workflows/once.yml` runs fmt, clippy, tests, shellspec, and a
  Windows build gate on any change under `once/**`.
- `.github/workflows/once-release.yml` cuts a release whenever the monorepo's
  `mise run release:check once` reports a bumped version. Releases are tagged
  `once@X.Y.Z` and published as GitHub Releases with per-target archives.
- `.github/workflows/once-docs.yml` builds the VitePress site under
  `once/docs/` and deploys it to `once.tuist.dev` via Cloudflare Workers.
- The component registry entry lives in
  `../mise/tasks/release/components.json` (name `once`, tag prefix `once@`).
- Release scripts (`release:package`, `release:notes`, `release:changelog`)
  live under `once/mise/tasks/release/`.

## Module Layout

**Avoid monolith Rust files.** When a `lib.rs` or `main.rs` grows past
roughly 200 lines or starts mixing unrelated concerns, split it into a
module per responsibility. The top-level file should read as a table of
contents: re-exports, `mod` declarations, and dispatch.

Tests live next to the code they exercise: `#[cfg(test)] mod tests { ... }`
inside each module file. Cross-module integration tests go under
`crates/<crate>/tests/`.

## Manifest Files

- Per-package manifests are named `once.toml`.
- The `.once/` directory at the workspace root is cache and runtime
  state, not a manifest. It is gitignored.
- `once.toml` is reserved for workspace configuration such as cache
  providers.
- Scripts declare their execution metadata with `# once` headers in the
  script file.

## Scope

Once focuses on cacheable and remotely executable scripts plus the
runtime API. It is not a build system and should not grow language
compiler frontends, dependency graph generation, or build target rules
without an explicit product decision.

Keep the CLI surface centered on:

- `once exec` for literal commands and annotated script files
- `once cache` for CAS and action-cache primitives
- `once runtime` for JSON-RPC runtime sessions
- `once auth` and `once toolchain` for supporting infrastructure

## Tests

- Rust unit tests cover in-process behavior such as digest stability,
  parser errors, cache key partitioning, and runtime query logic.
- Shellspec (`spec/*.sh`) covers the CLI's external contract end to
  end. Run `mise exec -- shellspec` after a release build.

## Toolchain

The repo pins `rust = "1.88"` in `mise.toml` and the workspace
`rust-version`. Bumping the toolchain affects the user-facing MSRV;
do it deliberately, not as a side effect of adding a dependency. The
Windows CI job reads the workspace `rust-version` so it stays aligned
with the same pin.

## Native Dependencies

Linux builds need `libcap-ng-dev` because the embedded Microsandbox
provider links through native KVM support. Install it before running
workspace builds locally on Linux:

```sh
sudo apt-get update && sudo apt-get install -y libcap-ng-dev
```

## Style

- No em dashes in user-facing text: README, docs, PRs, commits, and
  release notes. Rewrite with a comma, semicolon, or sentence break.
- No roadmap-phase numbers in code or doc comments. Describe behavior,
  not milestones, since milestones rename and the comments rot.
- Default to writing no comments. Add one only when the why is
  non-obvious.

## Running Things

```sh
mise install
mise exec -- cargo test --workspace
mise exec -- cargo clippy --workspace --all-targets -- -D warnings
mise exec -- cargo fmt --all -- --check
mise exec -- cargo build --release
mise exec -- shellspec

mise exec -- target/release/once exec -- cargo check --workspace
mise exec -- target/release/once exec -- /bin/sh -c 'printf hello'
```

`mise exec --` is required because the project's toolchain is mise-managed;
calling `cargo` directly will miss the pinned rustc.
