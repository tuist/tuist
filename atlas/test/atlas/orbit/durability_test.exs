defmodule Atlas.Orbit.DurabilityTest do
  @moduledoc """
  Regression coverage for run fencing, deploy/replica-loss resumption, and the
  final-reply authorization fence.
  """
  # Profiles bound to the Orbit role are a singleton across the table.
  # credo:disable-for-next-line Credo.Check.Warning.AsyncTests
  use Atlas.DataCase, async: false
  use Oban.Testing, repo: Atlas.Repo

  import Atlas.OrbitFixtures

  alias Atlas.Audit.Activity
  alias Atlas.Authorization.Roles
  alias Atlas.Orbit
  alias Atlas.Orbit.Checkpoints
  alias Atlas.Orbit.Message
  alias Atlas.Orbit.ModelFence
  alias Atlas.Orbit.Run
  alias Atlas.Orbit.Runs
  alias Atlas.Orbit.Thread
  alias Atlas.Orbit.Tools
  alias Atlas.Orbit.Workers.RunThread
  alias Atlas.Repo

  setup do
    orbit_profile_fixture()
    user = user_fixture(["accounts:read"])
    {:ok, thread, _} = Orbit.ensure_private(user)

    {:ok, _message, :created} =
      Orbit.post_message(user, thread, %{
        "body" => "Find Example Org",
        "client_id" => Ecto.UUID.generate()
      })

    run = Repo.one!(from r in Run, where: r.thread_id == ^thread.id)
    %{user: user, thread: thread, run: run}
  end

  describe "attempt fencing" do
    test "a superseded attempt cannot write tool cards, finish, or checkpoint its successor", %{
      run: run,
      thread: thread
    } do
      running!(run, attempt: 0)
      assert :requeued = Runs.checkpoint(run.id, 0)
      running!(run, attempt: 1)

      assert {:error, _} = Tools.call(run.id, 0, "list_accounts", %{})
      refute Repo.exists?(from m in Message, where: m.run_id == ^run.id and m.kind == "tool")

      assert :stale = Runs.complete(run.id, 0, {:ok, "Old attempt reply"})
      refute Repo.exists?(from m in Message, where: m.thread_id == ^thread.id and m.kind == "agent")

      assert :stale = Runs.checkpoint(run.id, 0)
      assert %Run{status: "running", resume_count: 1} = Repo.get!(Run, run.id)

      # The owning attempt still works.
      assert {:ok, _} = Tools.call(run.id, 1, "list_accounts", %{})
      assert :ok = Runs.complete(run.id, 1, {:ok, "New attempt reply"})
      assert %Run{status: "succeeded"} = Repo.get!(Run, run.id)
    end

    test "the sweeper re-checks the lease under the lock", %{run: run} do
      running!(run, attempt: 0)

      # The scan saw an expired lease, but the worker renewed before the lock.
      assert :fresh = Runs.checkpoint(run.id, 0, only_if_expired: true)
      assert %Run{status: "running", resume_count: 0} = Repo.get!(Run, run.id)
    end

    test "duplicate jobs for the same attempt start the run once", %{run: run} do
      plug = fn conn -> Req.Test.json(conn, completion(%{"role" => "assistant", "content" => "Done."})) end
      assert :ok = Runs.execute(run.id, client_opts: client_opts(plug))
      assert :ok = Runs.execute(run.id, client_opts: client_opts(fn _ -> flunk("model called twice") end))
      assert Repo.aggregate(from(m in Message, where: m.run_id == ^run.id and m.kind == "agent"), :count) == 1
    end
  end

  describe "final reply authorization" do
    test "a reply is discarded when the acting user lost access before completion" do
      owner = user_fixture()
      member = user_fixture()
      {:ok, shared} = Orbit.create_shared(owner, %{"title" => "Team", "participant_ids" => [member.id]})

      {:ok, _m, :created} =
        Orbit.post_message(member, shared, %{"body" => "Hi", "client_id" => Ecto.UUID.generate()})

      run = Repo.one!(from r in Run, where: r.thread_id == ^shared.id)
      running!(run, attempt: 0)
      :ok = Orbit.remove_participant(owner, shared, member.id)

      assert :ok = Runs.complete(run.id, 0, {:ok, "Reply built for the old audience"})
      assert %Run{status: "cancelled", error_category: "access_changed"} = Repo.get!(Run, run.id)
      refute Repo.exists?(from m in Message, where: m.thread_id == ^shared.id and m.kind == "agent")
    end

    test "adding a participant cancels the run so its reply is discarded", %{user: _user} do
      owner = user_fixture()
      newcomer = user_fixture()
      {:ok, shared} = Orbit.create_shared(owner, %{"title" => "Team"})

      {:ok, _m, :created} =
        Orbit.post_message(owner, shared, %{"body" => "Hi", "client_id" => Ecto.UUID.generate()})

      run = Repo.one!(from r in Run, where: r.thread_id == ^shared.id)
      running!(run, attempt: 0)

      {:ok, _} = Orbit.add_participant(owner, shared, newcomer.id)
      assert :ok = Runs.complete(run.id, 0, {:ok, "Reply"})
      assert %Run{status: "cancelled"} = Repo.get!(Run, run.id)
      refute Repo.exists?(from m in Message, where: m.thread_id == ^shared.id and m.kind == "agent")
    end
  end

  describe "deploys and lost replicas" do
    test "a shutdown signal checkpoints the attempt and enqueues a resume", %{run: run} do
      test_pid = self()

      plug = fn conn ->
        send(test_pid, {:model_called, self()})
        Process.sleep(:infinity)
        conn
      end

      worker = Task.async(fn -> Runs.execute(run.id, client_opts: client_opts(plug)) end)
      assert_receive {:model_called, _}, 2_000
      send(worker.pid, {:EXIT, self(), :shutdown})
      assert :ok = Task.await(worker, 5_000)

      assert %Run{status: "queued", resume_count: 1, session_id: nil} = Repo.get!(Run, run.id)
      assert_enqueued(worker: RunThread, args: %{"run_id" => run.id, "resume" => 1})
    end

    test "a worker crash that is not a shutdown fails the run instead of looping", %{run: run} do
      # Invalid client options crash the run task itself.
      assert :ok = Runs.execute(run.id, client_opts: :invalid)
      assert %Run{status: "failed", error_category: "crashed"} = Repo.get!(Run, run.id)
      refute_enqueued(worker: RunThread, args: %{"run_id" => run.id, "resume" => 1})
    end

    test "a model call that never returns is stopped at the run deadline", %{run: run} do
      plug = fn conn ->
        Process.sleep(:infinity)
        conn
      end

      assert :ok = Runs.execute(run.id, client_opts: client_opts(plug), max_duration: 300)
      assert %Run{status: "failed", error_category: "timeout"} = Repo.get!(Run, run.id)
    end

    test "per-turn snapshots are encrypted and restore the exact protocol messages on resume", %{run: run} do
      running!(run, attempt: 0)
      %Run{session_id: session_id} = Repo.get!(Run, run.id)

      messages = [
        Condukt.Message.user("Original request with the triggering question"),
        Condukt.Message.assistant("Looking that up.")
      ]

      :telemetry.execute([:condukt, :llm_turn, :start], %{system_time: 0}, %{
        agent: Atlas.Orbit.Agent,
        session_id: session_id,
        turn: 1,
        messages: messages
      })

      stored = Repo.get!(Run, run.id)
      assert stored.checkpoint_turn == 1
      assert {:ok, %{messages: ^messages}} = Checkpoints.load(stored)

      %{rows: [[raw]]} =
        Repo.query!("SELECT checkpoint FROM orbit_runs WHERE id = $1", [Ecto.UUID.dump!(run.id)])

      refute raw =~ "Original request"

      # Another attempt's session cannot overwrite it.
      Checkpoints.record("some-other-session", [Condukt.Message.user("intruder")], 2)
      assert Repo.get!(Run, run.id).checkpoint_turn == 1

      assert :requeued = Runs.checkpoint(run.id, 0)
      test_pid = self()

      plug = fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:request, JSON.decode!(body)})
        Req.Test.json(conn, completion(%{"role" => "assistant", "content" => "Resumed."}))
      end

      assert :ok = Runs.execute(run.id, client_opts: client_opts(plug))
      assert_receive {:request, %{"messages" => sent}}
      contents = Enum.map(sent, &(&1["content"] |> inspect()))
      assert Enum.any?(contents, &(&1 =~ "Original request with the triggering question"))
      assert Enum.any?(contents, &(&1 =~ "interrupted by a server restart"))
      assert %Run{status: "succeeded", checkpoint: nil} = Repo.get!(Run, run.id)
    end

    test "undecodable snapshots fall back to transcript replay", %{run: run} do
      running!(run, attempt: 0)
      Repo.update_all(from(r in Run, where: r.id == ^run.id), set: [checkpoint: "not a term"])
      assert :none = Checkpoints.load(Repo.get!(Run, run.id))
    end

    test "messages posted while a run is checkpointed are answered by a follow-up", ctx do
      %{run: run, user: user, thread: thread} = ctx
      running!(run, attempt: 0)

      {:ok, later, :created} =
        Orbit.post_message(user, thread, %{"body" => "Also this", "client_id" => Ecto.UUID.generate()})

      assert :requeued = Runs.checkpoint(run.id, 0)

      plug = fn conn -> Req.Test.json(conn, completion(%{"role" => "assistant", "content" => "Done."})) end
      assert :ok = Runs.execute(run.id, client_opts: client_opts(plug))

      assert [%Run{status: "queued", trigger_seq: trigger}] =
               Repo.all(from r in Run, where: r.thread_id == ^thread.id and r.id != ^run.id)

      assert trigger == later.position
    end
  end

  describe "lease transfer" do
    test "a worker whose lease was transferred stops its session and cannot write", %{
      run: run,
      thread: thread
    } do
      test_pid = self()

      blocking = fn conn ->
        send(test_pid, {:model_called, :a, self()})
        Process.sleep(:infinity)
        conn
      end

      worker_a =
        Task.async(fn ->
          Runs.execute(run.id, client_opts: client_opts(blocking), heartbeat_interval: :timer.hours(1))
        end)

      assert_receive {:model_called, :a, a_model_call}, 2_000
      a_call_monitor = Process.monitor(a_model_call)

      # Replica A goes quiet; its lease expires and the sweeper hands the run over.
      expire_lease!(run)
      Runs.resume_stale()
      assert %Run{status: "queued", resume_count: 1} = Repo.get!(Run, run.id)

      replying = fn conn ->
        Req.Test.json(conn, completion(%{"role" => "assistant", "content" => "From replica B."}))
      end

      assert :ok = Runs.execute(run.id, client_opts: client_opts(replying))
      assert %Run{status: "succeeded", resume_count: 1} = Repo.get!(Run, run.id)

      # Replica A wakes up: its renewal fails, so it kills its session.
      send(worker_a.pid, :heartbeat)
      assert :ok = Task.await(worker_a, 5_000)
      assert_receive {:DOWN, ^a_call_monitor, :process, _, _}, 2_000

      replies = Repo.all(from m in Message, where: m.thread_id == ^thread.id and m.kind == "agent")
      assert Enum.map(replies, & &1.body) == ["From replica B."]
    end

    test "a worker that cannot renew in time fences itself before the lease can transfer", %{run: run} do
      test_pid = self()

      blocking = fn conn ->
        send(test_pid, {:model_called, self()})
        Process.sleep(:infinity)
        conn
      end

      worker =
        Task.async(fn ->
          Runs.execute(run.id,
            client_opts: client_opts(blocking),
            heartbeat_interval: :timer.hours(1),
            self_fence_after: 0
          )
        end)

      assert_receive {:model_called, model_call}, 2_000
      monitor = Process.monitor(model_call)
      # The fence window elapsed without a renewal.
      Process.sleep(5)
      send(worker.pid, :heartbeat)
      assert :ok = Task.await(worker, 5_000)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 2_000
      # It stopped without writing; the sweeper resumes it once the lease expires.
      assert %Run{status: "running", resume_count: 0} = Repo.get!(Run, run.id)
    end

    test "a worker that dies takes its model session with it", %{run: run} do
      test_pid = self()

      blocking = fn conn ->
        send(test_pid, {:model_called, self()})
        Process.sleep(:infinity)
        conn
      end

      worker = spawn(fn -> Runs.execute(run.id, client_opts: client_opts(blocking)) end)
      assert_receive {:model_called, model_call}, 2_000
      monitor = Process.monitor(model_call)
      Process.exit(worker, :kill)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 2_000
    end
  end

  describe "ratchet on failures" do
    test "an authorized tool error ratchets its scopes, so later readers must hold them" do
      owner = user_fixture(["accounts:read", "documents:read"])
      {:ok, shared} = Orbit.create_shared(owner, %{"title" => "Accounts"})

      {:ok, _m, :created} =
        Orbit.post_message(owner, shared, %{"body" => "Look up", "client_id" => Ecto.UUID.generate()})

      run = Repo.one!(from r in Run, where: r.thread_id == ^shared.id)
      running!(run, attempt: 0)

      assert {:error, reason} = Tools.call(run.id, 0, "get_account", %{"account_id" => Ecto.UUID.generate()})
      assert Repo.get_by!(Message, run_id: run.id, tool_name: "get_account").tool_output == reason
      assert Enum.sort(Repo.get!(Thread, shared.id).required_scopes) == ["accounts:read", "documents:read"]

      outsider = user_fixture(["accounts:read"])
      assert {:error, :missing_access} = Orbit.add_participant(owner, shared, outsider.id)
    end

    test "an authorized tool error hides the thread from existing lower-scope participants" do
      owner = user_fixture(["accounts:read", "documents:read"])
      member = user_fixture(["accounts:read", "documents:read"])
      {:ok, shared} = Orbit.create_shared(owner, %{"title" => "Accounts", "participant_ids" => [member.id]})

      {:ok, _m, :created} =
        Orbit.post_message(owner, shared, %{"body" => "Look up", "client_id" => Ecto.UUID.generate()})

      run = Repo.one!(from r in Run, where: r.thread_id == ^shared.id)
      running!(run, attempt: 0)

      assert {:error, _reason} = Tools.call(run.id, 0, "get_account", %{"account_id" => Ecto.UUID.generate()})

      # The member later loses documents access: the failed card's history is no longer readable to them.
      role = Roles.get_role_by_slug("test-#{member.id}")
      {:ok, _} = Roles.update_role(role, %{scopes: ["accounts:read"]})
      assert {:error, :not_found} = Orbit.fetch(member, shared.id)
      assert {:ok, _} = Orbit.fetch(owner, shared.id)
    end
  end

  describe "model fence" do
    test "a superseded or cancelled attempt cannot make another model call", %{
      run: run,
      user: user,
      thread: thread
    } do
      running!(run, attempt: 1)
      inner = fn conn -> Req.Test.json(conn, %{"ok" => true}) end
      fence = fn attempt -> ModelFence.init(run_id: run.id, attempt: attempt, worker: self(), inner: inner) end
      request = fn -> Plug.Test.conn(:post, "/chat/completions", "{}") end

      assert ModelFence.call(request.(), fence.(1)).status == 200
      assert ModelFence.call(request.(), fence.(0)).status == 409
      assert_received {:thread_model_process, pid} when pid == self()

      {:ok, _} = Orbit.cancel_run(user, thread, run.id)
      assert ModelFence.call(request.(), fence.(1)).status == 409
    end
  end

  describe "resumption without duplicate events" do
    test "a resumed attempt answers completed tool calls from their record instead of executing again", ctx do
      %{run: run, thread: thread} = ctx
      {:ok, _} = Atlas.Accounts.create_manual_account(%{name: "Example Org"})
      running!(run, attempt: 0)
      args = %{"query" => "Example"}

      assert {:ok, first} = Tools.call(run.id, 0, "list_accounts", args)
      assert :requeued = Runs.checkpoint(run.id, 0)
      running!(run, attempt: 1)
      executions = audit_count("list_accounts")

      assert {:ok, ^first} = Tools.call(run.id, 1, "list_accounts", args)
      assert audit_count("list_accounts") == executions
      assert Repo.aggregate(from(m in Message, where: m.run_id == ^run.id and m.kind == "tool"), :count) == 1

      # Completed results stay encrypted until the run finishes, then are dropped.
      assert :ok = Runs.complete(run.id, 1, {:ok, "Done."})
      refute Repo.one!(from m in Message, where: m.run_id == ^run.id and m.kind == "tool").tool_result

      assert Repo.aggregate(
               from(m in Message, where: m.thread_id == ^thread.id and m.kind == "agent"),
               :count
             ) == 1
    end

    test "a tool call interrupted mid-flight reuses its card when the resumed attempt makes it", %{run: run} do
      running!(run, attempt: 0)

      Repo.transaction(fn ->
        locked = Orbit.lock!(run.thread_id)

        key =
          :crypto.hash(:sha256, :erlang.term_to_binary({"list_tasks", %{}}, [:deterministic]))
          |> Base.encode16(case: :lower)

        Orbit.append!(locked, %{
          kind: "tool",
          run_id: run.id,
          tool_name: "list_tasks",
          tool_status: "running",
          tool_call_key: key
        })
      end)

      assert :requeued = Runs.checkpoint(run.id, 0)
      assert Repo.get_by!(Message, run_id: run.id, tool_name: "list_tasks").tool_status == "cancelled"
      running!(run, attempt: 1)

      assert {:ok, _} = Tools.call(run.id, 1, "list_tasks", %{})

      assert [%Message{tool_status: "succeeded"}] =
               Repo.all(from m in Message, where: m.run_id == ^run.id and m.kind == "tool")
    end
  end

  describe "queued work is never lost" do
    test "a queued run whose job disappeared is re-enqueued once", %{run: run} do
      Repo.delete_all(Oban.Job)
      Repo.update_all(from(r in Run, where: r.id == ^run.id), set: [updated_at: DateTime.add(DateTime.utc_now(), -120)])

      Runs.recover_queued()
      assert_enqueued(worker: RunThread, args: %{"run_id" => run.id, "resume" => 0})
      Runs.recover_queued()
      assert Repo.aggregate(Oban.Job, :count) == 1
    end

    test "an interrupted run still starts a follow-up for messages addressed after it", ctx do
      %{run: run, user: user, thread: thread} = ctx

      {:ok, later, :created} =
        Orbit.post_message(user, thread, %{"body" => "And this?", "client_id" => Ecto.UUID.generate()})

      running!(run, attempt: Runs.max_resumes())
      expire_lease!(run)

      Runs.resume_stale()
      assert %Run{status: "interrupted"} = Repo.get!(Run, run.id)

      assert [%Run{status: "queued", trigger_seq: trigger}] =
               Repo.all(from r in Run, where: r.thread_id == ^thread.id and r.id != ^run.id)

      assert trigger == later.position
    end
  end

  describe "replay context and privacy" do
    test "fallback replay keeps the triggering request even behind many tool calls", ctx do
      %{run: run, thread: thread} = ctx

      Repo.transaction(fn ->
        locked = Orbit.lock!(thread.id)

        for n <- 1..45 do
          Orbit.append!(locked, %{
            kind: "tool",
            run_id: run.id,
            tool_name: "list_accounts",
            tool_status: "succeeded",
            tool_input: "{}",
            tool_output: "result #{n}"
          })
        end
      end)

      test_pid = self()

      plug = fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:body, body})
        Req.Test.json(conn, completion(%{"role" => "assistant", "content" => "Done."}))
      end

      assert :ok = Runs.execute(run.id, client_opts: client_opts(plug))
      assert_receive {:body, body}
      assert body =~ "Find Example Org"
    end

    test "a resumed run's system prompt reflects the current audience, not the stored one" do
      owner = user_fixture()
      member = user_fixture()
      {:ok, shared} = Orbit.create_shared(owner, %{"title" => "Team", "participant_ids" => [member.id]})

      {:ok, _m, :created} =
        Orbit.post_message(owner, shared, %{"body" => "Hi", "client_id" => Ecto.UUID.generate()})

      run = Repo.one!(from r in Run, where: r.thread_id == ^shared.id)
      running!(run, attempt: 0)
      %Run{session_id: session_id} = Repo.get!(Run, run.id)
      Checkpoints.record(session_id, [Condukt.Message.user("Hi")], 0)
      assert :requeued = Runs.checkpoint(run.id, 0)
      :ok = Orbit.remove_participant(owner, shared, member.id)
      # Removing a participant does not cancel; only additions do.
      test_pid = self()

      plug = fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        send(
          test_pid,
          {:system, body |> JSON.decode!() |> Map.fetch!("messages") |> hd() |> Map.fetch!("content") |> inspect()}
        )

        Req.Test.json(conn, completion(%{"role" => "assistant", "content" => "Done."}))
      end

      assert :ok = Runs.execute(run.id, client_opts: client_opts(plug))
      assert_receive {:system, system}
      assert system =~ owner.name
      refute system =~ member.name
    end

    test "a failed checkpoint logs only a fixed category" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          :telemetry.execute([:condukt, :llm_turn, :start], %{system_time: 0}, %{
            agent: Atlas.Orbit.Agent,
            session_id: Condukt.SessionID.generate(),
            turn: 1,
            messages: "private thread text that is not a list"
          })
        end)

      assert log =~ "thread checkpoint failed"
      refute log =~ "private thread text"

      assert Enum.any?(
               :telemetry.list_handlers([:condukt, :llm_turn, :start]),
               &(&1.id == "atlas-thread-checkpoints")
             )
    end
  end

  defp expire_lease!(run) do
    Repo.update_all(from(r in Run, where: r.id == ^run.id), set: [heartbeat_at: DateTime.add(DateTime.utc_now(), -120)])
  end

  defp audit_count(tool) do
    Repo.aggregate(from(a in Activity, where: a.action == "mcp.tool_called" and a.target_id == ^tool), :count)
  end

  defp running!(run, attempt: attempt) do
    Repo.update_all(from(r in Run, where: r.id == ^run.id),
      set: [
        status: "running",
        resume_count: attempt,
        heartbeat_at: DateTime.utc_now(),
        session_id: Condukt.SessionID.generate()
      ]
    )
  end
end
