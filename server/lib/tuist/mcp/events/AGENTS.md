# Model Context Protocol Events

- `Tuist.MCP.Events` owns project-filtered subscriptions. Subscribe only for a real user and a scoped account or OAuth credential; check both against the project without Atlas operator-read elevation.
- Store callback URLs and Standard Webhooks secrets encrypted. Verify callbacks before saving them, and pin public addresses again for every delivery. Do not follow redirects.
- Domain writers enqueue one fan-out job per event. Delivery jobs recheck owner access, token validity, and expiry. Event IDs remain stable across retries.
- Keep event payloads limited to resource identifiers and links. Agents obtain failure details through authorized read tools.
- Add an event to `events/list` only when its domain hook and delivery path are ready.
