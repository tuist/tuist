defmodule TuistCloud.TestsTest do
  alias TuistCloud.CommandEventsFixtures
  alias TuistCloud.ProjectsFixtures
  alias TuistCloud.Tests
  use TuistCloud.DataCase
  use Mimic

  describe "current_month_tested_target_hits_count" do
    test "returns only the events from the current month when it's a project" do
      # Given
      TuistCloud.Time |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      project = ProjectsFixtures.project_fixture()

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1500,
        created_at: ~N[2024-04-01 03:00:00],
        remote_test_target_hits: ["target1", "target2"]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1500,
        created_at: ~N[2024-01-02 03:00:00],
        remote_test_target_hits: ["target1", "target2"]
      )

      # When
      got = Tests.current_month_tested_target_hits_count(project)

      # Then
      assert got == 1
    end

    test "returns only the events from the current month when it's an account" do
      # Given
      TuistCloud.Time |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

      %{account: account} =
        project = ProjectsFixtures.project_fixture() |> TuistCloud.Repo.preload(:account)

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1500,
        created_at: ~N[2024-04-01 03:00:00],
        remote_test_target_hits: ["target1", "target2"]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        duration: 1500,
        created_at: ~N[2024-01-02 03:00:00],
        remote_test_target_hits: ["target1", "target2"]
      )

      # When
      got = Tests.current_month_tested_target_hits_count(account)

      # Then
      assert got == 1
    end
  end
end
