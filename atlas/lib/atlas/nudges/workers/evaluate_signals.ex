defmodule Atlas.Nudges.Workers.EvaluateSignals do
  @moduledoc """
  Cron entry point. Fans out one `EvaluateSignalForAccount` job per
  (signal, account) so a slow or failing signal does not hold up the rest.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Atlas.Nudges.Signals.ActivationStalled
  alias Atlas.Nudges.Signals.CacheEffectivenessDropped
  alias Atlas.Nudges.Signals.FirstBuildEvent
  alias Atlas.Nudges.Signals.FirstCacheEvent
  alias Atlas.Nudges.Signals.FirstTestEvent
  alias Atlas.Nudges.Signals.HeavyUsageEnterpriseFit
  alias Atlas.Nudges.Signals.InvitedTeammatesSso
  alias Atlas.Nudges.Signals.TestSelectionEffectivenessDropped
  alias Atlas.Nudges.Workers.EvaluateSignalForAccount

  @signals [
    InvitedTeammatesSso,
    CacheEffectivenessDropped,
    TestSelectionEffectivenessDropped,
    HeavyUsageEnterpriseFit,
    ActivationStalled,
    FirstCacheEvent,
    FirstBuildEvent,
    FirstTestEvent
  ]

  def signals, do: @signals

  @impl true
  def perform(%Oban.Job{}) do
    for signal <- @signals,
        account_id <- signal.candidate_account_ids() do
      %{"signal" => to_string(signal), "account_id" => account_id}
      |> EvaluateSignalForAccount.new()
      |> Oban.insert()
    end

    :ok
  end
end
