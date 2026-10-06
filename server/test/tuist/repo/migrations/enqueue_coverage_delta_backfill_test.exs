Code.require_file(
  Path.expand("../../../../priv/repo/migrations/20261006100000_enqueue_coverage_delta_backfill.exs", __DIR__)
)

defmodule Tuist.Repo.Migrations.EnqueueCoverageDeltaBackfillTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Repo.Migrations.EnqueueCoverageDeltaBackfill
  alias Tuist.Tests.Coverage.Workers.DeltaBackfillWorker
  alias Tuist.Tests.CoverageCommit
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  defp commit(project, sha, complete) do
    now = DateTime.utc_now()

    Repo.insert_all(CoverageCommit, [
      %{
        project_id: project.id,
        git_commit_sha: sha,
        committed_at: now,
        ran_at: now,
        complete: complete,
        inserted_at: DateTime.truncate(now, :second),
        updated_at: DateTime.truncate(now, :second)
      }
    ])
  end

  test "queues one backfill per project with complete commits, on the deltas' queue" do
    complete = ProjectsFixtures.project_fixture()
    in_progress = ProjectsFixtures.project_fixture()
    commit(complete, "a", true)
    commit(complete, "b", true)
    commit(in_progress, "c", false)

    EnqueueCoverageDeltaBackfill.enqueue_backfills!(Repo)

    assert [%{args: %{"project_id" => project_id}, queue: "coverage_deltas", max_attempts: 20}] =
             all_enqueued(worker: DeltaBackfillWorker)

    assert project_id == complete.id
  end
end
