defmodule Tuist.IngestRepo.Migrations.ScopeCrossRunFlakinessToDestination do
  @moduledoc """
  Adds report-local destination identity to case executions and their commit lookup.

  Deploy this migration before application writers. Historical rows keep the
  empty (unknown) environment; no existing flaky flags or aggregates are rewritten.
  The lookup retains its sort key and is extended in place without a backfill or
  a materialized-view ingestion gap. Roll back writers before dropping columns.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    for table <- ["test_case_runs", "test_case_runs_by_commit"] do
      # ClickHouse adds a defaulted column without rewriting existing parts.
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute("""
      ALTER TABLE #{table} ADD COLUMN IF NOT EXISTS
        flakiness_environment LowCardinality(String) DEFAULT ''
      """)
    end

    update_commit_lookup(", flakiness_environment")
    update_reported_runs("shard_report_id")
  end

  def down do
    update_commit_lookup("")
    update_reported_runs("shard_report_id, flakiness_environment")

    for table <- ["test_case_runs_by_commit", "test_case_runs"] do
      # Writers must be rolled back first; only the derived destination key is removed.
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute("ALTER TABLE #{table} DROP COLUMN IF EXISTS flakiness_environment")
    end

    update_reported_runs("shard_report_id")
  end

  defp update_commit_lookup(environment_column) do
    # Replace the query atomically while retaining the target table and evidence filters.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    ALTER TABLE test_case_runs_by_commit_mv MODIFY QUERY
    SELECT project_id, git_commit_sha, scheme, is_ci, status, id, test_case_id, is_flaky, inserted_at#{environment_column}
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
