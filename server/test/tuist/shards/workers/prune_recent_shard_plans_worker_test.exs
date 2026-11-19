defmodule Tuist.Shards.Workers.PruneRecentShardPlansWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Repo
  alias Tuist.Shards.RecentShardPlan
  alias Tuist.Shards.Workers.PruneRecentShardPlansWorker
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "deletes recent plans older than a day and keeps newer ones" do
    project = ProjectsFixtures.project_fixture()
    now = DateTime.utc_now()
    old = insert_recent_plan(project, DateTime.add(now, -25, :hour))
    recent = insert_recent_plan(project, DateTime.add(now, -23, :hour))

    assert :ok = PruneRecentShardPlansWorker.perform(%Oban.Job{})

    assert Repo.get(RecentShardPlan, old.plan_id) == nil
    assert Repo.get(RecentShardPlan, recent.plan_id)
  end

  defp insert_recent_plan(project, inserted_at) do
    Repo.insert!(%RecentShardPlan{
      plan_id: Ecto.UUID.generate(),
      project_id: project.id,
      reference: "reference",
      inserted_at: inserted_at
    })
  end
end
