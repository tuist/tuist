defmodule Tuist.IngestRepo.Migrations.DropCoverageTestSources do
  @moduledoc """
  Drops `coverage_test_sources`, each test's versions by the files it
  executed, which coverage carry and test selection looked up before the
  test maps (`Tuist.TestImpactAnalysis.Snapshots`) replaced them. The
  previous release neither reads nor writes it, so its pods, which keep
  serving while this runs, don't notice.
  `test_impact_run_tests` is dropped one release later
  (`20261117120000_drop_test_impact_run_tests`): the previous release still
  writes it.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  # `SYNC` because on a `Replicated` database a plain DROP is queued.
  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    # excellent_migrations:safety-assured-for-next-line table_dropped
    IngestRepo.query!("DROP TABLE IF EXISTS coverage_test_sources SYNC", [], timeout: :infinity)
  end

  def down, do: :ok
end
