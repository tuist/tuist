defmodule Atlas.FeatureUsage.Workers.RefreshAccountFeatureUsage do
  @moduledoc """
  Recomputes the feature-usage snapshot for a single account and fires Slack
  notifications for adoption ("started") and churn ("stopped") transitions.
  Enqueued by `ScheduleFeatureUsage`.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Atlas.FeatureUsage

  require Logger

  @impl true
  def perform(%Oban.Job{} = job), do: perform(job, [])

  def perform(%Oban.Job{args: %{"account_id" => account_id}}, opts) do
    refresh = Keyword.get(opts, :refresh, &FeatureUsage.refresh_account/1)

    case refresh.(account_id) do
      {:ok, _result} ->
        :ok

      {:error, :not_found} ->
        {:cancel, :account_not_found}

      {:error, :invalid_handle} ->
        {:cancel, :invalid_handle}

      {:error, reason} ->
        Logger.warning("Feature usage refresh failed for account #{account_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
