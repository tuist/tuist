defmodule Tuist.Automations.HoldsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Automations.Holds
  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.TestCase
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "place_claim/3 + current_claims/2" do
    test "reads id lists larger than one query batch" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      test_case_ids = Enum.map(1..600, fn _ -> Ecto.UUID.generate() end)

      claimed = Enum.take(test_case_ids, 550)
      Enum.each(claimed, fn id -> {:ok, _} = Holds.place_claim(alert, id, %{state: "skipped"}) end)

      claims = Holds.current_claims(project.id, test_case_ids)

      assert map_size(claims) == 550
      assert Enum.all?(claimed, &match?([%{state: "skipped"}], claims[&1]))
    end

    test "a placed claim reads back live" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      test_case_id = Ecto.UUID.generate()

      assert {:ok, _hold} = Holds.place_claim(alert, test_case_id, %{state: "skipped"})

      assert [claim] = Holds.current_claims(project.id, [test_case_id])[test_case_id]
      assert claim.alert_id == alert.id
      assert claim.state == "skipped"
      assert claim.actor_id == nil
      assert claim.expiry_kind == "none"
    end

    test "a newer claim from the same owner supersedes the older one" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      test_case_id = Ecto.UUID.generate()

      assert {:ok, _} = Holds.place_claim(alert, test_case_id, %{state: "muted"})
      assert {:ok, _} = Holds.place_claim(alert, test_case_id, %{state: "skipped"})

      assert [claim] = Holds.current_claims(project.id, [test_case_id])[test_case_id]
      assert claim.state == "skipped"
    end

    test "a claim with expiry fields reads them back" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.manual_automation_alert_fixture(project: project)
      test_case_id = Ecto.UUID.generate()
      expires_at = DateTime.add(DateTime.utc_now(), 7, :day)

      assert {:ok, _} =
               Holds.place_claim(alert, test_case_id, %{
                 state: "muted",
                 actor_id: 42,
                 expiry_kind: "days",
                 expires_at: expires_at
               })

      assert [claim] = Holds.current_claims(project.id, [test_case_id])[test_case_id]
      assert claim.actor_id == 42
      assert claim.expiry_kind == "days"
      assert claim.expires_at
      assert claim.expiry_runs == nil
    end

    test "re-inserting a row with the same id is idempotent at read time" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      test_case_id = Ecto.UUID.generate()
      now = DateTime.utc_now()
      attrs = %{id: Ecto.UUID.generate(), state: "skipped", placed_at: now, inserted_at: now}

      assert {:ok, _} = Holds.place_claim(alert, test_case_id, attrs)
      assert {:ok, _} = Holds.place_claim(alert, test_case_id, attrs)

      assert [claim] = Holds.current_claims(project.id, [test_case_id])[test_case_id]
      assert claim.state == "skipped"
    end
  end

  describe "withdraw_claim/3" do
    test "withdrawing with no prior claim leaves no live claim" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      test_case_id = Ecto.UUID.generate()

      assert {:ok, _} = Holds.withdraw_claim(alert, test_case_id)

      assert Holds.current_claims(project.id, [test_case_id]) == %{}
    end

    test "withdraw then re-claim is live again" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      test_case_id = Ecto.UUID.generate()

      assert {:ok, _} = Holds.place_claim(alert, test_case_id, %{state: "muted"})
      assert {:ok, _} = Holds.withdraw_claim(alert, test_case_id)
      assert Holds.current_claims(project.id, [test_case_id]) == %{}

      assert {:ok, _} = Holds.place_claim(alert, test_case_id, %{state: "skipped"})

      assert [claim] = Holds.current_claims(project.id, [test_case_id])[test_case_id]
      assert claim.state == "skipped"
    end

    test "one owner's withdraw leaves another owner's claim untouched" do
      project = ProjectsFixtures.project_fixture()
      alert_a = AutomationsFixtures.automation_alert_fixture(project: project)
      alert_b = AutomationsFixtures.automation_alert_fixture(project: project)
      test_case_id = Ecto.UUID.generate()

      assert {:ok, _} = Holds.place_claim(alert_a, test_case_id, %{state: "muted"})
      assert {:ok, _} = Holds.place_claim(alert_b, test_case_id, %{state: "skipped"})
      assert {:ok, _} = Holds.withdraw_claim(alert_a, test_case_id)

      assert [claim] = Holds.current_claims(project.id, [test_case_id])[test_case_id]
      assert claim.alert_id == alert_b.id
      assert claim.state == "skipped"
    end
  end

  describe "live_claims_for_alert/1" do
    test "returns only the alert's live claims" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      other_alert = AutomationsFixtures.automation_alert_fixture(project: project)
      held_id = Ecto.UUID.generate()
      withdrawn_id = Ecto.UUID.generate()

      assert {:ok, _} = Holds.place_claim(alert, held_id, %{state: "skipped"})
      assert {:ok, _} = Holds.place_claim(alert, withdrawn_id, %{state: "skipped"})
      assert {:ok, _} = Holds.withdraw_claim(alert, withdrawn_id)
      assert {:ok, _} = Holds.place_claim(other_alert, Ecto.UUID.generate(), %{state: "muted"})

      assert [claim] = Holds.live_claims_for_alert(alert)
      assert claim.test_case_id == held_id
      assert claim.alert_id == alert.id
    end
  end

  describe "derive/1" do
    test "a human enabled claim wins over a rule skipped claim" do
      claims = [
        %{state: "enabled", actor_id: 7, placed_at: ~N[2026-08-19 10:00:00.000000]},
        %{state: "skipped", actor_id: nil, placed_at: ~N[2026-08-19 09:00:00.000000]}
      ]

      assert %{state: "enabled", held_by: "human", winning_claim: %{actor_id: 7}} =
               Holds.derive(claims)
    end

    test "a human muted claim wins over a rule skipped claim regardless of severity" do
      claims = [
        %{state: "muted", actor_id: 7, placed_at: ~N[2026-08-19 10:00:00.000000]},
        %{state: "skipped", actor_id: nil, placed_at: ~N[2026-08-19 09:00:00.000000]}
      ]

      assert %{state: "muted", held_by: "human"} = Holds.derive(claims)
    end

    test "skipped outranks muted within rules" do
      claims = [
        %{state: "muted", actor_id: nil, placed_at: ~N[2026-08-19 10:00:00.000000]},
        %{state: "skipped", actor_id: nil, placed_at: ~N[2026-08-19 09:00:00.000000]}
      ]

      assert %{state: "skipped", held_by: "rules", winning_claim: %{state: "skipped"}} =
               Holds.derive(claims)
    end

    test "a single rule muted claim derives to muted" do
      claims = [%{state: "muted", actor_id: nil, placed_at: ~N[2026-08-19 10:00:00.000000]}]

      assert %{state: "muted", held_by: "rules"} = Holds.derive(claims)
    end

    test "no claims derives to enabled" do
      assert Holds.derive([]) == %{state: "enabled", held_by: "none", winning_claim: nil}
    end
  end

  describe "derive_and_apply/3" do
    test "placing a rule skipped claim emits one skipped event attributed to the rule" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      test_case = clickhouse_test_case(project)
      test_case_id = test_case.id

      {:ok, _} = Holds.place_claim(alert, test_case_id, %{state: "skipped"})

      assert {:ok, %{changed: [^test_case_id], unchanged_count: 0}} =
               Holds.derive_and_apply(project.id, [test_case_id], alert_id: alert.id)

      assert Tests.get_test_case_states(project.id, [test_case_id])[test_case_id].state == "skipped"

      {events, _meta} = Tests.list_test_case_events(test_case_id)
      assert [event] = events
      assert event.event_type == "skipped"
      assert event.alert_id == alert.id
      assert event.actor_id == nil
    end

    test "withdrawing the only claim returns the state to enabled, attributed to the releasing alert" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      test_case = clickhouse_test_case(project)
      test_case_id = test_case.id

      {:ok, _} = Holds.place_claim(alert, test_case_id, %{state: "skipped"})
      {:ok, _} = Holds.derive_and_apply(project.id, [test_case_id], alert_id: alert.id)

      {:ok, _} = Holds.withdraw_claim(alert, test_case_id)

      assert {:ok, %{changed: [^test_case_id], unchanged_count: 0}} =
               Holds.derive_and_apply(project.id, [test_case_id], alert_id: alert.id)

      assert Tests.get_test_case_states(project.id, [test_case_id])[test_case_id].state == "enabled"

      {events, _meta} = Tests.list_test_case_events(test_case_id)
      assert [latest_event, _skipped_event] = events
      assert latest_event.event_type == "unskipped"
      assert latest_event.alert_id == alert.id
    end

    test "withdrawing a non-winning claim emits no event and leaves the state unchanged" do
      project = ProjectsFixtures.project_fixture()
      skipping_alert = AutomationsFixtures.automation_alert_fixture(project: project)
      muting_alert = AutomationsFixtures.automation_alert_fixture(project: project)
      test_case = clickhouse_test_case(project)
      test_case_id = test_case.id

      {:ok, _} = Holds.place_claim(skipping_alert, test_case_id, %{state: "skipped"})
      {:ok, _} = Holds.place_claim(muting_alert, test_case_id, %{state: "muted"})
      {:ok, _} = Holds.derive_and_apply(project.id, [test_case_id], alert_id: skipping_alert.id)

      {:ok, _} = Holds.withdraw_claim(muting_alert, test_case_id)

      assert {:ok, %{changed: [], unchanged_count: 1}} =
               Holds.derive_and_apply(project.id, [test_case_id], alert_id: muting_alert.id)

      assert Tests.get_test_case_states(project.id, [test_case_id])[test_case_id].state == "skipped"

      {events, _meta} = Tests.list_test_case_events(test_case_id)
      assert [event] = events
      assert event.event_type == "skipped"
      assert event.alert_id == skipping_alert.id
    end

    test "a Manual enabled claim over a rule skipped claim flips to enabled and back on withdraw" do
      project = ProjectsFixtures.project_fixture()
      rule = AutomationsFixtures.automation_alert_fixture(project: project)
      manual = AutomationsFixtures.manual_automation_alert_fixture(project: project)
      test_case = clickhouse_test_case(project)
      test_case_id = test_case.id
      actor_id = 42

      {:ok, _} = Holds.place_claim(rule, test_case_id, %{state: "skipped"})
      {:ok, _} = Holds.derive_and_apply(project.id, [test_case_id], alert_id: rule.id)

      {:ok, _} = Holds.place_claim(manual, test_case_id, %{state: "enabled", actor_id: actor_id})

      assert {:ok, %{changed: [^test_case_id], unchanged_count: 0}} =
               Holds.derive_and_apply(project.id, [test_case_id], alert_id: manual.id, actor_id: actor_id)

      assert Tests.get_test_case_states(project.id, [test_case_id])[test_case_id].state == "enabled"

      {events, _meta} = Tests.list_test_case_events(test_case_id)
      assert [enable_event | _] = events
      assert enable_event.event_type == "unskipped"
      assert enable_event.actor_id == actor_id
      assert enable_event.alert_id == manual.id

      {:ok, _} = Holds.withdraw_claim(manual, test_case_id, actor_id: actor_id)

      assert {:ok, %{changed: [^test_case_id], unchanged_count: 0}} =
               Holds.derive_and_apply(project.id, [test_case_id], alert_id: manual.id, actor_id: actor_id)

      assert Tests.get_test_case_states(project.id, [test_case_id])[test_case_id].state == "skipped"

      {events, _meta} = Tests.list_test_case_events(test_case_id)
      assert [reskip_event | _] = events
      assert reskip_event.event_type == "skipped"
      assert reskip_event.actor_id == actor_id
      assert reskip_event.alert_id == manual.id
      assert length(events) == 3
    end

    test "is idempotent: a second derivation with no claim changes emits nothing" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      test_case = clickhouse_test_case(project)
      test_case_id = test_case.id

      {:ok, _} = Holds.place_claim(alert, test_case_id, %{state: "muted"})

      assert {:ok, %{changed: [^test_case_id], unchanged_count: 0}} =
               Holds.derive_and_apply(project.id, [test_case_id], alert_id: alert.id)

      assert {:ok, %{changed: [], unchanged_count: 1}} =
               Holds.derive_and_apply(project.id, [test_case_id], alert_id: alert.id)

      {events, _meta} = Tests.list_test_case_events(test_case_id)
      assert [event] = events
      assert event.event_type == "muted"
    end

    test "a state change broadcasts on the test_case topic exactly once; an unchanged derivation broadcasts nothing" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      test_case = clickhouse_test_case(project)
      test_case_id = test_case.id

      :ok = Tuist.PubSub.subscribe(Tests.test_case_topic(test_case_id))

      {:ok, _} = Holds.place_claim(alert, test_case_id, %{state: "skipped"})
      {:ok, _} = Holds.derive_and_apply(project.id, [test_case_id], alert_id: alert.id)

      assert_receive {:test_case_updated, %{id: ^test_case_id, state: "skipped"}}, 500
      refute_receive {:test_case_updated, _}, 100

      {:ok, _} = Holds.derive_and_apply(project.id, [test_case_id], alert_id: alert.id)

      refute_receive {:test_case_updated, _}, 100
    end

    test "two claims and one derivation emit a single transition to the most severe state" do
      project = ProjectsFixtures.project_fixture()
      muting_alert = AutomationsFixtures.automation_alert_fixture(project: project)
      skipping_alert = AutomationsFixtures.automation_alert_fixture(project: project)
      test_case = clickhouse_test_case(project)
      test_case_id = test_case.id

      {:ok, _} = Holds.place_claim(muting_alert, test_case_id, %{state: "muted"})
      {:ok, _} = Holds.place_claim(skipping_alert, test_case_id, %{state: "skipped"})

      assert {:ok, %{changed: [^test_case_id], unchanged_count: 0}} =
               Holds.derive_and_apply(project.id, [test_case_id], alert_id: skipping_alert.id)

      assert Tests.get_test_case_states(project.id, [test_case_id])[test_case_id].state == "skipped"

      {events, _meta} = Tests.list_test_case_events(test_case_id)
      assert [event] = events
      assert event.event_type == "skipped"
    end

    test "reports a test case whose state write errored as failed, excluded from unchanged_count" do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      test_case_id = Ecto.UUID.generate()

      {:ok, _} = Holds.place_claim(alert, test_case_id, %{state: "skipped"})

      expect(Tests, :update_test_case, fn ^test_case_id, %{state: "skipped"}, _opts ->
        {:error, :not_found}
      end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, %{changed: [], failed: [^test_case_id], unchanged_count: 0}} =
                   Holds.derive_and_apply(project.id, [test_case_id], alert_id: alert.id)
        end)

      assert log =~ test_case_id
      assert log =~ "not_found"
    end
  end

  describe "changeset validation" do
    setup do
      project = ProjectsFixtures.project_fixture()
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
      %{alert: alert, test_case_id: Ecto.UUID.generate()}
    end

    test "rejects an invalid state", %{alert: alert, test_case_id: test_case_id} do
      assert {:error, changeset} = Holds.place_claim(alert, test_case_id, %{state: "paused"})
      assert "is invalid" in errors_on(changeset).state
    end

    test "rejects an enabled claim without an actor", %{test_case_id: test_case_id} do
      manual = AutomationsFixtures.manual_automation_alert_fixture()

      assert {:error, changeset} = Holds.place_claim(manual, test_case_id, %{state: "enabled"})
      assert "enabled claims require an actor" in errors_on(changeset).state

      assert {:ok, _} = Holds.place_claim(manual, test_case_id, %{state: "enabled", actor_id: 42})
    end

    test "rejects human-tier claims placed through a standard alert", %{alert: alert, test_case_id: test_case_id} do
      assert {:error, :manual_alert_required} =
               Holds.place_claim(alert, test_case_id, %{state: "muted", actor_id: 42})

      assert {:error, :manual_alert_required} = Holds.place_claim(alert, test_case_id, %{state: "enabled"})
    end

    test "rejects an invalid expiry kind", %{alert: alert, test_case_id: test_case_id} do
      assert {:error, changeset} =
               Holds.place_claim(alert, test_case_id, %{state: "muted", expiry_kind: "weeks"})

      assert "is invalid" in errors_on(changeset).expiry_kind
    end

    test "rejects a days expiry without expires_at", %{alert: alert, test_case_id: test_case_id} do
      assert {:error, changeset} =
               Holds.place_claim(alert, test_case_id, %{state: "muted", expiry_kind: "days"})

      assert "is required for a days expiry" in errors_on(changeset).expires_at
    end

    test "rejects a days expiry carrying expiry_runs", %{alert: alert, test_case_id: test_case_id} do
      assert {:error, changeset} =
               Holds.place_claim(alert, test_case_id, %{
                 state: "muted",
                 expiry_kind: "days",
                 expires_at: DateTime.utc_now(),
                 expiry_runs: 10
               })

      assert "must be nil for a days expiry" in errors_on(changeset).expiry_runs
    end

    test "rejects a runs expiry without expiry_runs", %{alert: alert, test_case_id: test_case_id} do
      assert {:error, changeset} =
               Holds.place_claim(alert, test_case_id, %{state: "muted", expiry_kind: "runs"})

      assert "is required for a runs expiry" in errors_on(changeset).expiry_runs
    end

    test "rejects a none expiry carrying expiry fields", %{alert: alert, test_case_id: test_case_id} do
      assert {:error, changeset} =
               Holds.place_claim(alert, test_case_id, %{state: "muted", expires_at: DateTime.utc_now()})

      assert "none expiry does not take expiry fields" in errors_on(changeset).expiry_kind
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
