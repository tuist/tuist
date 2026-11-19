# Pulse

Pulse is the observability database behind Tuist's clusters. It stores metrics,
logs, and traces, and serves them over SQL, PromQL, and the ingestion protocols
the collectors use (OTLP, Prometheus remote write, Loki, and others).

Pulse is licensed under Apache-2.0 ([`LICENSE`](LICENSE)). [`FORK.md`](FORK.md)
records the upstream it was forked from, what Tuist changed, and how releases
reach the clusters; [`AGENTS.md`](AGENTS.md) has the commands for building and
testing it.
