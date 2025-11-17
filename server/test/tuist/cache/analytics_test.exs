defmodule Tuist.Cache.AnalyticsTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Cache.Analytics
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "cache_hit_rate/4" do
    test "averages Module cache and Xcode cache hit rates" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: ["C"],
        created_at: ~N[2024-04-30 03:00:00]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-30 04:00:00Z],
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :hit_local},
          %{key: "task2_key", type: :swift, status: :hit_remote},
          %{key: "task3_key", type: :swift, status: :miss},
          %{key: "task4_key", type: :clang, status: :miss}
        ]
      )

      got =
        Analytics.cache_hit_rate(
          project.id,
          Date.add(DateTime.utc_now(), -2),
          DateTime.to_date(DateTime.utc_now()),
          []
        )

      assert got == 0.5
    end

    test "returns zero when no data exists" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      got =
        Analytics.cache_hit_rate(
          project.id,
          Date.add(DateTime.utc_now(), -2),
          DateTime.to_date(DateTime.utc_now()),
          []
        )

      assert got == 0.0
    end

    test "returns only module hit rate when no Xcode builds exist" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A", "B"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-04-30 03:00:00]
      )

      got =
        Analytics.cache_hit_rate(
          project.id,
          Date.add(DateTime.utc_now(), -2),
          DateTime.to_date(DateTime.utc_now()),
          []
        )

      assert got == 0.5
    end

    test "returns only Xcode hit rate when no module cache events exist" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-30 04:00:00Z],
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :hit_local},
          %{key: "task2_key", type: :swift, status: :hit_remote},
          %{key: "task3_key", type: :swift, status: :miss}
        ]
      )

      got =
        Analytics.cache_hit_rate(
          project.id,
          Date.add(DateTime.utc_now(), -2),
          DateTime.to_date(DateTime.utc_now()),
          []
        )

      assert_in_delta got, 0.6666, 0.01
    end

    test "filters by is_ci when specified" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-04-30 03:00:00],
        is_ci: true
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["C", "D"],
        local_cache_target_hits: ["C", "D"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-04-30 03:00:00],
        is_ci: false
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-30 04:00:00Z],
        is_ci: true,
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :hit_local},
          %{key: "task2_key", type: :swift, status: :miss}
        ]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-30 04:00:00Z],
        is_ci: false,
        cacheable_tasks: [
          %{key: "task3_key", type: :swift, status: :hit_local},
          %{key: "task4_key", type: :clang, status: :hit_remote}
        ]
      )

      got =
        Analytics.cache_hit_rate(
          project.id,
          Date.add(DateTime.utc_now(), -2),
          DateTime.to_date(DateTime.utc_now()),
          is_ci: true
        )

      assert got == 0.5
    end
  end

  describe "cache_hit_rates/5" do
    test "averages Module cache and Xcode cache hit rates over time" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-04-29 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["C", "D"],
        local_cache_target_hits: [],
        remote_cache_target_hits: ["D"],
        created_at: ~N[2024-04-30 03:00:00]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-29 04:00:00Z],
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :hit_local},
          %{key: "task2_key", type: :swift, status: :miss}
        ]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-30 04:00:00Z],
        cacheable_tasks: [
          %{key: "task3_key", type: :swift, status: :hit_remote},
          %{key: "task4_key", type: :clang, status: :miss}
        ]
      )

      got =
        Analytics.cache_hit_rates(
          project.id,
          ~D[2024-04-29],
          ~D[2024-04-30],
          :day,
          "1 day",
          []
        )

      assert length(got) == 2

      day1 = Enum.find(got, &(&1.date == "2024-04-29"))
      assert day1.cache_hit_rate == 0.5

      day2 = Enum.find(got, &(&1.date == "2024-04-30"))
      assert day2.cache_hit_rate == 0.5
    end

    test "returns zero when no data exists" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      got =
        Analytics.cache_hit_rates(
          project.id,
          ~D[2024-04-28],
          ~D[2024-04-30],
          :day,
          "1 day",
          []
        )

      assert got == []
    end

    test "handles monthly aggregation" do
      stub(DateTime, :utc_now, fn -> ~U[2024-05-15 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-03-15 03:00:00]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-15 04:00:00Z],
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :hit_remote}
        ]
      )

      got =
        Analytics.cache_hit_rates(
          project.id,
          ~D[2024-03-01],
          ~D[2024-04-30],
          :month,
          "1 month",
          []
        )

      assert length(got) == 2

      march = Enum.find(got, &(&1.date == "2024-03"))
      assert march.cache_hit_rate == 0.5

      april = Enum.find(got, &(&1.date == "2024-04"))
      assert april.cache_hit_rate == 1.0
    end
  end

  describe "cache_hit_rate_analytics/1" do
    test "returns analytics with trend, current hit rate, and time-series data" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-04-29 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-04-27 03:00:00]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-29 04:00:00Z],
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :hit_local},
          %{key: "task2_key", type: :swift, status: :miss}
        ]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-27 04:00:00Z],
        cacheable_tasks: [
          %{key: "task3_key", type: :swift, status: :hit_local},
          %{key: "task4_key", type: :swift, status: :miss}
        ]
      )

      got =
        Analytics.cache_hit_rate_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-28],
          end_date: ~D[2024-04-30]
        )

      assert got.cache_hit_rate == 0.5
      assert got.trend == 0.0
      assert length(got.dates) == 1
      assert length(got.values) == 1
      assert List.first(got.dates) == "2024-04-29"
      assert List.first(got.values) == 0.5
    end

    test "calculates positive trend when cache hit rate improves" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A", "B"],
        remote_cache_target_hits: ["C"],
        created_at: ~N[2024-04-29 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-04-27 03:00:00]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-29 04:00:00Z],
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :hit_local},
          %{key: "task2_key", type: :swift, status: :miss}
        ]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-27 04:00:00Z],
        cacheable_tasks: [
          %{key: "task3_key", type: :swift, status: :miss},
          %{key: "task4_key", type: :swift, status: :miss}
        ]
      )

      got =
        Analytics.cache_hit_rate_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-28],
          end_date: ~D[2024-04-30]
        )

      assert got.cache_hit_rate == 0.625
      assert got.trend > 0
    end

    test "calculates negative trend when cache hit rate declines" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-04-29 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A", "B"],
        remote_cache_target_hits: ["C"],
        created_at: ~N[2024-04-27 03:00:00]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-29 04:00:00Z],
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :miss},
          %{key: "task2_key", type: :swift, status: :miss}
        ]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-27 04:00:00Z],
        cacheable_tasks: [
          %{key: "task3_key", type: :swift, status: :hit_local},
          %{key: "task4_key", type: :swift, status: :miss}
        ]
      )

      got =
        Analytics.cache_hit_rate_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-28],
          end_date: ~D[2024-04-30]
        )

      assert got.cache_hit_rate == 0.25
      assert got.trend < 0
    end

    test "returns zero trend and rate when no data exists" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      got =
        Analytics.cache_hit_rate_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-28],
          end_date: ~D[2024-04-30]
        )

      assert got.cache_hit_rate == 0.0
      assert got.trend == 0.0
      assert got.dates == []
      assert got.values == []
    end

    test "works with only module cache data" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B", "C", "D"],
        local_cache_target_hits: ["A", "B"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-04-29 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-04-27 03:00:00]
      )

      got =
        Analytics.cache_hit_rate_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-28],
          end_date: ~D[2024-04-30]
        )

      assert got.cache_hit_rate == 0.5
      assert got.trend == 0.0
      assert length(got.dates) == 1
      assert length(got.values) == 1
    end

    test "works with only Xcode cache data" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-29 04:00:00Z],
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :hit_local},
          %{key: "task2_key", type: :swift, status: :hit_remote},
          %{key: "task3_key", type: :swift, status: :miss}
        ]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-27 04:00:00Z],
        cacheable_tasks: [
          %{key: "task4_key", type: :swift, status: :hit_local},
          %{key: "task5_key", type: :swift, status: :miss},
          %{key: "task6_key", type: :swift, status: :miss}
        ]
      )

      got =
        Analytics.cache_hit_rate_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-28],
          end_date: ~D[2024-04-30]
        )

      assert_in_delta got.cache_hit_rate, 0.6666, 0.01
      assert got.trend > 0
      assert length(got.dates) == 1
      assert length(got.values) == 1
    end

    test "filters by is_ci when specified" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-04-29 03:00:00],
        is_ci: true
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["C", "D"],
        local_cache_target_hits: ["C", "D"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-04-29 03:00:00],
        is_ci: false
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-29 04:00:00Z],
        is_ci: true,
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :hit_local},
          %{key: "task2_key", type: :swift, status: :miss}
        ]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-29 04:00:00Z],
        is_ci: false,
        cacheable_tasks: [
          %{key: "task3_key", type: :swift, status: :hit_local},
          %{key: "task4_key", type: :clang, status: :hit_remote}
        ]
      )

      got =
        Analytics.cache_hit_rate_analytics(
          project_id: project.id,
          start_date: ~D[2024-04-28],
          end_date: ~D[2024-04-30],
          is_ci: true
        )

      assert got.cache_hit_rate == 0.5
    end

    test "handles monthly aggregation for longer date ranges" do
      stub(DateTime, :utc_now, fn -> ~U[2024-05-15 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-03-15 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["C", "D"],
        local_cache_target_hits: [],
        remote_cache_target_hits: ["D"],
        created_at: ~N[2024-04-15 03:00:00]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-03-15 04:00:00Z],
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :hit_local},
          %{key: "task2_key", type: :swift, status: :miss}
        ]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-15 04:00:00Z],
        cacheable_tasks: [
          %{key: "task3_key", type: :swift, status: :hit_remote},
          %{key: "task4_key", type: :clang, status: :miss}
        ]
      )

      got =
        Analytics.cache_hit_rate_analytics(
          project_id: project.id,
          start_date: ~D[2024-03-01],
          end_date: ~D[2024-04-30]
        )

      assert length(got.dates) == 2
      assert length(got.values) == 2
      assert "2024-03" in got.dates
      assert "2024-04" in got.dates
    end
  end
end
