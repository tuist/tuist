defmodule Tuist.Shards.Workers.PruneShardPlanRoutesWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Repo
  alias Tuist.Shards.ShardPlanRoute
  alias Tuist.Shards.Workers.PruneShardPlanRoutesWorker
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "deletes routes older than a day and keeps newer ones" do
    project = ProjectsFixtures.project_fixture()
    now = DateTime.utc_now()
    old = insert_route(project, DateTime.add(now, -25, :hour))
    recent = insert_route(project, DateTime.add(now, -23, :hour))

    assert :ok = PruneShardPlanRoutesWorker.perform(%Oban.Job{})

    assert Repo.get(ShardPlanRoute, old.plan_id) == nil
    assert Repo.get(ShardPlanRoute, recent.plan_id)
  end

  defp insert_route(project, inserted_at) do
    Repo.insert!(%ShardPlanRoute{
      plan_id: Ecto.UUID.generate(),
      project_id: project.id,
      reference: "reference",
      inserted_at: inserted_at
    })
  end
end
