# Pulse 🫀

An open-source, headless reliability backend built for agent-driven investigation.

Imported into this monorepo from source commit
`e69500960ac357d9e537bd18b85f4753451fc0eb` (v1.39.0).
The archived source repository retains its history; development continues here.
See [migration notes](docs/deployment.md#monorepo-migration) before upgrading an
existing installation.

Pulse's direction is to turn telemetry into actionable reliability signals with
supporting evidence for external agent workflows, with raw queryable retention
as an opt-in capability. The target combines bounded cross-signal service
summaries with opt-in, budgeted model assessments; your workflow owns deeper
investigation and policy-gated actions. Assessment, object-storage overhead and
investigation have separate allowances. See the
[architecture](docs/architecture.md#reliability-signals-and-optional-raw-retention)
for the target design and its boundary with current behavior.

Today, Pulse accepts logs, metrics, and traces over the protocols your collectors
already speak (Loki push, Prometheus remote write, and OpenTelemetry), stores
them as Parquet in an S3-compatible bucket, and lets agents investigate them
through a native [Model Context Protocol](https://modelcontextprotocol.io/)
interface. Prometheus- and Loki-compatible query APIs keep existing dashboards
working. Experimental [periodic reliability assessments](docs/reliability.md)
combine bounded cross-signal windows with opt-in OpenAI Decisions, durable MCP
signals and capped external investigation handoffs. Processing-only ingestion
is not implemented; raw records are retained indefinitely unless expiry is configured.

Experimental [error tracking](docs/error-tracking.md) accepts Sentry SDK JSON errors
into the same object storage and exposes error events and issue groups through MCP.
An optional [error monitoring index](docs/error-monitoring.md) adds compact
retained-history summaries and replayable changes without gating ingestion.
Its first bounded detector emits measured error-rate increases with compact
evidence for an external workflow to consume; it does not execute that workflow.

## Why Pulse

- **One system instead of three.** Logs, metrics, and traces share one ingest path, one storage format, and one query surface.
- **Object storage is the source of truth.** No database, no local disks to back up, no consensus service. Nodes are disposable.
- **Agent-native.** Diagnosis tools are part of the server, not a wrapper bolted on afterwards, and they stay read-only by design.
- **No UI.** Bring your own dashboards, or your own agent.

> [!WARNING]
> Pulse is early software. Logs, metrics, and OTLP/HTTP traces work end to end. Native alerting and opt-in trace lifecycle policies are experimental; bounded Tempo lookup/search/discovery are experimental, while full TraceQL and deployed Tempo-client parity are not implemented yet. Bounded catalogs require explicit event-time retention; unlimited-retention catalogs remain unbounded. Expect breaking changes between releases.

## Try it locally

You need [mise](https://mise.jdx.dev/), a stable Rust toolchain, and Docker.

```sh
cd pulse                      # from the monorepo root
mise install                  # Erlang and Elixir
docker compose up -d          # local S3-compatible storage
mix setup
mix phx.server
```

In another terminal, push a log line and read it back (local development accepts any tenant without a token):

```sh
curl -X POST localhost:4000/loki/api/v1/push \
  -H 'Content-Type: application/json' -H 'X-Scope-OrgID: demo' \
  -d "{\"streams\":[{\"stream\":{\"service_name\":\"api\"},\"values\":[[\"$(date +%s)000000000\",\"hello pulse\"]]}]}"

curl -G localhost:4000/loki/api/v1/query_range \
  -H 'X-Scope-OrgID: demo' --data-urlencode 'query={service_name="api"}'
```

The listener port can differ per checkout; `mix phx.server` prints the one it uses.

## Documentation

The [documentation](docs/README.md) covers deploying Pulse with the Helm chart or container image published with every release, configuration, sending telemetry, querying, limits, and monitoring Pulse itself. The [architecture](docs/architecture.md) explains the design.

## Contributing

Run `mix precommit` before opening a pull request; it runs the same compile, format, and test checks as CI. [`AGENTS.md`](AGENTS.md) describes the codebase conventions.

## License

Pulse is released under the [MIT License](LICENSE).
