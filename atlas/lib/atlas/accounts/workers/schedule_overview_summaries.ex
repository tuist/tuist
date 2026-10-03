defmodule Atlas.Accounts.Workers.ScheduleOverviewSummaries do
  @moduledoc """
  Enqueues account overview summary refresh jobs for accounts whose summary is
  missing or stale.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Atlas.Accounts
  alias Atlas.Accounts.Workers.UpdateOverviewSummary

  @impl true
  def perform(%Oban.Job{} = job), do: perform(job, [])

  def perform(%Oban.Job{}, opts) do
    list_account_ids = Keyword.get(opts, :list_account_ids, &Accounts.list_overview_summary_candidate_ids/0)
    insert = Keyword.get(opts, :insert, &Oban.insert/1)

    list_account_ids.()
    |> Enum.reduce_while({:ok, 0}, fn account_id, {:ok, count} ->
      account_id
      |> update_job()
      |> insert.()
      |> case do
        {:ok, _job} -> {:cont, {:ok, count + 1}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp update_job(account_id) do
    UpdateOverviewSummary.new(
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
