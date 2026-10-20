defmodule Atlas.Nudges.Workers.ReconcileDeliveryOutcomes do
  @moduledoc """
  Refreshes Slack cards for nudges whose linked delivery has reached a
  terminal stage (`:delivered` or `:failed`). Nudges still in `:pending` or
  `:retrying` are left alone; the next tick re-checks.

  Runs on a one-minute cron because `Atlas.GTM.Workers.DeliverDirectEmail`
  only writes to the delivery row and has no direct hook back into the
  nudge layer. Direction of dependency is preserved (nudges own the
  reconciliation; GTM does not depend on Nudges).
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Atlas.Nudges
  alias Atlas.Nudges.SlackNotifier

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Nudges.list_nudges_for_reconciliation()
    |> Enum.each(&reconcile/1)

    :ok
  end

  defp reconcile(%{nudge: nudge, stage: stage}) do
    case SlackNotifier.update_sent_card(nudge, stage) do
      :ok ->
        {:ok, _} = Nudges.observe_delivery(nudge)
        :ok

      {:error, reason} ->
        Logger.warning(
          "ReconcileDeliveryOutcomes failed to refresh Slack card for nudge=#{nudge.id}: #{inspect(reason)}"
        )

        :ok
    end
  end
end
