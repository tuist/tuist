# Isolated public demo

- `Atlas.Demo` is the fail-closed page/event policy. Its virtual visitor receives only curated read scopes; never load a real session user in demo mode.
- `Config.validate!/1` rejects integration configuration and requires a dedicated `atlas_demo` database URL. Keep it pure for async tests. Never switch datasets based on the request hostname.
- `Seeds` owns the small deterministic fictional dataset, separate from `priv/repo/seeds.exs`. Use schema writes, not domain actions that can send messages, enqueue jobs, or call integrations. It is operator-only through `Atlas.Release.seed_demo/0`, not a dashboard or MCP capability.
- `DatasetCheck` runs synchronously after Repo and before Endpoint. It requires the isolated database, a SELECT-only role, and demo-only records. Serving connections also enable transaction read-only mode; migrations and seeding use separately provisioned credentials.
- Adding a page requires reviewing mount, parameter, info, async, component, and query side effects, then explicit HTTP-path, view, and per-view event allowlisting. Never permit an event based only on a name prefix like `search` or `select`.
- The demo has no workers, integrations, API/MCP/inference, sign-in, file upload/download, public verification, or admin surfaces. Demo pages omit write controls; rejected write events explain the read-only restriction rather than pretending to save.
- Runbook: `../../../deploy/demo.md`. Deployment starts from the standalone chart plus `values-demo.yaml`, never the managed production overlay. No live deployment is part of code changes.
- Integration coverage is in `test/atlas_web/live/demo_live_test.exs`; runtime validation has pure tests in `test/atlas/demo/config_test.exs`. Stub `Demo.enabled?/0` with Mimic rather than mutating application or system environment.
