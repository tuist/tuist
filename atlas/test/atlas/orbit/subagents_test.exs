defmodule Atlas.Orbit.SubagentsTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo

  import Atlas.OrbitFixtures

  alias Atlas.Authorization.Roles
  alias Atlas.Orbit
  alias Atlas.Orbit.Agent
  alias Atlas.Orbit.Message
  alias Atlas.Orbit.ModelFence
  alias Atlas.Orbit.Run
  alias Atlas.Orbit.Runs
  alias Atlas.Orbit.Subagents
  alias Atlas.Orbit.Thread
  alias Atlas.Orbit.Tools
  alias Atlas.Push.Workers.Deliver
  alias Atlas.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    # ModelFence links provider loops to their worker. This test process plays
    # that worker and, like Runs, handles their exits without dying itself.
    Process.flag(:trap_exit, true)
    owner = self()
    trace = Condukt.TraceContext.new()
    handler = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler,
      [:condukt, :agent, :start],
      fn _event, _measurements, _metadata, _config ->
        if Condukt.TraceContext.current() == trace, do: Sandbox.allow(Repo, owner, self())
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    %{trace: trace}
  end

  for kind <- [:private, :shared] do
    test "#{kind} research makes nested, fenced lookups and only the parent completes", %{trace: trace} do
      {owner, thread, run} = running(unquote(kind), ["accounts:read"])
      test_pid = self()

      plug = fn conn ->
        {body, conn} = request(conn)
        send(test_pid, {:request, body})
        names = tool_names(body)
        contents = inspect(body["messages"])

        response =
          cond do
            "task" in names and not String.contains?(contents, "Child findings") ->
              tool_call("task", %{"task" => "Research accounts"})

            "task" in names ->
              completion(%{"role" => "assistant", "content" => "Parent answer."})

            not String.contains?(contents, "tool_call_id") ->
              refute "subagent" in names
              refute "task" in names
              refute "search_web" in names
              assert "list_accounts" in names
              tool_call("list_accounts", %{})

            true ->
              completion(%{"role" => "assistant", "content" => "Child findings"})
          end

        Req.Test.json(conn, response)
      end

      session = session(run, plug)
      assert {:ok, "Parent answer."} = Condukt.run(session, "Find accounts", trace_context: trace)
      assert %Run{status: "running"} = Repo.get!(Run, run.id)
      task = Repo.get_by!(Message, run_id: run.id, tool_name: "task")
      nested = Repo.get_by!(Message, run_id: run.id, tool_name: "list_accounts")
      assert task.tool_status == "succeeded" and task.parent_message_id == nil
      assert nested.parent_message_id == task.id and nested.tool_status == "succeeded"
      assert Repo.get!(Thread, thread.id).required_scopes == ["accounts:read"]
      refute Repo.exists?(from message in Message, where: message.run_id == ^run.id and message.kind == "agent")
      assert [] = all_enqueued(worker: Deliver)

      assert :ok = Runs.complete(run.id, run.resume_count, {:ok, "Parent answer."})

      assert Repo.aggregate(
               from(message in Message, where: message.run_id == ^run.id and message.kind == "agent"),
               :count
             ) == 1

      assert {:ok, _} = Orbit.fetch(owner, thread.id)
    end
  end

  test "completed research replays across attempts, without another child or tool card", %{trace: trace} do
    {_owner, _thread, run} = running(:private, [])
    test_pid = self()

    plug = fn conn ->
      {body, conn} = request(conn)

      if "task" in tool_names(body) do
        if inspect(body["messages"]) =~ "Child findings" do
          Req.Test.json(conn, completion(%{"role" => "assistant", "content" => "Done"}))
        else
          Req.Test.json(conn, tool_call("task", %{"task" => "One question"}))
        end
      else
        send(test_pid, :child_called)
        Req.Test.json(conn, completion(%{"role" => "assistant", "content" => "Child findings"}))
      end
    end

    assert {:ok, "Done"} = Condukt.run(session(run, plug), "Research", trace_context: trace)
    assert_receive :child_called
    assert :requeued = Runs.checkpoint(run.id, 0)
    run = Repo.update!(Ecto.Changeset.change(Repo.get!(Run, run.id), status: "running"))
    assert {:ok, "Done"} = Condukt.run(session(run, plug), "Research again", trace_context: trace)
    refute_receive :child_called

    assert Repo.aggregate(
             from(message in Message, where: message.run_id == ^run.id and message.tool_name == "task"),
             :count
           ) == 1
  end

  test "shared audience denial applies even to an invented child tool call", %{trace: trace} do
    {_owner, _thread, run} = running(:shared, ["accounts:read"], [])

    plug = fn conn ->
      {body, conn} = request(conn)
      contents = inspect(body["messages"])

      response =
        cond do
          "task" in tool_names(body) and not String.contains?(contents, "Child done") ->
            tool_call("task", %{"task" => "Find accounts"})

          "task" in tool_names(body) ->
            completion(%{"role" => "assistant", "content" => "Parent done"})

          not String.contains?(contents, "tool_call_id") ->
            refute "list_accounts" in tool_names(body)
            tool_call("list_accounts", %{})

          true ->
            completion(%{"role" => "assistant", "content" => "Child done"})
        end

      Req.Test.json(conn, response)
    end

    assert {:ok, "Parent done"} = Condukt.run(session(run, plug), "Research", trace_context: trace)

    refute Repo.exists?(
             from message in Message, where: message.run_id == ^run.id and message.tool_name == "list_accounts"
           )
  end

  test "revoking the acting user's scope discards the child result and blocks replay", %{trace: trace} do
    {owner, _thread, run} = running(:shared, ["accounts:read"])
    role = Roles.get_role_by_slug("test-#{owner.id}")
    parent = task_card(run)

    # Gather and ratchet actual child evidence before revocation.
    assert {:ok, _} = Tools.call(run.id, 0, "list_accounts", %{}, parent.id)
    {:ok, _} = Roles.update_role(role, %{scopes: []})

    assert {:error, _} = Tools.call(run.id, 0, "list_accounts", %{}, parent.id)
    assert {:error, _} = Tools.task(run, %{"task" => "No access now"}, %{})

    plug = fn _conn -> flunk("revoked child dispatched a provider request") end
    assert {:error, _} = Condukt.run(session(run, plug), "Research", trace_context: trace)
  end

  test "shared access revoked during child inference discards its completed findings", %{trace: trace} do
    {owner, _thread, run} = running(:shared, ["accounts:read"])
    role = Roles.get_role_by_slug("test-#{owner.id}")

    plug = fn conn ->
      {body, conn} = request(conn)

      response =
        cond do
          "task" in tool_names(body) ->
            tool_call("task", %{"task" => "Research before revocation"})

          not String.contains?(inspect(body["messages"]), "tool_call_id") ->
            tool_call("list_accounts", %{})

          true ->
            {:ok, _} = Roles.update_role(role, %{scopes: []})
            completion(%{"role" => "assistant", "content" => "Findings that must be discarded"})
        end

      Req.Test.json(conn, response)
    end

    assert {:error, _} = Condukt.run(session(run, plug), "Research", trace_context: trace)
    task = Repo.get_by!(Message, run_id: run.id, tool_name: "task")
    assert task.tool_status == "cancelled" and task.tool_output == "" and task.tool_result == nil
    assert {:error, _} = Tools.task(run, %{"task" => "Research before revocation"}, %{})
    refute Repo.exists?(from message in Message, where: message.run_id == ^run.id and message.kind == "agent")
  end

  test "root replay keys remain stable and identical child lookups are distinct per task" do
    {_owner, _thread, run} = running(:private, ["accounts:read"])
    first = task_card(run)
    second = task_card(run)
    assert {:ok, _} = Tools.call(run.id, 0, "list_accounts", %{})
    assert {:ok, _} = Tools.call(run.id, 0, "list_accounts", %{}, first.id)
    assert {:ok, _} = Tools.call(run.id, 0, "list_accounts", %{}, second.id)
    cards = Repo.all(from message in Message, where: message.run_id == ^run.id and message.tool_name == "list_accounts")
    assert length(cards) == 3
    assert length(Enum.uniq_by(cards, & &1.tool_call_key)) == 3
    root = Enum.find(cards, &is_nil(&1.parent_message_id))

    expected =
      :sha256
      |> :crypto.hash(:erlang.term_to_binary({"list_accounts", %{}}, [:deterministic]))
      |> Base.encode16(case: :lower)

    assert root.tool_call_key == expected
  end

  test "reservation boundaries, invalid input, and unfenced contexts cannot start children" do
    {_owner, _thread, run} = running(:private, [])
    assert {:error, _} = Tools.task(run, %{"task" => String.duplicate("x", 4_001)}, %{})
    assert {:error, _} = Tools.task(run, %{"task" => "x", "role" => "other"}, %{})
    assert {:error, _} = Tools.task(run, %{"task" => "   "}, %{})
    assert Repo.aggregate(from(message in Message, where: message.run_id == ^run.id), :count) == 0

    first = task_card(run)
    second = task_card(run)
    assert {:error, _} = Tools.task(run, %{"task" => "Third active"}, %{})
    for task <- [first, second], do: Repo.update!(Ecto.Changeset.change(task, tool_status: "failed"))
    assert {:error, _} = Tools.task(run, %{"task" => "Third total, unfenced"}, %{})
    assert {:error, _} = Tools.task(run, %{"task" => "Fourth total, unfenced"}, %{})
    assert {:error, _} = Tools.task(run, %{"task" => "Fifth total"}, %{})

    assert Repo.aggregate(
             from(message in Message, where: message.run_id == ^run.id and message.tool_name == "task"),
             :count
           ) == 4
  end

  test "expired, foreign, finished and superseded parents cannot execute nested tools" do
    {_owner, _thread, run} = running(:private, [])
    {_other, _other_thread, other_run} = running(:private, [])
    foreign = task_card(other_run)
    parent = task_card(run)
    assert {:error, _} = Tools.call(run.id, 0, "list_tasks", %{}, foreign.id)
    Repo.update!(Ecto.Changeset.change(parent, inserted_at: DateTime.add(DateTime.utc_now(), -61)))
    assert Tools.build(run, parent.id) == []
    assert {:error, _} = Tools.call(run.id, 0, "list_tasks", %{}, parent.id)
    Repo.update!(Ecto.Changeset.change(parent, tool_status: "succeeded"))
    assert {:error, _} = Tools.call(run.id, 0, "list_tasks", %{}, parent.id)
    assert {:error, _} = Tools.task(%{run | resume_count: 1}, %{"task" => "Stale"}, %{})
  end

  test "a child stops after six model turns and returns only a fixed failure", %{trace: trace} do
    {_owner, _thread, run} = running(:private, [])
    test_pid = self()

    plug = fn conn ->
      {body, conn} = request(conn)

      response =
        if "task" in tool_names(body) do
          if inspect(body["messages"]) =~ "failed or was interrupted" do
            completion(%{"role" => "assistant", "content" => "Parent survived"})
          else
            tool_call("task", %{"task" => "Never finish"})
          end
        else
          send(test_pid, :child_turn)
          tool_call("list_tasks", %{})
        end

      Req.Test.json(conn, response)
    end

    assert {:ok, "Parent survived"} = Condukt.run(session(run, plug), "Research", trace_context: trace)
    for _ <- 1..6, do: assert_receive(:child_turn)
    refute_receive :child_turn
    assert Repo.get_by!(Message, run_id: run.id, tool_name: "task").tool_status == "failed"
  end

  test "cancelling a parent kills a blocked child model loop", %{trace: trace} do
    {_owner, _thread, run} = running(:private, [])
    test_pid = self()

    plug = fn conn ->
      {body, conn} = request(conn)

      if "task" in tool_names(body) do
        Req.Test.json(conn, tool_call("task", %{"task" => "Wait"}))
      else
        send(test_pid, {:blocked_child, self()})

        receive do
          :continue -> Req.Test.json(conn, completion(%{"role" => "assistant", "content" => "Too late"}))
        end
      end
    end

    session = session(run, plug)
    caller = Task.async(fn -> Condukt.run(session, "Research", trace_context: trace) end)
    assert_receive {:blocked_child, child}, 5_000
    child_monitor = Process.monitor(child)
    Repo.update!(Ecto.Changeset.change(run, cancel_requested_at: DateTime.utc_now()))
    # Runs.stop_session/1 kills each registered model process on cancellation.
    assert_receive {:thread_model_process, root}, 2_000
    Process.exit(root, :kill)
    assert_receive {:DOWN, ^child_monitor, :process, ^child, _}, 2_000
    Process.exit(session, :kill)
    assert {:error, _} = Task.await(caller, 2_000)
    refute Repo.exists?(from message in Message, where: message.run_id == ^run.id and message.kind == "agent")
  end

  defp session(run, plug) do
    opts =
      client_opts(plug)
      |> ModelFence.wrap(run, self())
      |> Keyword.merge(
        tools: Tools.build(run) ++ [Subagents.tool(run)],
        system_prompt: Agent.system_prompt(),
        load_project_instructions: false,
        retry: false
      )

    pid = start_supervised!(Supervisor.child_spec({Agent, opts}, id: make_ref()))
    Sandbox.allow(Repo, self(), pid)
    pid
  end

  defp running(kind, scopes, member_scopes \\ nil) do
    owner = user_fixture(scopes)

    thread =
      case kind do
        :private ->
          {:ok, thread, _} = Orbit.ensure_private(owner)
          thread

        :shared ->
          member = user_fixture(member_scopes || scopes)
          {:ok, thread} = Orbit.create_shared(owner, %{"title" => "Research", "participant_ids" => [member.id]})
          thread
      end

    run = Repo.insert!(%Run{thread_id: thread.id, acting_user_id: owner.id, status: "running", trigger_seq: 0})
    {owner, thread, run}
  end

  defp task_card(run) do
    {:ok, message} =
      Runs.with_attempt(run.id, run.resume_count, fn thread, _ ->
        Orbit.append!(thread, %{kind: "tool", run_id: run.id, tool_name: "task", tool_status: "running"})
      end)

    message
  end

  defp request(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    {JSON.decode!(body), conn}
  end

  defp tool_names(body), do: Enum.map(body["tools"] || [], & &1["function"]["name"])
end
