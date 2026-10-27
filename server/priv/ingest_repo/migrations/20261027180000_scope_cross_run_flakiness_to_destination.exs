defmodule Tuist.IngestRepo.Migrations.ScopeCrossRunFlakinessToDestination do
  @moduledoc """
  Links case runs directly to the destination that produced their results.

  Deploy this migration before application writers. Historical rows keep the
  null destination reference; no existing flags or aggregates are rewritten.
  The commit lookup retains its sort key and is extended without a backfill or
  materialized-view ingestion gap. Roll back writers before dropping the schema.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    for table <- ["test_case_runs", "test_case_runs_by_commit"] do
      # ClickHouse adds a defaulted column without rewriting existing parts.
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute("""
      ALTER TABLE #{table}
        ADD COLUMN IF NOT EXISTS test_run_destination_id Nullable(UUID),
        ADD COLUMN IF NOT EXISTS is_destination_ambiguous Bool DEFAULT false
      """)
    end

    # Parent IDs let the lookup restrict destination reads by their existing sort
    # key. Historical rows need no backfill because they have no destination link.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_case_runs_by_commit ADD COLUMN IF NOT EXISTS test_run_id UUID")

    update_commit_lookup(", test_run_id, test_run_destination_id, is_destination_ambiguous")
    update_reported_runs("shard_report_id")
  end

  def down do
    update_commit_lookup("")
    update_reported_runs("shard_report_id, test_run_destination_id, is_destination_ambiguous")

    for table <- ["test_case_runs_by_commit", "test_case_runs"] do
      # Writers must be rolled back first; existing outcomes/destinations remain.
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute("""
      ALTER TABLE #{table}
        DROP COLUMN IF EXISTS test_run_destination_id,
        DROP COLUMN IF EXISTS is_destination_ambiguous
      """)
    end

    update_reported_runs("shard_report_id")

    # Only the redundant lookup parent reference is removed, not the case-run parent.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE test_case_runs_by_commit DROP COLUMN IF EXISTS test_run_id")
  end

  defp update_commit_lookup(destination_columns) do
    # Replace the query atomically while retaining the target table and evidence filters.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE test_case_runs_by_commit_mv MODIFY QUERY
    SELECT project_id, git_commit_sha, scheme, is_ci, status, id, test_case_id, is_flaky, inserted_at#{destination_columns}
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
  end
end
