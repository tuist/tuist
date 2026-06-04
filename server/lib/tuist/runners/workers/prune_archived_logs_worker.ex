defmodule Tuist.Runners.Workers.PruneArchivedLogsWorker do
  @moduledoc """
  Daily prune of runner-log archives that have aged past the documented
  90-day retention. `runner_job_logs` enforces its retention with a
  ClickHouse TTL clause, so without this worker the S3 archive would
  outlive the per-line rows and the documented retention.

  Iterates expired archives one by one. A per-archive S3 error is
  logged and skipped so one account with bad credentials can't block
  deletion for every other account; `log_archive_key` stays set on
  the failing row so the next daily run retries it. Only a
  successful delete clears the key.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Accounts
  alias Tuist.Runners.Jobs
  alias Tuist.Storage

  require Logger

  # Matches the `runner_job_logs` table-level TTL so the archive and
  # the per-line rows expire on the same clock.
  @ttl_days 90

  @impl Oban.Worker
  def perform(_job) do
    threshold = DateTime.add(DateTime.utc_now(), -@ttl_days * 24 * 60 * 60, :second)

    threshold
    |> Jobs.list_expired_archives()
    |> Enum.each(&prune/1)

    :ok
  end

  defp prune(%{workflow_job_id: workflow_job_id, account_id: account_id, log_archive_key: key}) do
    with {:ok, account} <- Accounts.get_account_by_id(account_id),
         :ok <- Storage.delete_object(key, account) do
      Jobs.set_log_archive_key(workflow_job_id, "")
    else
      {:error, reason} ->
        Logger.warning("runners: archive prune delete failed for #{key}: #{inspect(reason)}",
          workflow_job_id: workflow_job_id
        )

        :ok

      _ ->
        :ok
    end
  end
end
