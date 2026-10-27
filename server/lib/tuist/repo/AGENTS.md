# Repo Monitoring

- Shared repo pool metrics belong in `tuist_common/`; configure the server wrappers here.
- Keep repo labels and telemetry prefixes aligned with PromEx wiring; startup and supervision belong in `server/lib/tuist/application.ex`.
- Export identical pool and query metrics in every runtime, using the bounded `workload` label from `Tuist.Environment.mode/0`.
- `PromExPlugin.attach/0` forwards physical repository query events to one metrics event with separate bounded `repo` labels, including dynamic routes. Poll optional pools only when running. Keep query text, parameters and customer identifiers out of the event. Missing timing phases stay absent, not zero; `idle_time` is time before checkout, not occupancy or part of total query duration. Retain physical attribution in Ecto tracing and read-outcome metrics.
- Attach the ClickHouse read-outcome forwarder at startup, merging raw events into one sanitized event before exporting existing metric names; never duplicate Prometheus metric families. Follow the authoritative-only ClickHouse contract in the parent guide, not removed shadow-repository deployment machinery.
