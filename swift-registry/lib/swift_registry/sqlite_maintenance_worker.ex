defmodule SwiftRegistry.SQLiteMaintenanceWorker do
  @moduledoc """
  Periodic worker that reclaims free pages from the SQLite data file.

  The Repo runs with `auto_vacuum: :incremental`, which adds deleted
  pages to a free list but never shrinks the file on its own. Without
  periodic `PRAGMA incremental_vacuum`, the file grows monotonically as
  s3_transfers and cache_artifacts churn.

  Mirrors `Cache.SQLiteMaintenanceWorker` so the maintenance behaviour
  matches what cache ran for the registry tables before the extraction.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias SwiftRegistry.Repo

  @impl Oban.Worker
  def perform(_job) do
    Repo.query("PRAGMA incremental_vacuum(128000)")
    :ok
  rescue
    error ->
      if contention_error?(error) do
        :ok
      else
        reraise error, __STACKTRACE__
      end
  end

  defp contention_error?(%Exqlite.Error{message: message}) when is_binary(message) do
    String.contains?(message, ["database is locked", "Database busy", "SQLITE_BUSY"])
  end

  defp contention_error?(%DBConnection.ConnectionError{}), do: true
  defp contention_error?(_), do: false
end
