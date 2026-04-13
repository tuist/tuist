defmodule Tuist.Gradle.AnalyticsTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Gradle.Analytics
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @now ~N[2026-01-15 10:20:30]
  @start_datetime ~U[2026-01-13 00:00:00Z]
  @end_datetime ~U[2026-01-15 23:59:59Z]

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
      assert got.dates == [~D[2026-01-13], ~D[2026-01-14], ~D[2026-01-15]]
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

  describe "cache_hit_rate_scatter_data/2" do
    test "returns individual build cache hit rates grouped by environment" do
      project = ProjectsFixtures.project_fixture()

      ci_build_id =
        GradleFixtures.build_fixture(
          project_id: project.id,
          inserted_at: @now,
          is_ci: true,
          root_project_name: "my-app",
          tasks: [
            %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true},
            %{task_path: ":app:assembleDebug", outcome: "executed", cacheable: true}
          ]
        )

      local_build_id =
        GradleFixtures.build_fixture(
          project_id: project.id,
          inserted_at: @now,
          is_ci: false,
          root_project_name: "my-app",
          tasks: [
            %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true},
            %{task_path: ":app:compileJava", outcome: "remote_hit", cacheable: true},
            %{task_path: ":app:assembleDebug", outcome: "local_hit", cacheable: true},
            %{task_path: ":app:test", outcome: "executed", cacheable: true}
          ]
        )

      got =
        Analytics.cache_hit_rate_scatter_data(
          project.id,
          start_datetime: @start_datetime,
          end_datetime: @end_datetime
        )

      assert got.truncated == false
      assert got.oldest_entry == nil
      assert length(got.series) == 2

      ci_series = Enum.find(got.series, &(&1.name == true))
      local_series = Enum.find(got.series, &(&1.name == false))

      assert ci_series
      assert local_series

      [ci_point] = ci_series.data
      assert [_ts, hit_rate] = ci_point.value
      assert Decimal.equal?(hit_rate, Decimal.new("50.0"))
      assert ci_point.id == ci_build_id

      assert ci_point.meta.root_project_name == "my-app"
      assert ci_point.meta.is_ci == true

      [local_point] = local_series.data
      assert [_ts, local_hit_rate] = local_point.value
      assert Decimal.equal?(local_hit_rate, Decimal.new("75.0"))
      assert local_point.id == local_build_id
    end

    test "groups by project name when group_by is :project" do
      project = ProjectsFixtures.project_fixture()

      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: @now,
        root_project_name: "app-one",
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true}
        ]
      )

      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: @now,
        root_project_name: "app-two",
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "executed", cacheable: true}
        ]
      )

      got =
        Analytics.cache_hit_rate_scatter_data(
          project.id,
          start_datetime: @start_datetime,
          end_datetime: @end_datetime,
          group_by: :project
        )

      assert length(got.series) == 2

      app_one_series = Enum.find(got.series, &(&1.name == "app-one"))
      app_two_series = Enum.find(got.series, &(&1.name == "app-two"))

      assert app_one_series
      assert app_two_series
    end

    test "returns empty series when no builds exist" do
      project = ProjectsFixtures.project_fixture()

      got =
        Analytics.cache_hit_rate_scatter_data(
          project.id,
          start_datetime: @start_datetime,
          end_datetime: @end_datetime
        )

      assert got.series == []
      assert got.truncated == false
      assert got.oldest_entry == nil
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
