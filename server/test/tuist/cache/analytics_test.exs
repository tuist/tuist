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
          DateTime.add(DateTime.utc_now(), -2, :day),
          DateTime.utc_now(),
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
          DateTime.add(DateTime.utc_now(), -2, :day),
          DateTime.utc_now(),
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
          DateTime.add(DateTime.utc_now(), -2, :day),
          DateTime.utc_now(),
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
          DateTime.add(DateTime.utc_now(), -2, :day),
          DateTime.utc_now(),
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
          DateTime.add(DateTime.utc_now(), -2, :day),
          DateTime.utc_now(),
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
          ~U[2024-04-29 00:00:00Z],
          ~U[2024-04-30 23:59:59Z],
          :day,
          "1 day",
          []
        )

      assert length(got) == 2

      day1 = Enum.find(got, &(&1.date == ~D[2024-04-29]))
      assert day1.cache_hit_rate == 0.5

      day2 = Enum.find(got, &(&1.date == ~D[2024-04-30]))
      assert day2.cache_hit_rate == 0.5
    end

    test "returns zero when no data exists" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      got =
        Analytics.cache_hit_rates(
          project.id,
          ~U[2024-04-28 00:00:00Z],
          ~U[2024-04-30 00:00:00Z],
          :day,
          "1 day",
          []
        )

      assert got == [
               %{date: ~D[2024-04-28], cache_hit_rate: 0.0},
               %{date: ~D[2024-04-29], cache_hit_rate: 0.0},
               %{date: ~D[2024-04-30], cache_hit_rate: 0.0}
             ]
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
          ~U[2024-03-01 00:00:00Z],
          ~U[2024-04-30 00:00:00Z],
          :month,
          "1 month",
          []
        )

      assert length(got) == 2

      march = Enum.find(got, &(&1.date == ~D[2024-03-01]))
      assert march.cache_hit_rate == 0.5

      april = Enum.find(got, &(&1.date == ~D[2024-04-01]))
      assert april.cache_hit_rate == 1.0
    end

    test "handles 12 month range with missing months in ascending order" do
      stub(DateTime, :utc_now, fn -> ~U[2024-12-15 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # Data only for January, April, and October
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-01-15 03:00:00]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-15 04:00:00Z],
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :hit_remote}
        ]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["C", "D"],
        local_cache_target_hits: [],
        remote_cache_target_hits: ["C"],
        created_at: ~N[2024-10-15 03:00:00]
      )

      got =
        Analytics.cache_hit_rates(
          project.id,
          ~U[2024-01-01 00:00:00Z],
          ~U[2024-12-31 00:00:00Z],
          :month,
          "1 month",
          []
        )

      assert length(got) == 12
      dates = Enum.map(got, & &1.date)

      assert dates == [
               ~D[2024-01-01],
               ~D[2024-02-01],
               ~D[2024-03-01],
               ~D[2024-04-01],
               ~D[2024-05-01],
               ~D[2024-06-01],
               ~D[2024-07-01],
               ~D[2024-08-01],
               ~D[2024-09-01],
               ~D[2024-10-01],
               ~D[2024-11-01],
               ~D[2024-12-01]
             ]

      values = Enum.map(got, & &1.cache_hit_rate)

      assert values == [
               0.5,
               0.0,
               0.0,
               1.0,
               0.0,
               0.0,
               0.0,
               0.0,
               0.0,
               0.5,
               0.0,
               0.0
             ]
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
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 00:00:00Z]
        )

      assert got.cache_hit_rate == 0.5
      assert got.trend == 0.0
      assert length(got.dates) == 3
      assert length(got.values) == 3
      assert got.dates == [~D[2024-04-28], ~D[2024-04-29], ~D[2024-04-30]]
      assert got.values == [0.0, 0.5, 0.0]
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
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 00:00:00Z]
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
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 00:00:00Z]
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
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 00:00:00Z]
        )

      assert got.cache_hit_rate == 0.0
      assert got.trend == 0.0
      assert got.dates == [~D[2024-04-28], ~D[2024-04-29], ~D[2024-04-30]]
      assert got.values == [0.0, 0.0, 0.0]
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
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 00:00:00Z]
        )

      assert got.cache_hit_rate == 0.5
      assert got.trend == 0.0
      assert length(got.dates) == 3
      assert length(got.values) == 3
      assert got.dates == [~D[2024-04-28], ~D[2024-04-29], ~D[2024-04-30]]
      assert got.values == [0.0, 0.5, 0.0]
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
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 00:00:00Z]
        )

      assert_in_delta got.cache_hit_rate, 0.6666, 0.01
      assert got.trend > 0
      assert length(got.values) == 3
      assert got.dates == [~D[2024-04-28], ~D[2024-04-29], ~D[2024-04-30]]
      assert Enum.at(got.values, 0) == 0.0
      assert_in_delta Enum.at(got.values, 1), 0.6666, 0.01
      assert Enum.at(got.values, 2) == 0.0
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
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 00:00:00Z],
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
          start_datetime: ~U[2024-03-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 00:00:00Z]
        )

      assert length(got.dates) == 2
      assert length(got.values) == 2
      assert ~D[2024-03-01] in got.dates
      assert ~D[2024-04-01] in got.dates
    end

    test "handles hourly aggregation for 24-hour date range" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 23:59:59Z] end)
      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["A", "B"],
        local_cache_target_hits: ["A"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-04-30 03:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        cacheable_targets: ["C", "D"],
        local_cache_target_hits: ["C", "D"],
        remote_cache_target_hits: [],
        created_at: ~N[2024-04-30 08:00:00]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-30 03:30:00Z],
        cacheable_tasks: [
          %{key: "task1_key", type: :swift, status: :hit_local},
          %{key: "task2_key", type: :swift, status: :miss}
        ]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~U[2024-04-30 08:30:00Z],
        cacheable_tasks: [
          %{key: "task3_key", type: :swift, status: :hit_remote},
          %{key: "task4_key", type: :clang, status: :hit_local}
        ]
      )

      got =
        Analytics.cache_hit_rate_analytics(
          project_id: project.id,
          start_datetime: ~U[2024-04-30 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # 24 hours in a day
      assert length(got.dates) == 24
      assert length(got.values) == 24

      # Hourly ranges return DateTime structs
      assert ~U[2024-04-30 03:00:00Z] in got.dates
      assert ~U[2024-04-30 08:00:00Z] in got.dates
    end
  end
end
