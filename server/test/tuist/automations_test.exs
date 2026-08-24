defmodule Tuist.AutomationsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.Automations
  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Automations.Holds
  alias Tuist.Automations.Workers.AlertEvaluationWorker
  alias Tuist.FeatureFlags
  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Tests
  alias Tuist.Tests.TestCase
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

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

    test "excludes the Manual automation" do
      project = ProjectsFixtures.project_fixture()
      standard = AutomationsFixtures.automation_alert_fixture(project: project)
      {:ok, _manual} = Automations.get_or_create_manual_alert(project.id)

      assert [%{id: id}] = Automations.list_alerts(project.id)
      assert id == standard.id
    end
  end

  describe "get_or_create_manual_alert/1" do
    test "creates the Manual alert on first call and returns the same row after" do
      project = ProjectsFixtures.project_fixture()

      assert {:ok, %Alert{} = alert} = Automations.get_or_create_manual_alert(project.id)
      assert alert.kind == "manual"
      assert alert.name == "Manual"
      assert alert.enabled
      assert alert.monitor_type == nil

      assert {:ok, again} = Automations.get_or_create_manual_alert(project.id)
      assert again.id == alert.id

      manual_rows =
        Repo.all(from(a in Alert, where: a.project_id == ^project.id, where: a.kind == "manual"))

      assert [%{id: id}] = manual_rows
      assert id == alert.id
    end

    test "returns the surviving row when a concurrent insert wins the race" do
      project = ProjectsFixtures.project_fixture()
      {:ok, existing} = Automations.get_or_create_manual_alert(project.id)

      # Simulate the race: the pre-insert read misses the row a concurrent
      # writer just committed, forcing this call down the on_conflict insert
      # path against the partial unique index.
      expect(Repo, :get_by, fn Alert, _clauses -> nil end)

      assert {:ok, alert} = Automations.get_or_create_manual_alert(project.id)
      assert alert.id == existing.id

      assert [_only_row] =
               Repo.all(from(a in Alert, where: a.project_id == ^project.id, where: a.kind == "manual"))
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
      assert updated.baseline_generation == automation.baseline_generation + 1
    end

    test "keeps the baseline when only enabled changes" do
      automation = AutomationsFixtures.automation_alert_fixture()

      assert {:ok, updated} = Automations.update_alert(automation, %{"enabled" => false})

      assert updated.baseline_established_at == automation.baseline_established_at
      assert updated.baseline_generation == automation.baseline_generation
    end

    test "refuses to update the Manual automation" do
      project = ProjectsFixtures.project_fixture()
      {:ok, manual} = Automations.get_or_create_manual_alert(project.id)

      assert {:error, :manual_alert} = Automations.update_alert(manual, %{"enabled" => false})

      assert {:ok, reloaded} = Automations.get_alert(manual.id)
      assert reloaded.enabled
      assert reloaded.kind == "manual"
    end

    test "a disable and re-enable cycle leaves live claims untouched" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      test_case_id = Ecto.UUID.generate()

      {:ok, _} = Holds.place_claim(alert, test_case_id, %{state: "skipped"})

      assert {:ok, disabled} = Automations.update_alert(alert, %{"enabled" => false})
      assert [%{state: "skipped"}] = Holds.live_claims_for_alert(alert)

      assert {:ok, _reenabled} = Automations.update_alert(disabled, %{"enabled" => true})
      assert [%{state: "skipped", test_case_id: ^test_case_id}] = Holds.live_claims_for_alert(alert)
    end
  end

  describe "delete_alert/1" do
    test "deletes the automation" do
      automation = AutomationsFixtures.automation_alert_fixture()
      assert {:ok, _} = Automations.delete_alert(automation)
      assert {:error, :not_found} = Automations.get_alert(automation.id)
    end

    test "refuses to delete the Manual automation" do
      project = ProjectsFixtures.project_fixture()
      {:ok, manual} = Automations.get_or_create_manual_alert(project.id)

      assert {:error, :manual_alert} = Automations.delete_alert(manual)
      assert {:ok, _still_there} = Automations.get_alert(manual.id)
    end

    test "releases live claims with re-derivation when the holds flag is on" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      other_alert = AutomationsFixtures.automation_alert_fixture(project: project)
      co_claimed_id = clickhouse_test_case(project).id
      solely_claimed_id = clickhouse_test_case(project).id

      {:ok, _} = Holds.place_claim(alert, co_claimed_id, %{state: "skipped"})
      {:ok, _} = Holds.place_claim(other_alert, co_claimed_id, %{state: "skipped"})
      {:ok, _} = Holds.place_claim(alert, solely_claimed_id, %{state: "skipped"})

      {:ok, _} =
        Holds.derive_and_apply(project.id, [co_claimed_id, solely_claimed_id], alert_id: alert.id)

      stub(FeatureFlags, :test_state_holds_enabled?, fn _project_id -> true end)

      assert {:ok, _} = Automations.delete_alert(alert)
      assert {:error, :not_found} = Automations.get_alert(alert.id)

      assert Holds.live_claims_for_alert(alert) == []
      assert [%{test_case_id: ^co_claimed_id}] = Holds.live_claims_for_alert(other_alert)

      states = Tests.get_test_case_states(project.id, [co_claimed_id, solely_claimed_id])
      assert states[co_claimed_id].state == "skipped"
      assert states[solely_claimed_id].state == "enabled"
    end

    test "withdraws claims without touching state when the holds flag is off" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      test_case_id = clickhouse_test_case(project).id

      {:ok, _} = Holds.place_claim(alert, test_case_id, %{state: "skipped"})
      {:ok, _} = Holds.derive_and_apply(project.id, [test_case_id], alert_id: alert.id)

      assert {:ok, _} = Automations.delete_alert(alert)
      assert {:error, :not_found} = Automations.get_alert(alert.id)

      assert Holds.live_claims_for_alert(alert) == []
      assert Tests.get_test_case_states(project.id, [test_case_id])[test_case_id].state == "skipped"
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
    test "enqueues one debounced scoped evaluation per project and cadence" do
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()

      _flakiness_alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{"threshold" => 10, "window_type" => "rolling", "rolling_window_size" => 75}
        )

      _count_alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flaky_run_count",
          trigger_config: %{"threshold" => 1, "window_type" => "last_days", "window" => "30d"}
        )

      _reliability_alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "reliability_rate",
          trigger_config: %{"threshold" => 90, "comparison" => "lt", "window_type" => "last_days", "window" => "30d"}
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

      assert [
               %{
                 args: %{
                   "project_id" => project_id,
                   "cadence_seconds" => 300,
                   "evaluate_recent_test_case_runs" => true
                 }
               }
             ] = all_enqueued(worker: AlertEvaluationWorker)

      assert project_id == project.id
    end

    test "ignores the Manual automation" do
      project = ProjectsFixtures.project_fixture()
      {:ok, _manual} = Automations.get_or_create_manual_alert(project.id)

      assert :ok = Automations.enqueue_flaky_alert_evaluations(project.id, [Ecto.UUID.generate()])

      assert [] = all_enqueued(worker: AlertEvaluationWorker)
    end

    test "leaves calendar-window alerts and rolling baselines to the scheduler" do
      project = ProjectsFixtures.project_fixture()

      _calendar_window_alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate"
        )

      _rolling_baseline_alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          baseline_established_at: nil,
          monitor_type: "flaky_run_count",
          trigger_config: %{"threshold" => 1, "window_type" => "rolling", "rolling_window_size" => 75}
        )

      assert :ok = Automations.enqueue_flaky_alert_evaluations(project.id, [Ecto.UUID.generate()])

      assert [] = all_enqueued(worker: AlertEvaluationWorker)
    end

    test "merges repeated enqueue calls into one scoped evaluation job per project and cadence" do
      project = ProjectsFixtures.project_fixture()

      _alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          trigger_config: %{"threshold" => 10, "window_type" => "rolling", "rolling_window_size" => 75}
        )

      [first_id, second_id, third_id] = Enum.map(1..3, fn _ -> Ecto.UUID.generate() end)

      assert :ok = Automations.enqueue_flaky_alert_evaluations(project.id, [first_id, second_id])
      assert :ok = Automations.enqueue_flaky_alert_evaluations(project.id, [second_id, third_id])

      assert [
               %{
                 args: %{
                   "project_id" => project_id,
                   "cadence_seconds" => 300,
                   "evaluate_recent_test_case_runs" => true
                 }
               }
             ] =
               all_enqueued(worker: AlertEvaluationWorker)

      assert project_id == project.id
    end

    test "keeps different alert cadences in separate evaluation jobs" do
      project = ProjectsFixtures.project_fixture()

      _five_minute_alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          cadence: "5m",
          trigger_config: %{"threshold" => 10, "window_type" => "rolling", "rolling_window_size" => 75}
        )

      _one_minute_alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "reliability_rate",
          cadence: "1m",
          trigger_config: %{
            "threshold" => 90,
            "comparison" => "lt",
            "window_type" => "rolling",
            "rolling_window_size" => 75
          }
        )

      assert :ok = Automations.enqueue_flaky_alert_evaluations(project.id, [Ecto.UUID.generate()])

      assert [60, 300] ==
               [worker: AlertEvaluationWorker]
               |> all_enqueued()
               |> Enum.map(& &1.args["cadence_seconds"])
               |> Enum.sort()
    end

    test "schedules scoped evaluations at the alert cadence" do
      project = ProjectsFixtures.project_fixture()

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          cadence: "30s"
        )

      enqueued_at = DateTime.utc_now(:second)

      assert :ok = Automations.enqueue_scoped_alert_evaluation(alert)

      assert [%{scheduled_at: scheduled_at}] = all_enqueued(worker: AlertEvaluationWorker)
      assert DateTime.diff(scheduled_at, enqueued_at, :second) in 30..31
    end

    test "does not enqueue a second scoped evaluation while the existing job is active" do
      project = ProjectsFixtures.project_fixture()

      alert =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          monitor_type: "flakiness_rate",
          cadence: "5m",
          trigger_config: %{
            "threshold" => 10,
            "window_type" => "rolling",
            "rolling_window_size" => 75
          }
        )

      assert :ok = Automations.enqueue_scoped_alert_evaluation(alert)

      job_query =
        from(job in Oban.Job,
          where: job.worker == ^inspect(AlertEvaluationWorker)
        )

      job = Repo.one!(job_query)

      for state <- ["executing", "retryable"] do
        Repo.update!(Ecto.Changeset.change(job, state: state))

        assert :ok = Automations.enqueue_scoped_alert_evaluation(alert)
        assert [%{id: job_id, state: ^state}] = Repo.all(job_query)
        assert job_id == job.id
      end
    end
  end

  describe "recent_test_case_run_changes_for_alert/1" do
    test "returns distinct recently inserted test case ids for the alert project" do
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      {:ok, alert} = Automations.update_alert_scoped_evaluation_cursor(alert, ~U[2026-06-09 10:00:50Z])

      first_id = Ecto.UUID.generate()
      second_id = Ecto.UUID.generate()
      corrected_id = Ecto.UUID.generate()
      outside_window_id = Ecto.UUID.generate()

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: Ecto.UUID.generate(),
        inserted_at: ~N[2026-06-09 09:00:00.000000]
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: first_id,
        inserted_at: ~N[2026-06-09 10:00:45.000000]
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: first_id,
        inserted_at: ~N[2026-06-09 10:00:48.000000]
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: second_id,
        inserted_at: ~N[2026-06-09 10:00:46.000000]
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: corrected_id,
        ran_at: ~N[2025-01-01 00:00:00.000000],
        inserted_at: ~N[2026-06-09 10:10:00.000000]
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: outside_window_id,
        inserted_at: ~N[2026-06-09 10:15:50.000000]
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: nil,
        inserted_at: ~N[2026-06-09 10:00:49.000000]
      )

      RunsFixtures.test_case_run_fixture(
        project_id: other_project.id,
        test_case_id: Ecto.UUID.generate(),
        inserted_at: ~N[2026-06-09 10:00:49.000000]
      )

      assert %{test_case_ids: test_case_ids, cursor: cursor, more?: true} =
               Automations.recent_test_case_run_changes_for_alert(alert)

      assert MapSet.new(test_case_ids) == MapSet.new([first_id, second_id, corrected_id])
      assert cursor == ~U[2026-06-09 10:15:50Z]
    end
  end

  describe "scoped_evaluation_ranges/1" do
    test "keeps ordered identifiers in several bounded ranges" do
      identifiers = Enum.to_list(1..8001)

      ranges = Automations.scoped_evaluation_ranges(identifiers)

      assert Enum.map(ranges, &length/1) == [2000, 2000, 2000, 2000, 1]
      assert List.flatten(ranges) == identifiers
    end

    test "splits smaller sets into at least four ranges" do
      identifiers = Enum.to_list(1..4000)

      assert [1000, 1000, 1000, 1000] ==
               identifiers
               |> Automations.scoped_evaluation_ranges()
               |> Enum.map(&length/1)
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

    test "never dispatches to the Manual automation" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      {:ok, _manual} = Automations.get_or_create_manual_alert(project.id)

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

    test "skips alerts whose trigger state filter does not match the test case" do
      project = ProjectsFixtures.project_fixture()
      test_case = %{id: Ecto.UUID.generate(), project_id: project.id}
      alert = test_updated_alert(project, trigger_config: %{"events" => ["marked_flaky"], "states" => ["skipped"]})
      project_id = project.id
      test_case_id = test_case.id

      expect(Tests, :get_test_case_states, fn ^project_id, [^test_case_id] ->
        %{test_case_id => %{state: "muted", is_flaky: false}}
      end)

      reject(&ActionExecutor.execute_actions/3)

      assert :ok = Automations.dispatch_test_case_event(:marked_flaky, test_case)
      assert Automations.list_active_alert_events(alert.id) == []
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

  # `update_test_case/3` resolves the test case from ClickHouse, so derivation
  # tests need a real `test_cases` row, not just the fixture struct.
  defp clickhouse_test_case(project) do
    test_case = RunsFixtures.test_case_fixture(project_id: project.id, state: "enabled")
    IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])
    test_case
  end
end
