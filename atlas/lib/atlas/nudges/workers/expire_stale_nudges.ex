defmodule Atlas.Nudges.Workers.ExpireStaleNudges do
  @moduledoc """
  Cron worker. Flips `pending_post` / `proposed` / `claimed` nudges past
  `expires_at` to `expired`, freeing the open-dedup slot for the next
  window. Also updates each expired card in Slack so it no longer looks
  actionable.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Atlas.Nudges
  alias Atlas.Nudges.SlackNotifier

  require Logger

  @impl true
  def perform(%Oban.Job{}) do
    Nudges.expire_stale()
    |> Enum.each(fn nudge ->
      case SlackNotifier.update_expired_card(nudge) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to update expired Slack card for nudge=#{nudge.id}: #{inspect(reason)}")
      end
    end)

    :ok
  end
end
