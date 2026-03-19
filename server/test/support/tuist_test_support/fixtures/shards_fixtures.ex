defmodule TuistTestSupport.Fixtures.ShardsFixtures do
  @moduledoc """
  Fixtures for shard plans and shard plan targets.
  """
  alias Ecto.Adapters.SQL
  alias Tuist.IngestRepo
  alias Tuist.Shards.ShardPlan
  alias Tuist.Shards.ShardPlanModule
  alias Tuist.Shards.ShardPlanTestSuite
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  def optimize_shard_plans do
    SQL.query!(IngestRepo, "OPTIMIZE TABLE shard_plans FINAL", [])
  end

  def optimize_shard_plan_modules do
    SQL.query!(IngestRepo, "OPTIMIZE TABLE shard_plan_modules FINAL", [])
  end

  def optimize_shard_plan_test_suites do
    SQL.query!(IngestRepo, "OPTIMIZE TABLE shard_plan_test_suites FINAL", [])
  end

  def shard_plan_fixture(attrs \\ []) do
    project_id =
      Keyword.get_lazy(attrs, :project_id, fn ->
        ProjectsFixtures.project_fixture().id
      end)

    now = NaiveDateTime.utc_now()

    plan_attrs = %{
      id: Keyword.get(attrs, :id, Ecto.UUID.generate()),
      reference: Keyword.get(attrs, :reference, "plan-#{System.unique_integer([:positive])}"),
      project_id: project_id,
      shard_count: Keyword.get(attrs, :shard_count, 2),
      granularity: Keyword.get(attrs, :granularity, "module"),
      modules_count: Keyword.get(attrs, :modules_count, 0),
      suites_count: Keyword.get(attrs, :suites_count, 0),
      inserted_at: Keyword.get(attrs, :inserted_at, now)
    }

    {:ok, plan} =
      %ShardPlan{}
      |> ShardPlan.create_changeset(plan_attrs)
      |> IngestRepo.insert()

    plan
  end

  def shard_plan_module_fixture(attrs \\ []) do
    now = NaiveDateTime.utc_now()

    row = %{
      reference: Keyword.fetch!(attrs, :plan_id),
      project_id: Keyword.fetch!(attrs, :project_id),
      shard_index: Keyword.get(attrs, :shard_index, 0),
      module_name: Keyword.fetch!(attrs, :module_name),
      estimated_duration_ms: Keyword.get(attrs, :estimated_duration_ms, 1000),
      inserted_at: Keyword.get(attrs, :inserted_at, now)
    }

    IngestRepo.insert_all(ShardPlanModule, [row])
    row
  end

  def shard_plan_test_suite_fixture(attrs \\ []) do
    now = NaiveDateTime.utc_now()

    row = %{
      reference: Keyword.fetch!(attrs, :plan_id),
      project_id: Keyword.fetch!(attrs, :project_id),
      shard_index: Keyword.get(attrs, :shard_index, 0),
      module_name: Keyword.fetch!(attrs, :module_name),
      test_suite_name: Keyword.fetch!(attrs, :test_suite_name),
      estimated_duration_ms: Keyword.get(attrs, :estimated_duration_ms, 1000),
      inserted_at: Keyword.get(attrs, :inserted_at, now)
    }

    IngestRepo.insert_all(ShardPlanTestSuite, [row])
    row
  end
end
