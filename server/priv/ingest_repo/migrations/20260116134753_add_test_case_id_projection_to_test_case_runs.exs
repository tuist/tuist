defmodule Tuist.IngestRepo.Migrations.AddTestCaseIdProjectionToTestCaseRuns do
  use Ecto.Migration

  def up do
    # Enable projection support for ReplacingMergeTree by setting deduplicate_merge_projection_mode
    # 'rebuild' ensures projections stay consistent during deduplication merges
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    MODIFY SETTING deduplicate_merge_projection_mode = 'rebuild'
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD PROJECTION proj_by_test_case_id (
      SELECT *
      ORDER BY test_case_id, ran_at
    )
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_test_case_id"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    MODIFY SETTING deduplicate_merge_projection_mode = 'throw'
    """
  end
end
