defmodule Atlas.Outreach.Workers.NotifyRecommendation do
  @moduledoc """
  Delivers one guided outreach recommendation to Slack.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  alias Atlas.Audit
  alias Atlas.Outreach
  alias Atlas.Outreach.RecommendationNotifier

  @impl true
  def perform(%Oban.Job{args: %{"recommendation_id" => recommendation_id}}) do
    Audit.with_context(%{interface: "worker"}, fn ->
      case Outreach.get_recommendation(recommendation_id) do
        nil ->
          {:cancel, :recommendation_not_found}

        %{status: status} when status != "pending" ->
          :ok

        recommendation ->
          with {:ok, notification} <- RecommendationNotifier.notify(recommendation),
               {:ok, _recommendation} <- Outreach.mark_recommendation_notified(recommendation, notification) do
            :ok
          else
            {:error, :outreach_recommendation_slack_channel_not_configured} ->
              {:cancel, :outreach_recommendation_slack_channel_not_configured}

            {:error, reason} ->
              {:error, reason}
          end
      end
    end)
  end
end
