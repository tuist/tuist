# Pulse: Tuist's fork of GreptimeDB

Pulse is the observability backend in Tuist's clusters. Since November 2026 it is
a fork of [GreptimeDB](https://github.com/GreptimeTeam/greptimedb); before that it
was a separate Elixir application, which is in this directory's history before
the import commit. Tuist renamed the code to Pulse (see [Tuist changes](#tuist-changes)),
publishes it as `ghcr.io/tuist/pulse`, and clusters deploy it as the `pulse`
release.

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
  for triggers, the recycle bin, and undrop and purge of dropped tables. The
  `enterprise` Cargo feature and the code it gated were removed after the
  import (see below).
- **Upstream automation.** `.github/` (its workflows do not run inside this
  monorepo) and the agent skills in `.agents/skills/` and `.claude/`.
  `AGENTS.md`, its `CLAUDE.md` symlink and the rest of `.agents/` are kept.

## Tuist changes

Every upstream source file Tuist changed is marked with a `Modified by Tuist`
line under its license header, or a `Tuist:` comment at the change. Files
without a license header, such as test expectations and configuration, are
covered by this list.

- **Renamed to Pulse.** Every GreptimeDB name in the code is now a Pulse name:
  crates (`common-pulse-telemetry`), types, modules and files, the `pulse`
  binary and the image's entrypoint, comments, and the names Pulse stores or
  speaks on the wire: the default catalog `pulse` and its `pulse_private`
  schema (and so the object-store paths under them), the `pulse_timestamp`,
  `pulse_value` and `pulse_native_histogram` columns, the `pulse_identity` and
  `pulse_trace_v*` pipelines, the `x-pulse-*` HTTP headers, the `PULSE_*`
  configuration environment prefix, the `pulse_v1` response format, the
  `pulse_*` self-metrics, and the `pulse_data`, `pulse_wal_topic` and
  `pulse_metakv` defaults. Data written under the old catalog is not migrated
  (see [Rolling out the rename](#rolling-out-the-rename)).
  These keep Greptime names:
  - On-disk format identifiers, so a renamed release opens the metadata, SSTs
    and indexes earlier releases wrote and stays readable by upstream tools:
    `greptime:` column and parquet metadata keys, the `greptime.json`,
    `greptime.json2` and `greptime.histogram` extension types,
    `greptime.series_index`, `greptime.semantic.*` table options, puffin index
    blob types, the fulltext index's field names, and the `__greptime_*` flow
    and DDL options.
  - Headers only Pulse's own nodes send each other (`x-greptime-snapshot-seqs`,
    `x-greptime-flow-extensions`, `x-greptime-internal-create-database-creator-bin`),
    so nodes on either side of a rolling upgrade still understand each other.
  - The `Copyright … Greptime Team` license headers and `LICENSE`, which
    Apache-2.0 requires us to keep.
  - Dependencies: `greptime-proto` and what it generates (`GreptimeRequest`,
    `GreptimeDatabase` and the other gRPC types, and the `greptime.v1`
    packages on the wire), and the other GreptimeTeam crates `Cargo.toml`
    fetches from GitHub.
  - Links to upstream issues and documentation, and the Greptime container
    images some tests and harnesses start. `tests/compatibility` and
    `tests/perf` still compare against upstream GreptimeDB releases, so they no
    longer match Pulse's names; Tuist's CI runs neither.
- **No enterprise feature.** The `enterprise` Cargo feature and every code path
  it gated are gone, as is the license tooling for enterprise files. Undrop and
  purge of dropped tables, and `gc.experimental_soft_drop`, which needs them,
  are rejected as unsupported, as they were in the default build.
- **No upstream docs or release tooling.** `docs/`, the Grafana dashboards, the
  `cyborg` bot, upstream's README, contribution and security guides, changelog
  and coverage configuration, the generated configuration reference, the
  Docker builds other than `docker/buildx/ubuntu`, and the Makefile targets
  that used them.

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
  `sql` crate's tests (where the limits live), and type-checks the `pulse`
  binary, which covers the other changed crates.
- [`pulse-release.yml`](../.github/workflows/pulse-release.yml) publishes
  `ghcr.io/tuist/pulse:<version>` and the `pulse@<version>` tag when `pulse/`
  changes on main. Versions are the upstream version plus a fork revision, such
  as `1.3.0-1`. The image is built with upstream's
  `docker/buildx/ubuntu/Dockerfile` and release profile (`nightly`), without
  the embedded web dashboard (`servers/dashboard`).
- Publishing deploys nothing. In each cluster's `observability` namespace the
  `pulse` release ([`infra/helm/greptimedb`](../infra/helm/greptimedb), Service
  `pulse`) runs the fork release pinned in its `values.yaml`, and collectors
  write to it directly. `greptimedb-deployment.yml` rolls it out when
  dispatched. Moving to a new release means changing that pin and the one in
  `infra/helm/greptimedb/test-managed.sh`, then dispatching the deployment.
  `.github/scripts/pulse-readiness.sh`, the gate every server deploy runs,
  accepts any `ghcr.io/tuist/pulse:<version>-<n>` image.

## Rolling out the rename

The clusters run releases built before the rename, and the infrastructure
around them still uses GreptimeDB's names. The change that moves the pin to the
first renamed release has to switch them too, or ingestion and queries fail:

- The chart's storage credentials: `GREPTIMEDB_STANDALONE__*` and
  `GREPTIMEDB_DATANODE__*` become `PULSE_STANDALONE__*` and `PULSE_DATANODE__*`.
- The collectors in `infra/helm/k8s-monitoring` and the server's `Tuist.Pulse`
  deploy independently of the backend, so they send both the `X-Greptime-*`
  and `X-Pulse-*` headers (and both trace pipeline names) until every
  environment runs a renamed release. Each release ignores the other's names.
- `infra/helm/greptimedb/loki-otlp.yaml` and the smoke scripts in
  `.github/scripts`: headers and the `greptime_timestamp` column.
- Storage: the upgrade is in place, without a migration and without wiping
  anything, because the on-disk formats are unchanged. The renamed release
  creates the `pulse` catalog next to the old `greptime` one, and collectors
  write into it from then on; tables in the `greptime` catalog stay in
  metadata and under `data/greptime/` in the bucket, unread.

## Moving to a newer upstream version

1. Import the new upstream tag's tree over `pulse/` with the same exclusions,
   using that version's `licenserc-enterprise.toml` for the enterprise list.
2. Reapply the Tuist changes above (the commits touching `pulse/` since the
   previous import), including the rename and the enterprise removal, and
   update this file's upstream table.
3. Check that every PromQL parse still goes through `sql::nesting::parse_promql`
   (`rg 'promql_parser::parser::parse\(' src` outside tests), and repeat the
   overflow checks against the new planner before trusting the limits.
