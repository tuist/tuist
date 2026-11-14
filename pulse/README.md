# Pulse

Pulse is the observability database behind Tuist's clusters. It stores metrics,
logs, and traces, and serves them over SQL, PromQL, and the ingestion protocols
the collectors use (OTLP, Prometheus remote write, Loki, and others).

Pulse started as a fork of [GreptimeDB](https://github.com/GreptimeTeam/greptimedb)
and is licensed under Apache-2.0 ([`LICENSE`](LICENSE)). [`FORK.md`](FORK.md)
records the upstream base, what Tuist changed, and how releases reach the
clusters; [`AGENTS.md`](AGENTS.md) has the commands for building and testing it.
