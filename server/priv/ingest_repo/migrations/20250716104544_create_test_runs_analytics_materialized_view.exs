defmodule Tuist.ClickHouseRepo.Migrations.CreateTestRunsAnalyticsMaterializedView do
  use Ecto.Migration

  def up do
    # Create materialized view for daily test runs analytics
    # This covers most use cases including 7-day and 30-day windows
    execute("""
    CREATE MATERIALIZED VIEW test_runs_analytics_daily
    ENGINE = SummingMergeTree()
    PARTITION BY toYYYYMM(date)
    ORDER BY (project_id, date, is_ci, assumeNotNull(status))
    AS SELECT
        project_id,
        toDate(ran_at) as date,
        is_ci,
        status,
        count() as run_count,
        sum(duration) as total_duration
    FROM command_events
    WHERE (name = 'test' OR (name = 'xcodebuild' AND (subcommand = 'test' OR subcommand = 'test-without-building'))) AND status IS NOT NULL
    GROUP BY project_id, toDate(ran_at), is_ci, status
    """)

    execute("""
    INSERT INTO test_runs_analytics_daily
    SELECT
        project_id,
        toDate(ran_at) as date,
        is_ci,
        status,
        count() as run_count,
        sum(duration) as total_duration
    FROM command_events
    WHERE (name = 'test' OR (name = 'xcodebuild' AND (subcommand = 'test' OR subcommand = 'test-without-building'))) AND status IS NOT NULL
    GROUP BY project_id, toDate(ran_at), is_ci, status
    """)

    # Create materialized view for monthly test runs analytics
    # Only used for 12-month windows (>= 60 days)
    execute("""
    CREATE MATERIALIZED VIEW test_runs_analytics_monthly
    ENGINE = SummingMergeTree()
    PARTITION BY toYear(date)
    ORDER BY (project_id, date, is_ci, assumeNotNull(status))
    AS SELECT
        project_id,
        toStartOfMonth(ran_at) as date,
        is_ci,
        status,
        count() as run_count,
        sum(duration) as total_duration
    FROM command_events
    WHERE (name = 'test' OR (name = 'xcodebuild' AND (subcommand = 'test' OR subcommand = 'test-without-building'))) AND status IS NOT NULL
    GROUP BY project_id, toStartOfMonth(ran_at), is_ci, status
    """)

    execute("""
    INSERT INTO test_runs_analytics_monthly
    SELECT
        project_id,
        toStartOfMonth(ran_at) as date,
        is_ci,
        status,
        count() as run_count,
        sum(duration) as total_duration
    FROM command_events
    WHERE (name = 'test' OR (name = 'xcodebuild' AND (subcommand = 'test' OR subcommand = 'test-without-building'))) AND status IS NOT NULL
    GROUP BY project_id, toStartOfMonth(ran_at), is_ci, status
    """)
  end

  def down do
    execute("DROP VIEW IF EXISTS test_runs_analytics_daily")
    execute("DROP VIEW IF EXISTS test_runs_analytics_monthly")
  end
end
