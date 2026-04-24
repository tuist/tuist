defmodule Tuist.Shards.AnalyticsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.IngestRepo
  alias Tuist.Shards.Analytics
  alias Tuist.Shards.ShardRun
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.ShardsFixtures

  describe "shard_metrics/1" do
    test "returns shard run records for a given test_run_id" do
      project = ProjectsFixtures.project_fixture()
      plan = ShardsFixtures.shard_plan_fixture(project_id: project.id)
      test_run_id = Ecto.UUID.generate()

      now = NaiveDateTime.utc_now()

      IngestRepo.insert_all(ShardRun, [
        %{
          shard_plan_id: plan.id,
          project_id: project.id,
          test_run_id: test_run_id,
          shard_index: 0,
          status: "success",
          duration: 5000,
          ran_at: now,
          inserted_at: now
        },
        %{
          shard_plan_id: plan.id,
          project_id: project.id,
          test_run_id: test_run_id,
          shard_index: 1,
          status: "success",
          duration: 3000,
          ran_at: now,
          inserted_at: now
        }
      ])

      results = Analytics.shard_metrics(test_run_id)

      assert length(results) == 2

      shard_indices = results |> Enum.map(& &1.shard_index) |> Enum.sort()
      assert shard_indices == [0, 1]

      durations = results |> Enum.map(& &1.actual_duration_ms) |> Enum.sort()
      assert durations == [3000, 5000]

      assert Enum.all?(results, fn r -> r.status == "success" end)
    end

    test "returns empty list for nil test_run_id" do
      assert Analytics.shard_metrics(nil) == []
    end

    test "returns empty list for non-existent test_run_id" do
      assert Analytics.shard_metrics(Ecto.UUID.generate()) == []
    end
  end

  describe "sharded_run_analytics/2" do
    test "returns analytics structure with shard plans present" do
      stub(DateTime, :utc_now, fn -> ~U[2024-06-15 12:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      plan1 =
        ShardsFixtures.shard_plan_fixture(
          project_id: project.id,
          reference: "run-1",
          inserted_at: ~N[2024-06-14 10:00:00]
        )

      plan2 =
        ShardsFixtures.shard_plan_fixture(
          project_id: project.id,
          reference: "run-2",
          inserted_at: ~N[2024-06-15 08:00:00]
        )

      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          shard_plan_id: plan1.id,
          shard_index: 0,
          status: "success",
          ran_at: ~N[2024-06-14 10:00:00.000000]
        )

      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          shard_plan_id: plan2.id,
          shard_index: 0,
          status: "success",
          ran_at: ~N[2024-06-15 08:00:00.000000]
        )

      result =
        Analytics.sharded_run_analytics(project.id,
          start_datetime: ~U[2024-06-13 00:00:00Z],
          end_datetime: ~U[2024-06-15 23:59:59Z]
        )

      assert is_list(result.dates)
      assert is_list(result.values)
      assert is_number(result.trend)
      assert is_integer(result.count)
      assert result.count == 2
    end

    test "returns zeros when no data exists" do
      stub(DateTime, :utc_now, fn -> ~U[2024-06-15 12:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      result =
        Analytics.sharded_run_analytics(project.id,
          start_datetime: ~U[2024-06-13 00:00:00Z],
          end_datetime: ~U[2024-06-15 23:59:59Z]
        )

      assert result.count == 0
      assert result.trend == 0.0
      assert Enum.all?(result.values, &(&1 == 0))
    end
  end

  describe "shard_count_analytics/2" do
    test "returns percentile and trend data with shard plans" do
      stub(DateTime, :utc_now, fn -> ~U[2024-06-15 12:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      ShardsFixtures.shard_plan_fixture(
        project_id: project.id,
        shard_count: 3,
        inserted_at: ~N[2024-06-14 10:00:00]
      )

      ShardsFixtures.shard_plan_fixture(
        project_id: project.id,
        shard_count: 5,
        inserted_at: ~N[2024-06-15 08:00:00]
      )

      ShardsFixtures.shard_plan_fixture(
        project_id: project.id,
        shard_count: 4,
        inserted_at: ~N[2024-06-15 09:00:00]
      )

      result =
        Analytics.shard_count_analytics(project.id,
          start_datetime: ~U[2024-06-13 00:00:00Z],
          end_datetime: ~U[2024-06-15 23:59:59Z]
        )

      assert is_list(result.dates)
      assert is_list(result.values)
      assert is_list(result.p50_values)
      assert is_list(result.p90_values)
      assert is_list(result.p99_values)
      assert is_number(result.p50)
      assert is_number(result.p90)
      assert is_number(result.p99)
      assert is_number(result.trend)
      assert is_number(result.total_average)
      assert result.p50 > 0
      assert result.p90 > 0
      assert result.p99 > 0
    end

    test "returns zeros when no data exists" do
      stub(DateTime, :utc_now, fn -> ~U[2024-06-15 12:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      result =
        Analytics.shard_count_analytics(project.id,
          start_datetime: ~U[2024-06-13 00:00:00Z],
          end_datetime: ~U[2024-06-15 23:59:59Z]
        )

      assert result.p50 == 0
      assert result.p90 == 0
      assert result.p99 == 0
      assert result.total_average == 0
      assert result.trend == 0.0
    end
  end

  describe "shard_balance_analytics/2" do
    test "returns balance analytics from shard runs linked to shard plans" do
      stub(DateTime, :utc_now, fn -> ~U[2024-06-15 12:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      plan =
        ShardsFixtures.shard_plan_fixture(
          project_id: project.id,
          shard_count: 2,
          inserted_at: ~N[2024-06-14 10:00:00]
        )

      {:ok, _test_run_1} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          shard_plan_id: plan.id,
          shard_index: 0,
          ran_at: ~N[2024-06-14 10:05:00.000000],
          duration: 5000,
          test_modules: [
            %{name: "ModA", status: "success", duration: 5000, test_cases: []}
          ]
        )

      {:ok, _test_run_2} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          shard_plan_id: plan.id,
          shard_index: 1,
          ran_at: ~N[2024-06-14 10:05:00.000000],
          duration: 4800,
          test_modules: [
            %{name: "ModB", status: "success", duration: 4800, test_cases: []}
          ]
        )

      RunsFixtures.optimize_shard_runs()

      result =
        Analytics.shard_balance_analytics(project.id,
          start_datetime: ~U[2024-06-13 00:00:00Z],
          end_datetime: ~U[2024-06-15 23:59:59Z]
        )

      assert is_list(result.dates)
      assert is_list(result.values)
      assert is_list(result.p50_values)
      assert is_list(result.p90_values)
      assert is_list(result.p99_values)
      assert is_number(result.p50)
      assert is_number(result.p90)
      assert is_number(result.p99)
      assert is_number(result.trend)
      assert is_number(result.total_average)
      assert result.total_average > 0
    end

    test "returns zeros when no data exists" do
      stub(DateTime, :utc_now, fn -> ~U[2024-06-15 12:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      result =
        Analytics.shard_balance_analytics(project.id,
          start_datetime: ~U[2024-06-13 00:00:00Z],
          end_datetime: ~U[2024-06-15 23:59:59Z]
        )

      assert result.total_average == 0
      assert result.p50 == 0
      assert result.p90 == 0
      assert result.p99 == 0
      assert result.trend == 0.0
      assert Enum.all?(result.values, &(&1 == 0))
    end
  end
end
