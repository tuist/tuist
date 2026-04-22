defmodule Cache.SQLiteMaintenanceWorker do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias Cache.Config
  alias Cache.KeyValueRepo
  alias Cache.Repo
  alias Cache.SQLiteHelpers

  @impl Oban.Worker
  def perform(_job) do
    Repo.query("PRAGMA incremental_vacuum(128000)")

    timeout_ms = Config.key_value_maintenance_busy_timeout_ms()
    pages = Config.key_value_incremental_vacuum_pages()

    SQLiteHelpers.with_repo_busy_timeout(KeyValueRepo, timeout_ms, fn ->
      SQLiteHelpers.query!(KeyValueRepo, "PRAGMA wal_checkpoint(PASSIVE)")
      SQLiteHelpers.query!(KeyValueRepo, "PRAGMA incremental_vacuum(#{pages})")
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
