defmodule Tuist.AutomationsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Automations
  alias Tuist.Automations.ActionExecutor
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

  describe "dispatch_test_case_event/2" do
    test "runs trigger actions for enabled manually_marked_flaky alerts on :marked_flaky" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "manually_marked_flaky",
          trigger_config: %{},
          trigger_actions: [%{"type" => "change_state", "state" => "muted"}]
        )

      expected_entity = %{type: :test_case, id: test_case.id}

      expect(ActionExecutor, :execute_actions, fn actions, ^alert, ^expected_entity ->
        assert actions == alert.trigger_actions
        :ok
      end)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)

      events = Automations.list_active_alert_events(alert.id)
      assert Enum.any?(events, &(&1.test_case_id == test_case.id))
    end

    test "skips disabled manually_marked_flaky alerts" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}

      AutomationsFixtures.automation_alert_fixture(
        project: project,
        enabled: false,
        monitor_type: "manually_marked_flaky",
        trigger_config: %{}
      )

      reject(&ActionExecutor.execute_actions/3)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)
    end

    test "skips alerts from other projects" do
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}

      AutomationsFixtures.automation_alert_fixture(
        project: other_project,
        monitor_type: "manually_marked_flaky",
        trigger_config: %{}
      )

      reject(&ActionExecutor.execute_actions/3)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)
    end

    test "skips other monitor types" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}

      AutomationsFixtures.automation_alert_fixture(
        project: project,
        monitor_type: "flaky_run_count",
        trigger_config: %{"threshold" => 3, "window" => "30d"}
      )

      reject(&ActionExecutor.execute_actions/3)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)
    end

    test "runs recovery actions for enabled manually_marked_flaky alerts with recovery on :unmarked_flaky" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "manually_marked_flaky",
          trigger_config: %{},
          trigger_actions: [%{"type" => "change_state", "state" => "muted"}],
          recovery_enabled: true,
          recovery_config: %{},
          recovery_actions: [%{"type" => "change_state", "state" => "enabled"}]
        )

      expected_entity = %{type: :test_case, id: test_case.id}

      expect(ActionExecutor, :execute_actions, fn actions, ^alert, ^expected_entity ->
        assert actions == alert.recovery_actions
        :ok
      end)

      assert :ok = Automations.dispatch_test_case_event(:unmarked_flaky, test_case)
    end

    test "does not run recovery when recovery_enabled is false" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}

      AutomationsFixtures.automation_alert_fixture(
        project: project,
        monitor_type: "manually_marked_flaky",
        trigger_config: %{},
        recovery_enabled: false
      )

      reject(&ActionExecutor.execute_actions/3)

      assert :ok = Automations.dispatch_test_case_event(:unmarked_flaky, test_case)
    end

    test "ignores unrelated event types" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}

      AutomationsFixtures.automation_alert_fixture(
        project: project,
        monitor_type: "manually_marked_flaky",
        trigger_config: %{}
      )

      reject(&ActionExecutor.execute_actions/3)

      assert :ok = Automations.dispatch_test_case_event(:muted, test_case)
      assert :ok = Automations.dispatch_test_case_event(:unmuted, test_case)
    end

    test "does not record an alert event when actions fail" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "manually_marked_flaky",
          trigger_config: %{},
          trigger_actions: [%{"type" => "change_state", "state" => "muted"}]
        )

      expect(ActionExecutor, :execute_actions, fn _actions, _alert, _entity ->
        {:error, :boom}
      end)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)
      assert Automations.list_active_alert_events(alert.id) == []
    end
  end
end
