# Once run events

This subsystem projects Once lifecycle events into run summaries and declared actions for the live build pages.

- Only `ActionCompleted` creates an action row. `TargetCompleted` is a target summary and must not create a substitute action or overwrite action zero.
- An action is identified by run, target execution, capability, and action index. Replayed completion events must not increment run counters again.
- Accept both numeric and decoded enum forms of terminal results.
- Keep durations and cache outcomes from the individual action events. Do not infer them from the enclosing target or command.
- Regression coverage lives in `test/tuist/once_events_test.exs`.
- Action search and filters apply to the whole run before pagination. Counts and rows share the same scoped query; sorting uses allowed fields and deterministic tie breakers.
