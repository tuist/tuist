defmodule Tuist.Automations.Monitors.TestDurationMonitorTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Automations.Monitors.TestDurationMonitor
  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  # One test run per entry; each run reports every test case at the duration
  # it maps to.
  defp report_runs(project, runs, opts \\ []) do
    for durations <- runs do
      {:ok, _run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          ran_at: Keyword.get(opts, :ran_at, NaiveDateTime.utc_now()),
          test_modules: [
            %{
              name: "M",
              status: "success",
              duration: 1000,
              test_cases:
                Enum.map(durations, fn {name, duration} -> %{name: name, status: "success", duration: duration} end)
            }
          ]
        )
    end

    {test_cases, _meta} = Tests.list_test_cases(project.id, %{})
    Map.new(test_cases, &{&1.name, &1.id})
  end

  defp alert(project, config) do
    AutomationsFixtures.automation_alert_fixture(
      project: project,
      monitor_type: "test_duration",
      trigger_config: Map.merge(%{"window_type" => "last_days", "window" => "30d", "comparison" => "gte"}, config)
    )
  end

  # "steady" always takes 3s. "spiky" takes 100ms except one 30s run, so its
  # median is fast while its mean (~5.1s) and tail are slow.
  defp steady_and_spiky(project) do
    runs = for duration <- [100, 100, 100, 100, 100, 30_000], do: %{"steady" => 3000, "spiky" => duration}
    report_runs(project, runs)
  end

  test "compares the selected statistic against the threshold in milliseconds" do
    project = ProjectsFixtures.project_fixture()
    ids = steady_and_spiky(project)

    assert TestDurationMonitor.evaluate(alert(project, %{"statistic" => "p50", "threshold" => 2000})).triggered ==
             [ids["steady"]]

    assert TestDurationMonitor.evaluate(alert(project, %{"statistic" => "average", "threshold" => 4000})).triggered ==
             [ids["spiky"]]

    assert TestDurationMonitor.evaluate(alert(project, %{"statistic" => "p99", "threshold" => 10_000})).triggered ==
             [ids["spiky"]]

    assert TestDurationMonitor.evaluate(
             alert(project, %{"statistic" => "p50", "threshold" => 2000, "comparison" => "lt"})
           ).triggered == [ids["spiky"]]
  end

  test "ignores test cases with fewer than five runs in the window" do
    project = ProjectsFixtures.project_fixture()
    ids = report_runs(project, List.duplicate(%{"slow_but_rare" => 50_000}, 4))
    alert = alert(project, %{"statistic" => "average", "threshold" => 1000})

    assert TestDurationMonitor.evaluate(alert).triggered == []
    assert TestDurationMonitor.measurable_test_case_ids(alert, [ids["slow_but_rare"]]) == []

    report_runs(project, [%{"slow_but_rare" => 50_000}])

    assert TestDurationMonitor.evaluate(alert).triggered == [ids["slow_but_rare"]]
    assert TestDurationMonitor.measurable_test_case_ids(alert, [ids["slow_but_rare"]]) == [ids["slow_but_rare"]]
  end

  test "only reads runs inside the window and the requested test cases" do
    project = ProjectsFixtures.project_fixture()
    old = NaiveDateTime.add(NaiveDateTime.utc_now(), -10, :day)
    report_runs(project, List.duplicate(%{"slow_last_week" => 20_000}, 5), ran_at: old)
    ids = report_runs(project, List.duplicate(%{"slow_today" => 20_000, "also_slow" => 20_000}, 5))

    seven_days = alert(project, %{"statistic" => "p90", "threshold" => 10_000, "window" => "7d"})
    thirty_days = alert(project, %{"statistic" => "p90", "threshold" => 10_000, "window" => "30d"})

    assert Enum.sort(TestDurationMonitor.evaluate(seven_days).triggered) ==
             Enum.sort([ids["slow_today"], ids["also_slow"]])

    assert ids["slow_last_week"] in TestDurationMonitor.evaluate(thirty_days).triggered
    assert TestDurationMonitor.evaluate(seven_days, [ids["slow_today"]]).triggered == [ids["slow_today"]]
    assert TestDurationMonitor.evaluate(seven_days, []).triggered == []
  end
end
