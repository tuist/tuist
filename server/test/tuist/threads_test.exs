defmodule Tuist.ThreadsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.FeatureFlags
  alias Tuist.Threads
  alias Tuist.Threads.Approval
  alias Tuist.Threads.Checkpoints
  alias Tuist.Threads.Message
  alias Tuist.Threads.Provider
  alias Tuist.Threads.Run
  alias Tuist.Threads.Shipping
  alias Tuist.Threads.Thread
  alias Tuist.Threads.Worker
  alias Tuist.Threads.Workspace
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
    assert {:ok, thread} = Threads.create(user, account, attrs)
    assert {:ok, replay} = Threads.create(user, account, attrs)
    assert replay.id == thread.id
    assert Repo.aggregate(Thread, :count) == 1
    assert [%{kind: "human", body: "Explain this codebase"}] = thread.messages
    assert_enqueued(worker: Worker, args: %{run_id: Repo.one!(Run).id, attempt: 0})
    assert {:error, :request_conflict} = Threads.create(user, account, %{attrs | "content" => "Different work"})
    stranger = AccountsFixtures.user_fixture()
    assert {:error, :forbidden} = Threads.get(stranger, account, thread.id)
    assert {:error, :not_found} = Threads.get(user, account, Ecto.UUID.generate())
    assert {:error, :invalid_arguments} = Threads.get(user, account, "not-a-uuid")
    assert {:ok, %{revision: revision}} = Threads.snapshot(user, account, :inbox)
    assert revision > 0
  end

  test "revoked feature access denies existing history", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    stub(FeatureFlags, :ai_enabled?, fn _ -> false end)
    assert {:error, :forbidden} = Threads.get(user, account, thread.id)
    assert {:error, :forbidden} = Threads.list(user, account)
    assert {:error, :forbidden} = Threads.snapshot(user, account, :inbox)
  end

  test "creation binds the selected model and retries never switch it", %{user: user, account: account} do
    attrs = request()
    assert {:error, :model_unavailable} = Threads.create(user, account, Map.delete(attrs, "model"))
    assert {:ok, thread} = Threads.create(user, account, attrs)
    assert %{provider: "chatgpt", model: "selected-model"} = Threads.serialize(thread)
    assert {:error, :request_conflict} = Threads.create(user, account, Map.put(attrs, "model", "different-model"))
    reject(Provider, :validate_model, 3)
    assert {:ok, %{id: id}} = Threads.create(user, account, attrs)
    assert id == thread.id

    expect(Provider, :client_opts, fn ^user, bound ->
      assert bound.provider == "chatgpt"
      assert bound.model == "selected-model"
      {:ok, []}
    end)

    {:ok, {run, _}} = Threads.claim(Repo.one!(Run).id)
    {:ok, _} = Threads.finish(run, {:ok, "Done"})
    assert {:ok, next} = Threads.message(user, account, id, Map.put(request(), "model", "different-model"))
    assert next.model == "selected-model"
  end

  test "remote tool effects use the ledger without a repository", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    assert thread.repository == nil
    {:ok, {run, _}} = Threads.claim(Repo.one!(Run).id)
    invocation = Ecto.UUID.generate()

    assert {:ok, "remote result"} =
             Threads.call_external_tool(run, invocation, "mcp_service_tool", %{}, fn -> {:ok, "remote result"} end)

    assert {:ok, "remote result"} =
             Threads.call_external_tool(run, invocation, "mcp_service_tool", %{}, fn ->
               flunk("replayed external write")
             end)

    assert {:error, :tool_outcome_unknown} =
             Threads.call_external_tool(run, Ecto.UUID.generate(), "mcp_service_tool", %{}, fn -> {:error, :timeout} end)

    assert {:error, :tool_outcome_unknown} =
             Threads.call_external_tool(run, Ecto.UUID.generate(), "mcp_service_tool", %{}, fn ->
               flunk("dispatched after uncertain write")
             end)
  end

  test "duplicate delivery cannot claim a second run and completion persists suggestions", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    run = Repo.one!(Run)
    assert {:ok, {claimed, _}} = Threads.claim(run.id)
    assert claimed.attempt == 1
    assert {:error, :stale_run} = Threads.claim(run.id)

    assert {:ok, _} =
             Threads.finish(
               claimed,
               {:ok, ~s({"reply":"Checked the code.","suggestions":["Show the change","Show the change"]})}
             )

    assert {:ok, fresh} = Threads.get(user, account, thread.id)
    assert fresh.agent_status == "idle"
    assert List.last(fresh.messages).body == "Checked the code."
    assert List.last(fresh.messages).suggestions == ["Show the change"]
    assert {:error, :stale_run} = Threads.finish(claimed, {:ok, "duplicate"})
    refute Threads.owns_run?(claimed.id, claimed.attempt)
  end

  test "completed tools replay their results without repeating effects", %{user: user, account: account} do
    {:ok, _} = Threads.create(user, account, request())
    {:ok, {run, _}} = Threads.claim(Repo.one!(Run).id)
    {:ok, effects} = Agent.start_link(fn -> 0 end)

    stub(Workspace, :call, fn _, "write", _ ->
      count = Agent.get_and_update(effects, &{&1 + 1, &1 + 1})
      {:ok, "writes=#{count}"}
    end)

    args = %{"path" => "example.txt", "content" => "new"}
    context = %{invocation_id: Ecto.UUID.generate()}
    assert {:ok, "writes=1"} = Threads.call_tool(run, context, "write", args)
    assert {:ok, "writes=1"} = Threads.call_tool(run, context, "write", args)
    assert Agent.get(effects, & &1) == 1
    raw = Repo.one!(from c in "thread_tool_calls", select: c.result)
    refute raw =~ "writes=1"
    assert {:ok, "writes=2"} = Threads.call_tool(run, %{invocation_id: Ecto.UUID.generate()}, "write", args)
  end

  test "an ambiguous tool effect blocks later writes and survives archiving", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    {:ok, {run, _}} = Threads.claim(Repo.one!(Run).id)
    stub(Workspace, :call, fn _, _, _ -> {:error, :workspace_command_failed} end)
    context = %{invocation_id: Ecto.UUID.generate()}
    assert {:error, :tool_outcome_unknown} = Threads.call_tool(run, context, "bash", %{"command" => "change-files"})

    assert {:error, :tool_outcome_unknown} =
             Threads.call_tool(run, context, "write", %{"path" => "other", "content" => "changed"})

    assert {:ok, _} = Threads.finish(run, {:ok, "Pretend success"})
    assert {:ok, fresh} = Threads.get(user, account, thread.id)
    assert fresh.agent_status == "outcome_unknown"
    refute Enum.any?(fresh.messages, &(&1.body == "Pretend success"))
    assert {:ok, _} = Threads.archive(user, account, thread.id, "archived")
    assert {:ok, _} = Threads.archive(user, account, thread.id, "active")
    assert {:error, :tool_outcome_unknown} = Threads.message(user, account, thread.id, request("Try a different write"))
  end

  test "expired attempts resume only safe work and reject old checkpoints", %{user: user, account: account} do
    {:ok, _} = Threads.create(user, account, request())
    {:ok, {first, _}} = Threads.claim(Repo.one!(Run).id)
    :ok = Checkpoints.record(first.session_id, [Condukt.Message.user("Original request")], 1)
    assert {:ok, _} = Checkpoints.load(Repo.reload!(first))

    Repo.update_all(from(r in Run, where: r.id == ^first.id),
      set: [heartbeat_at: DateTime.add(DateTime.utc_now(:second), -120)]
    )

    assert :ok = Threads.recover()
    assert {:ok, {second, _}} = Threads.claim(first.id)
    assert second.attempt == 2
    assert second.session_id != first.session_id
    :ok = Checkpoints.record(first.session_id, [Condukt.Message.user("Stale replacement")], 2)
    assert {:ok, %{messages: [%{content: "Original request"}]}} = Checkpoints.load(Repo.reload!(second))
    assert {:error, :stale_run} = Threads.rename(first, "Stale title")
    assert {:ok, _} = Threads.rename(second, "Current title")
  end

  test "recovery never regenerates effects missing from a protocol checkpoint", %{user: user, account: account} do
    {:ok, _} = Threads.create(user, account, request())
    {:ok, {run, _}} = Threads.claim(Repo.one!(Run).id)
    stub(Workspace, :call, fn _, _, _ -> {:ok, "changed once"} end)

    assert {:ok, _} =
             Threads.call_tool(run, %{invocation_id: Ecto.UUID.generate()}, "bash", %{"command" => "change-files"})

    Repo.update_all(from(r in Run, where: r.id == ^run.id),
      set: [heartbeat_at: DateTime.add(DateTime.utc_now(:second), -120)]
    )

    assert :ok = Threads.recover()
    assert Repo.reload!(run).status == "interrupted"
    assert {:error, :stale_run} = Threads.claim(run.id)
  end

  test "deactivation fences running model and tool access", %{user: user, account: account} do
    {:ok, _} = Threads.create(user, account, request())
    {:ok, {run, _}} = Threads.claim(Repo.one!(Run).id)
    Repo.update!(change(user, active: false))
    refute Threads.owns_run?(run.id, run.attempt)
    assert {:error, :stale_run} = Threads.rename(run, "Late title")
  end

  test "archive cancels active work, restore does not restart it", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    {:ok, {run, _}} = Threads.claim(Repo.one!(Run).id)
    assert {:ok, %{status: :archived}} = Threads.archive(user, account, thread.id, "archived")
    assert {:error, :stale_run} = Threads.finish(run, {:ok, "Late private reply"})
    assert {:ok, %{status: :active, agent_status: "idle"}} = Threads.archive(user, account, thread.id, "active")
    assert Repo.reload!(run).status == "cancelled"
    assert Repo.aggregate(Run, :count) == 1
  end

  test "history paging is bounded, chronological and disjoint", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())

    for position <- 10..69 do
      Repo.insert!(%Message{thread_id: thread.id, position: position, kind: "notice", body: "Message #{position}"})
    end

    assert {:ok, page} = Threads.get(user, account, thread.id)
    assert length(page.messages) == 50
    assert hd(page.messages).position == 20
    assert page.next_before == 20
    assert {:ok, older} = Threads.get(user, account, thread.id, before: page.next_before)
    assert Enum.map(older.messages, & &1.position) == [1 | Enum.to_list(10..19)]
    refute older.has_more
  end

  test "Ship authorizes one exact persisted review, never arbitrary client fields", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    {:ok, {run, _}} = Threads.claim(Repo.one!(Run).id)
    {:ok, _} = Threads.finish(run, {:ok, "Ready"})

    preview = %{
      request_id: Ecto.UUID.generate(),
      thread_id: thread.id,
      account_id: account.id,
      repository: "example/repo",
      sandbox_id: nil,
      head_sha: String.duplicate("a", 40),
      base_sha: nil,
      diff: "+ reviewed",
      target_branch: "threads/example",
      mode: :branch
    }

    stub(Shipping, :preview, fn _, _ -> {:ok, preview} end)
    assert {:ok, response} = Threads.ship_preview(user, account, thread.id)
    approval = Map.new(response, fn {key, value} -> {to_string(key), value} end)

    assert {:error, :shipping_approval_invalid} =
             Threads.ship(user, account, thread.id, %{approval | "head_sha" => String.duplicate("b", 40)})

    assert {:ok, %{agent_status: "shipping"}} = Threads.ship(user, account, thread.id, approval)
    assert {:ok, _} = Threads.ship(user, account, thread.id, approval)
    assert Repo.aggregate(Run, :count) == 2
    assert Repo.one!(Approval).approved_by_id == user.id
    assert Repo.one!(Approval).status == :approved
    ship_run = Repo.one!(from r in Run, where: r.kind == "ship")
    assert {:ok, {ship_run, _}} = Threads.claim(ship_run.id)
    assert {:ok, _} = Threads.finish(ship_run, {:error, :shipping_uncertain})
    assert Repo.reload!(ship_run).status == "outcome_unknown"
    assert {:ok, _} = Threads.archive(user, account, thread.id, "archived")
    assert {:ok, _} = Threads.archive(user, account, thread.id, "active")
    assert {:error, :tool_outcome_unknown} = Threads.message(user, account, thread.id, request("Continue"))
    stub(Shipping, :reconcile, fn _, _ -> {:error, :shipping_uncertain} end)
    assert {:error, :shipping_uncertain} = Threads.reconcile_ship(user, account, thread.id, approval)
    assert Repo.reload!(ship_run).status == "outcome_unknown"
    stub(Shipping, :reconcile, fn _, _ -> {:ok, %{head_sha: preview.head_sha}} end)
    assert {:ok, %{base_sha: sha}} = Threads.reconcile_ship(user, account, thread.id, approval)
    assert sha == preview.head_sha
    assert Repo.reload!(ship_run).status == "succeeded"
    assert {:ok, _} = Threads.message(user, account, thread.id, request("Continue"))
  end

  test "archiving an in-flight Ship cannot erase an unknown publication", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    {:ok, {run, _}} = Threads.claim(Repo.one!(Run).id)
    {:ok, _} = Threads.finish(run, {:ok, "Ready"})

    ship =
      Repo.insert!(%Run{
        thread_id: thread.id,
        kind: "ship",
        status: "running",
        attempt: 1,
        heartbeat_at: DateTime.utc_now(:second)
      })

    assert {:ok, _} = Threads.archive(user, account, thread.id, "archived")
    assert Repo.reload!(ship).status == "outcome_unknown"
    assert {:ok, _} = Threads.archive(user, account, thread.id, "active")
    assert {:error, :tool_outcome_unknown} = Threads.message(user, account, thread.id, request("Continue"))
  end

  defp request(content \\ "Inspect the repository"),
    do: %{
      "content" => content,
      "request_id" => Ecto.UUID.generate(),
      "provider" => "chatgpt",
      "model" => "selected-model"
    }
end
