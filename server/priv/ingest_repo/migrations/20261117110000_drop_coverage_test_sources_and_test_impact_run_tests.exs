defmodule Tuist.IngestRepo.Migrations.DropCoverageTestSourcesAndTestImpactRunTests do
  @moduledoc """
  Drops the per-test tables the test maps (`Tuist.TestImpactAnalysis.Snapshots`)
  replace: `coverage_test_sources`, each test's versions by the files it
  executed, which coverage carry and test selection looked up, and
  `test_impact_run_tests`, the tests each impact run selected, now
  `test_impact_run_decisions`' bitmaps. Nothing reads or writes either.
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
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    # excellent_migrations:safety-assured-for-next-line table_dropped
    IngestRepo.query!("DROP TABLE IF EXISTS test_impact_run_tests SYNC", [], timeout: :infinity)
  end

  def down, do: :ok
end
