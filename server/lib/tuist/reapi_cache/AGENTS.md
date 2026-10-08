# REAPI Cache Analytics

This module owns analytics events emitted by remote-cache clients that use the Remote Execution API.

## Boundaries

- Kura emits signed cache events; `TuistWeb.Webhooks.ReapiCacheController` validates and resolves their account and project handles.
- This context stores and queries diagnostic cache telemetry only. It must not infer build duration, build outcome, or test outcome from cache traffic.
- Cache events optionally retain one action-result `output_path`, limited to 1,024 bytes, with an empty default for older Kura nodes and existing rows. Append stored schema fields in physical ClickHouse column order. Profile-based action labels are virtual, keep the mnemonic searchable, and do not alter identity, replay deduplication or summary queries.
- New retained event fields require a corresponding entry in `server/data-export.md`.
