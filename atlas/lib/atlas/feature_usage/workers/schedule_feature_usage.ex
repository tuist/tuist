defmodule Atlas.FeatureUsage.Workers.ScheduleFeatureUsage do
  @moduledoc """
  Fans out one `RefreshAccountFeatureUsage` job per account that has a Tuist
  handle. Runs daily from the Oban cron.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Atlas.FeatureUsage
  alias Atlas.FeatureUsage.Workers.RefreshAccountFeatureUsage

  @impl true
  def perform(%Oban.Job{} = job), do: perform(job, [])

  def perform(%Oban.Job{}, opts) do
    list_account_ids = Keyword.get(opts, :list_account_ids, &FeatureUsage.list_tracked_account_ids/0)
    insert = Keyword.get(opts, :insert, &Oban.insert/1)

    list_account_ids.()
    |> Enum.reduce_while({:ok, 0}, fn account_id, {:ok, count} ->
      account_id
      |> refresh_job()
      |> insert.()
      |> case do
        {:ok, _job} -> {:cont, {:ok, count + 1}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp refresh_job(account_id) do
    RefreshAccountFeatureUsage.new(
      %{account_id: account_id},
      unique: [
        period: {23, :hour},
        fields: [:worker, :args],
        keys: [:account_id],
        states: [:available, :scheduled, :executing, :retryable]
      ]
    )
  end
end
