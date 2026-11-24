# Pulse symptoms and investigations

The contract is [`symptoms/README.md`](../../../../symptoms/README.md); read it
before changing anything here.

## Mirror (`Symptoms`)

- The evaluator is the only writer of detection state. The mirror only applies
  its log: in `seq` order, a revision only when newer, never past a revision it
  could not handle, rejecting an unknown major `schema_version`.
- Everything from the evaluator (titles, entity keys, evidence) is
  untrusted: render it escaped and never link it. It leaves the server (MCP
  events) only bounded and typed `untrusted_json`, and reaches a command only
  after it matches a strict pattern.
- Every read and action checks `Tuist.Pulse.authorized?/2`.

## Human state

- Acks, mutes, outcomes and investigations are what the evaluator reads back
  from `GET /api/internal/symptoms/state`. Every write draws its `change_seq`
  from `pulse_symptom_state_changes` under the shared advisory lock, inside the
  writing transaction (`Symptoms.draw_change_seq/0`), so the cursor never
  skips a late commit.
- A new kind of human state must join `Symptoms.state_changes/1` in
  `change_seq` order, and its fields need `server/data-export.md`.

## Investigation requests (`Investigations`)

- Generate investigation steps in the agent, not from backend command templates. Triggers record requests only; agent execution is not wired yet. Preserve existing briefs and feedback for state read-back.
- Triggers run inside the mirror's transaction, are decided from each applied
  revision's own fields (the board push's `board.rank` for top two), and are
  idempotent per `request_id`. Draw `change_seq` before reading what exists.
