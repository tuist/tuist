defmodule Tuist.Repo.Migrations.DeleteCoverageSourceBackfillJobs do
  @moduledoc """
  Deletes the jobs of `Tuist.Tests.Coverage.Workers.SourceBackfillWorker`,
  which no longer exists: the per-test versions it backfilled
  (`coverage_test_sources`) are dropped, and the test maps
  (`Tuist.TestImpactAnalysis.Snapshots`) take their place. An instance that
  upgrades from before `20261010120000_enqueue_coverage_source_backfill`
  queues those jobs in the same migration run, and any still waiting would
  otherwise fail every attempt as an unknown worker.
  """
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "DELETE FROM oban_jobs WHERE worker = 'Tuist.Tests.Coverage.Workers.SourceBackfillWorker'"
    )
  end

  def down, do: :ok
end
