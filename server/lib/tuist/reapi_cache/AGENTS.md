# REAPI Cache Analytics

This module owns analytics events emitted by remote-cache clients that use the Remote Execution API.

## Boundaries

- Kura emits signed Bazel and Mix cache events through the same webhook. `TuistWeb.Webhooks.ReapiCacheController` validates signatures, client kind and matching project build system, then resolves account/project handles. Mix invocations are the compile reporter's stable build IDs; dependency targets and CAS bundle hashes correlate actual outputs without introducing another analytics pipeline.
- Project and invocation identity scope every detail query; the optional `client_kind` restriction prevents cross-client history from blending. Mix CAS views always pass `client_kind: "mix"`. Environment-scoped project queries currently join Bazel invocations; do not use that join for Mix environments.
- This context stores and queries diagnostic cache telemetry only. It must not infer build duration, build outcome, or test outcome from cache traffic.
- Cache events optionally retain one action-result `output_path`, limited to 1,024 bytes, with an empty default for older Kura nodes and existing rows. Append stored schema fields in physical ClickHouse column order. Profile-based action labels are virtual, keep the mnemonic searchable, and do not alter identity, replay deduplication or summary queries.
- New retained event fields require a corresponding entry in `server/data-export.md`.
