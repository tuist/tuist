defmodule Tuist.Automations.ActionExecutorTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Actions.SendSlackAction
  alias Tuist.Automations.Holds
  alias Tuist.FeatureFlags
  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.TestCase
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  defp insert_test_case(attrs) do
    insert_test_case_in(ProjectsFixtures.project_fixture(), attrs)
  end

  defp insert_test_case_in(project, attrs) do
    test_case = RunsFixtures.test_case_fixture([project_id: project.id] ++ attrs)
    IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])
    test_case
  end

  # Synthetic alert stand-in. `apply_merged_attrs/3` reads `automation.id`
  # to stamp the resulting test_case_event with `alert_id`, so a real
  # UUID is required even though we don't preload the alert in these
  # tests.
  defp automation, do: %{id: UUIDv7.generate(), name: "Auto", project_id: 1}

  defp event_types(test_case_id) do
    {events, _meta} = Tests.list_test_case_events(test_case_id)
    Enum.map(events, & &1.event_type)
  end

  test "no-ops on empty action list" do
    assert :ok =
             ActionExecutor.execute_actions(
               [],
               automation(),
               %{type: :test_case, id: Ecto.UUID.generate()}
             )
  end

  test "applies change_state and writes the new state to ClickHouse" do
    test_case = insert_test_case(state: "enabled")

    assert :ok =
             ActionExecutor.execute_actions(
               [%{"type" => "change_state", "state" => "muted"}],
               automation(),
               %{type: :test_case, id: test_case.id}
             )

    assert {:ok, %{state: "muted"}} = Tests.get_test_case_by_id(test_case.id)
    assert "muted" in event_types(test_case.id)
  end

  test "dispatches send_slack to SendSlackAction" do
    entity = %{type: :test_case, id: Ecto.UUID.generate()}

    expect(SendSlackAction, :execute, fn _automation, ^entity, %{"type" => "send_slack"} -> :ok end)

    assert :ok =
             ActionExecutor.execute_actions(
               [%{"type" => "send_slack", "channel" => "C1", "message" => "hi"}],
               automation(),
               entity
             )
  end

  test "applies add_label flaky as is_flaky: true" do
    test_case = insert_test_case(is_flaky: false)

    assert :ok =
             ActionExecutor.execute_actions(
               [%{"type" => "add_label", "label" => "flaky"}],
               automation(),
               %{type: :test_case, id: test_case.id}
             )

    assert {:ok, %{is_flaky: true}} = Tests.get_test_case_by_id(test_case.id)
    assert "marked_flaky" in event_types(test_case.id)
  end

  test "applies remove_label flaky as is_flaky: false" do
    test_case = insert_test_case(is_flaky: true)

    assert :ok =
             ActionExecutor.execute_actions(
               [%{"type" => "remove_label", "label" => "flaky"}],
               automation(),
               %{type: :test_case, id: test_case.id}
             )

    assert {:ok, %{is_flaky: false}} = Tests.get_test_case_by_id(test_case.id)
    assert "unmarked_flaky" in event_types(test_case.id)
  end

  test "coalesces add_label flaky + change_state into one update emitting both events" do
    test_case = insert_test_case(is_flaky: false, state: "enabled")

    assert :ok =
             ActionExecutor.execute_actions(
               [
                 %{"type" => "add_label", "label" => "flaky"},
                 %{"type" => "change_state", "state" => "muted"}
               ],
               automation(),
               %{type: :test_case, id: test_case.id}
             )

    assert {:ok, %{is_flaky: true, state: "muted"}} = Tests.get_test_case_by_id(test_case.id)

    types = event_types(test_case.id)
    assert "marked_flaky" in types
    assert "muted" in types
  end

  test "coalesces recovery actions (remove_label flaky + change_state enabled) into one update emitting both events" do
    test_case = insert_test_case(is_flaky: true, state: "muted")

    assert :ok =
             ActionExecutor.execute_actions(
               [
                 %{"type" => "remove_label", "label" => "flaky"},
                 %{"type" => "change_state", "state" => "enabled"}
               ],
               automation(),
               %{type: :test_case, id: test_case.id}
             )

    assert {:ok, %{is_flaky: false, state: "enabled"}} = Tests.get_test_case_by_id(test_case.id)

    types = event_types(test_case.id)
    assert "unmarked_flaky" in types
    assert "unmuted" in types
  end

  test "later attribute actions override earlier ones in the merged update" do
    test_case = insert_test_case(is_flaky: false)

    assert :ok =
             ActionExecutor.execute_actions(
               [
                 %{"type" => "add_label", "label" => "flaky"},
                 %{"type" => "remove_label", "label" => "flaky"}
               ],
               automation(),
               %{type: :test_case, id: test_case.id}
             )

    assert {:ok, %{is_flaky: false}} = Tests.get_test_case_by_id(test_case.id)
    refute "marked_flaky" in event_types(test_case.id)
  end

  test "runs slack action after the merged attribute write is visible" do
    test_case = insert_test_case(is_flaky: false, state: "enabled")
    entity = %{type: :test_case, id: test_case.id}
    test_pid = self()

    expect(SendSlackAction, :execute, fn _automation, ^entity, %{"type" => "send_slack"} ->
      assert {:ok, %{is_flaky: true, state: "muted"}} = Tests.get_test_case_by_id(test_case.id)
      send(test_pid, :slack_called)
      :ok
    end)

    assert :ok =
             ActionExecutor.execute_actions(
               [
                 %{"type" => "add_label", "label" => "flaky"},
                 %{"type" => "send_slack", "channel" => "C1", "message" => "hi"},
                 %{"type" => "change_state", "state" => "muted"}
               ],
               automation(),
               entity
             )

    assert_received :slack_called
  end

  test "halts and returns error when the test case does not exist" do
    reject(&SendSlackAction.execute/3)

    assert {:error, :not_found} =
             ActionExecutor.execute_actions(
               [
                 %{"type" => "add_label", "label" => "flaky"},
                 %{"type" => "send_slack", "channel" => "C1", "message" => "hi"}
               ],
               automation(),
               %{type: :test_case, id: Ecto.UUID.generate()}
             )
  end

  test "no-ops add_label / remove_label with non-flaky labels" do
    test_case = insert_test_case(is_flaky: false, state: "enabled")

    assert :ok =
             ActionExecutor.execute_actions(
               [
                 %{"type" => "add_label", "label" => "slow"},
                 %{"type" => "remove_label", "label" => "slow"}
               ],
               automation(),
               %{type: :test_case, id: test_case.id}
             )

    assert {:ok, %{is_flaky: false, state: "enabled"}} = Tests.get_test_case_by_id(test_case.id)
    assert event_types(test_case.id) == []
  end

  describe "change_state with holds" do
    setup do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      %{project: project, alert: alert}
    end

    test "flag off: state direct-writes as before and a passive claim is recorded", %{
      project: project,
      alert: alert
    } do
      stub(FeatureFlags, :test_state_holds_enabled?, fn _ -> false end)
      test_case = insert_test_case_in(project, state: "enabled")

      assert :ok =
               ActionExecutor.execute_actions(
                 [%{"type" => "change_state", "state" => "muted"}],
                 alert,
                 %{type: :test_case, id: test_case.id}
               )

      assert {:ok, %{state: "muted"}} = Tests.get_test_case_by_id(test_case.id)
      assert "muted" in event_types(test_case.id)

      assert [claim] = Holds.current_claims(project.id, [test_case.id])[test_case.id]
      assert claim.alert_id == alert.id
      assert claim.state == "muted"
    end

    test "flag on: change_state places a claim and state projects via derivation", %{
      project: project,
      alert: alert
    } do
      stub(FeatureFlags, :test_state_holds_enabled?, fn _ -> true end)
      test_case = insert_test_case_in(project, state: "enabled")

      assert :ok =
               ActionExecutor.execute_actions(
                 [%{"type" => "change_state", "state" => "skipped"}],
                 alert,
                 %{type: :test_case, id: test_case.id}
               )

      assert [claim] = Holds.current_claims(project.id, [test_case.id])[test_case.id]
      assert claim.alert_id == alert.id
      assert claim.state == "skipped"

      assert Tests.get_test_case_states(project.id, [test_case.id])[test_case.id].state == "skipped"

      {events, _meta} = Tests.list_test_case_events(test_case.id)
      assert [event] = events
      assert event.event_type == "skipped"
      assert event.alert_id == alert.id
    end

    test "flag on: a Manual enabled claim shadows the trigger and suppresses send_slack", %{
      project: project,
      alert: alert
    } do
      stub(FeatureFlags, :test_state_holds_enabled?, fn _ -> true end)
      reject(&SendSlackAction.execute/3)
      test_case = insert_test_case_in(project, state: "enabled")
      manual = AutomationsFixtures.manual_automation_alert_fixture(project: project)
      {:ok, _} = Holds.place_claim(manual, test_case.id, %{state: "enabled", actor_id: 42})

      assert :ok =
               ActionExecutor.execute_actions(
                 [
                   %{"type" => "change_state", "state" => "skipped"},
                   %{"type" => "send_slack", "channel" => "C1", "message" => "hi"}
                 ],
                 alert,
                 %{type: :test_case, id: test_case.id}
               )

      claims = Holds.current_claims(project.id, [test_case.id])[test_case.id]
      assert Enum.any?(claims, &(&1.alert_id == alert.id and &1.state == "skipped"))

      assert Tests.get_test_case_states(project.id, [test_case.id])[test_case.id].state == "enabled"
      assert event_types(test_case.id) == []
    end

    test "flag on: coalesces is_flaky into one direct call without :state, state via derivation", %{
      project: project,
      alert: alert
    } do
      stub(FeatureFlags, :test_state_holds_enabled?, fn _ -> true end)
      test_case = insert_test_case_in(project, is_flaky: false, state: "enabled")
      test_pid = self()

      stub(Tests, :update_test_case, fn id, attrs, opts ->
        send(test_pid, {:update_test_case, attrs, opts})
        Mimic.call_original(Tests, :update_test_case, [id, attrs, opts])
      end)

      assert :ok =
               ActionExecutor.execute_actions(
                 [
                   %{"type" => "add_label", "label" => "flaky"},
                   %{"type" => "change_state", "state" => "muted"}
                 ],
                 alert,
                 %{type: :test_case, id: test_case.id}
               )

      alert_id = alert.id

      assert_received {:update_test_case, direct_attrs, direct_opts}
      assert direct_attrs == %{is_flaky: true}
      assert direct_opts[:alert_id] == alert_id

      assert_received {:update_test_case, %{state: "muted"}, derive_opts}
      assert derive_opts[:alert_id] == alert_id

      refute_received {:update_test_case, _, _}

      assert {:ok, %{is_flaky: true, state: "muted"}} = Tests.get_test_case_by_id(test_case.id)

      {events, _meta} = Tests.list_test_case_events(test_case.id)
      assert events |> Enum.map(& &1.event_type) |> Enum.sort() == ["marked_flaky", "muted"]
      assert Enum.all?(events, &(&1.alert_id == alert_id))
    end

    test "flag on: re-trigger refreshes the owner's single live claim", %{
      project: project,
      alert: alert
    } do
      stub(FeatureFlags, :test_state_holds_enabled?, fn _ -> true end)
      test_case = insert_test_case_in(project, state: "enabled")
      entity = %{type: :test_case, id: test_case.id}

      assert :ok =
               ActionExecutor.execute_actions(
                 [%{"type" => "change_state", "state" => "muted"}],
                 alert,
                 entity
               )

      assert :ok =
               ActionExecutor.execute_actions(
                 [%{"type" => "change_state", "state" => "skipped"}],
                 alert,
                 entity
               )

      assert [claim] = Holds.current_claims(project.id, [test_case.id])[test_case.id]
      assert claim.alert_id == alert.id
      assert claim.state == "skipped"
      assert Tests.get_test_case_states(project.id, [test_case.id])[test_case.id].state == "skipped"
    end

    test "flag off: change_state enabled direct-writes and withdraws the owner's claim", %{
      project: project,
      alert: alert
    } do
      stub(FeatureFlags, :test_state_holds_enabled?, fn _ -> false end)
      test_case = insert_test_case_in(project, state: "muted")
      {:ok, _} = Holds.place_claim(alert, test_case.id, %{state: "muted"})

      assert :ok =
               ActionExecutor.execute_actions(
                 [%{"type" => "change_state", "state" => "enabled"}],
                 alert,
                 %{type: :test_case, id: test_case.id}
               )

      assert {:ok, %{state: "enabled"}} = Tests.get_test_case_by_id(test_case.id)
      assert "unmuted" in event_types(test_case.id)
      assert Holds.live_claims_for_alert(alert) == []
    end

    test "flag on: change_state enabled withdraws the claim; another rule's claim keeps the state and suppresses slack",
         %{project: project, alert: alert} do
      stub(FeatureFlags, :test_state_holds_enabled?, fn _ -> true end)
      reject(&SendSlackAction.execute/3)
      test_case = insert_test_case_in(project, state: "enabled")
      other_alert = AutomationsFixtures.automation_alert_fixture(project: project)

      {:ok, _} = Holds.place_claim(alert, test_case.id, %{state: "skipped"})
      {:ok, _} = Holds.place_claim(other_alert, test_case.id, %{state: "skipped"})
      {:ok, _} = Holds.derive_and_apply(project.id, [test_case.id], alert_id: alert.id)

      assert :ok =
               ActionExecutor.execute_actions(
                 [
                   %{"type" => "change_state", "state" => "enabled"},
                   %{"type" => "send_slack", "channel" => "C1", "message" => "hi"}
                 ],
                 alert,
                 %{type: :test_case, id: test_case.id}
               )

      assert Holds.live_claims_for_alert(alert) == []
      assert [claim] = Holds.current_claims(project.id, [test_case.id])[test_case.id]
      assert claim.alert_id == other_alert.id

      assert Tests.get_test_case_states(project.id, [test_case.id])[test_case.id].state == "skipped"
      assert event_types(test_case.id) == ["skipped"]
    end
  end

  test "silently skips unknown action types without touching the row" do
    test_case = insert_test_case(is_flaky: false, state: "enabled")
    reject(&SendSlackAction.execute/3)

    assert :ok =
             ActionExecutor.execute_actions(
               [%{"type" => "fly_to_moon"}],
               automation(),
               %{type: :test_case, id: test_case.id}
             )

    assert {:ok, %{is_flaky: false, state: "enabled"}} = Tests.get_test_case_by_id(test_case.id)
    assert event_types(test_case.id) == []
  end
end
