defmodule Tuist.IngestRepo.Migrations.AddMatchedPathToTestImpactRunDecisions do
  @moduledoc """
  Keys each bitmap of `test_impact_run_decisions` by the changed file that
  decided its tests too (`matched_path`, empty when no file did), so why a
  test was selected is read from its decision instead of being stored per
  test. A column added in the same `ALTER` may end the sorting key; the
  table was still empty when this shipped.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE test_impact_run_decisions
      ADD COLUMN IF NOT EXISTS matched_path String CODEC(ZSTD(3)) AFTER reason,
      MODIFY ORDER BY (project_id, test_impact_run_id, decision, reason, evidence_snapshot_id, chunk, matched_path)
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE test_impact_run_decisions
      MODIFY ORDER BY (project_id, test_impact_run_id, decision, reason, evidence_snapshot_id, chunk)
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_impact_run_decisions DROP COLUMN IF EXISTS matched_path")
  end
end
