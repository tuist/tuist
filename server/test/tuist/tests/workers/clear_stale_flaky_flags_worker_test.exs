defmodule Tuist.Tests.Workers.ClearStaleFlakyFlagsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Tests.Workers.ClearStaleFlakyFlagsWorker

  describe "perform/1" do
    test "enqueues ClearCooledDownFlakyTestsWorker for projects with flaky test cases" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = Ecto.UUID.generate()

      test_case =
        RunsFixtures.test_case_fixture(
          id: test_case_id,
          project_id: project.id,
          is_flaky: true
        )

      Tuist.IngestRepo.insert_all(Tuist.Tests.TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

      assert :ok = ClearStaleFlakyFlagsWorker.perform(%Oban.Job{args: %{}})

      assert [%{args: %{"project_id" => project_id}}] =
               all_enqueued(worker: Tuist.Tests.Workers.ClearCooledDownFlakyTestsWorker)

      assert project_id == project.id
    end
  end
end
