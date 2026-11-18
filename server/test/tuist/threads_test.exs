defmodule Tuist.ThreadsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Condukt.SessionStore.ObjectStore
  alias Condukt.SessionStore.ObjectStore.Memory
  alias Condukt.SessionStore.Snapshot
  alias Tuist.Accounts
  alias Tuist.Agents.Lease
  alias Tuist.Agents.SessionStore
  alias Tuist.Agents.Workers.PurgeDeletedSessionsWorker
  alias Tuist.FeatureFlags
  alias Tuist.Push.Workers.ThreadFinishedWorker
  alias Tuist.Threads
  alias Tuist.Threads.Approval
  alias Tuist.Threads.Message
  alias Tuist.Threads.Provider
  alias Tuist.Threads.Run
  alias Tuist.Threads.Shipping
  alias Tuist.Threads.SnoozeWorker
  alias Tuist.Threads.Thread
  alias Tuist.Threads.ToolCall
  alias TuistTestSupport.Fixtures.AccountsFixtures

  # The built-in tools whose open calls of a run do not block each other.
  @tools ["Read", "Glob", "Grep", "Write", "Edit", "Bash"]

  setup do
    user = AccountsFixtures.user_fixture()
    stub(Provider, :client_opts, fn _, _ -> {:ok, []} end)

    stub(Provider, :validate_model, fn
      _, "chatgpt", "selected-model" -> :ok
      _, _, _ -> {:error, :model_unavailable}
    end)

    %{user: user, account: user.account}
  end

  # The previous release's recovery sweep, still running on its pods during a
  # rolling deploy, interrupts or re-queues runs without a heartbeat in the
  # last 60 seconds. Hosts keep their run's fresh; a queued run starts fresh.
  test "queued runs start with a heartbeat that only the run's host refreshes", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    run = Repo.one!(from r in Run, where: r.thread_id == ^thread.id)
    assert run.heartbeat_at

    [%{epoch: epoch}] = Enum.filter(Lease.claim("host", 100), &(&1.id == to_string(thread.id)))
    assert {:ok, {run, _thread}} = Threads.claim(run.id, epoch)
    stale = DateTime.utc_now() |> DateTime.add(-300, :second) |> DateTime.truncate(:second)
    Repo.update_all(from(r in Run, where: r.id == ^run.id), set: [heartbeat_at: stale])

    assert :ok = Threads.keep_alive(%{run | attempt: run.attempt - 1})
    assert Repo.reload!(run).heartbeat_at == stale

    assert :ok = Threads.keep_alive(run)
    assert DateTime.diff(DateTime.utc_now(), Repo.reload!(run).heartbeat_at) < 5
  end

  test "creation is durable, private and replay-safe", %{user: user, account: account} do
    attrs = request("Explain this codebase")
    assert {:ok, thread} = Threads.create(user, account, attrs)
    assert {:ok, replay} = Threads.create(user, account, attrs)
    assert replay.id == thread.id
    assert Repo.aggregate(Thread, :count) == 1
    assert [%{kind: "human", body: "Explain this codebase"}] = thread.messages
    assert %{wanted: true, kind: "thread"} = session(thread.id)
    assert {:error, :request_conflict} = Threads.create(user, account, %{attrs | "content" => "Different work"})
    stranger = AccountsFixtures.user_fixture()
    assert {:error, :forbidden} = Threads.get(stranger, account, thread.id)
    assert {:error, :not_found} = Threads.get(user, account, Ecto.UUID.generate())
    assert {:error, :invalid_arguments} = Threads.get(user, account, "not-a-uuid")
    assert {:ok, %{revision: revision}} = Threads.snapshot(user, account, :inbox)
    assert revision > 0
  end

  test "deleting a thread deletes its agent session and its stored conversation", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    {:ok, other} = Threads.create(user, account, request())
    id = to_string(thread.id)
    {ObjectStore, store} = SessionStore.store("thread", id, 1)
    :ok = ObjectStore.save(Snapshot.new(%{}), store)

    Repo.delete!(thread)

    # A trigger cannot reach object storage: it marks the session, and the
    # sweep deletes its objects once no host can still write them.
    assert %{wanted: false} = session(id)
    assert :ok = PurgeDeletedSessionsWorker.perform(%Oban.Job{})
    assert Repo.exists?(from s in "agent_sessions", where: s.id == ^id)

    Repo.update_all(from(s in "agent_sessions", where: s.id == ^id),
      set: [deleted_at: DateTime.add(DateTime.utc_now(), -120)]
    )

    assert :ok = PurgeDeletedSessionsWorker.perform(%Oban.Job{})

    refute Repo.exists?(from s in "agent_sessions", where: s.id == ^id)
    assert ObjectStore.load(Keyword.delete(store, :epoch)) == :not_found
    assert {:ok, []} = Memory.list(Tuist.Agents.TestBucket, "agents/thread/#{id}/", nil)
    assert %{wanted: true} = session(other.id)
  end

  test "revoked feature access denies existing history", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    stub(FeatureFlags, :luft_enabled?, fn _ -> false end)
    assert {:error, :forbidden} = Threads.get(user, account, thread.id)
    assert {:error, :forbidden} = Threads.list(user, account)
    assert {:error, :forbidden} = Threads.snapshot(user, account, :inbox)
  end

  test "organization threads need both the user's and the organization's luft flags", %{
    user: user,
    account: personal
  } do
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    :ok = Accounts.add_user_to_organization(user, organization, role: :admin)

    for {user_flag, organization_flag, organization_access, personal_access} <- [
          {true, true, :ok, :ok},
          {true, false, {:error, :forbidden}, :ok},
          {false, true, {:error, :forbidden}, {:error, :forbidden}}
        ] do
      stub(FeatureFlags, :luft_enabled?, fn _ -> user_flag end)
      stub(FeatureFlags, :organization_luft_enabled?, fn flagged -> organization_flag and flagged.id == account.id end)

      assert Threads.authorize(user, account) == organization_access
      assert Threads.authorize(user, personal) == personal_access
    end
  end

  test "mentions name account handles, not email addresses or words inside other text" do
    assert Threads.mentions("@Ana, ask @ben-c (not ana@ben.dev, x@cai or @-dan) about @ana again.") ==
             ["ana", "ben-c"]
  end

  test "mentioning organization members loops them into the thread on the owner's subscription", %{user: ana} do
    stub(FeatureFlags, :luft_enabled?, fn _ -> true end)
    stub(FeatureFlags, :organization_luft_enabled?, fn _ -> true end)
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    [ben, cai] = for _ <- 1..2, do: AccountsFixtures.user_fixture(preload: [:account])
    outsider = AccountsFixtures.user_fixture(preload: [:account])
    :ok = Accounts.add_user_to_organization(ana, organization, role: :admin)
    # Participants need only be members, not the admins who own threads.
    :ok = Accounts.add_user_to_organization(ben, organization, role: :user)
    :ok = Accounts.add_user_to_organization(cai, organization, role: :user)

    content = "Ship it with @#{String.upcase(ben.account.name)} and @#{outsider.account.name}"
    {:ok, thread} = Threads.create(ana, account, request(content))
    assert [%{id: ben_id}] = Threads.serialize(thread).participants
    assert ben_id == ben.id
    assert {:error, :not_found} = Threads.get(cai, account, thread.id)
    assert {:error, :forbidden} = Threads.get(outsider, account, thread.id)

    assert {:ok, %{threads: [%{id: id}]}} = Threads.list(ben, account)
    assert id == thread.id
    assert {:ok, %{revision: _}} = Threads.snapshot(ben, account, thread.id)

    {:ok, {run, _}} = claim(Repo.one!(Run).id)
    {:ok, _} = Threads.finish(run, {:ok, "Done"})

    # Ben prompts it on Ana's subscription, and loops Cai in.
    expect(Provider, :client_opts, fn owner, _thread ->
      assert owner.id == ana.id
      {:ok, []}
    end)

    assert {:ok, prompted} = Threads.message(ben, account, thread.id, request("Over to you, @#{cai.account.name}"))
    serialized = Threads.serialize(prompted)
    assert Enum.map(serialized.participants, & &1.id) == [ben.id, cai.id]
    assert serialized.owner.id == ana.id
    assert %{author: %{id: ^ben_id}} = List.last(serialized.messages)
    assert {:ok, %{threads: [_]}} = Threads.list(cai, account)

    # Archiving and shipping stay the owner's.
    assert {:error, :forbidden} = Threads.archive(ben, account, thread.id, "archived")
    assert {:error, :forbidden} = Threads.snooze(ben, account, thread.id, nil)
    assert {:error, :forbidden} = Threads.ship_preview(ben, account, thread.id)
  end

  test "mentions in a personal account's threads loop nobody in", %{user: user, account: account} do
    other = AccountsFixtures.user_fixture(preload: [:account])
    {:ok, thread} = Threads.create(user, account, request("Ask @#{other.account.name}"))
    assert Threads.serialize(thread).participants == []
    assert {:error, :forbidden} = Threads.get(other, account, thread.id)
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

    {:ok, {run, _}} = claim(Repo.one!(Run).id)
    {:ok, _} = Threads.finish(run, {:ok, "Done"})
    assert {:ok, next} = Threads.message(user, account, id, Map.put(request(), "model", "different-model"))
    assert next.model == "selected-model"
  end

  test "a finished run notifies the owner's Luft devices", %{user: user, account: account} do
    stub(Tuist.Environment, :apns_configured?, fn -> true end)
    {:ok, thread} = Threads.create(user, account, request())
    {:ok, {run, _}} = claim(Repo.one!(Run).id)

    {:ok, _} = Threads.finish(run, {:ok, "Done"})

    assert_enqueued(
      worker: ThreadFinishedWorker,
      args: %{"thread_id" => thread.id, "status" => "idle"}
    )
  end

  test "remote tool effects use the ledger without a repository", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    assert thread.repository == nil
    {:ok, {run, _}} = claim(Repo.one!(Run).id)
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
    assert {:ok, {claimed, _}} = claim(run.id)
    assert claimed.attempt == 1
    assert {:error, :stale_run} = claim(run.id)

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
    {:ok, {run, _}} = claim(Repo.one!(Run).id)
    {:ok, effects} = Agent.start_link(fn -> 0 end)

    write = fn ->
      count = Agent.get_and_update(effects, &{&1 + 1, &1 + 1})
      {:ok, "writes=#{count}"}
    end

    args = %{"path" => "example.txt", "content" => "new"}
    invocation = Ecto.UUID.generate()
    assert {:ok, "writes=1"} = Threads.call_external_tool(run, invocation, "write", args, write)
    assert {:ok, "writes=1"} = Threads.call_external_tool(run, invocation, "write", args, write)
    assert Agent.get(effects, & &1) == 1
    raw = Repo.one!(from c in "thread_tool_calls", select: c.result)
    refute raw =~ "writes=1"
    assert {:ok, "writes=2"} = Threads.call_external_tool(run, Ecto.UUID.generate(), "write", args, write)
  end

  test "the session's built-in tool calls are reserved before they run and completed after",
       %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    {:ok, {run, _}} = claim(Repo.one!(Run).id)
    args = %{"command" => "make"}

    assert :ok = Threads.begin_tool_call(run, "call_1", "Bash", args, @tools)
    {:ok, running} = Threads.get(user, account, thread.id)
    assert %{tool_name: "Bash", tool_state: "running"} = List.last(running.messages)

    # A call of the same run that is still running or parked holds back
    # nothing: Condukt orders the session's calls by their effects.
    assert :ok = Threads.begin_tool_call(run, "call_2", "Read", %{"path" => "a"}, @tools)
    # The snapshot names the newest call still executing, never its arguments.
    assert {:ok, %{activity: "Read"}} = Threads.snapshot(user, account, thread.id)

    assert :ok = Threads.complete_tool_call(run, "call_2", "Read", %{"path" => "a"}, {:error, "missing"})
    assert {:ok, %{activity: "Bash"}} = Threads.snapshot(user, account, thread.id)

    assert :ok = Threads.complete_tool_call(run, "call_1", "Bash", args, {:ok, "built"})
    assert {:ok, %{activity: nil}} = Threads.snapshot(user, account, thread.id)
    {:ok, done} = Threads.get(user, account, thread.id)
    assert Enum.any?(done.messages, &match?(%{tool_name: "Bash", tool_state: "complete", body: "built"}, &1))

    # The same call again replays its result instead of running twice.
    assert {:block, "This tool call already ran. Its result was:\n\nbuilt"} =
             Threads.begin_tool_call(run, "call_1", "Bash", args, @tools)

    assert Repo.one!(from c in ToolCall, where: c.name == "Read", select: c.status) == "completed"
  end

  test "an external call whose outcome is unknown blocks the run's later built-in calls",
       %{user: user, account: account} do
    {:ok, _thread} = Threads.create(user, account, request())
    {:ok, {run, _}} = claim(Repo.one!(Run).id)

    assert {:error, :tool_outcome_unknown} =
             Threads.call_external_tool(run, Ecto.UUID.generate(), "deploy", %{}, fn -> {:error, :timeout} end)

    assert {:block, "An earlier tool call's outcome is unknown, so this call did not run."} =
             Threads.begin_tool_call(run, "call_1", "Bash", %{"command" => "make"}, @tools)
  end

  test "cancelling a stopped session's calls closes only the named open calls",
       %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    {:ok, {run, _}} = claim(Repo.one!(Run).id)

    assert :ok = Threads.begin_tool_call(run, "call_1", "Bash", %{"command" => "make"}, @tools)
    assert :ok = Threads.begin_tool_call(run, "call_2", "Read", %{"path" => "a"}, @tools)
    assert :ok = Threads.begin_tool_call(run, "call_3", "Grep", %{"pattern" => "x"}, @tools)
    assert :ok = Threads.complete_tool_call(run, "call_2", "Read", %{"path" => "a"}, {:ok, "contents"})

    Threads.cancel_tool_calls(run, ["Bash", "Read"])

    calls = Map.new(Repo.all(ToolCall), &{&1.name, {&1.status, &1.result}})
    assert {"completed", "Cancelled: " <> _} = calls["Bash"]
    assert calls["Read"] == {"completed", "contents"}
    assert {"executing", _} = calls["Grep"]

    {:ok, %{messages: messages}} = Threads.get(user, account, thread.id)
    assert Enum.any?(messages, &match?(%{tool_name: "Bash", tool_state: "complete", body: "Cancelled: " <> _}, &1))
  end

  test "an ambiguous tool effect blocks later writes and survives archiving", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    {:ok, {run, _}} = claim(Repo.one!(Run).id)
    failed = fn -> {:error, :workspace_command_failed} end
    invocation = Ecto.UUID.generate()

    assert {:error, :tool_outcome_unknown} =
             Threads.call_external_tool(run, invocation, "bash", %{"command" => "change-files"}, failed)

    assert {:error, :tool_outcome_unknown} =
             Threads.call_external_tool(run, invocation, "write", %{"path" => "other", "content" => "changed"}, failed)

    assert {:ok, _} = Threads.finish(run, {:ok, "Pretend success"})
    assert {:ok, fresh} = Threads.get(user, account, thread.id)
    assert fresh.agent_status == "outcome_unknown"
    refute Enum.any?(fresh.messages, &(&1.body == "Pretend success"))
    assert {:ok, _} = Threads.archive(user, account, thread.id, "archived")
    assert {:ok, _} = Threads.archive(user, account, thread.id, "active")
    assert {:error, :tool_outcome_unknown} = Threads.message(user, account, thread.id, request("Try a different write"))
  end

  test "a lapsed host's run is resumed under the next lease, which fences the old attempt", %{
    user: user,
    account: account
  } do
    {:ok, thread} = Threads.create(user, account, request())
    {:ok, {first, _}} = claim(Repo.one!(Run).id)
    assert first.session_id == thread.id
    lapse(thread.id)

    assert {:ok, {second, _}} = claim(first.id)
    assert second.attempt == first.attempt + 1
    assert second.session_id == thread.id
    refute Threads.owns_run?(first.id, first.attempt)
    assert {:error, :stale_run} = Threads.rename(first, "Stale title")
    assert {:ok, _} = Threads.rename(second, "Current title")
  end

  test "each run shows one plan, which its updates replace in place", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    {:ok, {run, _}} = claim(Repo.one!(Run).id)

    assert {:error, :invalid_arguments} = Threads.update_progress(run, [])
    assert {:error, :invalid_arguments} = Threads.update_progress(run, [%{"title" => "Read", "status" => "done"}])

    assert {:ok, _} =
             Threads.update_progress(run, [
               %{"title" => "Read the code", "status" => "in_progress"},
               %{"title" => "Run tests", "status" => "pending"}
             ])

    {:ok, _} = Threads.rename(run, "Plan")

    assert {:ok, _} =
             Threads.update_progress(run, [
               %{"title" => " Read the code ", "status" => "completed"},
               %{"title" => "Run tests", "status" => "in_progress"}
             ])

    {:ok, _} = Threads.finish(run, {:ok, "Done"})
    {:ok, _} = Threads.message(user, account, thread.id, request("Again"))
    {:ok, {next, _}} = claim(Repo.one!(from r in Run, where: r.status == "queued").id)
    {:ok, _} = Threads.update_progress(next, [%{"title" => "Answer", "status" => "in_progress"}])

    messages = Threads.serialize(Threads.history(Repo.reload!(thread))).messages
    assert [first, second] = Enum.filter(messages, &Map.get(&1, :progress))
    assert Enum.map(messages, & &1.role) == ["user", "system", "assistant", "user", "system"]
    assert first.content == "- [x] Read the code\n- [ ] Run tests (in progress)"

    assert first.progress == %{
             "steps" => [
               %{"title" => "Read the code", "status" => "completed"},
               %{"title" => "Run tests", "status" => "in_progress"}
             ]
           }

    assert second.progress == %{"steps" => [%{"title" => "Answer", "status" => "in_progress"}]}
  end

  test "a Bash call shows the build progress its command reported while it runs", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    {:ok, {run, _}} = claim(Repo.one!(Run).id)
    assert :ok = Threads.begin_tool_call(run, "call_1", "Bash", %{"command" => "once build"}, @tools)
    assert :ok = Threads.begin_tool_call(run, "call_2", "Bash", %{"command" => "once test"}, @tools)

    snapshot = %{
      "v" => 1,
      "command" => "build",
      "state" => "running",
      "target" => "//app\e[31m\u202E",
      "planned" => 40,
      "done" => 12,
      "cached" => 9,
      "failed" => "many",
      "running" => ["//lib:a", 7],
      "tests" => %{"passed" => 0, "failed" => 0, "skipped" => 0},
      "elapsed_ms" => 1200,
      "secret" => "dropped"
    }

    revision = Repo.reload!(thread).revision
    assert :ok = Threads.record_build_progress(run, "call_2", snapshot)
    # Unchanged progress, apart from the clock, writes nothing, and counts
    # that only moved on wait a few seconds.
    assert :ok = Threads.record_build_progress(run, "call_2", Map.put(snapshot, "elapsed_ms", 2400))
    assert :ok = Threads.record_build_progress(run, "call_2", Map.put(snapshot, "done", 13))
    assert Repo.reload!(thread).revision == revision + 1

    # Not Once's snapshot shape: ignored.
    assert :ok = Threads.record_build_progress(run, "call_1", %{"v" => 2, "command" => "build"})

    messages = Threads.serialize(Threads.history(Repo.reload!(thread))).messages
    assert [%{content: "Working…"} = first, second] = Enum.filter(messages, &(&1.role == "tool"))
    refute Map.has_key?(first, :build)
    assert second.content == "Building //app[31m with Once · 12 of 40 targets (9 cached)"

    assert second.build == %{
             "command" => "build",
             "state" => "running",
             "target" => "//app[31m",
             "planned" => 40,
             "done" => 12,
             "cached" => 9,
             "failed" => 0,
             "running" => ["//lib:a"],
             "tests" => %{"passed" => 0, "failed" => 0, "skipped" => 0}
           }

    # The call's result replaces the summary; its last progress stays as evidence.
    assert :ok = Threads.complete_tool_call(run, "call_2", "Bash", %{"command" => "once test"}, {:ok, "built"})
    assert :ok = Threads.record_build_progress(run, "call_2", Map.put(snapshot, "done", 40))
    messages = Threads.serialize(Threads.history(Repo.reload!(thread))).messages
    assert %{content: "built", build: %{"done" => 12}} = messages |> Enum.filter(&(&1.role == "tool")) |> List.last()

    # A new outcome shows at once.
    assert :ok = Threads.record_build_progress(run, "call_1", snapshot)
    revision = Repo.reload!(thread).revision
    assert :ok = Threads.record_build_progress(run, "call_1", Map.merge(snapshot, %{"state" => "failed", "done" => 13}))
    assert Repo.reload!(thread).revision == revision + 1
  end

  # A host whose lease lapsed still receives the thread's wakes until it is
  # drained; it must not start the work the new host starts.
  test "a host whose lease lapsed cannot claim the thread's next run", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    run = Repo.one!(Run)
    [%{epoch: old}] = Enum.filter(Lease.claim("host-a", 100), &(&1.id == thread.id))
    lapse(thread.id)
    [%{epoch: new}] = Enum.filter(Lease.claim("host-b", 100), &(&1.id == thread.id))

    assert {:error, :stale_run} = Threads.claim(run.id, old)
    assert Repo.reload!(run).status == "queued"
    assert {:ok, {claimed, _}} = Threads.claim(run.id, new)
    assert claimed.attempt == new
  end

  # Each host gives a run a fresh budget, so the run's age bounds them all.
  test "a run handed on past its age limit ends instead of running again", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    {:ok, {run, _}} = claim(Repo.one!(Run).id)
    old = DateTime.utc_now() |> DateTime.add(-4, :hour) |> DateTime.truncate(:second)
    Repo.update_all(from(r in Run, where: r.id == ^run.id), set: [inserted_at: old])
    lapse(thread.id)

    assert {:error, :expired} = claim(run.id)
    assert Repo.reload!(run).status == "failed"
    assert {:ok, fresh} = Threads.get(user, account, thread.id)
    assert fresh.agent_status == "failed"
  end

  # An earlier release's Oban job can end without finishing its run, leaving
  # it running with no host and no session that wants one.
  test "recovery hands an earlier release's orphaned run to the thread's session", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    stale = DateTime.utc_now() |> DateTime.add(-300, :second) |> DateTime.truncate(:second)

    run =
      Repo.update!(Ecto.Changeset.change(Repo.one!(Run), status: "running", attempt: 3, heartbeat_at: stale))

    Repo.delete_all(from(s in "agent_sessions", where: s.id == ^to_string(thread.id)))

    assert :ok = Threads.recover()

    assert %{wanted: true} = session(thread.id)
    [%{epoch: epoch}] = Enum.filter(Lease.claim("test-host", 100), &(&1.id == thread.id))
    assert epoch > run.attempt
    assert {:ok, _} = Threads.claim(run.id, epoch)
  end

  test "a resumed run replays completed effects instead of repeating them", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    {:ok, {run, _}} = claim(Repo.one!(Run).id)
    invocation = Ecto.UUID.generate()
    args = %{"command" => "change-files"}

    assert {:ok, "changed once"} =
             Threads.call_external_tool(run, invocation, "bash", args, fn -> {:ok, "changed once"} end)

    lapse(thread.id)
    {:ok, {resumed, _}} = claim(run.id)

    assert {:ok, "changed once"} =
             Threads.call_external_tool(resumed, invocation, "bash", args, fn -> flunk("repeated a completed effect") end)
  end

  test "deactivation fences running model and tool access", %{user: user, account: account} do
    {:ok, _} = Threads.create(user, account, request())
    {:ok, {run, _}} = claim(Repo.one!(Run).id)
    Repo.update!(change(user, active: false))
    refute Threads.owns_run?(run.id, run.attempt)
    assert {:error, :stale_run} = Threads.rename(run, "Late title")
  end

  for revocation <- [:permission, :inactive, :disabled, :feature] do
    @revocation revocation
    test "the host's claim terminalizes queued work after #{@revocation} revocation", %{user: user} do
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      :ok = Accounts.add_user_to_organization(user, organization, role: :admin)
      stub(FeatureFlags, :organization_luft_enabled?, fn _ -> true end)
      {:ok, thread} = Threads.create(user, account, request())
      queued = Repo.get_by!(Run, thread_id: thread.id)

      case @revocation do
        :permission -> Accounts.update_user_role_in_organization(user, organization, :user)
        :inactive -> Repo.update!(change(user, active: false))
        :disabled -> Repo.update!(change(user, disabled_at: DateTime.utc_now(:second)))
        :feature -> stub(FeatureFlags, :organization_luft_enabled?, fn _ -> false end)
      end

      stub(Tuist.Environment, :apns_configured?, fn -> true end)
      assert {:error, :forbidden} = claim(queued.id)
      # The owner can't open the thread anymore, so it isn't worth a notification.
      refute_enqueued(worker: ThreadFinishedWorker)
      assert Repo.reload!(queued).status == "interrupted"
      assert Repo.reload!(queued).attempt == 0
      assert Repo.reload!(thread).agent_status == "interrupted"
      assert Threads.next_run(thread.id) == nil

      case @revocation do
        :permission -> Accounts.update_user_role_in_organization(user, organization, :admin)
        :inactive -> Repo.update!(change(Repo.reload!(user), active: true))
        :disabled -> Repo.update!(change(Repo.reload!(user), disabled_at: nil))
        :feature -> stub(FeatureFlags, :organization_luft_enabled?, fn _ -> true end)
      end

      lapse(thread.id)
      assert {:error, :stale_run} = claim(queued.id)
      assert Enum.count(Threads.history(Repo.reload!(thread)).messages, &(&1.kind == "notice")) == 1
    end
  end

  test "revocation preserves uncertain effects in queued attempts", %{user: user, account: account} do
    runs =
      for _ <- 1..2 do
        {:ok, thread} = Threads.create(user, account, request())
        {:ok, {run, _}} = claim(Repo.get_by!(Run, thread_id: thread.id).id)

        assert {:error, :tool_outcome_unknown} =
                 Threads.call_external_tool(run, Ecto.UUID.generate(), "remote_write", %{}, fn ->
                   {:error, :timeout}
                 end)

        Repo.update!(change(run, status: "queued", heartbeat_at: nil))
      end

    Repo.update!(change(user, active: false))

    for run <- runs do
      lapse(run.thread_id)
      assert {:error, :forbidden} = claim(run.id)
      assert Repo.reload!(run).status == "outcome_unknown"
    end

    assert Repo.aggregate(from(c in "thread_tool_calls", where: c.status == "executing"), :count) == 2
    Repo.update!(change(Repo.reload!(user), active: true))

    for run <- runs do
      assert {:error, :stale_run} = claim(run.id)
      assert {:error, :tool_outcome_unknown} = Threads.message(user, account, run.thread_id, request("Continue"))
    end
  end

  test "archive cancels active work, restore does not restart it", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    {:ok, {run, _}} = claim(Repo.one!(Run).id)
    assert {:ok, %{status: :archived}} = Threads.archive(user, account, thread.id, "archived")
    assert {:error, :stale_run} = Threads.finish(run, {:ok, "Late private reply"})
    assert {:ok, %{status: :active, agent_status: "idle"}} = Threads.archive(user, account, thread.id, "active")
    assert Repo.reload!(run).status == "cancelled"
    assert Repo.aggregate(Run, :count) == 1
  end

  test "snoozing until needed lasts until the run stops", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    assert {:ok, %{snoozed_until_needed: true}} = Threads.snooze(user, account, thread.id, %{"until_needed" => true})
    assert Threads.serialize(Repo.reload!(thread)).snoozed_until_needed

    {:ok, {run, _}} = claim(Repo.one!(Run).id)
    {:ok, _} = Threads.finish(run, {:ok, "Done"})

    refute Repo.reload!(thread).snoozed_until_needed
    # Nothing is left to wait for once the thread waits for its owner.
    assert {:error, :not_working} = Threads.snooze(user, account, thread.id, %{"until_needed" => true})
  end

  test "a timed snooze ends at its time unless it was changed, and a message ends it early", %{
    user: user,
    account: account
  } do
    {:ok, thread} = Threads.create(user, account, request())
    {:ok, {run, _}} = claim(Repo.one!(Run).id)
    {:ok, _} = Threads.finish(run, {:ok, "Done"})
    first = DateTime.utc_now() |> DateTime.add(2, :hour) |> DateTime.truncate(:second)
    later = DateTime.add(first, 1, :hour)

    assert {:ok, %{snoozed_until: ^first}} =
             Threads.snooze(user, account, thread.id, %{"until" => DateTime.to_iso8601(first)})

    assert_enqueued(worker: SnoozeWorker, args: %{"thread_id" => thread.id}, scheduled_at: first)

    assert {:ok, %{snoozed_until: ^later}} =
             Threads.snooze(user, account, thread.id, %{"until" => DateTime.to_iso8601(later)})

    # The first snooze's job finds a different snooze and leaves it.
    assert :ok = perform_job(SnoozeWorker, %{"thread_id" => thread.id, "until" => DateTime.to_iso8601(first)})
    assert Repo.reload!(thread).snoozed_until == later
    assert :ok = perform_job(SnoozeWorker, %{"thread_id" => thread.id, "until" => DateTime.to_iso8601(later)})
    assert Repo.reload!(thread).snoozed_until == nil

    {:ok, _} = Threads.snooze(user, account, thread.id, %{"until" => DateTime.to_iso8601(later)})
    assert {:ok, %{snoozed_until: nil}} = Threads.message(user, account, thread.id, request("I'm back"))
  end

  test "snoozes only until a time in the next 30 days", %{user: user, account: account} do
    {:ok, thread} = Threads.create(user, account, request())
    past = DateTime.utc_now() |> DateTime.add(-60) |> DateTime.to_iso8601()
    far = DateTime.utc_now() |> DateTime.add(31, :day) |> DateTime.to_iso8601()

    for snooze <- [%{"until" => past}, %{"until" => far}, %{"until" => "tomorrow"}, %{"until_needed" => "yes"}, "later"] do
      assert {:error, :invalid_arguments} = Threads.snooze(user, account, thread.id, snooze)
    end

    assert {:error, :forbidden} = Threads.snooze(AccountsFixtures.user_fixture(), account, thread.id, nil)
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
    {:ok, {run, _}} = claim(Repo.one!(Run).id)
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
    {:ok, {run, _}} = claim(Repo.one!(Run).id)
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

  test "an agent's request binds only a repository the owner can read, on a branch that exists",
       %{user: user, account: account} do
    stub(Threads.Repository, :authorize, fn _, owner, name ->
      assert owner.id == user.id

      case String.downcase(name) do
        "tuist/example" -> {:ok, %{name: "Tuist/Example", default_branch: "main"}}
        "tuist/other" -> {:ok, %{name: "Tuist/Other", default_branch: "main"}}
        "tuist/private" -> {:error, :repository_access_denied}
        _ -> {:error, :repository_not_authorized}
      end
    end)

    stub(Threads.Repository, :branch_head, fn
      _, _, "main" -> {:ok, String.duplicate("a", 40)}
      _, _, _ -> {:error, :repository_unavailable}
    end)

    {:ok, thread} = Threads.create(user, account, request("Fix the login bug"))
    {:ok, {claimed, _}} = claim(Repo.one!(Run).id)

    assert {:error, :repository_not_authorized} = Threads.request_repository(claimed, %{"repository" => "tuist/secret"})
    assert {:error, :repository_access_denied} = Threads.request_repository(claimed, %{"repository" => "tuist/private"})

    # A missing branch binds nothing, rather than a repository no run can check out.
    assert {:error, :repository_unavailable} =
             Threads.request_repository(claimed, %{"repository" => "tuist/example", "base_branch" => "gone"})

    assert is_nil(Repo.get!(Thread, thread.id).repository)

    assert {:ok, {:attached, "Tuist/Example", "main"}} =
             Threads.request_repository(claimed, %{"repository" => "tuist/example"})

    bound = Repo.get!(Thread, thread.id)
    assert {bound.repository, bound.base_branch, bound.branch} == {"Tuist/Example", "main", "threads/#{thread.id}"}
    refute bound.workspace_ready

    # Asking again is idempotent; another repository is refused.
    assert {:ok, {:attached, "Tuist/Example", "main"}} =
             Threads.request_repository(claimed, %{"repository" => "Tuist/Example"})

    assert {:error, :repository_attached} = Threads.request_repository(claimed, %{"repository" => "tuist/other"})
  end

  # Takes the thread's session lease as an agents host does, then claims the
  # run at its epoch. A lease that is still held keeps its epoch.
  defp claim(run_id) do
    thread_id = Repo.get!(Run, run_id).thread_id
    Lease.claim("test-host", 1_000)
    Threads.claim(run_id, session(thread_id).epoch)
  end

  defp lapse(thread_id) do
    Repo.update_all(from(s in "agent_sessions", where: s.id == ^to_string(thread_id)),
      set: [lease_expires_at: DateTime.add(DateTime.utc_now(), -1)]
    )
  end

  defp session(thread_id),
    do:
      Repo.one!(
        from s in "agent_sessions",
          where: s.id == ^to_string(thread_id),
          select: %{wanted: s.wanted, kind: s.kind, epoch: s.epoch, host: s.host}
      )

  defp request(content \\ "Inspect the repository"),
    do: %{
      "content" => content,
      "request_id" => Ecto.UUID.generate(),
      "provider" => "chatgpt",
      "model" => "selected-model"
    }
end
