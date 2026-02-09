defmodule Tuist.Gradle.AnalyticsTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Gradle.Analytics
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @now ~N[2024-04-30 10:20:30]
  @start_datetime ~U[2024-04-28 00:00:00Z]
  @end_datetime ~U[2024-04-30 23:59:59Z]

  describe "cache_hit_rate/4" do
    test "calculates cache hit rate from build data" do
      project = ProjectsFixtures.project_fixture()

      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: @now,
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true},
          %{task_path: ":app:compileJava", outcome: "local_hit", cacheable: true},
          %{task_path: ":app:assembleDebug", outcome: "executed", cacheable: true},
          %{task_path: ":app:test", outcome: "executed", cacheable: true}
        ]
      )

      got = Analytics.cache_hit_rate(project.id, @start_datetime, @end_datetime)

      assert got == 50.0
    end

    test "returns zero when no data exists" do
      project = ProjectsFixtures.project_fixture()

      got = Analytics.cache_hit_rate(project.id, @start_datetime, @end_datetime)

      assert got == 0.0
    end

    test "only considers cacheable tasks" do
      project = ProjectsFixtures.project_fixture()

      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: @now,
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true},
          %{task_path: ":app:clean", outcome: "executed", cacheable: false},
          %{task_path: ":app:assembleDebug", outcome: "executed", cacheable: true}
        ]
      )

      got = Analytics.cache_hit_rate(project.id, @start_datetime, @end_datetime)

      assert got == 50.0
    end

    test "aggregates across multiple builds" do
      project = ProjectsFixtures.project_fixture()

      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: @now,
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true}
        ]
      )

      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: @now,
        tasks: [
          %{task_path: ":app:compileJava", outcome: "executed", cacheable: true}
        ]
      )

      got = Analytics.cache_hit_rate(project.id, @start_datetime, @end_datetime)

      assert got == 50.0
    end
  end

  describe "cache_hit_rate_analytics/2" do
    test "returns analytics with trend and time-series data" do
      project = ProjectsFixtures.project_fixture()

      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: @now,
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true},
          %{task_path: ":app:assembleDebug", outcome: "executed", cacheable: true}
        ]
      )

      got =
        Analytics.cache_hit_rate_analytics(
          project.id,
          start_datetime: @start_datetime,
          end_datetime: @end_datetime
        )

      assert got.avg_hit_rate == 50.0
      assert is_number(got.trend)
      assert length(got.dates) == 3
      assert length(got.values) == 3
    end

    test "returns zero trend and rate when no data exists" do
      project = ProjectsFixtures.project_fixture()

      got =
        Analytics.cache_hit_rate_analytics(
          project.id,
          start_datetime: @start_datetime,
          end_datetime: @end_datetime
        )

      assert got.avg_hit_rate == 0.0
      assert got.trend == 0.0
      assert got.dates == [~D[2024-04-28], ~D[2024-04-29], ~D[2024-04-30]]
      assert got.values == [0.0, 0.0, 0.0]
    end
  end

  describe "cache_hit_rate_percentile/3" do
    test "returns percentile analytics" do
      project = ProjectsFixtures.project_fixture()

      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: @now,
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true},
          %{task_path: ":app:assembleDebug", outcome: "executed", cacheable: true}
        ]
      )

      got =
        Analytics.cache_hit_rate_percentile(
          project.id,
          0.5,
          start_datetime: @start_datetime,
          end_datetime: @end_datetime
        )

      assert is_number(got.total_percentile_hit_rate)
      assert is_number(got.trend)
      assert length(got.dates) == 3
      assert length(got.values) == 3
    end

    test "returns zero when no data exists" do
      project = ProjectsFixtures.project_fixture()

      got =
        Analytics.cache_hit_rate_percentile(
          project.id,
          0.99,
          start_datetime: @start_datetime,
          end_datetime: @end_datetime
        )

      assert got.total_percentile_hit_rate == 0.0
      assert got.trend == 0.0
    end
  end

  describe "cache_event_analytics/2" do
    test "returns upload and download statistics" do
      project = ProjectsFixtures.project_fixture()

      GradleFixtures.cache_event_fixture(
        project_id: project.id,
        action: "upload",
        size: 1_000_000,
        inserted_at: @now
      )

      GradleFixtures.cache_event_fixture(
        project_id: project.id,
        action: "upload",
        size: 2_000_000,
        inserted_at: @now
      )

      GradleFixtures.cache_event_fixture(
        project_id: project.id,
        action: "download",
        size: 500_000,
        inserted_at: @now
      )

      got =
        Analytics.cache_event_analytics(
          project.id,
          start_datetime: @start_datetime,
          end_datetime: @end_datetime
        )

      assert got.uploads.total_size == 3_000_000
      assert got.uploads.count == 2
      assert got.downloads.total_size == 500_000
      assert got.downloads.count == 1
    end

    test "returns zeros when no data exists" do
      project = ProjectsFixtures.project_fixture()

      got =
        Analytics.cache_event_analytics(
          project.id,
          start_datetime: @start_datetime,
          end_datetime: @end_datetime
        )

      assert got.uploads.total_size == 0
      assert got.uploads.count == 0
      assert got.downloads.total_size == 0
      assert got.downloads.count == 0
    end

    test "includes trend calculation" do
      project = ProjectsFixtures.project_fixture()

      GradleFixtures.cache_event_fixture(
        project_id: project.id,
        action: "upload",
        size: 1_000_000,
        inserted_at: @now
      )

      got =
        Analytics.cache_event_analytics(
          project.id,
          start_datetime: @start_datetime,
          end_datetime: @end_datetime
        )

      assert is_number(got.uploads.trend)
      assert is_number(got.downloads.trend)
    end
  end
end
