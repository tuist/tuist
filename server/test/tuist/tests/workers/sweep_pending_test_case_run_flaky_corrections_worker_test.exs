defmodule Tuist.Tests.Workers.SweepPendingTestCaseRunFlakyCorrectionsWorkerTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: Tuist.Repo

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Repo
  alias Tuist.Tests.TestCaseRunFlakyCorrection
  alias Tuist.Tests.Workers.CorrectTestCaseRunFlakyStateWorker
  alias Tuist.Tests.Workers.SweepPendingTestCaseRunFlakyCorrectionsWorker
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    Sandbox.checkout(Repo)
  end

  test "creates one homogeneous job per project and commit" do
    first_project = ProjectsFixtures.project_fixture()
    second_project = ProjectsFixtures.project_fixture()
    first_group_ids = [UUIDv7.generate(), UUIDv7.generate()]
    second_group_id = UUIDv7.generate()
    third_group_id = UUIDv7.generate()
    old_timestamp = DateTime.add(DateTime.utc_now(:second), -6 * 60, :second)

    corrections = [
      {first_project.id, "first-commit", first_group_ids},
      {first_project.id, "second-commit", [second_group_id]},
      {second_project.id, "first-commit", [third_group_id]}
    ]

    for {project_id, git_commit_sha, test_case_run_ids} <- corrections,
        test_case_run_id <- test_case_run_ids do
      Repo.insert!(%TestCaseRunFlakyCorrection{
        test_case_run_id: test_case_run_id,
        project_id: project_id,
        test_case_id: UUIDv7.generate(),
        git_commit_sha: git_commit_sha,
        inserted_at: old_timestamp,
        updated_at: old_timestamp
      })
    end

    assert :ok = perform_job(SweepPendingTestCaseRunFlakyCorrectionsWorker, %{})
    assert :ok = perform_job(SweepPendingTestCaseRunFlakyCorrectionsWorker, %{})

    jobs = all_enqueued(worker: CorrectTestCaseRunFlakyStateWorker)

    assert length(jobs) == 3

    enqueued_groups =
      MapSet.new(jobs, fn job -> MapSet.new(job.args["test_case_run_ids"]) end)

    assert enqueued_groups ==
             MapSet.new([
               MapSet.new(first_group_ids),
               MapSet.new([second_group_id]),
               MapSet.new([third_group_id])
             ])
  end
end
