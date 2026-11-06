defmodule Tuist.NetworkTrustedAutomationEvidenceTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Alerts
  alias Tuist.Builds.Analytics, as: BuildAnalytics
  alias Tuist.Tests.Analytics, as: TestAnalytics
  alias Tuist.Tests.Test.Buffer
  alias TuistTestSupport.Fixtures.AlertsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  test "unsigned rows cannot occupy rolling alert windows or alter their metrics" do
    project = ProjectsFixtures.project_fixture()
    now = DateTime.utc_now()

    for index <- 1..4 do
      RunsFixtures.build_fixture(
        project_id: project.id,
        duration: 1000,
        inserted_at: DateTime.add(now, -index, :minute),
        cacheable_tasks_count: 10,
        cacheable_task_local_hits_count: 5,
        cacheable_task_remote_hits_count: 5
      )

      RunsFixtures.test_fixture(project_id: project.id, duration: 1000, ran_at: DateTime.add(now, -index, :minute))
    end

    Buffer.flush()

    baseline =
      {BuildAnalytics.build_duration_metric_by_count(project.id, :average, limit: 2),
       BuildAnalytics.build_cache_hit_rate_metric_by_count(project.id, :average, limit: 2),
       TestAnalytics.test_duration_metric_by_count(project.id, :average, limit: 2)}

    assert baseline == {1000.0, 1.0, 1000.0}

    for _ <- 1..2 do
      RunsFixtures.build_fixture(
        project_id: project.id,
        submission_auth: "network_trusted",
        duration: 9_000_000,
        inserted_at: now,
        cacheable_tasks_count: 10,
        cacheable_task_local_hits_count: 0,
        cacheable_task_remote_hits_count: 0
      )

      RunsFixtures.test_fixture(project_id: project.id, submission_auth: "network_trusted", duration: 9_000_000)
    end

    Buffer.flush()

    assert {BuildAnalytics.build_duration_metric_by_count(project.id, :average, limit: 2),
            BuildAnalytics.build_cache_hit_rate_metric_by_count(project.id, :average, limit: 2),
            TestAnalytics.test_duration_metric_by_count(project.id, :average, limit: 2)} == baseline

    for category <- [:build_run_duration, :test_run_duration, :cache_hit_rate] do
      rule =
        AlertsFixtures.alert_rule_fixture(
          project: project,
          category: category,
          metric: :average,
          deviation_percentage: 20.0,
          rolling_window_size: 2
        )

      assert Alerts.evaluate(rule) == :ok
    end
  end
end
