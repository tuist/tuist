# Symptoms

Standalone Phoenix evaluator that replaces alert rules for Tuist's own
operations, with its own CNPG database. [README.md](README.md) is the design;
follow it and update it when behavior it describes changes.

## Boundaries

- This service is the only writer of detection state. Human and agent state
  (ack, mute, investigations, outcomes) belongs to the Tuist server; read it
  back, never write it here.
- Statistics and decision logic under `lib/symptoms/evidence/` and
  `lib/symptoms/decision/` stay pure: no database, and time and randomness
  injectable through arguments, so replays and tests are deterministic.
- The evaluator calls no model. Never train on outcomes the system
  caused (incidents after a page, reverts after a brief).
- Add a source or change calibration only after a held-out replay shows no
  loss of recall.
- Read environment variables only in `config/runtime.exs`, and keep the
  README "Configuration" table and `infra/helm/symptoms` in step with it.

## Tests

- Tests run with `mix test` and need no PostgreSQL. Tag database tests `:db`
  (`use Symptoms.DataCase`) and run them with `MIX_ENV=test mix ecto.setup`
  and `mix test --include db`. Drive the pipeline with
  `test/support/fake_source.exs`, or through the real sources against fake
  Pulse and Prometheus replies as `test/symptoms/end_to_end_test.exs` does.
- Derive expected values independently (closed forms or hand calculations in
  comments), not from the implementation's output.

Tool versions live in `mise.toml`.
