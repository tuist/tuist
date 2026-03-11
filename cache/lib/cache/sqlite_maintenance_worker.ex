defmodule Cache.SQLiteMaintenanceWorker do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias Cache.KeyValueRepo
  alias Cache.Repo
  alias Cache.SQLiteHelpers

  @impl Oban.Worker
  def perform(_job) do
    Repo.query("PRAGMA incremental_vacuum(128000)")

    SQLiteHelpers.with_repo_busy_timeout(KeyValueRepo, 0, fn ->
      SQLiteHelpers.query!(KeyValueRepo, "PRAGMA wal_checkpoint(PASSIVE)")
      SQLiteHelpers.query!(KeyValueRepo, "PRAGMA incremental_vacuum(1000)")
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
end
