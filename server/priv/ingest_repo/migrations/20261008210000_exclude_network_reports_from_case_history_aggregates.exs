defmodule Tuist.IngestRepo.Migrations.ExcludeNetworkReportsFromCaseHistoryAggregates do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up, do: update_queries(" AND submission_auth != 'network_trusted'")
  def down, do: update_queries("")

  defp update_queries(condition) do
    execute("""
    ALTER TABLE flaky_test_case_runs_mv MODIFY QUERY
    SELECT project_id, assumeNotNull(test_case_id) AS test_case_id, test_run_id, inserted_at, ran_at, is_ci
    FROM test_case_runs WHERE is_flaky = 1 AND test_case_id IS NOT NULL #{condition}
    """)

    execute("""
    ALTER TABLE test_case_duration_daily_stats_per_case_mv MODIFY QUERY
    SELECT project_id, toDate(ran_at) AS date, assumeNotNull(test_case_id) AS test_case_id, is_ci,
      uniqExactState(id) AS run_count, avgState(duration) AS avg_duration,
      quantileState(0.5)(duration) AS p50_duration, quantileState(0.9)(duration) AS p90_duration,
      quantileState(0.99)(duration) AS p99_duration
    FROM test_case_runs WHERE test_case_id IS NOT NULL #{condition}
    GROUP BY project_id, date, test_case_id, is_ci
    """)

    execute("""
    ALTER TABLE test_case_runs_active_daily_stats_mv MODIFY QUERY
    SELECT project_id, toDate(ran_at) AS date, is_ci, assumeNotNull(test_case_id) AS test_case_id
    FROM test_case_runs WHERE test_case_id IS NOT NULL #{condition}
    GROUP BY project_id, date, is_ci, test_case_id
    """)
  end
end
