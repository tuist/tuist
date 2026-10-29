defmodule Tuist.Gradle.MetricsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.BuildMetrics
  alias Tuist.Gradle.Metrics
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    project = ProjectsFixtures.project_fixture()
    start_at = DateTime.new!(Date.add(Date.utc_today(), -2), ~T[00:00:00])
    end_at = DateTime.add(start_at, 3, :day)
    %{project: project, opts: [start_datetime: start_at, end_datetime: end_at], start_at: start_at}
  end

  defp build(project, start_at, attrs) do
    GradleFixtures.build_fixture(
      Keyword.merge(
        [
          project_id: project.id,
          inserted_at: DateTime.to_naive(DateTime.add(start_at, 3600)),
          duration_ms: 1000,
          status: "success"
        ],
        attrs
      )
    )
  end

  test "automatic cache work is additive and legacy responses retain their metric keys", %{
    project: project,
    opts: opts,
    start_at: start_at
  } do
    build(project, start_at,
      custom_values: %{"tuist.cache_work_avoided_ms" => "1234", "tuist.cache_time_saved_ms" => "99"}
    )

    build(project, start_at, custom_values: %{"tuist.cache_work_avoided_ms" => "0"})
    build(project, start_at, custom_values: %{"tuist.cache_work_avoided_ms" => "-5"})
    build(project, start_at, custom_values: %{"tuist.cache_work_avoided_ms" => "18446744073709551616"})
    result = BuildMetrics.query(project.id, opts)
    assert result.totals["cache_work_avoided"] == 1234
    assert result.totals["cache_work_avoided_samples"] == 2
    assert result.totals["cache_time_saved"] == 99
    assert List.last(result.series["cache_work_avoided"]) == nil
    assert List.last(result.series["cache_work_avoided_samples"]) == 0
    legacy = Metrics.query(project.id, opts)
    refute Map.has_key?(legacy.totals, "cache_work_avoided")
    refute Map.has_key?(legacy.series, "cache_work_avoided_samples")
    assert legacy.totals["cache_time_saved"] == 99
    workloads = Metrics.query(project.id, Keyword.put(opts, :view, "workloads"))
    assert Enum.all?(workloads.rows, &(not Map.has_key?(&1, "cache_work_avoided")))
  end

  test "whole-period statistics weight builds and exclude cancellations from success rate", %{
    project: project,
    opts: opts,
    start_at: start_at
  } do
    for _ <- 1..9, do: build(project, start_at, duration_ms: 1000)

    build(project, start_at,
      duration_ms: 9000,
      status: "failure",
      inserted_at: DateTime.to_naive(DateTime.add(start_at, 1, :day))
    )

    build(project, start_at, duration_ms: 1000, status: "cancelled")
    result = Metrics.query(project.id, opts)
    assert result.totals["builds"] == 11
    assert result.totals["success_rate"] == 90.0
    assert result.totals["p50"] == 1000.0
    assert result.series["builds"] == [10, 1, 0]
    assert List.last(result.series["success_rate"]) == nil
    assert List.last(result.series["p50"]) == nil
  end

  test "attention counts the union of failed and slow builds", %{project: project, opts: opts, start_at: start_at} do
    build(project, start_at, status: "failure", duration_ms: 3000)
    build(project, start_at, duration_ms: 3000)
    build(project, start_at, duration_ms: 2000)
    result = Metrics.query(project.id, Keyword.merge(opts, view: "total", slow_build_threshold_ms: 2000))
    assert result.totals["builds_needing_attention"] == 2
    assert result.totals["slow_build_threshold"] == 2000
  end

  test "cache savings stay unknown without evidence and include coverage", %{
    project: project,
    opts: opts,
    start_at: start_at
  } do
    build(project, start_at, tasks: [%{task_path: ":compile", outcome: "remote_hit"}])
    assert Metrics.query(project.id, opts).totals["cache_time_saved"] == nil
    build(project, start_at, custom_values: %{"tuist.cache_time_saved_ms" => "1234"})
    build(project, start_at, custom_values: %{"tuist.cache_time_saved_ms" => "-5"})
    build(project, start_at, custom_values: %{"tuist.cache_time_saved_ms" => "NaN"})
    build(project, start_at, custom_values: %{"tuist.cache_time_saved_ms" => "18446744073709551616"})
    result = Metrics.query(project.id, opts)
    assert result.totals["cache_time_saved"] == 1234
    assert result.totals["cache_time_saved_samples"] == 1
    assert result.totals["builds"] == 5
    assert List.last(result.series["cache_time_saved"]) == nil
  end

  test "filters scope every view to the same project, branch, environment and workload", %{
    project: project,
    opts: opts,
    start_at: start_at
  } do
    build(project, start_at, git_branch: "develop", is_ci: true, requested_tasks: [":app:testDebugUnitTest"])
    build(project, start_at, git_branch: "main", is_ci: true)
    build(project, start_at, git_branch: "develop", is_ci: false)
    build(ProjectsFixtures.project_fixture(), start_at, git_branch: "develop", is_ci: true)
    opts = Keyword.merge(opts, git_branch: "develop", is_ci: true, workload: "Unit tests")
    assert Metrics.query(project.id, opts).totals["builds"] == 1

    assert [%{"workload" => "Unit tests", "builds" => 1}] =
             Metrics.query(project.id, Keyword.put(opts, :view, "workloads")).rows

    assert [%{category: "verification", builds: 0}, _, _] =
             Metrics.query(project.id, Keyword.put(opts, :view, "failures")).rows

    assert Metrics.query(project.id, Keyword.put(opts, :view, "recent_failures")).rows == []
  end

  test "workload classification supports explicit overrides and requested task paths", %{
    project: project,
    opts: opts,
    start_at: start_at
  } do
    build(project, start_at, requested_tasks: [":app:connectedDebugAndroidTest"])
    build(project, start_at, requested_tasks: [":app:pixel4api34AppDevDebugAndroidTest"])
    build(project, start_at, requested_tasks: [":app:assembleDebug"])
    build(project, start_at, requested_tasks: [":app:lintDebug"])
    build(project, start_at, custom_values: %{"tuist.workload" => "Release verification"})
    rows = Metrics.query(project.id, Keyword.put(opts, :view, "workloads")).rows

    assert Enum.map(rows, & &1["workload"]) == [
             "Assemble / package",
             "Instrumented tests",
             "Lint / checks",
             "Release verification"
           ]

    assert Metrics.dimension_values(project.id, "workload") == Enum.map(rows, & &1["workload"])
  end

  test "failure reasons preserve unknown instead of inventing infrastructure failures", %{
    project: project,
    opts: opts,
    start_at: start_at
  } do
    build(project, start_at, status: "failure")
    build(project, start_at, status: "failure", custom_values: %{"tuist.failure_category" => "verification"})
    build(project, start_at, status: "success", custom_values: %{"tuist.failure_category" => "verification"})
    result = Metrics.query(project.id, Keyword.put(opts, :view, "failures"))

    assert result.rows == [
             %{category: "verification", builds: 1},
             %{category: "infrastructure_tooling", builds: 0},
             %{category: "unknown", builds: 1}
           ]
  end

  test "recorded verification tasks establish a failure category without a metadata override", %{
    project: project,
    opts: opts,
    start_at: start_at
  } do
    build(project, start_at,
      status: "failure",
      tasks: [
        %{
          task_path: ":app:testDebugUnitTest",
          outcome: "failed",
          task_type: "org.gradle.api.tasks.testing.Test_Decorated"
        }
      ]
    )

    build(project, start_at,
      status: "failure",
      tasks: [
        %{
          task_path: ":app:compileKotlin",
          outcome: "failed",
          task_type: "org.jetbrains.kotlin.gradle.tasks.KotlinCompile"
        }
      ]
    )

    build(project, start_at,
      status: "failure",
      tasks: [%{task_path: ":script", outcome: "failed", task_type: "org.gradle.api.tasks.Exec"}]
    )

    result = Metrics.query(project.id, Keyword.put(opts, :view, "failures"))

    assert result.rows == [
             %{category: "verification", builds: 2},
             %{category: "infrastructure_tooling", builds: 0},
             %{category: "unknown", builds: 1}
           ]

    {native, _} =
      Tuist.Gradle.list_builds(
        project.id,
        %{filters: [%{field: :failure_category, op: :==, value: "verification"}], page_size: 20},
        failure_category: true
      )

    assert length(native) == 2
    assert Enum.all?(native, &(&1.failure_category == "verification"))
  end

  test "recent failures include recorded metadata and never leak other projects", %{
    project: project,
    opts: opts,
    start_at: start_at
  } do
    id = build(project, start_at, status: "failure", requested_tasks: [":app:test"])
    build(ProjectsFixtures.project_fixture(), start_at, status: "failure")

    assert [%{id: ^id, requested_tasks: [":app:test"], workload: "Unit tests", user: user}] =
             Metrics.query(project.id, Keyword.put(opts, :view, "recent_failures")).rows

    assert user != "Unknown"
  end

  test "range is half-open and empty counts differ from missing durations", %{
    project: project,
    opts: opts,
    start_at: start_at
  } do
    build(project, start_at, inserted_at: DateTime.to_naive(opts[:end_datetime]))
    result = Metrics.query(project.id, opts)
    assert result.totals["builds"] == 0
    assert result.totals["p50"] == nil
    assert result.totals["success_rate"] == nil
    assert result.totals["slow_build_threshold"] == nil
    build(project, start_at, inserted_at: DateTime.to_naive(start_at))
    assert Metrics.query(project.id, opts).totals["builds"] == 1
  end

  test "hourly and monthly ranges align dates with values", %{project: project, opts: opts, start_at: start_at} do
    hourly = Keyword.put(opts, :end_datetime, DateTime.add(start_at, 2, :hour))
    assert length(Metrics.query(project.id, hourly).dates) == 2
    monthly = Keyword.put(opts, :end_datetime, DateTime.add(start_at, 90, :day))
    result = Metrics.query(project.id, monthly)
    assert length(result.dates) in 3..4
    assert length(result.dates) == length(result.series["builds"])
  end
end
