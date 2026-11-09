defmodule Tuist.JamsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.FeatureFlags
  alias Tuist.Jams
  alias Tuist.Jams.Approval
  alias Tuist.Jams.Checkpoints
  alias Tuist.Jams.Jam
  alias Tuist.Jams.Message
  alias Tuist.Jams.Provider
  alias Tuist.Jams.Run
  alias Tuist.Jams.Shipping
  alias Tuist.Jams.Worker
  alias Tuist.Jams.Workspace
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    user = AccountsFixtures.user_fixture()
    stub(Provider, :client_opts, fn _, _ -> {:ok, []} end)

    stub(Provider, :validate_model, fn
      _, "chatgpt", "selected-model" -> :ok
      _, _, _ -> {:error, :model_unavailable}
    end)

    %{user: user, account: user.account}
  end

  test "creation is durable, private and replay-safe", %{user: user, account: account} do
    attrs = request("Explain this codebase")
    assert {:ok, jam} = Jams.create(user, account, attrs)
    assert {:ok, replay} = Jams.create(user, account, attrs)
    assert replay.id == jam.id
    assert Repo.aggregate(Jam, :count) == 1
    assert [%{kind: "human", body: "Explain this codebase"}] = jam.messages
    assert_enqueued(worker: Worker, args: %{run_id: Repo.one!(Run).id, attempt: 0})
    assert {:error, :request_conflict} = Jams.create(user, account, %{attrs | "content" => "Different work"})
    stranger = AccountsFixtures.user_fixture()
    assert {:error, :forbidden} = Jams.get(stranger, account, jam.id)
    assert {:error, :not_found} = Jams.get(user, account, Ecto.UUID.generate())
    assert {:error, :invalid_arguments} = Jams.get(user, account, "not-a-uuid")
    assert {:ok, %{revision: revision}} = Jams.snapshot(user, account, :inbox)
    assert revision > 0
  end

  test "revoked feature access denies existing history", %{user: user, account: account} do
    {:ok, jam} = Jams.create(user, account, request())
    stub(FeatureFlags, :ai_enabled?, fn _ -> false end)
    assert {:error, :forbidden} = Jams.get(user, account, jam.id)
    assert {:error, :forbidden} = Jams.list(user, account)
    assert {:error, :forbidden} = Jams.snapshot(user, account, :inbox)
  end

  test "creation binds the selected model and retries never switch it", %{user: user, account: account} do
    attrs = request()
    assert {:error, :model_unavailable} = Jams.create(user, account, Map.delete(attrs, "model"))
    assert {:ok, jam} = Jams.create(user, account, attrs)
    assert %{provider: "chatgpt", model: "selected-model"} = Jams.serialize(jam)
    assert {:error, :request_conflict} = Jams.create(user, account, Map.put(attrs, "model", "different-model"))
    reject(Provider, :validate_model, 3)
    assert {:ok, %{id: id}} = Jams.create(user, account, attrs)
    assert id == jam.id

    expect(Provider, :client_opts, fn ^user, bound ->
      assert bound.provider == "chatgpt"
      assert bound.model == "selected-model"
      {:ok, []}
    end)

    {:ok, {run, _}} = Jams.claim(Repo.one!(Run).id)
    {:ok, _} = Jams.finish(run, {:ok, "Done"})
    assert {:ok, next} = Jams.message(user, account, id, Map.put(request(), "model", "different-model"))
    assert next.model == "selected-model"
  end

  test "remote tool effects use the ledger without a repository", %{user: user, account: account} do
    {:ok, jam} = Jams.create(user, account, request())
    assert jam.repository == nil
    {:ok, {run, _}} = Jams.claim(Repo.one!(Run).id)
    invocation = Ecto.UUID.generate()

    assert {:ok, "remote result"} =
             Jams.call_external_tool(run, invocation, "mcp_service_tool", %{}, fn -> {:ok, "remote result"} end)

    assert {:ok, "remote result"} =
             Jams.call_external_tool(run, invocation, "mcp_service_tool", %{}, fn ->
               flunk("replayed external write")
             end)

    assert {:error, :tool_outcome_unknown} =
             Jams.call_external_tool(run, Ecto.UUID.generate(), "mcp_service_tool", %{}, fn -> {:error, :timeout} end)

    assert {:error, :tool_outcome_unknown} =
             Jams.call_external_tool(run, Ecto.UUID.generate(), "mcp_service_tool", %{}, fn ->
               flunk("dispatched after uncertain write")
             end)
  end

  test "duplicate delivery cannot claim a second run and completion persists suggestions", %{user: user, account: account} do
    {:ok, jam} = Jams.create(user, account, request())
    run = Repo.one!(Run)
    assert {:ok, {claimed, _}} = Jams.claim(run.id)
    assert claimed.attempt == 1
    assert {:error, :stale_run} = Jams.claim(run.id)

    assert {:ok, _} =
             Jams.finish(
               claimed,
               {:ok, ~s({"reply":"Checked the code.","suggestions":["Show the change","Show the change"]})}
             )

    assert {:ok, fresh} = Jams.get(user, account, jam.id)
    assert fresh.agent_status == "idle"
    assert List.last(fresh.messages).body == "Checked the code."
    assert List.last(fresh.messages).suggestions == ["Show the change"]
    assert {:error, :stale_run} = Jams.finish(claimed, {:ok, "duplicate"})
    refute Jams.owns_run?(claimed.id, claimed.attempt)
  end

  test "completed tools replay their results without repeating effects", %{user: user, account: account} do
    {:ok, _} = Jams.create(user, account, request())
    {:ok, {run, _}} = Jams.claim(Repo.one!(Run).id)
    {:ok, effects} = Agent.start_link(fn -> 0 end)

    stub(Workspace, :call, fn _, "write", _ ->
      count = Agent.get_and_update(effects, &{&1 + 1, &1 + 1})
      {:ok, "writes=#{count}"}
    end)

    args = %{"path" => "example.txt", "content" => "new"}
    context = %{invocation_id: Ecto.UUID.generate()}
    assert {:ok, "writes=1"} = Jams.call_tool(run, context, "write", args)
    assert {:ok, "writes=1"} = Jams.call_tool(run, context, "write", args)
    assert Agent.get(effects, & &1) == 1
    raw = Repo.one!(from c in "jam_tool_calls", select: c.result)
    refute raw =~ "writes=1"
    assert {:ok, "writes=2"} = Jams.call_tool(run, %{invocation_id: Ecto.UUID.generate()}, "write", args)
  end

  test "an ambiguous tool effect blocks later writes and survives archiving", %{user: user, account: account} do
    {:ok, jam} = Jams.create(user, account, request())
    {:ok, {run, _}} = Jams.claim(Repo.one!(Run).id)
    stub(Workspace, :call, fn _, _, _ -> {:error, :workspace_command_failed} end)
    context = %{invocation_id: Ecto.UUID.generate()}
    assert {:error, :tool_outcome_unknown} = Jams.call_tool(run, context, "bash", %{"command" => "change-files"})

    assert {:error, :tool_outcome_unknown} =
             Jams.call_tool(run, context, "write", %{"path" => "other", "content" => "changed"})

    assert {:ok, _} = Jams.finish(run, {:ok, "Pretend success"})
    assert {:ok, fresh} = Jams.get(user, account, jam.id)
    assert fresh.agent_status == "outcome_unknown"
    refute Enum.any?(fresh.messages, &(&1.body == "Pretend success"))
    assert {:ok, _} = Jams.archive(user, account, jam.id, "archived")
    assert {:ok, _} = Jams.archive(user, account, jam.id, "active")
    assert {:error, :tool_outcome_unknown} = Jams.message(user, account, jam.id, request("Try a different write"))
  end

  test "expired attempts resume only safe work and reject old checkpoints", %{user: user, account: account} do
    {:ok, _} = Jams.create(user, account, request())
    {:ok, {first, _}} = Jams.claim(Repo.one!(Run).id)
    :ok = Checkpoints.record(first.session_id, [Condukt.Message.user("Original request")], 1)
    assert {:ok, _} = Checkpoints.load(Repo.reload!(first))

    Repo.update_all(from(r in Run, where: r.id == ^first.id),
      set: [heartbeat_at: DateTime.add(DateTime.utc_now(:second), -120)]
    )

    assert :ok = Jams.recover()
    assert {:ok, {second, _}} = Jams.claim(first.id)
    assert second.attempt == 2
    assert second.session_id != first.session_id
    :ok = Checkpoints.record(first.session_id, [Condukt.Message.user("Stale replacement")], 2)
    assert {:ok, %{messages: [%{content: "Original request"}]}} = Checkpoints.load(Repo.reload!(second))
    assert {:error, :stale_run} = Jams.rename(first, "Stale title")
    assert {:ok, _} = Jams.rename(second, "Current title")
  end

  test "recovery never regenerates effects missing from a protocol checkpoint", %{user: user, account: account} do
    {:ok, _} = Jams.create(user, account, request())
    {:ok, {run, _}} = Jams.claim(Repo.one!(Run).id)
    stub(Workspace, :call, fn _, _, _ -> {:ok, "changed once"} end)

    assert {:ok, _} =
             Jams.call_tool(run, %{invocation_id: Ecto.UUID.generate()}, "bash", %{"command" => "change-files"})

    Repo.update_all(from(r in Run, where: r.id == ^run.id),
      set: [heartbeat_at: DateTime.add(DateTime.utc_now(:second), -120)]
    )

    assert :ok = Jams.recover()
    assert Repo.reload!(run).status == "interrupted"
    assert {:error, :stale_run} = Jams.claim(run.id)
  end

  test "deactivation fences running model and tool access", %{user: user, account: account} do
    {:ok, _} = Jams.create(user, account, request())
    {:ok, {run, _}} = Jams.claim(Repo.one!(Run).id)
    Repo.update!(change(user, active: false))
    refute Jams.owns_run?(run.id, run.attempt)
    assert {:error, :stale_run} = Jams.rename(run, "Late title")
  end

  for revocation <- [:permission, :inactive, :disabled, :feature] do
    @revocation revocation
    test "claim and recovery terminalize queued work after #{@revocation} revocation", %{user: user} do
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      :ok = Accounts.add_user_to_organization(user, organization, role: :admin)
      {:ok, claimed_jam} = Jams.create(user, account, request())
      {:ok, recovered_jam} = Jams.create(user, account, request())
      claimed = Repo.get_by!(Run, jam_id: claimed_jam.id)
      recovered = Repo.get_by!(Run, jam_id: recovered_jam.id)
      Repo.delete_all(Oban.Job)

      case @revocation do
        :permission -> Accounts.update_user_role_in_organization(user, organization, :user)
        :inactive -> Repo.update!(change(user, active: false))
        :disabled -> Repo.update!(change(user, disabled_at: DateTime.utc_now(:second)))
        :feature -> stub(FeatureFlags, :ai_enabled?, fn _ -> false end)
      end

      assert {:error, :forbidden} = Jams.claim(claimed.id)
      assert Repo.reload!(claimed).status == "interrupted"
      assert Repo.reload!(claimed).attempt == 0
      assert :ok = Jams.recover()
      assert Repo.reload!(recovered).status == "interrupted"
      assert Repo.reload!(recovered).attempt == 0
      assert Repo.reload!(recovered_jam).agent_status == "interrupted"
      refute_enqueued(worker: Worker)

      case @revocation do
        :permission -> Accounts.update_user_role_in_organization(user, organization, :admin)
        :inactive -> Repo.update!(change(Repo.reload!(user), active: true))
        :disabled -> Repo.update!(change(Repo.reload!(user), disabled_at: nil))
        :feature -> stub(FeatureFlags, :ai_enabled?, fn _ -> true end)
      end

      assert :ok = Jams.recover()
      assert {:error, :stale_run} = Jams.claim(claimed.id)
      assert {:error, :stale_run} = Jams.claim(recovered.id)
      assert Enum.count(Jams.history(Repo.reload!(claimed_jam)).messages, &(&1.kind == "notice")) == 1
      assert Enum.count(Jams.history(Repo.reload!(recovered_jam)).messages, &(&1.kind == "notice")) == 1
      refute_enqueued(worker: Worker)
    end
  end

  test "unauthorized queued runs leave the bounded recovery window", %{user: user, account: account} do
    for _ <- 1..100 do
      {:ok, _} = Jams.create(user, account, request())
    end

    blocked_ids = Repo.all(from r in Run, select: r.id)
    Repo.update!(change(user, disabled_at: DateTime.utc_now(:second)))

    permitted = AccountsFixtures.user_fixture()
    {:ok, jam} = Jams.create(permitted, permitted.account, request())
    waiting = Repo.get_by!(Run, jam_id: jam.id)
    Repo.delete_all(Oban.Job)

    # Give every revoked run priority over the still-authorized queued run.
    Repo.update_all(from(r in Run, where: r.id in ^blocked_ids),
      set: [heartbeat_at: DateTime.add(DateTime.utc_now(:second), -120)]
    )

    assert :ok = Jams.recover()
    assert Repo.aggregate(from(r in Run, where: r.id in ^blocked_ids and r.status == "interrupted"), :count) == 100
    refute_enqueued(worker: Worker)
    assert :ok = Jams.recover()
    assert_enqueued(worker: Worker, args: %{run_id: waiting.id, attempt: 0})
    assert {:ok, {_, _}} = Jams.claim(waiting.id)
  end

  test "revocation preserves uncertain effects in queued attempts", %{user: user, account: account} do
    runs =
      for _ <- 1..2 do
        {:ok, jam} = Jams.create(user, account, request())
        {:ok, {run, _}} = Jams.claim(Repo.get_by!(Run, jam_id: jam.id).id)

        assert {:error, :tool_outcome_unknown} =
                 Jams.call_external_tool(run, Ecto.UUID.generate(), "remote_write", %{}, fn ->
                   {:error, :timeout}
                 end)

        Repo.update!(change(run, status: "queued", heartbeat_at: nil))
      end

    [claimed, recovered] = runs
    Repo.delete_all(Oban.Job)
    Repo.update!(change(user, active: false))
    assert {:error, :forbidden} = Jams.claim(claimed.id)
    assert :ok = Jams.recover()
    assert Repo.reload!(claimed).status == "outcome_unknown"
    assert Repo.reload!(recovered).status == "outcome_unknown"
    assert Repo.aggregate(from(c in "jam_tool_calls", where: c.status == "executing"), :count) == 2

    Repo.update!(change(Repo.reload!(user), active: true))
    assert :ok = Jams.recover()
    refute_enqueued(worker: Worker)

    for run <- runs do
      assert {:error, :stale_run} = Jams.claim(run.id)
      assert {:error, :tool_outcome_unknown} = Jams.message(user, account, run.jam_id, request("Continue"))
    end
  end

  test "archive cancels active work, restore does not restart it", %{user: user, account: account} do
    {:ok, jam} = Jams.create(user, account, request())
    {:ok, {run, _}} = Jams.claim(Repo.one!(Run).id)
    assert {:ok, %{status: :archived}} = Jams.archive(user, account, jam.id, "archived")
    assert {:error, :stale_run} = Jams.finish(run, {:ok, "Late private reply"})
    assert {:ok, %{status: :active, agent_status: "idle"}} = Jams.archive(user, account, jam.id, "active")
    assert Repo.reload!(run).status == "cancelled"
    assert Repo.aggregate(Run, :count) == 1
  end

  test "history paging is bounded, chronological and disjoint", %{user: user, account: account} do
    {:ok, jam} = Jams.create(user, account, request())

    for position <- 10..69 do
      Repo.insert!(%Message{jam_id: jam.id, position: position, kind: "notice", body: "Message #{position}"})
    end

    assert {:ok, page} = Jams.get(user, account, jam.id)
    assert length(page.messages) == 50
    assert hd(page.messages).position == 20
    assert page.next_before == 20
    assert {:ok, older} = Jams.get(user, account, jam.id, before: page.next_before)
    assert Enum.map(older.messages, & &1.position) == [1 | Enum.to_list(10..19)]
    refute older.has_more
  end

  test "Ship authorizes one exact persisted review, never arbitrary client fields", %{user: user, account: account} do
    {:ok, jam} = Jams.create(user, account, request())
    {:ok, {run, _}} = Jams.claim(Repo.one!(Run).id)
    {:ok, _} = Jams.finish(run, {:ok, "Ready"})

    preview = %{
      request_id: Ecto.UUID.generate(),
      jam_id: jam.id,
      account_id: account.id,
      repository: "example/repo",
      sandbox_id: nil,
      head_sha: String.duplicate("a", 40),
      base_sha: nil,
      diff: "+ reviewed",
      target_branch: "jams/example",
      mode: :branch
    }

    stub(Shipping, :preview, fn _, _ -> {:ok, preview} end)
    assert {:ok, response} = Jams.ship_preview(user, account, jam.id)
    approval = Map.new(response, fn {key, value} -> {to_string(key), value} end)

    assert {:error, :shipping_approval_invalid} =
             Jams.ship(user, account, jam.id, %{approval | "head_sha" => String.duplicate("b", 40)})

    assert {:ok, %{agent_status: "shipping"}} = Jams.ship(user, account, jam.id, approval)
    assert {:ok, _} = Jams.ship(user, account, jam.id, approval)
    assert Repo.aggregate(Run, :count) == 2
    assert Repo.one!(Approval).approved_by_id == user.id
    assert Repo.one!(Approval).status == :approved
    ship_run = Repo.one!(from r in Run, where: r.kind == "ship")
    assert {:ok, {ship_run, _}} = Jams.claim(ship_run.id)
    assert {:ok, _} = Jams.finish(ship_run, {:error, :shipping_uncertain})
    assert Repo.reload!(ship_run).status == "outcome_unknown"
    assert {:ok, _} = Jams.archive(user, account, jam.id, "archived")
    assert {:ok, _} = Jams.archive(user, account, jam.id, "active")
    assert {:error, :tool_outcome_unknown} = Jams.message(user, account, jam.id, request("Continue"))
    stub(Shipping, :reconcile, fn _, _ -> {:error, :shipping_uncertain} end)
    assert {:error, :shipping_uncertain} = Jams.reconcile_ship(user, account, jam.id, approval)
    assert Repo.reload!(ship_run).status == "outcome_unknown"
    stub(Shipping, :reconcile, fn _, _ -> {:ok, %{head_sha: preview.head_sha}} end)
    assert {:ok, %{base_sha: sha}} = Jams.reconcile_ship(user, account, jam.id, approval)
    assert sha == preview.head_sha
    assert Repo.reload!(ship_run).status == "succeeded"
    assert {:ok, _} = Jams.message(user, account, jam.id, request("Continue"))
  end

  test "archiving an in-flight Ship cannot erase an unknown publication", %{user: user, account: account} do
    {:ok, jam} = Jams.create(user, account, request())
    {:ok, {run, _}} = Jams.claim(Repo.one!(Run).id)
    {:ok, _} = Jams.finish(run, {:ok, "Ready"})

    ship =
      Repo.insert!(%Run{
        jam_id: jam.id,
        kind: "ship",
        status: "running",
        attempt: 1,
        heartbeat_at: DateTime.utc_now(:second)
      })

    assert {:ok, _} = Jams.archive(user, account, jam.id, "archived")
    assert Repo.reload!(ship).status == "outcome_unknown"
    assert {:ok, _} = Jams.archive(user, account, jam.id, "active")
    assert {:error, :tool_outcome_unknown} = Jams.message(user, account, jam.id, request("Continue"))
  end

  defp request(content \\ "Inspect the repository"),
    do: %{
      "content" => content,
      "request_id" => Ecto.UUID.generate(),
      "provider" => "chatgpt",
      "model" => "selected-model"
    }
end
