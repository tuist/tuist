defmodule Tuist.Automations.Monitors.TestDurationMonitorTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Automations.Monitors.TestDurationMonitor
  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "evaluate/2" do
    test "fires for a test case whose p90 is at or above the threshold" do
      # Given
      project = ProjectsFixtures.project_fixture()
      run_test_case(project, "testSlow", [5000, 5100, 5200, 5300, 5400])
      run_test_case(project, "testFast", [10, 11, 12, 13, 14])

      slow_id = test_case_id(project, "testSlow")

      alert = duration_alert(project, %{"threshold" => 1000})

      # When
      %{triggered: triggered} = TestDurationMonitor.evaluate(alert)

      # Then
      assert triggered == [slow_id]
    end

    test "does not fire for a test case below the sample floor" do
      # Given - four runs, all far above the threshold, one short of the floor
      project = ProjectsFixtures.project_fixture()
      run_test_case(project, "testRarelySlow", [60_000, 60_000, 60_000, 60_000])

      alert = duration_alert(project, %{"threshold" => 1000})

      # When
      %{triggered: triggered} = TestDurationMonitor.evaluate(alert)

      # Then - a percentile over four runs is not a percentile, so it is not
      # compared against the threshold at all
      assert triggered == []
      assert Tests.min_duration_samples() == 5
    end

    test "measures the configured statistic rather than always the mean" do
      # Given - a distribution whose mean is dragged up by one outlier, which
      # is the exact shape that made the dashboard's average misleading
      project = ProjectsFixtures.project_fixture()
      run_test_case(project, "testDebugged", [2, 2, 2, 2, 2, 2, 2, 2, 2, 4_676_155])

      # When
      p50_triggered =
        project
        |> duration_alert(%{"threshold" => 1000, "percentile" => "p50"})
        |> TestDurationMonitor.evaluate()

      avg_triggered =
        project
        |> duration_alert(%{"threshold" => 1000, "percentile" => "avg"})
        |> TestDurationMonitor.evaluate()

      # Then - the median is unmoved by the outlier while the mean is not
      assert p50_triggered.triggered == []
      assert avg_triggered.triggered == [test_case_id(project, "testDebugged")]
    end

    test "narrows to CI runs when the environment is ci" do
      # Given - the same test case is slow locally and fast on CI
      project = ProjectsFixtures.project_fixture()
      run_test_case(project, "testMixed", [9000, 9100, 9200, 9300, 9400], is_ci: false)
      run_test_case(project, "testMixed", [10, 11, 12, 13, 14], is_ci: true)

      # When
      ci = project |> duration_alert(%{"threshold" => 1000, "environment" => "ci"}) |> TestDurationMonitor.evaluate()

      local =
        project |> duration_alert(%{"threshold" => 1000, "environment" => "local"}) |> TestDurationMonitor.evaluate()

      any = project |> duration_alert(%{"threshold" => 1000, "environment" => "any"}) |> TestDurationMonitor.evaluate()

      # Then
      assert ci.triggered == []
      assert local.triggered == [test_case_id(project, "testMixed")]
      assert any.triggered == [test_case_id(project, "testMixed")]
    end

    test "honours the comparison direction" do
      # Given
      project = ProjectsFixtures.project_fixture()
      run_test_case(project, "testQuick", [10, 11, 12, 13, 14])

      # When
      below =
        project |> duration_alert(%{"threshold" => 1000, "comparison" => "lt"}) |> TestDurationMonitor.evaluate()

      above =
        project |> duration_alert(%{"threshold" => 1000, "comparison" => "gte"}) |> TestDurationMonitor.evaluate()

      # Then
      assert below.triggered == [test_case_id(project, "testQuick")]
      assert above.triggered == []
    end

    test "restricts the evaluation to the given test case ids" do
      # Given
      project = ProjectsFixtures.project_fixture()
      run_test_case(project, "testSlowOne", [5000, 5100, 5200, 5300, 5400])
      run_test_case(project, "testSlowTwo", [5000, 5100, 5200, 5300, 5400])

      one = test_case_id(project, "testSlowOne")
      alert = duration_alert(project, %{"threshold" => 1000})

      # When
      %{triggered: triggered} = TestDurationMonitor.evaluate(alert, [one])

      # Then
      assert triggered == [one]
    end

    test "excludes runs outside the configured window" do
      # Given
      project = ProjectsFixtures.project_fixture()
      run_test_case(project, "testSlow", [5000, 5100, 5200, 5300, 5400])

      # When - a window that ends before any run was recorded
      alert = duration_alert(project, %{"threshold" => 1000, "window" => "1d"})
      backdate_duration_stats(project, -10)

      %{triggered: triggered} = TestDurationMonitor.evaluate(alert)

      # Then
      assert triggered == []
    end
  end

  defp duration_alert(project, trigger_config) do
    AutomationsFixtures.automation_alert_fixture(
      project: project,
      monitor_type: "duration",
      trigger_config:
        Map.merge(
          %{"window_type" => "last_days", "window" => "30d", "percentile" => "p90", "comparison" => "gte"},
          trigger_config
        )
    )
  end

  defp test_case_id(project, name) do
    {test_cases, _meta} = Tests.list_test_cases(project.id, %{})
    %{id: id} = Enum.find(test_cases, &(&1.name == name))
    id
  end

  # The aggregate is keyed on the run's own date, so moving the rows back is
  # how a run lands outside the window without waiting for one to pass.
  defp backdate_duration_stats(project, days) do
    Tuist.IngestRepo.query!("""
    INSERT INTO test_case_duration_daily_stats_per_case
      (project_id, date, test_case_id, is_ci, run_count, avg_duration,
       p50_duration, p90_duration, p99_duration)
    SELECT
      project_id,
      addDays(date, #{days}) AS date,
      test_case_id,
      is_ci,
      run_count,
      avg_duration,
      p50_duration,
      p90_duration,
      p99_duration
    FROM test_case_duration_daily_stats_per_case
    WHERE project_id = #{project.id}
    """)

    Tuist.IngestRepo.query!("""
    ALTER TABLE test_case_duration_daily_stats_per_case
    DELETE WHERE project_id = #{project.id} AND date > addDays(today(), #{days})
    """)
  end

  defp run_test_case(project, name, durations, opts \\ []) do
    for duration <- durations do
      RunsFixtures.test_fixture(
        project_id: project.id,
        account_id: project.account_id,
        is_ci: Keyword.get(opts, :is_ci, false),
        test_modules: [
          %{
            name: "DurationModule",
            status: "success",
            duration: duration,
            test_cases: [%{name: name, status: "success", duration: duration}]
          }
        ]
      )
    end
  end
end
