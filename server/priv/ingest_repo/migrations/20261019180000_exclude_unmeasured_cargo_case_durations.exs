defmodule Tuist.IngestRepo.Migrations.ExcludeUnmeasuredCargoCaseDurations do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up, do: update_views(true)
  def down, do: update_views(false)

  defp update_views(exclude_unmeasured) do
    measured =
      if exclude_unmeasured,
        do: "scheme != 'cargo test' AND NOT startsWith(scheme, 'cargo test · ')",
        else: "1"

    # Keep outcome counts, while only measured durations enter the aggregate states.
    # StateIf preserves the existing AggregateFunction types, including genuine zero timings.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs_daily_stats MODIFY QUERY
    SELECT project_id, toDate(inserted_at) AS date, status, is_ci, is_flaky,
      countState() AS count_state,
      avgStateIf(duration, #{measured}) AS avg_duration_state,
      quantileStateIf(0.50)(duration, #{measured}) AS p50_duration_state,
      quantileStateIf(0.90)(duration, #{measured}) AS p90_duration_state,
      quantileStateIf(0.99)(duration, #{measured}) AS p99_duration_state
    FROM test_case_runs
    GROUP BY project_id, toDate(inserted_at), status, is_ci, is_flaky
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_duration_daily_stats_per_case_mv MODIFY QUERY
    SELECT project_id, toDate(ran_at) AS date,
      assumeNotNull(test_case_id) AS test_case_id, is_ci,
      uniqExactState(id) AS run_count,
      avgState(duration) AS avg_duration,
      quantileState(0.5)(duration) AS p50_duration,
      quantileState(0.9)(duration) AS p90_duration,
      quantileState(0.99)(duration) AS p99_duration
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL AND (#{measured})
    GROUP BY project_id, date, test_case_id, is_ci
    """
  end
end
