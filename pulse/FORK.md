# Pulse: Tuist's fork of GreptimeDB

Pulse is the observability backend in Tuist's clusters. Since November 2026 it is
a fork of [GreptimeDB](https://github.com/GreptimeTeam/greptimedb); before that it
was a separate Elixir application, which is in this directory's history before
the import commit. The code keeps GreptimeDB's names; Tuist publishes it as
`ghcr.io/tuist/pulse`, and clusters deploy it as the `pulse` release.

## Upstream base

| | |
| --- | --- |
| Repository | https://github.com/GreptimeTeam/greptimedb |
| Tag | `v1.3.0` |
| Commit | `badceec12a0e98fd69e83e9b9b9b06d9358b78dd` (2026-10-28) |
| License | Apache-2.0, in [`LICENSE`](LICENSE). Upstream has no NOTICE file. |

The import is the upstream tree at that commit, except:

- **Enterprise sources.** GreptimeDB is open core. The files under the GreptimeDB
  Enterprise License are not Apache-2.0, and that license forbids copying or
  distributing them, so they are not in this repository: `LICENSE-ENTERPRISE`,
  `licenserc-enterprise.toml`, `licenses/enterprise-header.txt`, and the sources
  below (triggers, the recycle bin, and undrop and purge of dropped tables).
  They compile only with the `enterprise` Cargo feature, which the fork never
  enables; the default build is unchanged, and building with the feature fails
  on the missing files. `pulse.yml` reads this list to stub the files for
  rustfmt, which follows `mod` declarations even when they are cfg'd out.

  - `src/catalog/src/system_schema/information_schema/recycle_bin.rs`
  - `src/catalog/src/system_schema/information_schema/recycle_bin_test.rs`
  - `src/common/function/src/admin/purge_table.rs`
  - `src/common/meta/src/ddl/purge_dropped_table.rs`
  - `src/common/meta/src/ddl/undrop_table.rs`
  - `src/common/meta/src/rpc/ddl/trigger.rs`
  - `src/mito2/src/extension.rs`
  - `src/operator/src/expr_helper/trigger.rs`
  - `src/sql/src/parsers/alter_parser/trigger.rs`
  - `src/sql/src/parsers/create_parser/trigger.rs`
  - `src/sql/src/parsers/show_parser/trigger.rs`
  - `src/sql/src/statements/alter/trigger.rs`
  - `src/sql/src/statements/create/trigger.rs`
  - `src/sql/src/statements/drop/trigger.rs`
  - `src/sql/src/statements/show/trigger.rs`

- **Upstream automation.** `.github/` (its workflows do not run inside this
  monorepo) and the agent skills in `.agents/skills/` and `.claude/`.
  `AGENTS.md`, its `CLAUDE.md` symlink and the rest of `.agents/` are kept.

## Tuist changes

Every Tuist change to an upstream file is marked with a `Modified by Tuist`
line under its license header, or a `Tuist:` comment at the change.

- **Query nesting limits** ([`src/sql/src/nesting.rs`](src/sql/src/nesting.rs)).
  GreptimeDB v1.3.0 aborts the whole process with a stack overflow on short,
  deeply nested queries, and any reader can send them: a PromQL chain of about
  80 binary operators (`vector(1)+vector(1)+…`, around 800 bytes), 48 nested
  subqueries, a SQL chain of about 4,000 operators (`SELECT 1+1+…`) or 256
  chained `UNION ALL`s. Parsing now rejects, with an ordinary syntax error:
  - PromQL nested more than 32 levels, or with more than 4,096 operators,
    parentheses and brackets. Every PromQL parse in the query path goes through
    `sql::nesting::parse_promql`: the HTTP API, TQL, and the format, parse and
    series endpoints. The deepest query in Tuist's dashboards and alerts is 14
    levels deep.
  - SQL expressions nested more than 128 levels and queries chaining more than
    64 set operations, checked in `ParserContext::create_with_dialect`. This is
    stricter than the query analyzer's later limit of the same number: depth
    carries across subqueries and parentheses count, so a `WHERE` with about
    130 chained `AND`s is rejected. MySQL `EXECUTE … USING` arguments bypass
    this check; Tuist's deployments do not expose the MySQL port.
  - SQL texts over 8 MiB. Parsing runs on a stack sized to the input, so a long
    statement cannot overflow the parser or its drop.
- **Release image protoc** ([`docker/buildx/ubuntu/Dockerfile`](docker/buildx/ubuntu/Dockerfile)).
  The image `pulse-release.yml` builds installed Ubuntu 22.04's protoc 3.12,
  which cannot compile `substrait`'s proto3 optional fields. It now installs
  protoc 29.3 from GitHub, checksum-pinned, as upstream's dev-builder does.

## Build, release and deploy

- [`pulse.yml`](../.github/workflows/pulse.yml) checks formatting, runs the
  `sql` crate's tests (where the limits live), and type-checks the `greptime`
  binary, which covers the other changed crates.
- [`pulse-release.yml`](../.github/workflows/pulse-release.yml) publishes
  `ghcr.io/tuist/pulse:<version>` and the `pulse@<version>` tag when `pulse/`
  changes on main. Versions are the upstream version plus a fork revision, such
  as `1.3.0-tuist.1`. The image is built with upstream's
  `docker/buildx/ubuntu/Dockerfile` and release profile (`nightly`), without
  the embedded web dashboard (`servers/dashboard`).
- Publishing deploys nothing. In each cluster's `observability` namespace the
  `pulse` release ([`infra/helm/greptimedb`](../infra/helm/greptimedb), Service
  `pulse`) runs the fork release pinned in its `values.yaml`, and collectors
  write to it directly. `greptimedb-deployment.yml` rolls it out when
  dispatched. Moving to a new release means changing that pin and the one in
  `infra/helm/greptimedb/test-managed.sh`, then dispatching the deployment.
  `.github/scripts/pulse-readiness.sh`, the gate every server deploy runs,
  accepts any `ghcr.io/tuist/pulse:<version>-tuist.<n>` image.

## Moving to a newer upstream version

1. Import the new upstream tag's tree over `pulse/` with the same exclusions,
   using that version's `licenserc-enterprise.toml` for the enterprise list.
2. Reapply the Tuist changes above (the commits touching `pulse/` since the
   previous import) and update this file's upstream table.
3. Check that every PromQL parse still goes through `sql::nesting::parse_promql`
   (`rg 'promql_parser::parser::parse\(' src` outside tests), and repeat the
   overflow checks against the new planner before trusting the limits.
