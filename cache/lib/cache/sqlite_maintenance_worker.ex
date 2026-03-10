defmodule Cache.SQLiteMaintenanceWorker do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias Cache.KeyValueRepo
  alias Cache.SQLiteHelpers

  @impl Oban.Worker
  def perform(_job) do
    Cache.Repo.query("PRAGMA incremental_vacuum(128000)")

    SQLiteHelpers.with_repo_busy_timeout(KeyValueRepo, 0, fn ->
      query!(KeyValueRepo, "PRAGMA wal_checkpoint(PASSIVE)")
      query!(KeyValueRepo, "PRAGMA incremental_vacuum(1000)")
    end)

    :ok
  rescue
    error ->
      if SQLiteHelpers.busy_error?(error) do
        :ok
      else
        reraise error, __STACKTRACE__
      end
  end

  defp query!(repo, query) do
    case repo.query(query) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end
end
