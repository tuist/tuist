defmodule Tuist.IngestRepo.Migrations.AddShardPlanIdIndexToTestRuns do
  @moduledoc """
  Adds a skipping index for the first-shard recovery lookup.

  Normal sharded updates resolve through the small `shard_runs` table. The
  fallback reads `test_runs` only before that row exists or after an
  interrupted report, and this index lets new parts skip unrelated shard
  plans without rewriting historical data during deployment.
  """
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_runs
    ADD INDEX IF NOT EXISTS idx_shard_plan_id shard_plan_id
    TYPE bloom_filter GRANULARITY 4
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_runs DROP INDEX IF EXISTS idx_shard_plan_id"
  end
end
