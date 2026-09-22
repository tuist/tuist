defmodule Atlas.Nudges.Signal do
  @moduledoc """
  Behaviour a nudge signal implements. Each signal owns:

    * `name/0` — stable identifier persisted on the nudge and used as the
      episode key.
    * `candidate_account_ids/0` — narrow the fan-out; the evaluator only
      calls `evaluate/1` for these accounts.
    * `evaluate/1` — inspect one account and either propose a nudge or
      return `:skip` / `{:recovered, evidence}`.

  Edge-triggered fire: `evaluate/1` returns `{:ok, proposal}` only on a
  fresh threshold crossing (episode open). While the metric is still bad
  and an episode is already open, the signal returns `:skip`. When the
  metric recovers, `{:recovered, evidence}` closes the episode.
  """

  alias Atlas.Accounts.Account
  alias Atlas.Nudges.Proposal

  @type evaluation ::
          {:ok, Proposal.t()}
          | {:recovered, evidence :: map()}
          | :skip

  @callback name() :: String.t()
  @callback candidate_account_ids() :: [binary()]
  @callback evaluate(Account.t()) :: evaluation()
end
