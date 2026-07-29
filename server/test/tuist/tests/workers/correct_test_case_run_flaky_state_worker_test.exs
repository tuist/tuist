defmodule Tuist.Tests.Workers.CorrectTestCaseRunFlakyStateWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Repo
  alias Tuist.Tests.TestCaseRun
  alias Tuist.Tests.TestCaseRunFlakyCorrection
  alias Tuist.Tests.Workers.CorrectTestCaseRunFlakyStateWorker
  alias Tuist.Tests.Workers.SweepPendingTestCaseRunFlakyCorrectionsWorker
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  test "adds at most one correction tuple when the job is retried" do
    project = ProjectsFixtures.project_fixture()
    test_case_id = UUIDv7.generate()
    git_commit_sha = "flaky-correction-#{System.unique_integer([:positive])}"

    run =
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        git_commit_sha: git_commit_sha,
        status: "failure",
        is_flaky: false
      )

    insert_correction(run)

    args = %{batch_id: "one-run", test_case_run_ids: [run.id]}

    assert :ok = perform_job(CorrectTestCaseRunFlakyStateWorker, args)
    assert :ok = perform_job(CorrectTestCaseRunFlakyStateWorker, args)

    assert physical_tuple_count(project.id, test_case_id, run.id) == 2
    assert latest_flaky_state(project.id, test_case_id, run.id)
    assert Repo.get!(TestCaseRunFlakyCorrection, run.id).state == "applied"
  end

  test "leaves the correction pending when the source run is not visible yet" do
    project = ProjectsFixtures.project_fixture()
    test_case_run_id = UUIDv7.generate()

    Repo.insert!(%TestCaseRunFlakyCorrection{
      test_case_run_id: test_case_run_id,
      project_id: project.id,
      test_case_id: UUIDv7.generate(),
      git_commit_sha: "missing"
    })

    assert :ok =
             perform_job(CorrectTestCaseRunFlakyStateWorker, %{
               batch_id: "missing-run",
               test_case_run_ids: [test_case_run_id]
             })

    assert Repo.get!(TestCaseRunFlakyCorrection, test_case_run_id).state == "pending"
  end

  test "marks an already-flaky source as applied without adding another tuple" do
    project = ProjectsFixtures.project_fixture()
    test_case_id = UUIDv7.generate()

    run =
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        git_commit_sha: "already-flaky",
        status: "failure",
        is_flaky: true
      )

    insert_correction(run)

    assert :ok =
             perform_job(CorrectTestCaseRunFlakyStateWorker, %{
               batch_id: "already-flaky",
               test_case_run_ids: [run.id]
             })

    assert physical_tuple_count(project.id, test_case_id, run.id) == 1
    assert Repo.get!(TestCaseRunFlakyCorrection, run.id).state == "applied"
  end

  test "corrects multiple runs in one batch" do
    project = ProjectsFixtures.project_fixture()
    git_commit_sha = "flaky-correction-batch-#{System.unique_integer([:positive])}"

    runs =
      Enum.map(1..2, fn _index ->
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: UUIDv7.generate(),
          git_commit_sha: git_commit_sha,
          status: "failure",
          is_flaky: false
        )
      end)

    Enum.each(runs, &insert_correction/1)

    assert :ok =
             perform_job(CorrectTestCaseRunFlakyStateWorker, %{
               batch_id: "two-runs",
               test_case_run_ids: Enum.map(runs, & &1.id)
             })

    Enum.each(runs, fn run ->
      assert physical_tuple_count(project.id, run.test_case_id, run.id) == 2
      assert latest_flaky_state(project.id, run.test_case_id, run.id)
      assert Repo.get!(TestCaseRunFlakyCorrection, run.id).state == "applied"
    end)
  end

  test "corrects runs from multiple project and commit groups" do
    first_project = ProjectsFixtures.project_fixture()
    second_project = ProjectsFixtures.project_fixture()

    runs = [
      RunsFixtures.test_case_run_fixture(
        project_id: first_project.id,
        test_case_id: UUIDv7.generate(),
        git_commit_sha: "first-commit",
        status: "failure",
        is_flaky: false
      ),
      RunsFixtures.test_case_run_fixture(
        project_id: first_project.id,
        test_case_id: UUIDv7.generate(),
        git_commit_sha: "second-commit",
        status: "failure",
        is_flaky: false
      ),
      RunsFixtures.test_case_run_fixture(
        project_id: second_project.id,
        test_case_id: UUIDv7.generate(),
        git_commit_sha: "first-commit",
        status: "failure",
        is_flaky: false
      )
    ]

    Enum.each(runs, &insert_correction/1)

    assert :ok =
             perform_job(CorrectTestCaseRunFlakyStateWorker, %{
               batch_id: "mixed-groups",
               test_case_run_ids: Enum.map(runs, & &1.id)
             })

    Enum.each(runs, fn run ->
      assert latest_flaky_state(run.project_id, run.test_case_id, run.id)
      assert Repo.get!(TestCaseRunFlakyCorrection, run.id).state == "applied"
    end)
  end

  test "the sweeper re-enqueues corrections left pending by an exhausted job" do
    project = ProjectsFixtures.project_fixture()
    test_case_run_id = UUIDv7.generate()

    Repo.insert!(%TestCaseRunFlakyCorrection{
      test_case_run_id: test_case_run_id,
      project_id: project.id,
      test_case_id: UUIDv7.generate(),
      git_commit_sha: "pending"
    })

    Repo.update_all(
      from(correction in TestCaseRunFlakyCorrection,
        where: correction.test_case_run_id == ^test_case_run_id
      ),
      set: [
        inserted_at: DateTime.add(DateTime.utc_now(:second), -6 * 60, :second),
        updated_at: DateTime.add(DateTime.utc_now(:second), -6 * 60, :second)
      ]
    )

    assert :ok =
             perform_job(SweepPendingTestCaseRunFlakyCorrectionsWorker, %{})

    assert_enqueued(
      worker: CorrectTestCaseRunFlakyStateWorker,
      args: %{test_case_run_ids: [test_case_run_id]}
    )
  end

  defp insert_correction(run) do
    Repo.insert!(%TestCaseRunFlakyCorrection{
      test_case_run_id: run.id,
      project_id: run.project_id,
      test_case_id: run.test_case_id,
      git_commit_sha: run.git_commit_sha
    })
  end

  defp physical_tuple_count(project_id, test_case_id, test_case_run_id) do
    ClickHouseRepo.one(
      from(tcr in TestCaseRun,
        where: tcr.project_id == ^project_id,
        where: tcr.test_case_id == ^test_case_id,
        where: tcr.id == ^test_case_run_id,
        select: count()
      )
    )
  end

  defp latest_flaky_state(project_id, test_case_id, test_case_run_id) do
    ClickHouseRepo.one(
      from(tcr in TestCaseRun,
        where: tcr.project_id == ^project_id,
        where: tcr.test_case_id == ^test_case_id,
        where: tcr.id == ^test_case_run_id,
        order_by: [desc: tcr.inserted_at],
        limit: 1,
        select: tcr.is_flaky
      )
    )
  end
end
