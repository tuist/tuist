defmodule SwiftRegistry.SQLiteMaintenanceWorker do
  @moduledoc """
  Periodic worker that reclaims free pages from the SQLite data file.

  The Repo runs with `auto_vacuum: :incremental`, which adds deleted pages
  to a free list but never shrinks the file on its own. Without periodic
  `PRAGMA incremental_vacuum`, the file grows monotonically as
  s3_transfers and cache_artifacts churn.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias SwiftRegistry.Repo

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    Repo.query("PRAGMA incremental_vacuum(128000)")
    :ok
  rescue
    exception ->
      Logger.warning(
        "SQLite incremental vacuum failed: " <>
          Exception.format(:error, exception, __STACKTRACE__)
      )

      :ok
  end
end
