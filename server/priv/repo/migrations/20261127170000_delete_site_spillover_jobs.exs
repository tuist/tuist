defmodule Tuist.Repo.Migrations.DeleteSiteSpilloverJobs do
  @moduledoc """
  Deletes the jobs of `Tuist.Runners.Workers.SiteSpilloverWorker`, which no
  longer exists: it moved queued jobs off the rack to the rented macOS runner
  fleet, which is gone. Its cron jobs queued before the deploy would otherwise
  stay available forever, put back by every node as an unknown worker.
  """
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DELETE FROM oban_jobs WHERE worker = 'Tuist.Runners.Workers.SiteSpilloverWorker'")
  end

  def down, do: :ok
end
