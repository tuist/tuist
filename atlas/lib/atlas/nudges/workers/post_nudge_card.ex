defmodule Atlas.Nudges.Workers.PostNudgeCard do
  @moduledoc """
  Outbox worker for the Slack card. Post-then-persist, with a client-
  generated id (`nudge_slack_post_attempts.client_msg_id`) attached to the
  Slack message metadata so a retry after an ambiguous failure reconciles
  via `Atlas.Slack.API.find_message_by_metadata/4` before re-posting.

  Duplicate risk past Slack's 100-message reconciliation window is
  accepted for v1; operators dismiss any duplicate card.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  alias Atlas.Nudges
  alias Atlas.Nudges.Nudge
  alias Atlas.Nudges.SlackNotifier

  require Logger

  @impl true
  def perform(%Oban.Job{args: %{"nudge_id" => nudge_id}}) do
    case Nudges.get_nudge(nudge_id) do
      nil ->
        {:cancel, :nudge_not_found}

      %Nudge{state: "pending_post"} = nudge ->
        SlackNotifier.post_nudge(nudge)

      %Nudge{state: state} ->
        Logger.info("PostNudgeCard skipping nudge=#{nudge_id} state=#{state}")
        :ok
    end
  end
end
