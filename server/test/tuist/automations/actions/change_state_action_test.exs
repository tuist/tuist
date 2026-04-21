defmodule Tuist.Automations.Actions.ChangeStateActionTest do
  # Integration test: exercise the action through the real Tests.update_test_case
  # down to a ClickHouse write so we catch drift in the context contract.
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Automations.Actions.ChangeStateAction
  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.TestCase
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "execute/2" do
    test "flips a test case's state to muted" do
      project = ProjectsFixtures.project_fixture()
      test_case = RunsFixtures.test_case_fixture(project_id: project.id, state: "enabled")
      IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

      assert :ok =
               ChangeStateAction.execute(
                 %{type: :test_case, id: test_case.id},
                 %{"state" => "muted"}
               )

      assert {:ok, %{state: "muted"}} = Tests.get_test_case_by_id(test_case.id)
    end

    test "flips a muted test case back to enabled" do
      project = ProjectsFixtures.project_fixture()
      test_case = RunsFixtures.test_case_fixture(project_id: project.id, state: "muted")
      IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

      assert :ok =
               ChangeStateAction.execute(
                 %{type: :test_case, id: test_case.id},
                 %{"state" => "enabled"}
               )

      assert {:ok, %{state: "enabled"}} = Tests.get_test_case_by_id(test_case.id)
    end

    test "returns :not_found when the test case doesn't exist" do
      assert {:error, :not_found} =
               ChangeStateAction.execute(
                 %{type: :test_case, id: Ecto.UUID.generate()},
                 %{"state" => "enabled"}
               )
    end
  end
end
