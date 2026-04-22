defmodule Tuist.Tests.Workers.ClearCooledDownFlakyTestsSchedulerTest do
  use TuistTestSupport.Cases.DataCase, clickhouse: true
  use Mimic

  alias Tuist.Tests.Workers.ClearCooledDownFlakyTestsScheduler
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

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

      assert :ok = ClearCooledDownFlakyTestsScheduler.perform(%Oban.Job{args: %{}})

      enqueued = all_enqueued(worker: Tuist.Tests.Workers.ClearCooledDownFlakyTestsWorker)
      assert Enum.any?(enqueued, fn job -> job.args["project_id"] == project.id end)
    end
  end
end
