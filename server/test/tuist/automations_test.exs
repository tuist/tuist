defmodule Tuist.AutomationsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Automations
  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Automations.Workers.AlertEvaluationWorker
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
        "trigger_config" => %{"threshold" => 5, "window_type" => "last_days", "window" => "30d"},
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

    test "resets the baseline when the monitor definition changes" do
      automation = AutomationsFixtures.automation_alert_fixture()

      assert {:ok, updated} =
               Automations.update_alert(automation, %{
                 "trigger_config" => %{"threshold" => 20, "window_type" => "last_days", "window" => "30d"}
               })

      assert updated.baseline_established_at == nil
    end

    test "keeps the baseline when only enabled changes" do
      automation = AutomationsFixtures.automation_alert_fixture()

      assert {:ok, updated} = Automations.update_alert(automation, %{"enabled" => false})

      assert updated.baseline_established_at == automation.baseline_established_at
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

  describe "enqueue_flaky_alert_evaluations/2" do
    test "coalesces pending evaluations for enabled flaky monitors only" do
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()

      flakiness_alert =
        AutomationsFixtures.automation_alert_fixture(project: project, monitor_type: "flakiness_rate")

      count_alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flaky_run_count",
          trigger_config: %{"threshold" => 1, "window_type" => "last_days", "window" => "30d"}
        )

      _disabled =
        AutomationsFixtures.automation_alert_fixture(project: project, monitor_type: "flaky_run_count", enabled: false)

      _event_driven =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "test_updated",
          trigger_config: %{"events" => ["marked_flaky"]}
        )

      _other_project =
        AutomationsFixtures.automation_alert_fixture(project: other_project, monitor_type: "flakiness_rate")

      test_case_ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]

      assert :ok = Automations.enqueue_flaky_alert_evaluations(project.id, test_case_ids ++ [hd(test_case_ids), nil])

      jobs = all_enqueued(worker: AlertEvaluationWorker)

      assert length(jobs) == 2

      args_by_alert_id = Map.new(jobs, fn job -> {job.args["alert_id"], job.args} end)

      assert args_by_alert_id[flakiness_alert.id]["drain_pending_test_case_ids"]
      refute Map.has_key?(args_by_alert_id[flakiness_alert.id], "test_case_ids")
      assert args_by_alert_id[count_alert.id]["drain_pending_test_case_ids"]
      refute Map.has_key?(args_by_alert_id[count_alert.id], "test_case_ids")

      assert MapSet.new(Automations.list_pending_alert_test_case_ids(flakiness_alert.id)) == MapSet.new(test_case_ids)
      assert MapSet.new(Automations.list_pending_alert_test_case_ids(count_alert.id)) == MapSet.new(test_case_ids)
    end

    test "merges repeated enqueue calls into one pending drain job per alert" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project, monitor_type: "flakiness_rate")

      [first_id, second_id, third_id] = Enum.map(1..3, fn _ -> Ecto.UUID.generate() end)

      assert :ok = Automations.enqueue_flaky_alert_evaluations(project.id, [first_id, second_id])
      assert :ok = Automations.enqueue_flaky_alert_evaluations(project.id, [second_id, third_id])

      assert [%{args: %{"alert_id" => alert_id, "drain_pending_test_case_ids" => true}}] =
               all_enqueued(worker: AlertEvaluationWorker)

      assert alert_id == alert.id

      assert MapSet.new(Automations.list_pending_alert_test_case_ids(alert.id)) ==
               MapSet.new([first_id, second_id, third_id])
    end

    test "keeps a test case pending when it is re-added while a drain is evaluating" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project, monitor_type: "flakiness_rate")
      test_case_id = Ecto.UUID.generate()

      assert :ok = Automations.enqueue_flaky_alert_evaluations(project.id, [test_case_id])

      assert :ok =
               Automations.with_pending_alert_test_case_ids(alert.id, fn [^test_case_id] ->
                 Automations.enqueue_flaky_alert_evaluations(project.id, [test_case_id])
               end)

      assert Automations.list_pending_alert_test_case_ids(alert.id) == [test_case_id]
    end
  end

  describe "dispatch_test_case_event/2" do
    defp test_updated_alert(project, opts \\ []) do
      AutomationsFixtures.automation_alert_fixture(
        Keyword.merge(
          [
            project: project,
            monitor_type: "test_updated",
            trigger_config: %{"events" => ["marked_flaky"]},
            trigger_actions: [%{"type" => "change_state", "state" => "muted"}]
          ],
          opts
        )
      )
    end

    test "runs trigger actions for an alert subscribed to :marked_flaky" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      alert = test_updated_alert(project)

      expected_entity = %{type: :test_case, id: test_case.id}

      expect(ActionExecutor, :execute_actions, fn actions, ^alert, ^expected_entity ->
        assert actions == alert.trigger_actions
        :ok
      end)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)

      events = Automations.list_active_alert_events(alert.id)
      assert Enum.any?(events, &(&1.test_case_id == test_case.id))
    end

    test "skips disabled alerts" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      test_updated_alert(project, enabled: false)

      reject(&ActionExecutor.execute_actions/3)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)
    end

    test "skips alerts from other projects" do
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      test_updated_alert(other_project)

      reject(&ActionExecutor.execute_actions/3)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)
    end

    test "skips alerts whose monitor_type isn't test_updated" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}

      AutomationsFixtures.automation_alert_fixture(
        project: project,
        monitor_type: "flaky_run_count",
        trigger_config: %{"threshold" => 3, "window_type" => "last_days", "window" => "30d"}
      )

      reject(&ActionExecutor.execute_actions/3)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)
    end

    test "skips alerts not subscribed to the firing event" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      # Subscribed only to unmarked_flaky.
      test_updated_alert(project, trigger_config: %{"events" => ["unmarked_flaky"]})

      reject(&ActionExecutor.execute_actions/3)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)
    end

    test ":unmarked_flaky fires an alert subscribed to unmarked_flaky" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      alert = test_updated_alert(project, trigger_config: %{"events" => ["unmarked_flaky"]})

      expect(ActionExecutor, :execute_actions, fn _actions, ^alert, _entity -> :ok end)

      assert :ok = Automations.dispatch_test_case_event(:unmarked_flaky, test_case)
    end

    test "an alert can subscribe to multiple events and fires on each" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}

      alert =
        test_updated_alert(project,
          trigger_config: %{
            "events" => ["marked_flaky", "state_changed_to_muted", "state_changed_to_enabled"]
          }
        )

      # Three matching firings: :marked_flaky, :muted, :unmuted.
      expect(ActionExecutor, :execute_actions, 3, fn _actions, ^alert, _entity -> :ok end)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)
      assert :ok = Automations.dispatch_test_case_event(:muted, test_case)
      # :unmuted maps to state_changed_to_enabled (subscribed).
      assert :ok = Automations.dispatch_test_case_event(:unmuted, test_case)
      # :skipped is NOT in the subscription, so this is a no-op.
      assert :ok = Automations.dispatch_test_case_event(:skipped, test_case)
    end

    test ":unmuted and :unskipped both map to state_changed_to_enabled" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      alert = test_updated_alert(project, trigger_config: %{"events" => ["state_changed_to_enabled"]})

      expect(ActionExecutor, :execute_actions, 2, fn _actions, ^alert, _entity -> :ok end)

      assert :ok = Automations.dispatch_test_case_event(:unmuted, test_case)
      assert :ok = Automations.dispatch_test_case_event(:unskipped, test_case)
    end

    test "does not record an alert event when actions fail" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      alert = test_updated_alert(project)

      expect(ActionExecutor, :execute_actions, fn _actions, _alert, _entity ->
        {:error, :boom}
      end)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)
      assert Automations.list_active_alert_events(alert.id) == []
    end

    test "depth guard caps recursion when an action re-fires the same event" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      _alert = test_updated_alert(project)

      # Simulate an automation whose action re-emits the same test case
      # event (the canonical cycle: a `state_changed_to_muted` alert that
      # mutes the test on fire). Without a guard this would loop forever.
      counter = :counters.new(1, [])

      stub(ActionExecutor, :execute_actions, fn _actions, _alert, _entity ->
        :counters.add(counter, 1, 1)
        Automations.dispatch_test_case_event(:marked_flaky, test_case)
        :ok
      end)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)

      # The dispatcher allows depths 0..9 to run, so we expect exactly 10
      # executor invocations before the guard trips on the 11th level.
      assert :counters.get(counter, 1) == 10
    end
  end
end
