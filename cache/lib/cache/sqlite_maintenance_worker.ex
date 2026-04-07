defmodule Cache.SQLiteMaintenanceWorker do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias Cache.Config
  alias Cache.KeyValueWriteRepo
  alias Cache.Repo
  alias Cache.SQLiteHelpers

  @impl Oban.Worker
  def perform(_job) do
    Repo.query("PRAGMA incremental_vacuum(128000)")

    timeout_ms = Config.key_value_maintenance_busy_timeout_ms()

    SQLiteHelpers.with_repo_busy_timeout(KeyValueWriteRepo, timeout_ms, fn ->
      SQLiteHelpers.query!(KeyValueWriteRepo, "PRAGMA wal_checkpoint(PASSIVE)")
      SQLiteHelpers.query!(KeyValueWriteRepo, "PRAGMA incremental_vacuum(1000)")
    end)

    :ok
  rescue
    error ->
      if SQLiteHelpers.contention_error?(error) do
        :ok
      else
        reraise error, __STACKTRACE__
      end
  end
end
