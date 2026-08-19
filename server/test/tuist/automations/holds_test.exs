defmodule Tuist.Automations.HoldsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Automations.Holds
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "place_claim/3 + current_claims/2" do
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
      alert = AutomationsFixtures.automation_alert_fixture(project: project)
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

    test "rejects an enabled claim without an actor", %{alert: alert, test_case_id: test_case_id} do
      assert {:error, changeset} = Holds.place_claim(alert, test_case_id, %{state: "enabled"})
      assert "enabled claims require an actor" in errors_on(changeset).state

      assert {:ok, _} = Holds.place_claim(alert, test_case_id, %{state: "enabled", actor_id: 42})
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
end
