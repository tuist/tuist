defmodule Tuist.IngestRepo.Migrations.ScopeCrossRunFlakinessToDestination do
  @moduledoc """
  Links case runs and destination rows to their producing report/shard execution.

  Deploy this migration before application writers. Historical rows keep the
  null execution reference; no existing flags or aggregates are rewritten.
  The commit lookup retains its sort key and is extended without a backfill or
  materialized-view ingestion gap. Roll back writers before dropping the schema.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # New metadata table; report replays reuse IDs and do not need a history rewrite.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE IF NOT EXISTS test_executions (
      id UUID,
      project_id Int64,
      test_run_id UUID,
      git_commit_sha String,
      scheme String,
      is_ci Bool DEFAULT false,
      shard_id Nullable(UUID),
      shard_index Nullable(Int32),
      destination_status Enum8('missing' = 0, 'single' = 1, 'ambiguous' = 2),
      inserted_at DateTime64(6)
    ) ENGINE = #{Migration.engine("ReplacingMergeTree(inserted_at)")}
    ORDER BY (project_id, git_commit_sha, scheme, is_ci, id)
    """)

    for table <- ["test_case_runs", "test_case_runs_by_commit", "test_run_destinations"] do
      # ClickHouse adds a defaulted column without rewriting existing parts.
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute("""
      ALTER TABLE #{table} ADD COLUMN IF NOT EXISTS
        test_execution_id Nullable(UUID)
      """)
    end

    update_commit_lookup(", test_execution_id")
    update_reported_runs("shard_report_id")
  end

  def down do
    update_commit_lookup("")
    update_reported_runs("shard_report_id, test_execution_id")

    for table <- ["test_case_runs_by_commit", "test_case_runs", "test_run_destinations"] do
      # Writers must be rolled back first; existing outcomes/destinations remain.
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute("ALTER TABLE #{table} DROP COLUMN IF EXISTS test_execution_id")
    end

    update_reported_runs("shard_report_id")

    # Only metadata introduced by this migration is removed on rollback.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE IF EXISTS test_executions")
  end

  defp update_commit_lookup(execution_column) do
    # Replace the query atomically while retaining the target table and evidence filters.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE test_case_runs_by_commit_mv MODIFY QUERY
    SELECT project_id, git_commit_sha, scheme, is_ci, status, id, test_case_id, is_flaky, inserted_at#{execution_column}
    FROM test_case_runs
    WHERE submission_auth != 'network_trusted' AND is_flakiness_excluded = false
    """)
  end

  defp update_reported_runs(excluded_columns) do
    # Refresh the ordinary view's columns; this does not rewrite any stored facts.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE OR REPLACE VIEW reported_test_case_runs AS
    SELECT * EXCEPT (#{excluded_columns}) FROM test_case_runs WHERE shard_report_id IS NULL
    UNION ALL
    SELECT f.* EXCEPT (#{excluded_columns}) FROM test_case_runs AS f FINAL
    INNER JOIN latest_shard_test_reports AS r
      ON f.test_run_id = r.id AND f.shard_report_id = r.fact_set_id AND f.project_id = r.project_id
    """)

    # Preserve immutable report membership and destination replay deduplication.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE OR REPLACE VIEW reported_test_run_destinations AS
    SELECT * EXCEPT (#{excluded_columns}) FROM test_run_destinations WHERE shard_report_id IS NULL
    UNION ALL
    SELECT f.* EXCEPT (#{excluded_columns}) REPLACE (min(f.inserted_at) AS inserted_at)
    FROM test_run_destinations AS f
    INNER JOIN latest_shard_test_reports AS r
      ON f.test_run_id = r.id AND f.shard_report_id = r.fact_set_id
    GROUP BY ALL
    """)
  end
end
