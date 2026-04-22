defmodule Tuist.AutomationsTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Automations
  alias Tuist.Automations.Alerts.Alert
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "list_alerts/1" do
    test "returns automations for the given project ordered by insertion time" do
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()
      first = AutomationsFixtures.automation_alert_fixture(project: project, name: "first")
      _other = AutomationsFixtures.automation_alert_fixture(project: other_project)
      second = AutomationsFixtures.automation_alert_fixture(project: project, name: "second")

      ids = project.id |> Automations.list_alerts() |> Enum.map(& &1.id)
      assert ids == [first.id, second.id]
    end

    test "returns an empty list when project has no automations" do
      project = ProjectsFixtures.project_fixture()
      assert Automations.list_alerts(project.id) == []
    end

    test "returns the seeded default alert when the fixture keeps it" do
      project = ProjectsFixtures.project_fixture(with_default_alert: true)
      assert [%{name: "Flaky test detection"}] = Automations.list_alerts(project.id)
    end
  end

  describe "get_alert/1" do
    test "returns the automation when found" do
      automation = AutomationsFixtures.automation_alert_fixture()
      assert {:ok, fetched} = Automations.get_alert(automation.id)
      assert fetched.id == automation.id
    end

    test "returns :not_found when missing" do
      assert {:error, :not_found} = Automations.get_alert(UUIDv7.generate())
    end
  end

  describe "create_alert/1" do
    test "inserts a valid automation" do
      project = ProjectsFixtures.project_fixture()

      attrs = %{
        "project_id" => project.id,
        "name" => "Quarantine flaky tests",
        "monitor_type" => "flakiness_rate",
        "trigger_config" => %{"threshold" => 5, "window" => "30d"},
        "trigger_actions" => [%{"type" => "change_state", "state" => "muted"}]
      }

      assert {:ok, %Alert{} = automation} = Automations.create_alert(attrs)
      assert automation.name == "Quarantine flaky tests"
      assert automation.enabled == true
    end

    test "returns a changeset error for invalid attrs" do
      assert {:error, %Ecto.Changeset{}} = Automations.create_alert(%{})
    end
  end

  describe "update_alert/2" do
    test "updates the given automation" do
      automation = AutomationsFixtures.automation_alert_fixture()
      assert {:ok, updated} = Automations.update_alert(automation, %{"enabled" => false})
      refute updated.enabled
    end
  end

  describe "delete_alert/1" do
    test "deletes the automation" do
      automation = AutomationsFixtures.automation_alert_fixture()
      assert {:ok, _} = Automations.delete_alert(automation)
      assert {:error, :not_found} = Automations.get_alert(automation.id)
    end
  end

  describe "alert events" do
    test "create_alert_event and list_active_alert_events roundtrip" do
      alert = AutomationsFixtures.automation_alert_fixture()
      test_case_id = Ecto.UUID.generate()

      assert :ok =
               Automations.create_alert_event(%{
                 alert_id: alert.id,
                 test_case_id: test_case_id,
                 status: "triggered",
                 triggered_at: NaiveDateTime.utc_now()
               })

      events = Automations.list_active_alert_events(alert.id)
      assert Enum.any?(events, &(&1.test_case_id == test_case_id))
    end

    test "a recovered event is no longer listed as active" do
      alert = AutomationsFixtures.automation_alert_fixture()
      test_case_id = Ecto.UUID.generate()
      now = NaiveDateTime.utc_now()

      :ok =
        Automations.create_alert_event(%{
          alert_id: alert.id,
          test_case_id: test_case_id,
          status: "triggered",
          triggered_at: now
        })

      :ok =
        Automations.create_alert_event(%{
          alert_id: alert.id,
          test_case_id: test_case_id,
          status: "recovered",
          triggered_at: now,
          recovered_at: now
        })

      events = Automations.list_active_alert_events(alert.id)
      refute Enum.any?(events, &(&1.test_case_id == test_case_id))
    end
  end
end
