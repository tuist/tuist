Code.require_file(
  Path.expand(
    "../../../priv/ingest_repo/migrations/20260724140000_stop_unused_recent_test_case_run_aggregates.exs",
    __DIR__
  )
)

defmodule Tuist.IngestRepo.Migrations.StopUnusedRecentTestCaseRunAggregatesIntegrationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.IngestRepo
  alias Tuist.IngestRepo.Migrations.StopUnusedRecentTestCaseRunAggregates
  alias Tuist.Tests.TestCaseRun

  @moduletag :destructive_clickhouse_migration

  @active_table "test_case_runs_recent_100_per_case"
  @active_views [
    "test_case_runs_recent_100_per_case_mv",
    "test_case_runs_recent_100_success_per_case_mv"
  ]

  @retired_tables [
    "test_case_runs_recent_250_per_case",
    "test_case_runs_recent_500_per_case",
    "test_case_runs_recent_750_per_case",
    "test_case_runs_recent_per_case"
  ]

  @retired_views [
    "test_case_runs_recent_250_per_case_mv",
    "test_case_runs_recent_250_success_per_case_mv",
    "test_case_runs_recent_500_per_case_mv",
    "test_case_runs_recent_500_success_per_case_mv",
    "test_case_runs_recent_750_per_case_mv",
    "test_case_runs_recent_750_success_per_case_mv",
    "test_case_runs_recent_per_case_mv",
    "test_case_runs_recent_success_per_case_mv"
  ]

  setup do
    owner = Sandbox.start_owner!(IngestRepo, shared: true, sandbox: false)

    on_exit(fn ->
      try do
        drop_retired_views!()
        stop_automatic_merges!()
      after
        Sandbox.stop_owner(owner)
      end
    end)

    recreate_retired_views!()
    :ok
  end

  test "is retryable and keeps only the 100-run aggregate ingesting" do
    assert table_names(@active_views) == Enum.sort(@active_views)
    assert table_names(@retired_views) == Enum.sort(@retired_views)
    assert table_names(@retired_tables) == Enum.sort(@retired_tables)

    StopUnusedRecentTestCaseRunAggregates.up()
    StopUnusedRecentTestCaseRunAggregates.up()

    assert table_names(@active_views) == Enum.sort(@active_views)
    assert table_names(@retired_views) == []
    assert table_names(@retired_tables) == Enum.sort(@retired_tables)

    project_id = System.unique_integer([:positive, :monotonic])
    test_case_id = UUIDv7.generate()
    active_count_before = row_count(@active_table, project_id, test_case_id)
    before_counts = Map.new(@retired_tables, &{&1, row_count(&1, project_id, test_case_id)})

    IngestRepo.insert_all(TestCaseRun, [run_attrs(project_id, test_case_id)])

    assert row_count(@active_table, project_id, test_case_id) > active_count_before

    for table <- @retired_tables do
      assert row_count(table, project_id, test_case_id) == Map.fetch!(before_counts, table)
    end
  end

  test "retired views ingest before the migration and stop ingesting after it" do
    project_id = System.unique_integer([:positive, :monotonic])
    test_case_id = UUIDv7.generate()
    initial_counts = Map.new(@retired_tables, &{&1, row_count(&1, project_id, test_case_id)})

    IngestRepo.insert_all(TestCaseRun, [run_attrs(project_id, test_case_id)])

    counts_before_retirement =
      Map.new(@retired_tables, fn table ->
        count = row_count(table, project_id, test_case_id)
        assert count > Map.fetch!(initial_counts, table)
        {table, count}
      end)

    StopUnusedRecentTestCaseRunAggregates.up()
    IngestRepo.insert_all(TestCaseRun, [run_attrs(project_id, test_case_id)])

    for table <- @retired_tables do
      assert row_count(table, project_id, test_case_id) ==
               Map.fetch!(counts_before_retirement, table)
    end
  end

  defp recreate_retired_views! do
    drop_retired_views!()

    for window_size <- [250, 500, 750] do
      IngestRepo.query!("""
      CREATE MATERIALIZED VIEW test_case_runs_recent_#{window_size}_per_case_mv
      TO test_case_runs_recent_#{window_size}_per_case
      AS SELECT
        project_id,
        assumeNotNull(test_case_id) AS test_case_id,
        groupArraySortedState(#{window_size})((-toUnixTimestamp64Micro(ran_at), toUInt8(is_flaky))) AS recent_runs
      FROM test_case_runs
      WHERE test_case_id IS NOT NULL
      GROUP BY project_id, test_case_id
      """)

      IngestRepo.query!("""
      CREATE MATERIALIZED VIEW test_case_runs_recent_#{window_size}_success_per_case_mv
      TO test_case_runs_recent_#{window_size}_per_case
      AS SELECT
        project_id,
        assumeNotNull(test_case_id) AS test_case_id,
        groupArraySortedState(#{window_size})((-toUnixTimestamp64Micro(ran_at), toUInt8(status = 'success'))) AS recent_successful_runs
      FROM test_case_runs
      WHERE test_case_id IS NOT NULL
      GROUP BY project_id, test_case_id
      """)
    end

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW test_case_runs_recent_per_case_mv
    TO test_case_runs_recent_per_case
    AS SELECT
      project_id,
      assumeNotNull(test_case_id) AS test_case_id,
      groupArrayLastState(1000)((ran_at, toUInt8(is_flaky))) AS recent_runs
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL
    GROUP BY project_id, test_case_id
    """)

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW test_case_runs_recent_success_per_case_mv
    TO test_case_runs_recent_per_case
    AS SELECT
      project_id,
      assumeNotNull(test_case_id) AS test_case_id,
      groupArrayLastState(1000)((ran_at, toUInt8(status = 'success'))) AS recent_successful_runs
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL
    GROUP BY project_id, test_case_id
    """)
  end

  defp drop_retired_views! do
    for view <- @retired_views do
      IngestRepo.query!("DROP VIEW IF EXISTS #{view}")
    end
  end

  defp stop_automatic_merges! do
    for table <- @retired_tables do
      IngestRepo.query!("""
      ALTER TABLE #{table}
      MODIFY SETTING max_bytes_to_merge_at_max_space_in_pool = 1
      """)
    end
  end

  defp table_names(names) do
    %{rows: rows} =
      IngestRepo.query!(
        """
        SELECT name
        FROM system.tables
        WHERE database = currentDatabase()
          AND name IN ({names:Array(String)})
        ORDER BY name
        """,
        %{names: names}
      )

    Enum.map(rows, fn [name] -> name end)
  end

  defp row_count(table, project_id, test_case_id) do
    %{rows: [[count]]} =
      IngestRepo.query!(
        """
        SELECT count()
        FROM #{table}
        WHERE project_id = {project_id:Int64}
          AND test_case_id = {test_case_id:UUID}
        """,
        %{project_id: project_id, test_case_id: test_case_id}
      )

    count
  end

  defp run_attrs(project_id, test_case_id) do
    now = NaiveDateTime.utc_now()

    %{
      id: UUIDv7.generate(),
      test_run_id: UUIDv7.generate(),
      test_module_run_id: UUIDv7.generate(),
      test_case_id: test_case_id,
      project_id: project_id,
      is_ci: false,
      scheme: "",
      git_branch: "main",
      git_commit_sha: "",
      module_name: "MyTests",
      suite_name: "TestSuite",
      name: "testExample",
      status: 0,
      is_flaky: false,
      is_new: false,
      is_quarantined: false,
      duration: 100,
      ran_at: now,
      inserted_at: now
    }
  end
end
