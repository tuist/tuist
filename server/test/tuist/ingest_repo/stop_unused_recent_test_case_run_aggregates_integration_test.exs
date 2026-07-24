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
    on_exit(fn -> Sandbox.stop_owner(owner) end)
  end

  test "is retryable and keeps only the 100-run aggregate ingesting" do
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
