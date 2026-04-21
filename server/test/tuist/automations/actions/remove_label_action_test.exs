defmodule Tuist.Automations.Actions.RemoveLabelActionTest do
  # Integration test: goes through Tests.update_test_case down to the DB so
  # drift in the context contract surfaces here, not in CI.
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Automations.Actions.RemoveLabelAction
  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.TestCase
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "execute/2 with flaky label" do
    test "unmarks the given test case as flaky" do
      project = ProjectsFixtures.project_fixture()
      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: true)
      IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

      assert :ok =
               RemoveLabelAction.execute(
                 %{type: :test_case, id: test_case.id},
                 %{"label" => "flaky"}
               )

      assert {:ok, %{is_flaky: false}} = Tests.get_test_case_by_id(test_case.id)
    end

    test "returns :not_found when the test case doesn't exist" do
      assert {:error, :not_found} =
               RemoveLabelAction.execute(
                 %{type: :test_case, id: Ecto.UUID.generate()},
                 %{"label" => "flaky"}
               )
    end
  end

  describe "execute/2 with unknown label" do
    test "no-ops for unsupported labels without touching the DB" do
      project = ProjectsFixtures.project_fixture()
      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: true)
      IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

      assert :ok =
               RemoveLabelAction.execute(
                 %{type: :test_case, id: test_case.id},
                 %{"label" => "slow"}
               )

      assert {:ok, %{is_flaky: true}} = Tests.get_test_case_by_id(test_case.id)
    end
  end
end
