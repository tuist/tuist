defmodule Tuist.Runners.Workers.PruneArchivedLogsWorker do
  @moduledoc """
  Daily prune of runner-log archives that have aged past the documented
  90-day retention. `runner_job_logs` enforces its retention with a
  ClickHouse TTL clause, so without this worker the S3 archive would
  outlive the per-line rows and the documented retention.

  Iterates expired archives one by one. A per-archive S3 error is
  logged and skipped so one account with bad credentials can't block
  deletion for every other account; `log_archived_at` stays set on
  the failing row so the next daily run retries it. Only a
  successful delete clears it.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Workers.ArchiveLogsWorker
  alias Tuist.Storage

  require Logger

  # Matches the `runner_job_logs` table-level TTL so the archive and
  # the per-line rows expire on the same clock.
  @ttl_days 90
  @batch_size 500

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id} = args} = job) do
    case Repo.get(Account, account_id) do
      %Account{runner_log_retention_days: days} = account when is_integer(days) ->
        threshold = DateTime.add(DateTime.utc_now(), -days, :day)

        archives =
          Jobs.list_expired_archives(threshold,
            account_id: account_id,
            after_workflow_job_id: Map.get(args, "after_workflow_job_id", 0),
            limit: @batch_size
          )

        Enum.each(archives, &prune(&1, account))

        if length(archives) == @batch_size do
          args
          |> Map.put("after_workflow_job_id", List.last(archives).workflow_job_id)
          |> __MODULE__.new()
          |> Oban.insert!(unique: job.unique)
        end

        :ok

      _ ->
        :ok
    end
  end

  def perform(_job) do
    threshold = DateTime.add(DateTime.utc_now(), -@ttl_days * 24 * 60 * 60, :second)

    threshold
    |> Jobs.list_expired_archives()
    |> Enum.each(&prune/1)

    :ok
  end

  defp prune(%{workflow_job_id: workflow_job_id, account_id: account_id}, account \\ nil) do
    key = ArchiveLogsWorker.archive_key(account_id, workflow_job_id)
    account_result = if account, do: {:ok, account}, else: Accounts.get_account_by_id(account_id)

    with {:ok, account} <- account_result,
         :ok <- Storage.delete_object(key, account) do
      Jobs.set_log_archived_at(workflow_job_id, nil)
    else
      {:error, reason} = error ->
        Logger.warning("runners: archive prune skipped for #{key}: #{inspect(reason)}",
          workflow_job_id: workflow_job_id
        )

        error
    end
  end
end
