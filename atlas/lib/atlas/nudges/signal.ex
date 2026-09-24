defmodule Atlas.Nudges.Signal do
  @moduledoc """
  Documentation-only contract for a nudge signal. Each signal module
  should define:

    * `name/0` — stable string identifier persisted on the nudge and used
      as the episode key.
    * `candidate_account_ids/0` — narrow the fan-out; the evaluator only
      calls `evaluate/1` for these account ids.
    * `evaluate/1` — inspect one `Atlas.Accounts.Account` and return
      `{:ok, %Atlas.Nudges.Proposal{}}` on a fresh threshold crossing,
      `{:recovered, evidence_map}` when the metric has recovered and the
      episode should close, or `:skip` otherwise.

  Edge-triggered fire: `evaluate/1` returns `{:ok, proposal}` only on a
  fresh threshold crossing (episode open). While the metric is still bad
  and an episode is already open, the signal returns `:skip`.
  """
end
