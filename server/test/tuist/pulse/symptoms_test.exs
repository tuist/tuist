defmodule Tuist.Pulse.SymptomsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.MCP.Events.Subscription
  alias Tuist.MCP.Events.Workers.FanoutWorker
  alias Tuist.Pulse.Symptom
  alias Tuist.Pulse.SymptomOutcome
  alias Tuist.Pulse.SymptomRevision
  alias Tuist.Pulse.Symptoms
  alias Tuist.Pulse.SymptomStateEvent
  alias Tuist.Pulse.Workers.SyncSymptomsWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.PulseFixtures

  @a "0193a1f0-0000-7000-8000-00000000000a"
  @b "0193a1f0-0000-7000-8000-00000000000b"
  @c "0193a1f0-0000-7000-8000-00000000000c"
  @d "0193a1f0-0000-7000-8000-00000000000d"
  @e "0193a1f0-0000-7000-8000-00000000000e"
  @f "0193a1f0-0000-7000-8000-00000000000f"
  @g "0193a1f0-0000-7000-8000-000000000010"

  setup do
    user = AccountsFixtures.user_fixture()
    account = AccountsFixtures.organization_fixture(creator: user).account
    stub(Environment, :pulse_config, fn -> [account_id: account.id] end)
    stub(Tuist.FeatureFlags, :pulse_enabled?, fn _ -> true end)
    %{user: user, account: account}
  end

  defp revision(id, seq, revision, overrides \\ %{}) do
    PulseFixtures.symptom_revision(Map.merge(%{"symptom_id" => id, "seq" => seq, "revision" => revision}, overrides))
  end

  # The `after` the next sync asks the evaluator for: the stored cursor.
  defp requested_after(account) do
    test = self()

    stub(Req, :get, fn _url, opts ->
      send(test, {:after, opts[:params][:after]})
      {:ok, %Req.Response{status: 200, body: %{"revisions" => [], "next" => opts[:params][:after]}}}
    end)

    {:ok, _} = Symptoms.sync(account)

    receive do
      {:after, seq} -> seq
    after
      0 -> nil
    end
  end

  describe "sync/1" do
    @tag :tmp_dir
    test "rereads the projected token after rotation and fails closed when it disappears", %{
      account: account,
      tmp_dir: dir
    } do
      path = Path.join(dir, "token")
      stub(Environment, :symptoms_config, fn -> [base_url: "https://symptoms.internal", token_path: path] end)

      for token <- ["first-bound-token", "rotated-bound-token"] do
        File.write!(path, token <> "\n")

        expect(Req, :get, fn "https://symptoms.internal/api/v1/symptoms/log", opts ->
          assert opts[:auth] == {:bearer, token}
          assert opts[:redirect] == false
          {:ok, %Req.Response{status: 200, body: %{"revisions" => []}}}
        end)

        assert {:ok, %{applied: 0}} = Symptoms.sync(account)
      end

      reject(&Req.get/2)
      File.write!(path, "\n")
      assert {:error, :unavailable} = Symptoms.sync(account)
      File.rm!(path)
      assert {:error, :unavailable} = Symptoms.sync(account)
    end

    test "applies a revision only when it is newer, and keeps every revision in history", %{account: account} do
      revisions = [
        # Keys the mirror does not know are ignored.
        revision(@a, 1, 1, %{"unknown_key" => %{"a" => 1}}),
        # Revision 3 arrives before revision 2.
        revision(@a, 2, 3, %{"state" => "resolved", "transition" => "resolved", "resolved_at" => "2026-11-16T13:00:00Z"}),
        revision(@a, 3, 2, %{"transition" => "annotated", "title" => "Stale title"})
      ]

      assert {:ok, %{applied: 2, superseded: 1}} = PulseFixtures.mirror_symptoms(account, revisions)

      assert %Symptom{revision: 3, state: :resolved, seq: 2, title: "Errors on POST /api/runs"} = Repo.get!(Symptom, @a)

      assert SymptomRevision |> order_by(:revision) |> select([r], {r.revision, r.seq}) |> Repo.all() ==
               [{1, 1}, {2, 3}, {3, 2}]

      # A replay of the same log changes nothing.
      Repo.update_all(Tuist.Pulse.SymptomCursor, set: [seq: 0])
      assert {:ok, %{applied: 0, superseded: 3}} = PulseFixtures.mirror_symptoms(account, revisions)
      assert %Symptom{revision: 3} = Repo.get!(Symptom, @a)
      assert Repo.aggregate(SymptomRevision, :count) == 3
    end

    test "stops at an unknown schema major and leaves the cursor before it", %{account: account} do
      revisions = [
        revision(@a, 1, 1),
        revision(@b, 2, 1, %{"schema_version" => "2.0"}),
        revision(@a, 3, 2, %{"schema_version" => "1.7", "transition" => "escalated", "tier" => "page"})
      ]

      assert {:error, {:unsupported_schema_version, "2.0"}} = PulseFixtures.mirror_symptoms(account, revisions)
      assert %Symptom{revision: 1} = Repo.get!(Symptom, @a)
      assert Repo.get(Symptom, @b) == nil
      assert requested_after(account) == 1

      # A known major with a newer minor applies.
      assert {:ok, %{applied: 2}} =
               PulseFixtures.mirror_symptoms(account, List.replace_at(revisions, 1, revision(@b, 2, 1)))

      assert %Symptom{revision: 2, tier: :page} = Repo.get!(Symptom, @a)
    end

    test "advances the cursor only over handled revisions", %{account: account} do
      assert {:ok, _} = PulseFixtures.mirror_symptoms(account, [revision(@a, 4, 1), revision(@a, 9, 2)])
      assert requested_after(account) == 9

      # A malformed revision is not passed over.
      assert {:error, {:malformed_revision, 10}} =
               PulseFixtures.mirror_symptoms(account, [revision(@a, 10, 3, %{"state" => "unknown"})])

      assert requested_after(account) == 9

      # Neither is a page the evaluator failed to serve.
      stub(Req, :get, fn _url, _opts -> {:ok, %Req.Response{status: 503, body: ""}} end)
      assert {:error, {:http_status, 503}} = Symptoms.sync(account)
      assert requested_after(account) == 9
    end

    test "is not configured without a URL and token path", %{account: account} do
      stub(Environment, :symptoms_config, fn -> [] end)
      reject(&Req.get/2)
      assert {:error, :not_configured} = Symptoms.sync(account)
      assert :ok = perform_job(SyncSymptomsWorker, %{})
    end

    test "announces openings and reopenings at board or page tier only", %{user: user, account: account} do
      subscribe_to_symptoms(user, account)

      ids = for i <- 1..6, do: "0193a1f0-0000-7000-8000-00000000010#{i}"

      revisions = [
        revision(Enum.at(ids, 0), 1, 1, %{"tier" => "board"}),
        revision(Enum.at(ids, 1), 2, 1, %{"tier" => "page"}),
        revision(Enum.at(ids, 2), 3, 1, %{"tier" => "audit"}),
        revision(Enum.at(ids, 3), 4, 1, %{"tier" => "page", "transition" => "escalated"}),
        revision(Enum.at(ids, 4), 5, 1, %{"tier" => "board", "transition" => "annotated"}),
        revision(Enum.at(ids, 4), 6, 2, %{"tier" => "board", "transition" => "reopened"}),
        # A late `opened` older than what the mirror holds is not news.
        revision(Enum.at(ids, 4), 7, 1, %{"tier" => "board"})
      ]

      assert {:ok, _} = PulseFixtures.mirror_symptoms(account, revisions)

      announced =
        [worker: FanoutWorker]
        |> all_enqueued()
        |> Enum.map(&{&1.args["source_id"], Map.take(&1.args, ~w(tier service kind key))})
        |> Enum.sort()

      entity = %{"service" => "tuist-server", "kind" => "route", "key" => "POST /api/runs"}

      assert announced == [
               {"#{Enum.at(ids, 0)}:1", Map.put(entity, "tier", "board")},
               {"#{Enum.at(ids, 1)}:1", Map.put(entity, "tier", "page")},
               {"#{Enum.at(ids, 4)}:2", Map.put(entity, "tier", "board")}
             ]
    end

    test "a fan-out failure rolls back the mirror and cursor so retry delivers each opening once", %{
      user: user,
      account: account
    } do
      subscribe_to_symptoms(user, account)
      revisions = [revision(@a, 1, 1, %{"tier" => "board"}), revision(@b, 2, 1, %{"tier" => "page"})]

      stub(Oban, :insert_all, fn jobs ->
        Mimic.call_original(Oban, :insert_all, [jobs])
        Repo.rollback(:fanout_unavailable)
      end)

      assert {:error, :fanout_unavailable} = PulseFixtures.mirror_symptoms(account, revisions)
      assert requested_after(account) == 0
      assert Repo.get(Symptom, @a) == nil
      assert Repo.get(Symptom, @b) == nil
      assert Repo.aggregate(SymptomRevision, :count) == 0
      assert all_enqueued(worker: FanoutWorker) == []

      stub(Oban, :insert_all, fn jobs -> Mimic.call_original(Oban, :insert_all, [jobs]) end)
      assert {:ok, %{applied: 2}} = PulseFixtures.mirror_symptoms(account, revisions)
      assert requested_after(account) == 2
      assert {:ok, %{applied: 0}} = PulseFixtures.mirror_symptoms(account, revisions)

      assert [worker: FanoutWorker] |> all_enqueued() |> Enum.map(& &1.args["source_id"]) |> Enum.sort() ==
               ["#{@a}:1", "#{@b}:1"]
    end
  end

  describe "ack/3 and mute/6" do
    setup %{account: account} do
      {:ok, _} = PulseFixtures.mirror_symptoms(account, [revision(@a, 1, 1, %{"tier" => "audit"})])
      :ok
    end

    test "need Pulse access", %{user: user, account: account} do
      outsider = AccountsFixtures.user_fixture()
      expires_at = DateTime.add(DateTime.utc_now(), 3600)

      assert {:error, :forbidden} = Symptoms.ack(outsider, account, @a)
      assert {:error, :forbidden} = Symptoms.mute(outsider, account, @a, "latency", expires_at)
      assert %{"acks" => [], "mutes" => []} = Symptoms.state_changes(0)

      # Pulse runs only for the configured account, even for its members.
      stub(Tuist.FeatureFlags, :pulse_enabled?, fn _ -> false end)
      assert {:error, :forbidden} = Symptoms.ack(user, account, @a)
    end

    test "reject unknown symptoms, phenomena and expiries", %{user: user, account: account} do
      now = DateTime.utc_now()
      assert {:error, :not_found} = Symptoms.ack(user, account, @b)
      assert {:error, :invalid_params} = Symptoms.mute(user, account, @a, "saturation", DateTime.add(now, 3600))
      assert {:error, :invalid_params} = Symptoms.mute(user, account, @a, "latency", DateTime.add(now, -1))
      assert {:error, :invalid_params} = Symptoms.mute(user, account, @a, "latency", DateTime.add(now, 31 * 86_400))
    end

    test "are read back in change order with a cursor", %{user: user, account: account} do
      expires_at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)
      assert :ok = Symptoms.ack(user, account, @a)
      assert :ok = Symptoms.mute(user, account, @a, "latency", expires_at)

      assert %{"acks" => [%{"symptom_id" => @a, "revision" => 1, "change_seq" => ack_seq}], "next" => next} =
               state = Symptoms.state_changes(0)

      assert [%{"phenomenon" => "latency", "change_seq" => mute_seq} = mute] = state["mutes"]

      assert mute["entity"] == %{
               "environment" => "production",
               "service" => "tuist-server",
               "kind" => "route",
               "key" => "POST /api/runs"
             }

      assert mute["expires_at"] == DateTime.to_iso8601(expires_at)
      assert state["investigations"] == []
      assert ack_seq < mute_seq and next == mute_seq

      assert %{"acks" => [], "mutes" => [], "outcomes" => [], "next" => ^next} = Symptoms.state_changes(next)

      # Muting the same scope again moves its expiry and its place in the order.
      assert :ok = Symptoms.mute(user, account, @a, "latency", DateTime.add(expires_at, 3600))
      assert %{"mutes" => [%{"expires_at" => later}], "acks" => []} = Symptoms.state_changes(next)
      assert later == DateTime.to_iso8601(DateTime.add(expires_at, 3600))
    end

    test "confirmed outcomes are read back", %{user: user, account: account} do
      Repo.insert!(%SymptomOutcome{
        account_id: account.id,
        symptom_id: @a,
        user_id: user.id,
        outcome: :bad,
        change_seq: 5
      })

      assert %{"outcomes" => [%{"symptom_id" => @a, "outcome" => "bad"}], "next" => 5} = Symptoms.state_changes(0)
    end
  end

  describe "history/2" do
    setup %{account: account} do
      {:ok, _} = PulseFixtures.mirror_symptoms(account, [revision(@a, 1, 1, %{"tier" => "audit"})])
      :ok
    end

    test "keeps every ack, mute and outcome with the person who made it, though the state rows are overwritten", %{
      user: user,
      account: account
    } do
      other = AccountsFixtures.user_fixture()

      :ok =
        Tuist.Accounts.add_user_to_organization(other, Repo.get!(Tuist.Accounts.Organization, account.organization_id))

      now = DateTime.utc_now()
      day = DateTime.add(now, 86_400)
      month = DateTime.add(now, 30 * 86_400)

      assert :ok = Symptoms.mute(user, account, @a, "latency", day, now)
      assert :ok = Symptoms.confirm_outcome(user, account, @a, "bad")
      # The second member silences paging for 30 days and flips the outcome;
      # the state rows now name only them.
      assert :ok = Symptoms.mute(other, account, @a, "latency", month, now)
      assert :ok = Symptoms.confirm_outcome(other, account, @a, "fine")
      assert :ok = Symptoms.ack(other, account, @a)

      assert Repo.one!(from(m in Tuist.Pulse.SymptomMute, select: m.user_id)) == other.id

      assert [
               %{kind: :mute, user_id: first_muter, details: first_mute},
               %{kind: :outcome, user_id: first_judge, details: %{"outcome" => "bad", "previous" => nil}},
               %{kind: :mute, user_id: second_muter, details: second_mute},
               %{kind: :outcome, user_id: second_judge, details: %{"outcome" => "fine", "previous" => "bad"}},
               %{kind: :ack, user_id: acker, details: %{"revision" => 1}}
             ] = events = Symptoms.history(account, @a)

      assert {first_muter, first_judge} == {user.id, user.id}
      assert {second_muter, second_judge, acker} == {other.id, other.id, other.id}
      assert first_mute["phenomenon"] == "latency" and first_mute["previous_expires_at"] == nil
      assert first_mute["expires_at"] == day |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      assert second_mute["expires_at"] == month |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      assert second_mute["previous_expires_at"] == first_mute["expires_at"]
      # Each event carries the change_seq of the state row it produced.
      seqs = Enum.map(events, & &1.change_seq)
      assert seqs == Enum.sort(seqs) and length(Enum.uniq(seqs)) == 5
    end

    test "is append-only in the database", %{user: user, account: account} do
      assert :ok = Symptoms.ack(user, account, @a)

      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        Repo.update_all(SymptomStateEvent, set: [user_id: nil])
      end

      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        Repo.delete_all(SymptomStateEvent)
      end

      # Deleting the account still removes its trail.
      Repo.delete!(account)
      assert Repo.aggregate(SymptomStateEvent, :count) == 0
    end

    test "a refused change records nothing", %{account: account} do
      outsider = AccountsFixtures.user_fixture()
      assert {:error, :forbidden} = Symptoms.ack(outsider, account, @a)
      assert Symptoms.history(account, @a) == []
    end
  end

  describe "confirm_outcome/4" do
    setup %{account: account} do
      {:ok, _} = PulseFixtures.mirror_symptoms(account, [revision(@a, 1, 1, %{"tier" => "audit"})])
      :ok
    end

    test "needs Pulse access, a known symptom and bad or fine", %{user: user, account: account} do
      outsider = AccountsFixtures.user_fixture()
      assert {:error, :forbidden} = Symptoms.confirm_outcome(outsider, account, @a, "bad")
      assert {:error, :not_found} = Symptoms.confirm_outcome(user, account, @b, "bad")
      assert {:error, :invalid_params} = Symptoms.confirm_outcome(user, account, @a, "worse")

      stub(Tuist.FeatureFlags, :pulse_enabled?, fn _ -> false end)
      assert {:error, :forbidden} = Symptoms.confirm_outcome(user, account, @a, "bad")
      assert Repo.aggregate(SymptomOutcome, :count) == 0
    end

    test "is one row per symptom, read back in change order", %{user: user, account: account} do
      assert :ok = Symptoms.ack(user, account, @a)
      assert :ok = Symptoms.confirm_outcome(user, account, @a, "bad")
      assert :ok = Symptoms.mute(user, account, @a, "latency", DateTime.add(DateTime.utc_now(), 3600))

      assert %{
               "acks" => [%{"change_seq" => ack_seq}],
               "outcomes" => [%{"symptom_id" => @a, "outcome" => "bad", "change_seq" => outcome_seq}],
               "mutes" => [%{"change_seq" => mute_seq}]
             } = Symptoms.state_changes(0)

      assert ack_seq < outcome_seq and outcome_seq < mute_seq
      assert %SymptomOutcome{outcome: :bad, user_id: user_id} = Repo.get_by!(SymptomOutcome, symptom_id: @a)
      assert user_id == user.id

      # Confirming again replaces the outcome and moves it past the cursor.
      assert :ok = Symptoms.confirm_outcome(user, account, @a, "fine")
      assert Repo.aggregate(SymptomOutcome, :count) == 1

      assert %{"outcomes" => [%{"outcome" => "fine", "change_seq" => later}], "next" => later} =
               Symptoms.state_changes(mute_seq)

      assert later > mute_seq
    end
  end

  describe "analytics/4" do
    test "counts symptoms from when they reach board or page tier on", %{user: user, account: account} do
      # The window is the 24 hours ending at 13:00, so it starts 23.5 hours
      # before `now`, and the previous one 47.5 hours before.
      now = ~U[2026-11-16 12:30:00Z]
      at = fn hours -> now |> DateTime.add(-hours * 3600) |> DateTime.to_iso8601() end
      audit = fn overrides -> Map.put(overrides, "tier", "audit") end

      {:ok, _} =
        PulseFixtures.mirror_symptoms(account, [
          # Reached the board in the previous window and drops back to audit
          # before it. Its resolution in this window counts, though only its
          # audit revision precedes the previous window.
          revision(@g, 1, 1, %{"updated_at" => at.(50)}),
          revision(@g, 2, 2, audit.(%{"transition" => "deescalated", "updated_at" => at.(49)})),
          # Opens in the previous window; an annotation in this one is no
          # new opening.
          revision(@a, 3, 1, %{"updated_at" => at.(30)}),
          revision(@g, 4, 3, audit.(%{"state" => "resolved", "transition" => "resolved", "updated_at" => at.(10)})),
          revision(@a, 5, 2, %{"transition" => "annotated", "updated_at" => at.(10)}),
          # Pages, quiets down to audit and resolves there: it still resolves.
          revision(@e, 6, 1, %{"tier" => "page", "updated_at" => at.(8)}),
          # Merging takes it out of the open count without resolving it.
          revision(@f, 7, 1, %{"updated_at" => at.(7)}),
          revision(@d, 8, 1, audit.(%{"updated_at" => at.(6)})),
          revision(@e, 9, 2, audit.(%{"transition" => "deescalated", "updated_at" => at.(6)})),
          revision(@f, 10, 2, %{
            "state" => "merged",
            "transition" => "merged",
            "merged_into" => @a,
            "updated_at" => at.(6)
          }),
          revision(@b, 11, 1, %{"updated_at" => at.(5)}),
          revision(@e, 12, 3, audit.(%{"state" => "resolved", "transition" => "resolved", "updated_at" => at.(5)})),
          # Opens at audit tier and counts once, from its escalation, however
          # often it moves between audit and the board afterwards.
          revision(@c, 13, 1, audit.(%{"updated_at" => at.(4)})),
          revision(@d, 14, 2, %{"transition" => "escalated", "updated_at" => at.(4)}),
          # Only logged: opens and resolves at audit tier, so it never counts.
          revision(@c, 15, 2, audit.(%{"state" => "resolved", "transition" => "resolved", "updated_at" => at.(3)})),
          revision(@d, 16, 3, audit.(%{"transition" => "deescalated", "updated_at" => at.(3)})),
          revision(@b, 17, 2, %{"state" => "resolved", "transition" => "resolved", "updated_at" => at.(2)}),
          revision(@d, 18, 4, %{"transition" => "escalated", "updated_at" => at.(2)})
        ])

      assert {:ok, %{widgets: widgets}} = Symptoms.analytics(user, account, %{"range" => "24h"}, now)
      widgets = Map.new(widgets, &{&1.id, &1})

      # Opened: @b, @d, @e and @f in the window; @a in the previous one (@g
      # opened before both).
      assert %{value: 4, previous_value: 1} = widgets["opened"]
      # Resolved: @b, @e and @g.
      assert %{value: 3, previous_value: 0} = widgets["resolved"]
      # Open now: @a and @d. At the window's start: @a and @g.
      assert %{value: 2, previous_value: 2} = widgets["open"]
    end
  end

  describe "list/3" do
    test "leaves out merged symptoms, and those that never left audit tier unless a filter asks for them", %{
      user: user,
      account: account
    } do
      {:ok, _} =
        PulseFixtures.mirror_symptoms(account, [
          revision(@a, 1, 1),
          revision(@b, 2, 1, %{"tier" => "audit"}),
          revision(@c, 3, 1, %{"state" => "merged", "transition" => "merged", "merged_into" => @a}),
          # Paged, then quieted down to audit and resolved there.
          revision(@d, 4, 1, %{"tier" => "page"}),
          revision(@d, 5, 2, %{"tier" => "audit", "state" => "resolved", "transition" => "resolved"})
        ])

      ids = fn params ->
        {:ok, %{rows: rows}} = Symptoms.list(user, account, params)
        rows |> Enum.map(& &1.id) |> Enum.sort()
      end

      assert ids.(%{}) == [@a, @d]
      assert ids.(%{"state" => "open"}) == [@a]
      assert ids.(%{"tier" => "audit"}) == [@b, @d]
      assert {:error, :invalid_params} = Symptoms.list(user, account, %{"state" => "merged"})
    end
  end

  defp subscribe_to_symptoms(user, account) do
    %Subscription{}
    |> Subscription.changeset(%{
      id: "sub_symptoms",
      user_id: user.id,
      account_token_id: AccountsFixtures.account_token_fixture(account: account, scopes: ["mcp"]).id,
      account_id: account.id,
      event_name: "pulse_symptom.opened",
      callback_url: "https://example.com/events",
      signing_secret: "whsec_" <> Base.encode64(:crypto.strong_rand_bytes(32)),
      refresh_before: DateTime.utc_now() |> DateTime.add(1, :day) |> DateTime.truncate(:second)
    })
    |> Repo.insert!()
  end
end
