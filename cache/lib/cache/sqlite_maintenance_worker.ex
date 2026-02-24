defmodule Cache.SQLiteMaintenanceWorker do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, max_attempts: 1

  @impl Oban.Worker
  def perform(_job) do
    Cache.Repo.query("PRAGMA incremental_vacuum(128000)")
    :ok
  end
end
