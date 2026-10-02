# Once run events

This subsystem projects Once lifecycle events into run summaries and declared actions for the live build pages.

- Only `ActionCompleted` creates an action row. `TargetCompleted` is a target summary and must not create a substitute action or overwrite action zero.
- An action is identified by run, target execution, capability, and action index. Replayed completion events must not increment run counters again.
- Accept both numeric and decoded enum forms of terminal results.
- Keep durations and cache outcomes from the individual action events. Do not infer them from the enclosing target or command.
- Regression coverage lives in `test/tuist/once_events_test.exs`.
- Action search and filters apply to the whole run before pagination. Counts and rows share the same scoped query; sorting uses allowed fields and deterministic tie breakers.
- The transport resends a batch whenever an ack is lost, so every write here has to be idempotent and every run-level roll-up has to be guarded by the insert actually having happened. Never increment a counter from an upsert whose `on_conflict` does not touch `updated_at`; derive it instead.
- Never ack a batch whose projection failed. `NEEDS_RESYNC` without advancing the high-water mark is the retry signal; `ACCEPTED` after a failure loses the event.
- `run_id` is chosen by the client, so anything keyed by it (ack store, pub/sub topic) must also be keyed by `project_id`.
- `priv/proto/once/events/v1/events.proto` is a copy of the client's file in `tuist/once`. Sync it from there rather than hand-editing `proto/once/events/v1/events.pb.ex`, then regenerate with `mix protobuf.generate --include-path=priv/proto --output-path=lib/tuist/once_events/proto --plugin=ProtobufGenerate.Plugins.GRPC priv/proto/once/events/v1/events.proto` followed by `mise run format`, which is why the checked-in file does not match the generator's raw output byte for byte. The generated modules live in the `Once` boundary (`lib/once.ex`).
- Authentication reuses `Tuist.Authentication.authenticated_subject/1`, so a login session, an account token and a project token all work. A project token identifies its project. Every other credential names it in the `once-project-id` call metadata (`account/project`, the key RFC 0008 defines in `tuist/once`), and `Tuist.Authorization` `:run_create` decides access. Never add a separate token lookup here.
- Unknown projects and projects without access must return the same message, and handles are validated for shape and length before any database lookup.
- The credential is read when a stream opens and again every few minutes while it stays open, so a revoked token or a removed member cannot keep writing for hours.
- Not done yet: the gRPC endpoint has no rate limiting, and the subject is not cached the way the HTTP API caches it, so a valid account token costs several queries and a password check per call.

