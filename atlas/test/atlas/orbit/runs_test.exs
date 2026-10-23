defmodule Atlas.Orbit.RunsTest do
  # Profiles bound to the Orbit role are a singleton across the table.
  # credo:disable-for-next-line Credo.Check.Warning.AsyncTests
  use Atlas.DataCase, async: false
  use Oban.Testing, repo: Atlas.Repo

  import Atlas.OrbitFixtures

  alias Atlas.Agents.Sessions.Event
  alias Atlas.Agents.Sessions.Session
  alias Atlas.Audit.Activity
  alias Atlas.Orbit
  alias Atlas.Orbit.Message
  alias Atlas.Orbit.Run
  alias Atlas.Orbit.Runs
  alias Atlas.Orbit.Thread
  alias Atlas.Orbit.Workers.RunThread
  alias Atlas.Repo

  setup do
    orbit_profile_fixture()
    :ok
  end

  test "runs a read-only tool, ratchets its scopes, and posts the reply" do
    owner = user_fixture(["accounts:read"])
    member = user_fixture(["accounts:read"])
    {:ok, thread} = Orbit.create_shared(owner, %{"title" => "Accounts", "participant_ids" => [member.id]})
    {:ok, _account} = Atlas.Accounts.create_manual_account(%{name: "Example Org"})
    run = post_and_get_run(owner, thread, "Which accounts exist?")
    test_pid = self()

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = JSON.decode!(body)
      send(test_pid, {:tools, Enum.map(request["tools"] || [], &get_in(&1, ["function", "name"]))})

      if Enum.any?(request["messages"], &(&1["role"] == "tool")) do
        Req.Test.json(conn, completion(%{"role" => "assistant", "content" => "There is one account."}))
      else
        Req.Test.json(conn, tool_call("list_accounts", %{"query" => "Example"}))
      end
    end

    assert :ok = Runs.execute(run.id, client_opts: client_opts(plug))
    assert_receive {:tools, tools}
    assert "list_accounts" in tools
    refute "list_finance_transactions" in tools

    assert %Run{status: "succeeded"} = Repo.get!(Run, run.id)
    assert Repo.get!(Thread, thread.id).required_scopes == ["accounts:read"]

    messages = thread |> Orbit.list_messages() |> elem(0)
    tool = Enum.find(messages, &(&1.kind == "tool"))
    assert tool.tool_name == "list_accounts" and tool.tool_status == "succeeded"
    assert tool.tool_input =~ "Example"
    assert tool.tool_output =~ "Example Org"
    assert %Message{body: "There is one account."} = Enum.find(messages, &(&1.kind == "agent"))

    # Audit and session telemetry never carry thread content.
    activity = Repo.one!(from a in Activity, where: a.action == "mcp.tool_called" and a.target_id == "list_accounts")
    assert activity.metadata["arguments"] == %{}
    assert activity.metadata["orbit_run_id"] == run.id

    session = Repo.one!(from s in Session, where: s.prompt == ^"orbit_run:#{run.id}")
    refute inspect(session.result) =~ "one account"
    events = Repo.all(from e in Event, where: e.agent_session_id == ^session.id)
    assert events != []
    refute Enum.any?(events, &(inspect(&1.metadata) =~ "Example"))
  end

  test "a tool the audience cannot all read is neither offered nor callable" do
    owner = user_fixture(["finance:read"])
    member = user_fixture()
    {:ok, thread} = Orbit.create_shared(owner, %{"title" => "Mixed", "participant_ids" => [member.id]})
    run = post_and_get_run(owner, thread, "What is our runway?")
    test_pid = self()

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = JSON.decode!(body)
      send(test_pid, {:tools, Enum.map(request["tools"] || [], &get_in(&1, ["function", "name"]))})

      if Enum.any?(request["messages"], &(&1["role"] == "tool")) do
        tool_result = Enum.find(request["messages"], &(&1["role"] == "tool"))
        send(test_pid, {:tool_result, tool_result["content"]})
        Req.Test.json(conn, completion(%{"role" => "assistant", "content" => "I can't look that up here."}))
      else
        Req.Test.json(conn, tool_call("get_finance_overview", %{}))
      end
    end

    assert :ok = Runs.execute(run.id, client_opts: client_opts(plug))
    assert_receive {:tools, tools}
    refute "get_finance_overview" in tools
    assert_receive {:tool_result, content}
    refute content =~ "cash"
    assert Repo.get!(Thread, thread.id).required_scopes == []
    refute thread |> Orbit.list_messages() |> elem(0) |> Enum.any?(&(&1.kind == "tool"))
  end

  test "cancellation discards the reply, and only queued runs start" do
    user = user_fixture()
    {:ok, thread, _} = Orbit.ensure_private(user)
    run = post_and_get_run(user, thread, "Hello")
    {:ok, _} = Orbit.cancel_run(user, thread, run.id)

    assert :ok = Runs.execute(run.id, client_opts: client_opts(fn _conn -> flunk("model called") end))
    assert %Run{status: "cancelled"} = Repo.get!(Run, run.id)
    assert :ok = Runs.execute(run.id, client_opts: client_opts(fn _conn -> flunk("model called") end))
  end

  test "a checkpointed run resumes on another worker with its recorded tool results" do
    user = user_fixture(["accounts:read"])
    {:ok, thread, _} = Orbit.ensure_private(user)
    run = post_and_get_run(user, thread, "Find Example Org")

    # Simulate a replica that started the run and recorded a tool call before a deploy.
    Repo.update_all(from(r in Run, where: r.id == ^run.id),
      set: [status: "running", heartbeat_at: DateTime.add(DateTime.utc_now(), -120)]
    )

    Repo.transaction(fn ->
      locked = Orbit.lock!(thread.id)

      Orbit.append!(locked, %{
        kind: "tool",
        run_id: run.id,
        tool_name: "list_accounts",
        tool_status: "succeeded",
        tool_input: ~s({"query":"Example"}),
        tool_output: ~s({"accounts":[{"name":"Example Org"}]})
      })

      Orbit.append!(locked, %{kind: "tool", run_id: run.id, tool_name: "get_account", tool_status: "running"})
    end)

    Runs.resume_stale()
    assert %Run{status: "queued", resume_count: 1} = Repo.get!(Run, run.id)
    assert_enqueued(worker: RunThread, args: %{"run_id" => run.id, "resume" => 1})
    assert Repo.get_by!(Message, run_id: run.id, tool_name: "get_account").tool_status == "cancelled"

    test_pid = self()

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:prompt, body})
      Req.Test.json(conn, completion(%{"role" => "assistant", "content" => "Example Org is an account."}))
    end

    assert :ok = Runs.execute(run.id, client_opts: client_opts(plug))
    assert_receive {:prompt, prompt}
    assert prompt =~ "Earlier in this run you called list_accounts"
    assert %Run{status: "succeeded"} = Repo.get!(Run, run.id)
  end

  test "runs stop resuming after the maximum number of checkpoints" do
    user = user_fixture()
    {:ok, thread, _} = Orbit.ensure_private(user)
    run = post_and_get_run(user, thread, "Hello")

    Repo.update_all(from(r in Run, where: r.id == ^run.id),
      set: [status: "running", resume_count: Runs.max_resumes(), heartbeat_at: DateTime.add(DateTime.utc_now(), -120)]
    )

    Runs.resume_stale()
    assert %Run{status: "interrupted"} = Repo.get!(Run, run.id)
  end

  test "a run whose acting user loses access is cancelled" do
    owner = user_fixture()
    member = user_fixture()
    {:ok, thread} = Orbit.create_shared(owner, %{"title" => "Team", "participant_ids" => [member.id]})
    run = post_and_get_run(member, thread, "Hello")
    test_pid = self()

    plug = fn conn ->
      send(test_pid, :model_called)
      Process.sleep(:infinity)
      conn
    end

    task = Task.async(fn -> Runs.execute(run.id, client_opts: client_opts(plug)) end)
    assert_receive :model_called, 2_000
    :ok = Orbit.remove_participant(owner, thread, member.id)
    send(task.pid, :heartbeat)
    assert :ok = Task.await(task, 5_000)
    assert %Run{status: "cancelled"} = Repo.get!(Run, run.id)
    refute thread |> Orbit.list_messages() |> elem(0) |> Enum.any?(&(&1.kind == "agent"))
  end

  test "follow-up runs pick up messages addressed during an active run" do
    user = user_fixture()
    {:ok, thread, _} = Orbit.ensure_private(user)
    run = post_and_get_run(user, thread, "First")

    {:ok, second, :created} =
      Orbit.post_message(user, thread, %{"body" => "Second", "client_id" => Ecto.UUID.generate()})

    plug = fn conn -> Req.Test.json(conn, completion(%{"role" => "assistant", "content" => "Done."})) end
    assert :ok = Runs.execute(run.id, client_opts: client_opts(plug))

    assert [%Run{status: "queued", trigger_seq: trigger}] =
             Repo.all(from r in Run, where: r.thread_id == ^thread.id and r.id != ^run.id)

    assert trigger == second.position
  end

  defp post_and_get_run(user, thread, body) do
    {:ok, _message, :created} =
      Orbit.post_message(user, thread, %{"body" => body, "client_id" => Ecto.UUID.generate()})

    Repo.one!(from r in Run, where: r.thread_id == ^thread.id and r.status == "queued")
  end
end
