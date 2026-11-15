# Pulse: Tuist's fork

Pulse was forked from [GreptimeDB](https://github.com/GreptimeTeam/greptimedb) under Apache-2.0.

Pulse is the observability backend in Tuist's clusters. Since November 2026 it
is this fork; before that it was a separate Elixir application, which is in
this directory's history before the import commit. Tuist renamed the code to
Pulse (see [Tuist changes](#tuist-changes)), publishes it as
`ghcr.io/tuist/pulse`, and clusters deploy it as the `pulse` release.

## Upstream base

| | |
| --- | --- |
| Repository | The upstream project linked above |
| Tag | `v1.3.0` |
| Commit | `badceec12a0e98fd69e83e9b9b9b06d9358b78dd` (2026-10-28) |
| License | Apache-2.0, in [`LICENSE`](LICENSE). Upstream has no NOTICE file. |

The import is the upstream tree at that commit, except:

- **Enterprise sources.** Upstream is open core. The files under its
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

- **Renamed to Pulse.** Every upstream name in the code is now a Pulse name:
  crates (`common-pulse-telemetry`), types, modules and files, the `pulse`
  binary and the image's entrypoint, comments, and the names Pulse stores or
  speaks on the wire: the default catalog `pulse` and its `pulse_private`
  schema (and so the object-store paths under them), the `pulse_timestamp`,
  `pulse_value` and `pulse_native_histogram` columns, the `pulse_identity` and
  `pulse_trace_v*` pipelines, the `x-pulse-*` HTTP headers and the
  `x-pulse-*` gRPC metadata nodes send each other, the `PULSE_*`
  configuration environment prefix, the `pulse_v1` response format, the
  `pulse_*` self-metrics, the `pulse_data`, `pulse_wal_topic` and
  `pulse_metakv` defaults, the `pulse:` column and parquet metadata keys, the
  `pulse.json`, `pulse.json2` and `pulse.histogram` extension types,
  `pulse.series_index`, the `pulse.semantic.*` table options, the `pulse-*`
  puffin index blob types, the fulltext index's `pulse_fulltext_*` field
  names, and the `__pulse_*` flow and DDL options. Releases before the rename
  wrote other names, which a renamed release does not read (see
  [Rolling out the rename](#rolling-out-the-rename)). Comments no longer link
  to upstream issues or documentation, tests start the Bitnami images
  upstream mirrored, and usage telemetry, which reported to upstream's
  collector, has no URL to report to. `tests/compatibility` and `tests/perf` compare against
  released binaries and images that Pulse does not publish; Tuist's CI runs
  neither.
  These keep upstream names:
  - The upstream copyright lines in the license headers and `LICENSE`, which
    Apache-2.0 requires us to keep.
  - Dependencies: the protobuf crate and what it generates (the request and
    response types, the gRPC services, and their packages on the wire), and
    the other upstream crates `Cargo.toml` fetches from GitHub, until Tuist
    forks them.
- **No enterprise feature.** The `enterprise` Cargo feature and every code path
  it gated are gone, as is the license tooling for enterprise files. Undrop and
  purge of dropped tables, and `gc.experimental_soft_drop`, which needs them,
  are rejected as unsupported, as they were in the default build.
- **No upstream docs or release tooling.** The code is the documentation:
  `docs/`, the READMEs and other Markdown guides in the source and test trees,
  the Grafana dashboards, the `cyborg` bot, upstream's README, contribution and
  security guides, changelog and coverage configuration, the generated
  configuration reference, the Docker builds other than `docker/buildx/ubuntu`,
  and the Makefile targets that used them are gone. The `AGENTS.md` guides are
  kept for agents working in those crates.

- **Query nesting limits** ([`src/sql/src/nesting.rs`](src/sql/src/nesting.rs)).
  Upstream v1.3.0 aborts the whole process with a stack overflow on short,
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
- **Sentry envelope ingestion** ([`src/servers/src/http/sentry.rs`](src/servers/src/http/sentry.rs)).
  Sentry SDKs report errors to Pulse with a DSN such as
  `http://<user>:<password>@pulse.observability:4000/v1/sentry/<service>/1`:
  they post envelopes to `/v1/sentry/<service>/api/1/envelope/`, and the DSN's
  key and secret (`X-Sentry-Auth`, or the `sentry_key` and `sentry_secret`
  query parameters) authenticate as that Pulse user (`http/authorize.rs`).
  Every `event` item becomes a `{"service", "event"}` row for the
  `sentry_errors` pipeline and `errors` table that
  [`infra/helm/pulse`](../infra/helm/pulse) installs; other items
  are dropped. Responses carry the envelope's event ID, as Sentry's do.
  `tests-integration`'s `test_sentry_envelope` sends envelopes captured from
  sentry-elixir and sentry-rust.
- **Release image protoc** ([`docker/buildx/ubuntu/Dockerfile`](docker/buildx/ubuntu/Dockerfile)).
  The image `pulse-build-publish.yml` builds installed Ubuntu 22.04's protoc 3.12,
  which cannot compile `substrait`'s proto3 optional fields. It now installs
  protoc 29.3 from GitHub, checksum-pinned, as upstream's dev-builder does.

## Build, release and deploy

- [`pulse.yml`](../.github/workflows/pulse.yml) checks formatting, runs the
  `sql` crate's tests (where the limits live), and type-checks the `pulse`
  binary, which covers the other changed crates.
- Pulse owns its versions and releases through the same channels as Kura
  (`kura-release.yml`, `kura-rc.yml`, `kura-promote.yml`): every `pulse/`
  change on main publishes a canary `X.Y.0-canary.N`
  ([`pulse-release.yml`](../.github/workflows/pulse-release.yml)); each Monday
  [`pulse-promote.yml`](../.github/workflows/pulse-promote.yml) promotes the
  previous week's `releases/pulse-X.Y.x` line to stable `X.Y.0`, and
  [`pulse-rc.yml`](../.github/workflows/pulse-rc.yml) cuts the next line as
  `X.Y.0-rc.1`. Versions continue the Elixir Pulse's line (`1.43.6`), so the
  first canary is `1.44.0-canary.1`; the upstream version stays in
  `Cargo.toml`'s `[workspace.package]` and the [table above](#upstream-base).
  The earlier `pulse@1.3.0-1` and `pulse@1.3.0-2` tags used the retired
  `<upstream>-<n>` scheme.
- [`pulse-build-publish.yml`](../.github/workflows/pulse-build-publish.yml)
  does each build: it stamps the version into `[workspace.metadata.pulse]`
  (what `pulse --version` and SQL `version()` report), builds the image with
  upstream's `docker/buildx/ubuntu/Dockerfile` and release profile (`nightly`)
  without the embedded web dashboard (`servers/dashboard`), smoke-tests it,
  and publishes `ghcr.io/tuist/pulse:<version>` (stable releases also move
  `:latest`), the `pulse@<version>` tag and a GitHub prerelease or release
  with git-cliff notes ([`cliff.toml`](cliff.toml)). Pulse releases never take
  the repository's GitHub "Latest" release, which the CLI, server and Kura use.
- Canaries deploy continuously, as Kura's do.
  [`pulse-production-deployment.yml`](../.github/workflows/pulse-production-deployment.yml)
  runs on every push to main that changes `pulse/`, the chart or its
  deployment: it publishes a canary when `pulse/` changed, then deploys
  staging, canary and production in turn through `pulse-deployment.yml`,
  each leg only after the previous one qualified. In each cluster's
  `observability` namespace the `pulse` release
  ([`infra/helm/pulse`](../infra/helm/pulse), Service `pulse`) runs the newest
  `pulse@*-canary.*` the deployed commit contains, or the image pinned in its
  `values.yaml` for a commit without one. RCs and stable releases deploy
  nothing. Dispatch `pulse-deployment.yml` to redeploy or roll back one
  environment. `.github/scripts/pulse-readiness.sh`, the gate every server
  deploy runs, accepts any published `ghcr.io/tuist/pulse` version.

## Rolling out the rename

The infrastructure around Pulse uses Pulse's names: the chart
([`infra/helm/pulse`](../infra/helm/pulse)), its deployment workflow
(`pulse-deployment.yml`) and smoke scripts, the storage credentials
(`PULSE_STANDALONE__*`, `PULSE_DATANODE__*`), and the `X-Pulse-*` headers and
`pulse_trace_v1` pipeline the collectors in `infra/helm/k8s-monitoring` and the
server's `Tuist.Pulse` send.

The rename changed the names Pulse writes to disk and sends between its own
nodes (metadata keys, extension types, index blob types, table options and
internal gRPC metadata), and Pulse reads only the new ones. A renamed release
therefore neither opens data an earlier release wrote nor talks to its nodes,
so every cluster (staging, canary, production and management) is reinstalled
from empty (storage, metadata and WAL) when it moves to a renamed release, and
nothing is migrated.

## Moving to a newer upstream version

1. Import the new upstream tag's tree over `pulse/` with the same exclusions,
   using that version's `licenserc-enterprise.toml` for the enterprise list.
2. Reapply the Tuist changes above (the commits touching `pulse/` since the
   previous import), including the rename, the enterprise removal and the
   removed docs, and update this file's upstream table. Keep
   `[workspace.metadata.pulse]` out of `Cargo.toml`: the release build stamps
   it and refuses to run when it is already set. The Pulse version is not tied
   to upstream's; the next canary continues the current line.
3. Check that every PromQL parse still goes through `sql::nesting::parse_promql`
   (`rg 'promql_parser::parser::parse\(' src` outside tests), and repeat the
   overflow checks against the new planner before trusting the limits.
