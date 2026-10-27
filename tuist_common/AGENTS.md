# Shared Elixir utilities

Put reusable cross-service helpers and telemetry implementations here. Keep
application-specific configuration, supervision, HTTP, and UI code in the owning
service. Repository-monitoring wrappers in each app supply labels and telemetry
prefixes; the shared pool-metric implementation belongs here.

`ObanLogger` records job identity, lifecycle timings/state, and exception diagnostics,
never job arguments or metadata. `ObanTelemetry` reports failures to Sentry
independently.
