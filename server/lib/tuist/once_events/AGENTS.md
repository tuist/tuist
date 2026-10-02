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
