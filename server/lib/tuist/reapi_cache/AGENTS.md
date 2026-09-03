# REAPI Cache Analytics

This module owns analytics events emitted by remote-cache clients that use the Remote Execution API.

## Boundaries

- Kura emits signed cache events; `TuistWeb.Webhooks.ReapiCacheController` validates and resolves their account and project handles.
- This context stores and queries diagnostic cache telemetry only. It must not infer build duration, build outcome, or test outcome from cache traffic.
- New retained event fields require a corresponding entry in `server/data-export.md`.
