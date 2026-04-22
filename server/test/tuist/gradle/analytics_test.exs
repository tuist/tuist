defmodule Tuist.Gradle.AnalyticsTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Gradle.Analytics
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  # ClickHouse gradle tables have a 90-day TTL on inserted_at, so hard-coded
  # timestamps would silently expire over time. Anchor fixtures to the current
  # date so the tests stay within the retention window.
  setup do
    today = Date.utc_today()
    end_date = today
    start_date = Date.add(today, -2)

    end_datetime = DateTime.new!(end_date, ~T[23:59:59.000000], "Etc/UTC")
    start_datetime = DateTime.new!(start_date, ~T[00:00:00.000000], "Etc/UTC")
    now = NaiveDateTime.new!(today, ~T[10:20:30])

    {:ok,
     now: now,
     start_datetime: start_datetime,
     end_datetime: end_datetime,
     expected_dates: [start_date, Date.add(today, -1), end_date]}
  end

  describe "cache_hit_rate/4" do
    test "calculates cache hit rate from build data", %{
      now: now,
      start_datetime: start_datetime,
      end_datetime: end_datetime
    } do
      project = ProjectsFixtures.project_fixture()

      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: now,
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true},
          %{task_path: ":app:compileJava", outcome: "local_hit", cacheable: true},
          %{task_path: ":app:assembleDebug", outcome: "executed", cacheable: true},
          %{task_path: ":app:test", outcome: "executed", cacheable: true}
        ]
      )

      got = Analytics.cache_hit_rate(project.id, start_datetime, end_datetime)

      assert got == 50.0
    end

    test "returns zero when no data exists", %{start_datetime: start_datetime, end_datetime: end_datetime} do
      project = ProjectsFixtures.project_fixture()

      got = Analytics.cache_hit_rate(project.id, start_datetime, end_datetime)

      assert got == 0.0
    end

    test "only considers cacheable tasks", %{
      now: now,
      start_datetime: start_datetime,
      end_datetime: end_datetime
    } do
      project = ProjectsFixtures.project_fixture()

      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: now,
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true},
          %{task_path: ":app:clean", outcome: "executed", cacheable: false},
          %{task_path: ":app:assembleDebug", outcome: "executed", cacheable: true}
        ]
      )

      got = Analytics.cache_hit_rate(project.id, start_datetime, end_datetime)

      assert got == 50.0
    end

    test "aggregates across multiple builds", %{
      now: now,
      start_datetime: start_datetime,
      end_datetime: end_datetime
    } do
      project = ProjectsFixtures.project_fixture()

      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: now,
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true}
        ]
      )

      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: now,
        tasks: [
          %{task_path: ":app:compileJava", outcome: "executed", cacheable: true}
        ]
      )

      got = Analytics.cache_hit_rate(project.id, start_datetime, end_datetime)

      assert got == 50.0
    end
  end

  describe "cache_hit_rate_analytics/2" do
    test "returns analytics with trend and time-series data", %{
      now: now,
      start_datetime: start_datetime,
      end_datetime: end_datetime
    } do
      project = ProjectsFixtures.project_fixture()

      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: now,
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true},
          %{task_path: ":app:assembleDebug", outcome: "executed", cacheable: true}
        ]
      )

      got =
        Analytics.cache_hit_rate_analytics(
          project.id,
          start_datetime: start_datetime,
          end_datetime: end_datetime
        )

      assert got.avg_hit_rate == 50.0
      assert is_number(got.trend)
      assert length(got.dates) == 3
      assert length(got.values) == 3
    end

    test "returns zero trend and rate when no data exists", %{
      start_datetime: start_datetime,
      end_datetime: end_datetime,
      expected_dates: expected_dates
    } do
      project = ProjectsFixtures.project_fixture()

      got =
        Analytics.cache_hit_rate_analytics(
          project.id,
          start_datetime: start_datetime,
          end_datetime: end_datetime
        )

      assert got.avg_hit_rate == 0.0
      assert got.trend == 0.0
      assert got.dates == expected_dates
      assert got.values == [0.0, 0.0, 0.0]
    end
  end

  describe "cache_hit_rate_percentile/3" do
    test "returns percentile analytics", %{
      now: now,
      start_datetime: start_datetime,
      end_datetime: end_datetime
    } do
      project = ProjectsFixtures.project_fixture()

      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: now,
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true},
          %{task_path: ":app:assembleDebug", outcome: "executed", cacheable: true}
        ]
      )

      got =
        Analytics.cache_hit_rate_percentile(
          project.id,
          0.5,
          start_datetime: start_datetime,
          end_datetime: end_datetime
        )

      assert is_number(got.total_percentile_hit_rate)
      assert is_number(got.trend)
      assert length(got.dates) == 3
      assert length(got.values) == 3
    end

    test "returns zero when no data exists", %{
      start_datetime: start_datetime,
      end_datetime: end_datetime
    } do
      project = ProjectsFixtures.project_fixture()

      got =
        Analytics.cache_hit_rate_percentile(
          project.id,
          0.99,
          start_datetime: start_datetime,
          end_datetime: end_datetime
        )

      assert got.total_percentile_hit_rate == 0.0
      assert got.trend == 0.0
    end
  end

  describe "cache_hit_rate_scatter_data/2" do
    test "returns individual build cache hit rates grouped by environment", %{
      now: now,
      start_datetime: start_datetime,
      end_datetime: end_datetime
    } do
      project = ProjectsFixtures.project_fixture()

      ci_build_id =
        GradleFixtures.build_fixture(
          project_id: project.id,
          inserted_at: now,
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
          inserted_at: now,
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
          start_datetime: start_datetime,
          end_datetime: end_datetime
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

    test "groups by project name when group_by is :project", %{
      now: now,
      start_datetime: start_datetime,
      end_datetime: end_datetime
    } do
      project = ProjectsFixtures.project_fixture()

      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: now,
        root_project_name: "app-one",
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true}
        ]
      )

      GradleFixtures.build_fixture(
        project_id: project.id,
        inserted_at: now,
        root_project_name: "app-two",
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "executed", cacheable: true}
        ]
      )

      got =
        Analytics.cache_hit_rate_scatter_data(
          project.id,
          start_datetime: start_datetime,
          end_datetime: end_datetime,
          group_by: :project
        )

      assert length(got.series) == 2

      app_one_series = Enum.find(got.series, &(&1.name == "app-one"))
      app_two_series = Enum.find(got.series, &(&1.name == "app-two"))

      assert app_one_series
      assert app_two_series
    end

    test "returns empty series when no builds exist", %{
      start_datetime: start_datetime,
      end_datetime: end_datetime
    } do
      project = ProjectsFixtures.project_fixture()

      got =
        Analytics.cache_hit_rate_scatter_data(
          project.id,
          start_datetime: start_datetime,
          end_datetime: end_datetime
        )

      assert got.series == []
      assert got.truncated == false
      assert got.oldest_entry == nil
    end
  end

  describe "build_duration_analytics_by_category/3" do
    test "filters by is_ci", %{start_datetime: start_datetime} do
      project = ProjectsFixtures.project_fixture()
      inserted_at = NaiveDateTime.new!(Date.add(Date.utc_today(), -1), ~T[10:00:00])

      GradleFixtures.build_fixture(
        project_id: project.id,
        duration_ms: 2000,
        gradle_version: "8.5",
        is_ci: true,
        inserted_at: inserted_at
      )

      GradleFixtures.build_fixture(
        project_id: project.id,
        duration_ms: 1000,
        gradle_version: "8.5",
        is_ci: false,
        inserted_at: inserted_at
      )

      GradleFixtures.build_fixture(
        project_id: project.id,
        duration_ms: 3000,
        gradle_version: "8.4",
        is_ci: false,
        inserted_at: inserted_at
      )

      got =
        Analytics.build_duration_analytics_by_category(
          project.id,
          :gradle_version,
          start_datetime: start_datetime,
          is_ci: false
        )

      assert Enum.sort_by(got, & &1.category) ==
               Enum.sort_by([%{value: 1000.0, category: "8.5"}, %{value: 3000.0, category: "8.4"}], & &1.category)
    end
  end

  describe "cache_event_analytics/2" do
    test "returns upload and download statistics", %{
      now: now,
      start_datetime: start_datetime,
      end_datetime: end_datetime
    } do
      project = ProjectsFixtures.project_fixture()

      GradleFixtures.cache_event_fixture(
        project_id: project.id,
        action: "upload",
        size: 1_000_000,
        inserted_at: now
      )

      GradleFixtures.cache_event_fixture(
        project_id: project.id,
        action: "upload",
        size: 2_000_000,
        inserted_at: now
      )

      GradleFixtures.cache_event_fixture(
        project_id: project.id,
        action: "download",
        size: 500_000,
        inserted_at: now
      )

      got =
        Analytics.cache_event_analytics(
          project.id,
          start_datetime: start_datetime,
          end_datetime: end_datetime
        )

      assert got.uploads.total_size == 3_000_000
      assert got.uploads.count == 2
      assert got.downloads.total_size == 500_000
      assert got.downloads.count == 1
    end

    test "returns zeros when no data exists", %{
      start_datetime: start_datetime,
      end_datetime: end_datetime
    } do
      project = ProjectsFixtures.project_fixture()

      got =
        Analytics.cache_event_analytics(
          project.id,
          start_datetime: start_datetime,
          end_datetime: end_datetime
        )

      assert got.uploads.total_size == 0
      assert got.uploads.count == 0
      assert got.downloads.total_size == 0
      assert got.downloads.count == 0
    end

    test "includes trend calculation", %{
      now: now,
      start_datetime: start_datetime,
      end_datetime: end_datetime
    } do
      project = ProjectsFixtures.project_fixture()

      GradleFixtures.cache_event_fixture(
        project_id: project.id,
        action: "upload",
        size: 1_000_000,
        inserted_at: now
      )

      got =
        Analytics.cache_event_analytics(
          project.id,
          start_datetime: start_datetime,
          end_datetime: end_datetime
        )

      assert is_number(got.uploads.trend)
      assert is_number(got.downloads.trend)
    end
  end
end
