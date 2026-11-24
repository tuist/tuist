defmodule Tuist.IngestRepo.Migrations.AddSourceTestRunIdToShardRuns do
  @moduledoc """
  `source_test_run_id` on `shard_runs`: the ID a version-0 shard's report was
  sent under, which is where the CLI uploaded that shard's result bundle
  (`runs/<id>/result_bundle.zip`). The shards report into one merged run, so
  without it the only record of every shard but the first is the processing
  job's arguments, which are pruned within hours. Version-1 plans keep it on
  `shard_test_reports` already, so `shard_run_summaries` is recreated reading
  both.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE shard_runs ADD COLUMN IF NOT EXISTS source_test_run_id String DEFAULT ''"
    )

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE OR REPLACE VIEW shard_run_summaries AS
    SELECT shard_plan_id, project_id, test_run_id, shard_index, status, duration, ran_at, inserted_at,
      source_test_run_id
    FROM shard_runs
    UNION ALL
    SELECT assumeNotNull(shard_plan_id) AS shard_plan_id, project_id, toString(id) AS test_run_id,
      shard_index, status, toUInt64(greatest(duration, 0)) AS duration, execution_started_at AS ran_at, inserted_at,
      source_test_run_id
    FROM latest_shard_test_reports
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE OR REPLACE VIEW shard_run_summaries AS
    SELECT shard_plan_id, project_id, test_run_id, shard_index, status, duration, ran_at, inserted_at
    FROM shard_runs
    UNION ALL
    SELECT assumeNotNull(shard_plan_id) AS shard_plan_id, project_id, toString(id) AS test_run_id,
      shard_index, status, toUInt64(greatest(duration, 0)) AS duration, execution_started_at AS ran_at, inserted_at
    FROM latest_shard_test_reports
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE shard_runs DROP COLUMN IF EXISTS source_test_run_id")
  end
end
