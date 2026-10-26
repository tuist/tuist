defmodule Tuist.IngestRepo.Migrations.ExcludeCorrelatedRunnerCrashesFromTestHealth do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("""
    ALTER TABLE test_case_runs ADD COLUMN IF NOT EXISTS
      flakiness_exclusion_reason LowCardinality(String) DEFAULT ''
    """)

    update_evidence_queries(" AND flakiness_exclusion_reason = ''")
    update_reported_runs("shard_report_id")
  end

  def down do
    update_evidence_queries("")
    update_reported_runs("shard_report_id, flakiness_exclusion_reason")
    execute("ALTER TABLE test_case_runs DROP COLUMN IF EXISTS flakiness_exclusion_reason")
    update_reported_runs("shard_report_id")
  end

  # Extend the existing evidence filters in place. No historical rewrite:
  # old reports retain their empty reason, and rolling deployments keep working.
  defp update_evidence_queries(condition) do
    execute("""
    ALTER TABLE test_case_runs_by_commit_mv MODIFY QUERY
    SELECT project_id, git_commit_sha, scheme, is_ci, status, id, test_case_id, is_flaky, inserted_at
    FROM test_case_runs WHERE submission_auth != 'network_trusted' #{condition}
    """)

    for {view, values, branch_condition} <- [
          {"test_case_run_daily_stats_per_case_mv",
           "countState() AS run_count, sumState(toUInt8(is_flaky)) AS flaky_run_count", ""},
          {"test_case_run_daily_success_stats_per_case_mv",
           "sumState(toUInt8(status = 'success')) AS successful_run_count", ""},
          {"test_case_run_daily_stats_per_case_default_branch_mv",
           "countState() AS run_count, sumState(toUInt8(is_flaky)) AS flaky_run_count, " <>
             "sumState(toUInt8(status = 'success')) AS successful_run_count",
           " AND is_default_branch"}
        ] do
      execute("""
      ALTER TABLE #{view} MODIFY QUERY
      SELECT project_id, toDate(inserted_at) AS date, assumeNotNull(test_case_id) AS test_case_id, #{values}
      FROM test_case_runs
      WHERE test_case_id IS NOT NULL AND submission_auth != 'network_trusted' #{branch_condition} #{condition}
      GROUP BY project_id, date, test_case_id
      """)
    end

    for {view, branch_condition} <- [
          {"test_case_runs_recent_window_per_case_mv", ""},
          {"test_case_runs_default_branch_recent_window_per_case_mv", " AND is_default_branch"}
        ] do
      execute("""
      ALTER TABLE #{view} MODIFY QUERY
      SELECT project_id, assumeNotNull(test_case_id) AS test_case_id,
        groupArraySortedState(2000)(
          -toUnixTimestamp64Micro(ran_at) * 4 + toUInt8(is_flaky) * 2 + toUInt8(status = 'success')
        ) AS recent_runs
      FROM test_case_runs
      WHERE test_case_id IS NOT NULL AND submission_auth != 'network_trusted' #{branch_condition} #{condition}
      GROUP BY project_id, test_case_id
      """)
    end
  end

  defp update_reported_runs(excluded_columns) do
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
