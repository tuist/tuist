defmodule Tuist.Pulse.InvestigationsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Pulse.Investigations
  alias Tuist.Pulse.Investigations.Brief
  alias Tuist.Pulse.Investigations.BriefStep
  alias Tuist.Pulse.Investigations.Investigation
  alias Tuist.Pulse.Symptoms
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.PulseFixtures

  setup do
    user = AccountsFixtures.user_fixture()
    account = AccountsFixtures.organization_fixture(creator: user).account
    stub(Environment, :pulse_config, fn -> [account_id: account.id] end)
    stub(Tuist.FeatureFlags, :pulse_enabled?, fn _ -> true end)
    %{user: user, account: account}
  end

  defp id(i), do: "0193a1f0-0000-7000-8000-" <> String.pad_leading("#{i}", 12, "0")

  defp revision(i, seq, overrides) do
    PulseFixtures.symptom_revision(
      Map.merge(
        %{
          "symptom_id" => id(i),
          "seq" => seq,
          "root" => %{"root_symptom_id" => id(i), "member_symptom_ids" => [], "shared_cause" => false}
        },
        overrides
      )
    )
  end

  defp investigations, do: Repo.all(from(i in Investigation, order_by: i.change_seq))

  describe "triggers" do
    test "a root symptom opened at page tier requests investigation without generating a brief", %{
      user: user,
      account: account
    } do
      {:ok, _} = PulseFixtures.mirror_symptoms(account, [revision(1, 1, %{"tier" => "page"})])

      assert [%Investigation{trigger: :opened_page} = investigation] = investigations()
      assert investigation.request_id == Investigations.request_id(id(1), 1)
      assert {:ok, %{investigation: ^investigation, brief: nil}} = Investigations.get(user, account, id(1))
      assert Repo.aggregate(Brief, :count) == 0
      assert Repo.aggregate(BriefStep, :count) == 0

      assert %{
               "investigations" => [
                 %{"brief_id" => nil, "brief_revision" => nil, "steps_taken" => [], "reverted" => false}
               ]
             } = Symptoms.state_changes(0)
    end

    test "non-root symptoms retain the plain investigation trigger without a brief", %{account: account} do
      other_root = %{"root_symptom_id" => id(9), "member_symptom_ids" => [], "shared_cause" => false}
      {:ok, _} = PulseFixtures.mirror_symptoms(account, [revision(1, 1, %{"tier" => "page", "root" => other_root})])

      assert [%Investigation{trigger: :brief}] = investigations()
      assert Repo.aggregate(Brief, :count) == 0
    end

    test "tiers and transitions", %{account: account} do
      {:ok, _} =
        PulseFixtures.mirror_symptoms(account, [
          revision(1, 1, %{"tier" => "audit"}),
          revision(2, 2, %{"tier" => "page", "transition" => "escalated"}),
          revision(3, 3, %{"tier" => "page", "transition" => "annotated"})
        ])

      assert [%Investigation{symptom_id: symptom_id, trigger: :escalated_page}] = investigations()
      assert symptom_id == id(2)
    end

    test "triggers come from each revision in a sync, not only the symptom's latest", %{account: account} do
      {:ok, _} =
        PulseFixtures.mirror_symptoms(account, [
          revision(1, 1, %{"tier" => "page"}),
          revision(1, 2, %{"tier" => "page", "transition" => "annotated", "revision" => 2}),
          revision(2, 3, %{"tier" => "page", "transition" => "escalated"}),
          revision(2, 4, %{"tier" => "page", "transition" => "annotated", "revision" => 2})
        ])

      assert [
               %Investigation{trigger: :opened_page, request_id: opened_request},
               %Investigation{trigger: :escalated_page, request_id: escalated_request}
             ] = investigations()

      assert opened_request == Investigations.request_id(id(1), 1)
      assert escalated_request == Investigations.request_id(id(2), 3)
    end

    test "several qualifying revisions of one symptom in a sync write one request", %{account: account} do
      {:ok, _} =
        PulseFixtures.mirror_symptoms(account, [
          revision(1, 1, %{"tier" => "page"}),
          revision(1, 2, %{"tier" => "page", "transition" => "reopened", "revision" => 2})
        ])

      assert [%Investigation{trigger: :opened_page}] = investigations()
      assert Repo.aggregate(Brief, :count) == 0
    end

    test "a reopened root requests investigation", %{account: account} do
      {:ok, _} =
        PulseFixtures.mirror_symptoms(account, [revision(1, 1, %{"tier" => "page", "transition" => "reopened"})])

      assert [%Investigation{trigger: :reopened}] = investigations()
    end

    test "board roots ranked first or second request investigation, once per push", %{
      account: account
    } do
      board = fn rank -> %{"date" => "2026-11-16", "rank" => rank, "nats" => 7.2} end

      # Opened at board tier: no score ranking on the server.
      {:ok, _} =
        PulseFixtures.mirror_symptoms(account, [
          revision(1, 1, %{"score" => 1.0, "transition" => "annotated"}),
          revision(2, 2, %{"score" => 9.0, "transition" => "annotated"}),
          revision(3, 3, %{"score" => 5.0, "transition" => "annotated"})
        ])

      assert investigations() == []

      {:ok, _} =
        PulseFixtures.mirror_symptoms(account, [
          revision(1, 4, %{"revision" => 2, "transition" => "annotated", "board" => board.(1)}),
          revision(3, 5, %{"revision" => 2, "transition" => "annotated", "board" => board.(2)}),
          revision(2, 6, %{"revision" => 2, "transition" => "annotated", "board" => board.(3)})
        ])

      assert [%{symptom_id: first, trigger: :board_top_two}, %{symptom_id: second, trigger: :board_top_two}] =
               investigations()

      assert {first, second} == {id(1), id(3)}

      # A later revision carrying the same push does not write another.
      {:ok, _} =
        PulseFixtures.mirror_symptoms(account, [
          revision(1, 7, %{"revision" => 3, "transition" => "annotated", "board" => board.(1)})
        ])

      assert length(investigations()) == 2
    end

    test "merged symptoms join the root's latest row", %{account: account} do
      {:ok, _} = PulseFixtures.mirror_symptoms(account, [revision(1, 1, %{"tier" => "page"})])
      [investigation] = investigations()

      {:ok, _} =
        PulseFixtures.mirror_symptoms(account, [
          revision(5, 2, %{
            "state" => "merged",
            "transition" => "merged",
            "merged_into" => id(1),
            "root" => %{"root_symptom_id" => id(1)}
          })
        ])

      assert [%Investigation{id: same_id, member_symptom_ids: members}] = investigations()
      assert same_id == investigation.id
      assert members == [id(5)]
    end

    test "a replayed revision never writes a second request", %{account: account} do
      revision = revision(1, 1, %{"tier" => "page"})
      {:ok, _} = PulseFixtures.mirror_symptoms(account, [revision])
      Repo.update_all(Tuist.Pulse.SymptomCursor, set: [seq: 0])
      {:ok, _} = PulseFixtures.mirror_symptoms(account, [revision])

      assert [_] = investigations()
      assert Repo.aggregate(Brief, :count) == 0
    end

    test "a Pulse-authorized person requests investigation of the root without generated steps", %{
      user: user,
      account: account
    } do
      {:ok, _} =
        PulseFixtures.mirror_symptoms(account, [
          revision(1, 1, %{"tier" => "audit"}),
          revision(2, 2, %{"tier" => "audit", "root" => %{"root_symptom_id" => id(1)}})
        ])

      assert {:ok, %Investigation{symptom_id: root, trigger: :person, requested_by_id: user_id}} =
               Investigations.request_brief(user, account, id(2))

      assert root == id(1) and user_id == user.id
      assert {:ok, %Investigation{}} = Investigations.request_brief(user, account, id(1))
      assert length(investigations()) == 2
      assert Repo.aggregate(Brief, :count) == 0
      assert Repo.aggregate(BriefStep, :count) == 0

      stranger = AccountsFixtures.user_fixture()
      assert {:error, :forbidden} = Investigations.request_brief(stranger, account, id(1))
      assert {:error, :not_found} = Investigations.request_brief(user, account, id(7))
    end

    test "a sync draws the state lock before reading what exists", %{user: user, account: account} do
      {:ok, _} = PulseFixtures.mirror_symptoms(account, [revision(1, 1, %{"tier" => "audit"})])
      {:ok, _} = Investigations.request_brief(user, account, id(1))
      handler = "pulse-investigation-order-#{System.unique_integer()}"
      :telemetry.attach(handler, [:tuist, :repo, :query], &__MODULE__.record_query/4, self())
      on_exit(fn -> :telemetry.detach(handler) end)

      {:ok, _} = PulseFixtures.mirror_symptoms(account, [revision(1, 2, %{"tier" => "page", "revision" => 2})])

      # The first touch of pulse_investigations comes after a change_seq draw,
      # which holds the state lock, so a person's concurrent request is seen.
      assert [:draw | _] = Enum.drop_while(queries(), &(&1 == :other))
      assert [_, _] = investigations()
    end
  end

  def record_query(_event, _measurements, metadata, test) do
    if self() == test do
      kind =
        cond do
          metadata[:query] =~ "pulse_symptom_state_changes" -> :draw
          metadata[:source] == "pulse_investigations" -> :read
          true -> :other
        end

      send(test, {:query, kind})
    end
  end

  defp queries do
    receive do
      {:query, kind} -> [kind | queries()]
    after
      0 -> []
    end
  end

  describe "existing briefs" do
    setup %{account: account} do
      {:ok, _} = PulseFixtures.mirror_symptoms(account, [revision(1, 1, %{"tier" => "page"})])
      [investigation] = investigations()

      brief =
        Repo.insert!(%Brief{
          account_id: account.id,
          symptom_id: id(1),
          investigation_id: investigation.id,
          version: 1
        })

      Repo.insert!(%BriefStep{
        account_id: account.id,
        brief_id: brief.id,
        position: 0,
        kind: :rollback_server,
        title: "Previously recorded step",
        detail: "Retained for historical feedback",
        command: "previous-command",
        reverse_command: "previous-undo",
        safety: :unknown
      })

      %{investigation: investigation}
    end

    test "only Pulse-authorized people set step status", %{user: user, account: account, investigation: investigation} do
      {:ok, %{brief: %{steps: [step | _]}}} = Investigations.get(user, account, id(1))
      before = Repo.reload!(investigation).change_seq

      stranger = AccountsFixtures.user_fixture()
      assert {:error, :forbidden} = Investigations.set_step_status(stranger, account, step.id, "taken")
      assert {:error, :invalid_params} = Investigations.set_step_status(user, account, step.id, "deployed")
      assert Repo.reload!(step).status == :proposed

      assert :ok = Investigations.set_step_status(user, account, step.id, "helped")
      assert %{status: :helped, status_by_id: user_id} = Repo.reload!(step)
      assert user_id == user.id
      assert Repo.reload!(investigation).change_seq > before

      other = AccountsFixtures.organization_fixture(creator: user).account
      assert {:error, :forbidden} = Investigations.set_step_status(user, other, step.id, "taken")
    end

    test "state rows carry the brief, the steps taken and reverted", %{user: user, account: account} do
      {:ok, %{brief: brief}} = Investigations.get(user, account, id(1))
      [step | _] = brief.steps

      assert %{"investigations" => [%{"reverted" => false, "steps_taken" => []}]} = Symptoms.state_changes(0)

      for status <- ~w(taken helped did_not_help) do
        :ok = Investigations.set_step_status(user, account, step.id, status)
        %{"investigations" => [row], "next" => next} = Symptoms.state_changes(0)
        assert row["symptom_id"] == id(1)
        assert row["trigger"] == "opened_page"
        assert row["brief_id"] == brief.id and row["brief_revision"] == 1
        assert [%{"status" => ^status, "kind" => _}] = row["steps_taken"]
        assert row["reverted"]
        assert next == row["change_seq"]
        refute Map.has_key?(row, "status") or Map.has_key?(row, "thread_id")
      end

      :ok = Investigations.set_step_status(user, account, step.id, "proposed")
      assert %{"investigations" => [%{"reverted" => false}]} = Symptoms.state_changes(0)

      {:ok, _} = Investigations.request_brief(user, account, id(1))
      assert {:ok, %{brief: retained}} = Investigations.get(user, account, id(1))
      assert retained.id == brief.id and retained.version == 1
      assert Enum.map(retained.steps, & &1.id) == [step.id]
      assert Repo.aggregate(Brief, :count) == 1
      assert Repo.aggregate(BriefStep, :count) == 1
    end
  end
end
