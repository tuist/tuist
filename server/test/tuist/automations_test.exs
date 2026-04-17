defmodule Tuist.AutomationsTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Automations
  alias Tuist.Automations.Automation
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "list_automations/1" do
    test "returns automations for the given project ordered by insertion time" do
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()
      first = AutomationsFixtures.automation_fixture(project: project, name: "first")
      _other = AutomationsFixtures.automation_fixture(project: other_project)
      second = AutomationsFixtures.automation_fixture(project: project, name: "second")

      ids = project.id |> Automations.list_automations() |> Enum.map(& &1.id)
      assert ids == [first.id, second.id]
    end

    test "returns an empty list when project has no automations" do
      project = ProjectsFixtures.project_fixture()
      assert Automations.list_automations(project.id) == []
    end
  end

  describe "get_automation/1" do
    test "returns the automation when found" do
      automation = AutomationsFixtures.automation_fixture()
      assert {:ok, fetched} = Automations.get_automation(automation.id)
      assert fetched.id == automation.id
    end

    test "returns :not_found when missing" do
      assert {:error, :not_found} = Automations.get_automation(UUIDv7.generate())
    end
  end

  describe "create_automation/1" do
    test "inserts a valid automation" do
      project = ProjectsFixtures.project_fixture()

      attrs = %{
        "project_id" => project.id,
        "name" => "Quarantine flaky tests",
        "automation_type" => "flakiness_rate",
        "config" => %{"threshold" => 5, "window" => "30d"},
        "trigger_actions" => [%{"type" => "change_state", "state" => "muted"}]
      }

      assert {:ok, %Automation{} = automation} = Automations.create_automation(attrs)
      assert automation.name == "Quarantine flaky tests"
      assert automation.enabled == true
    end

    test "returns a changeset error for invalid attrs" do
      assert {:error, %Ecto.Changeset{}} = Automations.create_automation(%{})
    end
  end

  describe "update_automation/2" do
    test "updates the given automation" do
      automation = AutomationsFixtures.automation_fixture()
      assert {:ok, updated} = Automations.update_automation(automation, %{"enabled" => false})
      refute updated.enabled
    end
  end

  describe "delete_automation/1" do
    test "deletes the automation" do
      automation = AutomationsFixtures.automation_fixture()
      assert {:ok, _} = Automations.delete_automation(automation)
      assert {:error, :not_found} = Automations.get_automation(automation.id)
    end
  end

  describe "alerts" do
    test "create_alert and list_active_alerts roundtrip" do
      automation = AutomationsFixtures.automation_fixture()
      test_case_id = Ecto.UUID.generate()

      assert :ok =
               Automations.create_alert(%{
                 automation_id: automation.id,
                 test_case_id: test_case_id,
                 status: "triggered",
                 triggered_at: NaiveDateTime.utc_now()
               })

      alerts = Automations.list_active_alerts(automation.id)
      assert Enum.any?(alerts, &(&1.test_case_id == test_case_id))
    end

    test "resolve_alert appends a recovery event so test case is no longer listed as active" do
      automation = AutomationsFixtures.automation_fixture()
      test_case_id = Ecto.UUID.generate()

      :ok =
        Automations.create_alert(%{
          automation_id: automation.id,
          test_case_id: test_case_id,
          status: "triggered",
          triggered_at: NaiveDateTime.utc_now()
        })

      assert :ok = Automations.resolve_alert(automation.id, test_case_id)

      alerts = Automations.list_active_alerts(automation.id)
      refute Enum.any?(alerts, &(&1.test_case_id == test_case_id))
    end

    test "resolve_alert is safe to call when no active alert exists" do
      automation = AutomationsFixtures.automation_fixture()
      assert :ok = Automations.resolve_alert(automation.id, Ecto.UUID.generate())
    end
  end
end
