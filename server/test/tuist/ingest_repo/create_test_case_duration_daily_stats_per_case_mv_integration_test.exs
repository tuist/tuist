Code.require_file(
  Path.expand(
    "../../../priv/ingest_repo/migrations/20260818130000_create_test_case_duration_daily_stats_per_case_mv.exs",
    __DIR__
  )
)

defmodule Tuist.IngestRepo.Migrations.CreateTestCaseDurationDailyStatsPerCaseMvIntegrationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.IngestRepo
  alias Tuist.IngestRepo.Migrations.CreateTestCaseDurationDailyStatsPerCaseMv
  alias Tuist.Tests.TestCaseRun

  @moduletag :destructive_clickhouse_migration

  @table "test_case_duration_daily_stats_per_case"

  setup do
    owner = Sandbox.start_owner!(IngestRepo, shared: true, sandbox: false)

    # `up/0` rather than `down/0`: every test here leaves the table holding only
    # what its own run seeded, and the rest of the suite reads the table by name.
    # Restoring the schema is what the shared database needs back.
    on_exit(fn ->
      try do
        CreateTestCaseDurationDailyStatsPerCaseMv.up()
      after
        Sandbox.stop_owner(owner)
      end
    end)

    :ok
  end

  test "seeds the read window, leaves history out of it, and repeats without double counting" do
    project_id = 1_000_000_000 + :rand.uniform(1_000_000_000)
    in_window = UUIDv7.generate()
    out_of_window = UUIDv7.generate()
    today = Date.utc_today()

    runs =
      Enum.flat_map([0, 3, 11], fn days_ago ->
        for {duration, is_ci} <- [{100, true}, {900, true}, {500, false}] do
          run_attrs(project_id, in_window, Date.add(today, -days_ago), duration, is_ci)
        end
      end) ++
        [run_attrs(project_id, out_of_window, Date.add(today, -120), 700, true)]

    IngestRepo.insert_all(TestCaseRun, runs)

    CreateTestCaseDurationDailyStatsPerCaseMv.up()

    assert stats(project_id) == expected_stats(project_id, Date.add(today, -30))
    assert Enum.all?(stats(project_id), fn row -> row.test_case_id == in_window end)

    seeded = stats(project_id)
    CreateTestCaseDurationDailyStatsPerCaseMv.up()

    assert stats(project_id) == seeded
  end

  test "the view keeps the table filled forward once the backfill has run" do
    project_id = 1_000_000_000 + :rand.uniform(1_000_000_000)
    test_case_id = UUIDv7.generate()

    CreateTestCaseDurationDailyStatsPerCaseMv.up()

    assert stats(project_id) == []

    IngestRepo.insert_all(TestCaseRun, [
      run_attrs(project_id, test_case_id, Date.utc_today(), 250, true)
    ])

    assert [%{test_case_id: ^test_case_id, run_count: 1, p50: 250}] = stats(project_id)
  end

  defp stats(project_id) do
    %{rows: rows} =
      IngestRepo.query!(
        """
        SELECT toString(test_case_id), date, is_ci,
               uniqExactMerge(run_count),
               round(quantileMerge(0.5)(p50_duration)),
               round(avgMerge(avg_duration))
        FROM #{@table}
        WHERE project_id = {project_id:Int64}
        GROUP BY test_case_id, date, is_ci
        ORDER BY test_case_id, date, is_ci
        """,
        %{project_id: project_id}
      )

    Enum.map(rows, &to_row/1)
  end

  defp expected_stats(project_id, window_start) do
    %{rows: rows} =
      IngestRepo.query!(
        """
        SELECT toString(assumeNotNull(test_case_id)), toDate(ran_at) AS date, is_ci,
               uniqExact(id),
               round(quantile(0.5)(duration)),
               round(avg(duration))
        FROM test_case_runs
        WHERE project_id = {project_id:Int64}
          AND toDate(ran_at) >= {window_start:Date}
          AND test_case_id IS NOT NULL
        GROUP BY test_case_id, date, is_ci
        ORDER BY test_case_id, date, is_ci
        """,
        %{project_id: project_id, window_start: window_start}
      )

    Enum.map(rows, &to_row/1)
  end

  defp to_row([test_case_id, date, is_ci, run_count, p50, avg]) do
    %{
      test_case_id: test_case_id,
      date: date,
      is_ci: is_ci,
      run_count: run_count,
      p50: round(p50),
      avg: round(avg)
    }
  end

  defp run_attrs(project_id, test_case_id, date, duration, is_ci) do
    ran_at = NaiveDateTime.new!(date, ~T[12:00:00.000000])

    %{
      id: UUIDv7.generate(),
      test_run_id: UUIDv7.generate(),
      test_module_run_id: UUIDv7.generate(),
      test_case_id: test_case_id,
      project_id: project_id,
      is_ci: is_ci,
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
      duration: duration,
      ran_at: ran_at,
      inserted_at: ran_at
    }
  end
end
