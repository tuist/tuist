defmodule Tuist.IngestRepo.Migrations.StopUnusedRecentTestCaseRunAggregates do
  @moduledoc """
  Stops writes and background merges for rolling test-run aggregates that the
  application no longer reads.

  The unpartitioned aggregate tables retain large arrays per test case. Merging
  the 750-run table recently exhausted the production ClickHouse memory limit
  even though the compressed source parts were small. Dropping the incremental
  materialized views stops new parts from reaching the unused tables. Setting
  the maximum automatic merge size to one byte prevents the retained parts from
  scheduling another background merge while they remain available for
  comparison during the replacement rollout.

  The 100-run table and its two materialized views stay active because rolling
  triggers are constrained to windows that it can serve.
  """

  use Ecto.Migration

  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  @active_materialized_views [
    "test_case_runs_recent_100_per_case_mv",
    "test_case_runs_recent_100_success_per_case_mv"
  ]

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
    assert_views_present!(@active_materialized_views)
    assert_no_active_merges!(@retired_tables)

    # Prevent a new automatic merge from starting while the views are removed.
    # A merge that won the race with this setting is caught by the second
    # assertion, leaving the views active so the migration can be retried.
    for table <- @retired_tables do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      IngestRepo.query!("""
      ALTER TABLE #{table}
      MODIFY SETTING max_bytes_to_merge_at_max_space_in_pool = 1
      """)
    end

    assert_no_active_merges!(@retired_tables)

    for materialized_view <- @retired_materialized_views do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      IngestRepo.query!("DROP VIEW IF EXISTS #{materialized_view}")
    end

    assert_views_absent!(@retired_materialized_views)
    assert_automatic_merges_stopped!(@retired_tables)
  end

  def down do
    raise Ecto.MigrationError,
          "the retired materialized views require a bounded backfill before they can be re-enabled safely"
  end

  defp assert_views_present!(views) do
    present_views = table_names(views)
    missing_views = views -- present_views

    if missing_views != [] do
      raise Ecto.MigrationError,
            "required rolling materialized views are missing: #{Enum.join(missing_views, ", ")}"
    end
  end

  defp assert_views_absent!(views) do
    case table_names(views) do
      [] ->
        :ok

      present_views ->
        raise Ecto.MigrationError,
              "retired rolling materialized views remain present: #{Enum.join(present_views, ", ")}"
    end
  end

  defp assert_no_active_merges!(tables) do
    quoted_names = Enum.map_join(tables, ", ", &"'#{&1}'")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    %{rows: rows} =
      IngestRepo.query!("""
      SELECT DISTINCT table
      FROM system.merges
      WHERE database = currentDatabase()
        AND table IN (#{quoted_names})
      ORDER BY table
      """)

    if rows != [] do
      tables = Enum.map_join(rows, ", ", fn [table] -> table end)

      raise Ecto.MigrationError,
            "active background merges must finish before retiring rolling aggregates: #{tables}"
    end
  end

  defp assert_automatic_merges_stopped!(tables) do
    stopped_tables =
      tables
      |> table_metadata()
      |> Enum.filter(fn [_name, create_table_query] ->
        String.contains?(
          create_table_query,
          "max_bytes_to_merge_at_max_space_in_pool = 1"
        )
      end)
      |> Enum.map(fn [name, _create_table_query] -> name end)

    mergeable_tables = tables -- stopped_tables

    if mergeable_tables != [] do
      raise Ecto.MigrationError,
            "rolling aggregate tables still allow automatic merges: #{Enum.join(mergeable_tables, ", ")}"
    end
  end

  defp table_names(names) do
    names
    |> table_metadata()
    |> Enum.map(fn [name, _create_table_query] -> name end)
  end

  defp table_metadata(names) do
    quoted_names = Enum.map_join(names, ", ", &"'#{&1}'")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    %{rows: rows} =
      IngestRepo.query!("""
      SELECT name, create_table_query
      FROM system.tables
      WHERE database = currentDatabase()
        AND name IN (#{quoted_names})
      ORDER BY name
      """)

    rows
  end
end
