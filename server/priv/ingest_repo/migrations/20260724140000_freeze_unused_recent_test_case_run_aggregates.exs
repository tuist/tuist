defmodule Tuist.IngestRepo.Migrations.FreezeUnusedRecentTestCaseRunAggregates do
  @moduledoc """
  Stops writes and background merges for rolling test-run aggregates that no
  enabled production automation reads.

  The unpartitioned aggregate tables retain large arrays per test case. Merging
  the 750-run table recently exhausted the production ClickHouse memory limit
  even though the compressed source parts were small. Dropping the incremental
  materialized views stops new parts from reaching the unused tables. Setting
  the maximum automatic merge size to one byte prevents the retained parts from
  scheduling another background merge while they remain available for
  comparison during the replacement rollout.

  The 100-run table and its two materialized views stay active because every
  enabled rolling automation currently uses a 75-run trigger window.
  """

  use Ecto.Migration

  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  @retired_tables [
    "test_case_runs_recent_250_per_case",
    "test_case_runs_recent_500_per_case",
    "test_case_runs_recent_750_per_case",
    "test_case_runs_recent_per_case"
  ]

  @retired_materialized_views [
    "test_case_runs_recent_250_per_case_mv",
    "test_case_runs_recent_250_success_per_case_mv",
    "test_case_runs_recent_500_per_case_mv",
    "test_case_runs_recent_500_success_per_case_mv",
    "test_case_runs_recent_750_per_case_mv",
    "test_case_runs_recent_750_success_per_case_mv",
    "test_case_runs_recent_per_case_mv",
    "test_case_runs_recent_success_per_case_mv"
  ]

  def up do
    for materialized_view <- @retired_materialized_views do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      IngestRepo.query!("DROP VIEW IF EXISTS #{materialized_view}")
    end

    for table <- @retired_tables do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      IngestRepo.query!("""
      ALTER TABLE #{table}
      MODIFY SETTING max_bytes_to_merge_at_max_space_in_pool = 1
      """)
    end
  end

  def down do
    raise Ecto.MigrationError,
          "the retired materialized views require a bounded backfill before they can be re-enabled safely"
  end
end
