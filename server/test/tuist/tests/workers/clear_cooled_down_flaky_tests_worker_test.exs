defmodule Tuist.Tests.Workers.ClearCooledDownFlakyTestsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Tests
  alias Tuist.Tests.Workers.ClearCooledDownFlakyTestsWorker
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "perform/1" do
    test "calls clear_cooled_down_flaky_tests for the given project" do
      project = ProjectsFixtures.project_fixture()

      expect(Tests, :clear_cooled_down_flaky_tests, fn p ->
        assert p.id == project.id
        {:ok, 0}
      end)

      assert {:ok, 0} =
               ClearCooledDownFlakyTestsWorker.perform(%Oban.Job{args: %{"project_id" => project.id}})
    end

    test "returns :ok when project does not exist" do
      assert :ok =
               ClearCooledDownFlakyTestsWorker.perform(%Oban.Job{args: %{"project_id" => -1}})
    end
  end
end
