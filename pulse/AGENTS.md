# AGENTS.md

This directory is Pulse, Tuist's observability database. It began as a fork of
GreptimeDB; [`FORK.md`](FORK.md) records the upstream base, every Tuist change
(including the rename from GreptimeDB and the removal of its enterprise
feature), how releases reach the clusters, and how to roll out the rename.

## Rules

- Keep each change listed in `FORK.md`, and add a
  `// Modified by Tuist; see pulse/FORK.md.` line under the license header of
  each upstream file you change. Keep upstream's `Copyright … Greptime Team`
  headers. New files carry the Apache-2.0 header with Tuist's copyright.
- Use Pulse names for new code and stored or wire names. Names from
  dependencies keep theirs: `greptime-proto` and what it generates
  (`GreptimeRequest`, `greptime.v1` gRPC packages), and the GreptimeTeam crates
  fetched in `Cargo.toml`.
- Parse PromQL with `sql::nesting::parse_promql`, never
  `promql_parser::parser::parse`, outside tests.
- `.github/workflows/pulse.yml` is the CI: `cargo fmt --all -- --check`,
  `cargo test -p sql --lib` for the nesting limits, and
  `cargo check --bin pulse`. Build scripts call `protoc` outside the repository,
  so set `PROTOC` to a real binary rather than a mise shim.
- `CLAUDE.md` is a symlink to this file. If `.local/AGENTS.md` exists, read it
  too; it holds machine-local overrides and is not shared.

## Core commands

| Task | Command |
| --- | --- |
| Build (debug) | `make build` |
| Build (release) | `make build RELEASE=true` |
| Run standalone | `cargo run -- standalone start` |
| Targeted Rust tests | `cargo nextest run -p <package>` (preferred over `cargo test`) |
| Full local Rust suite | `make test` |
| SQL tests | `cargo sqlness bare` (single case: `cargo sqlness bare -t <name>`) |
| Format | `make fmt` (and `make fmt-toml` for TOML) |
| Lint | `cargo clippy --workspace --all-targets -- -D warnings` |
| Type check | `cargo check --workspace --all-targets` |

Toolchain: Rust (pinned by `rust-toolchain.toml`), Protobuf compiler (>= 3.15),
C/C++ build essentials. Install the test runner with
`cargo install cargo-nextest --locked`.

## Repo map

Pulse is a Cargo workspace rooted at the repository; most crates live under
`src/` (plus `tests-fuzz`, `tests-integration`, `tests/runner`). Key areas:

- **Frontend / protocol**: `src/frontend/` (request orchestration), `src/servers/`
  (wire protocols), `src/sql/` (SQL parsing)
- **Storage engines**: `src/mito2/` (main time-series engine), `src/metric-engine/`
  (metrics), `src/file-engine/`
- **Coordination**: `src/meta-srv/` (metadata & cluster control), `src/meta-client/`
- **Execution / statements**: `src/operator/` (DDL/DML, request conversion, procedures)
- **Stream / transform**: `src/flow/` (continuous aggregation), `src/pipeline/`
- **Query / index**: `src/query/`, `src/promql/`, `src/index/`
- **Shared**: `src/common/`, `src/datatypes/`, `src/store-api/` (engine contract),
  `src/catalog/`, `src/table/`

Before editing a path, read every `AGENTS.md` from the repository root down to
that path. The root guide always applies; a nested guide adds or overrides rules
for its subtree. Changes spanning multiple subtrees must follow every applicable
guide.

`AGENTS.md` files are maps, not manuals. Keep them short and stable: record
where code lives, important boundaries or change-coupling, high-cost gotchas,
and the validation entry point. Implementation details belong in code. Do not
copy exhaustive test lists or workflow logic; link to the source of truth.

High-change areas and specialized test suites carry their own `AGENTS.md` with
a module map, read/write paths, change-coupling points, and gotchas:

- [`src/common/meta/AGENTS.md`](src/common/meta/AGENTS.md)
- [`src/query/AGENTS.md`](src/query/AGENTS.md)
- [`src/servers/AGENTS.md`](src/servers/AGENTS.md)
- [`src/operator/AGENTS.md`](src/operator/AGENTS.md)
- [`src/mito2/AGENTS.md`](src/mito2/AGENTS.md)
- [`src/metric-engine/AGENTS.md`](src/metric-engine/AGENTS.md)
- [`src/flow/AGENTS.md`](src/flow/AGENTS.md)
- [`src/frontend/AGENTS.md`](src/frontend/AGENTS.md)
- [`src/meta-srv/AGENTS.md`](src/meta-srv/AGENTS.md)
- [`tests-integration/AGENTS.md`](tests-integration/AGENTS.md)
- [`tests/compatibility/AGENTS.md`](tests/compatibility/AGENTS.md)
- [`tests/perf/AGENTS.md`](tests/perf/AGENTS.md)

## Read before changing code

- [`.agents/architecture-invariants.md`](.agents/architecture-invariants.md) —
  repo-wide rules that are easy to violate and expensive to get wrong (persisted
  and wire format compatibility, crate layering, async runtimes, error handling,
  the DataFusion fork).
- [`.agents/generated-files.md`](.agents/generated-files.md) — tool-generated
  artifacts that must not be hand-edited (sqlness `.result` files, proto).

## High-signal entry points

- Main binary: `src/cmd/src/bin/pulse.rs`
- Configuration: `src/common/config/`, example TOMLs in `config/`
- Error handling: `src/common/error/` (`ErrorExt`, `StatusCode`)
- Protocol implementations: `src/servers/src/`

## Validation by change type

Use the narrowest command that covers the change, then expand only when its
blast radius requires it.

| Change | Minimum validation |
| --- | --- |
| One Rust crate | `cargo nextest run -p <package>` |
| Cross-workspace Rust behavior | `make test` |
| SQL parsing, planning, execution, or output | `cargo sqlness bare -t <case>`; inspect regenerated `.result` files |
| Persisted metadata or wire format | Keep old data readable; `tests/compatibility/` has upstream's harness |
| Public configuration | Update example TOMLs and the configuration-loading and serialization snapshot tests |

For import/export, COPY, or snapshot-storage changes, follow
[`tests-integration/AGENTS.md`](tests-integration/AGENTS.md).

## Before committing

1. `make fmt`
2. `cargo clippy --workspace --all-targets -- -D warnings`
3. Targeted tests for the crates you changed (`make test` when the change spans
   the workspace).
4. `make check-udeps` (`make fix-udeps` removes unused dependencies).
5. Follow the repository root's commit conventions, with the `pulse` scope.
