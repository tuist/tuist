defmodule Tuist.IngestRepo.Migrations.ExcludeNetworkReportsFromTestValidation do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # These indexes are evidence for cross-run flakiness, selective execution,
  # reliability/quarantine automations and first-run detection. Unsigned results
  # remain in the report tables, but must not become authoritative evidence.
  # Updating SELECT in place preserves all historical authenticated states and
  # avoids a backfill or a gap in materialized-view ingestion.
  def up, do: update_queries(" AND submission_auth != 'network_trusted'")
  def down, do: update_queries("")

  defp update_queries(condition) do
    execute("""
    ALTER TABLE test_case_runs_by_commit_mv MODIFY QUERY
    SELECT project_id, git_commit_sha, scheme, is_ci, status, id, test_case_id, is_flaky, inserted_at
    FROM test_case_runs WHERE 1 = 1 #{condition}
    """)

    execute("""
    ALTER TABLE test_case_branch_presence MODIFY QUERY
    SELECT project_id, git_branch, is_ci, test_case_id, ran_at
    FROM test_case_runs WHERE 1 = 1 #{condition}
    """)

    execute("""
    ALTER TABLE test_case_runs_validated_on_branch_mv MODIFY QUERY
    SELECT project_id, git_branch, assumeNotNull(test_case_id) AS test_case_id
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL AND status = 'success' AND is_flaky = false #{condition}
    GROUP BY project_id, git_branch, test_case_id
    """)

    for {view, expression, column} <- [
          {"test_case_run_daily_stats_per_case_mv",
           "countState() AS run_count, sumState(toUInt8(is_flaky))", "flaky_run_count"},
          {"test_case_run_daily_success_stats_per_case_mv",
           "sumState(toUInt8(status = 'success'))", "successful_run_count"}
        ] do
      execute("""
      ALTER TABLE #{view} MODIFY QUERY
      SELECT project_id, toDate(inserted_at) AS date, assumeNotNull(test_case_id) AS test_case_id,
        #{expression} AS #{column}
      FROM test_case_runs WHERE test_case_id IS NOT NULL #{condition}
      GROUP BY project_id, date, test_case_id
      """)
    end

    execute("""
    ALTER TABLE test_case_run_daily_stats_per_case_default_branch_mv MODIFY QUERY
    SELECT project_id, toDate(inserted_at) AS date, assumeNotNull(test_case_id) AS test_case_id,
      countState() AS run_count, sumState(toUInt8(is_flaky)) AS flaky_run_count,
      sumState(toUInt8(status = 'success')) AS successful_run_count
    FROM test_case_runs WHERE test_case_id IS NOT NULL AND is_default_branch #{condition}
    GROUP BY project_id, date, test_case_id
    """)

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
      FROM test_case_runs WHERE test_case_id IS NOT NULL #{branch_condition} #{condition}
      GROUP BY project_id, test_case_id
      """)
    end
  end
end
