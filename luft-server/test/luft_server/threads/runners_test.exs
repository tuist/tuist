defmodule LuftServer.Threads.RunnersTest do
  use LuftServerWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.ConnTest, except: [connect: 3]

  alias LuftServer.Agents.Lease
  alias LuftServer.Repo
  alias LuftServer.RunnerCredentials
  alias LuftServer.Sessions
  alias LuftServer.Threads.Message
  alias LuftServer.Threads.Run
  alias LuftServer.Threads.Runner
  alias LuftServer.Threads.RunnerRequest
  alias LuftServer.Threads.Runners
  alias LuftServer.Threads.RunnerSandbox
  alias LuftServer.Threads.Thread
  alias LuftServerWeb.Plugs.Authenticate
  alias LuftServerWeb.ThreadRunnerConnectionController, as: Connection
  alias LuftServerWeb.ThreadRunnersController, as: Management

  setup do
    session = session("42")

    {:ok, runner, token} =
      Runners.register(session, %{"name" => " My Mac ", "platform" => "macos"})

    Req.Test.set_req_test_to_shared()

    Req.Test.stub(LuftServer.Tuist, fn conn ->
      Req.Test.json(conn, %{
        user_id: 42,
        account_id: 1,
        organization_id: nil,
        can_create_threads: true,
        people: []
      })
    end)

    owner = session("42")
    author = session("42")
    {thread, run} = running(runner, owner, author)

    %{
      session: session,
      runner: runner,
      token: token,
      owner: owner,
      author: author,
      thread: thread,
      run: run
    }
  end

  test "registration stores only a hash and keeps upstream-wrapped credentials working", ctx do
    assert ctx.runner.name == "My Mac"
    assert ctx.runner.user_id == 42
    assert ctx.runner.token_hash == :crypto.hash(:sha256, ctx.token)
    assert {:ok, %{id: id}, token} = RunnerCredentials.resolve(ctx.token)
    assert id == ctx.session.id
    assert token == ctx.token
    assert {:ok, %{id: runner_id}} = Runners.authenticate(ctx.token)
    assert runner_id == ctx.runner.id
    assert :error = RunnerCredentials.resolve(ctx.token <> "tampered")
    assert {:error, :unauthorized} = Runners.authenticate("tgr_upstream")
    wrapped = RunnerCredentials.wrap("tgr_upstream", ctx.session)
    assert {:ok, %{id: ^id}, "tgr_upstream"} = RunnerCredentials.resolve(wrapped)
    assert {:error, :unauthorized} = Runners.authenticate(wrapped)
    refute Map.has_key?(Runners.serialize(ctx.runner), :token_hash)
  end

  test "existing Authenticate plug resolves local machine credentials without granting management",
       ctx do
    conn =
      :post
      |> Plug.Test.conn("/api/thread-runner/poll", %{"wait_ms" => 0})
      |> put_req_header("authorization", "Bearer " <> ctx.token)
      |> Authenticate.call([])

    refute conn.halted
    assert conn.assigns.session.id == ctx.session.id
    assert conn.assigns.runner_token == ctx.token
    assert json_response(Connection.call(conn, :poll), 200) == %{"requests" => []}
    assert Management.call(conn, :index).status == 401

    assert Connection.call(Plug.Test.conn(:post, "/api/thread-runner/poll", %{}), :poll).status ==
             401
  end

  test "management response contracts and ownership", ctx do
    conn = manage(ctx.session, :create, %{"name" => "Linux", "platform" => "linux"})

    assert %{"id" => id, "token" => "luft_runner_local_" <> _, "online" => false} =
             json_response(conn, 201)

    response = ctx.session |> manage(:index) |> json_response(200)
    assert length(response["runners"]) == 2
    refute Enum.any?(response["runners"], &Map.has_key?(&1, "token"))
    assert manage(session("99"), :delete, %{"id" => id}).status == 404
    assert manage(ctx.session, :delete, %{"id" => "invalid"}).status == 404
    assert manage(ctx.session, :delete, %{"id" => id}).status == 204
    assert manage(ctx.session, :create, %{"name" => "", "platform" => "linux"}).status == 400
    assert manage(ctx.session, :create, %{"name" => "x", "platform" => "other"}).status == 400
  end

  test "registration limits are per person, not session or account", ctx do
    another_session = session("42")

    for n <- 1..19 do
      assert {:ok, _, _} =
               Runners.register(another_session, %{"name" => "runner #{n}", "platform" => "linux"})
    end

    assert manage(ctx.session, :create, %{"name" => "one too many", "platform" => "linux"}).status ==
             409

    assert :ok = Runners.revoke(ctx.session, ctx.runner.id)

    assert {:ok, _, _} =
             Runners.register(another_session, %{"name" => "replacement", "platform" => "linux"})
  end

  test "credentials stop on expiry, deletion and revocation; stale runner structs cannot claim or answer",
       ctx do
    request = request(ctx.runner)
    assert [%{"id" => id}] = Runners.poll(ctx.runner, %{}, 0)
    assert id == request.id
    assert :ok = Runners.revoke(ctx.session, ctx.runner.id)
    assert :error = RunnerCredentials.resolve(ctx.token)
    assert Runners.poll(ctx.runner, %{}, 0) == []
    assert {:error, :not_found} = Runners.respond(ctx.runner, id, %{"ok" => true})
    assert connect(ctx.token, :poll, %{"wait_ms" => 0}).status == 401

    {:ok, runner, token} =
      Runners.register(ctx.session, %{"name" => "second", "platform" => "linux"})

    Repo.update_all(from(s in Sessions.Session, where: s.id == ^ctx.session.id),
      set: [expires_at: DateTime.shift(DateTime.utc_now(:second), second: -1)]
    )

    assert :error = RunnerCredentials.resolve(token)
    assert Runners.poll(runner, %{}, 0) == []
    Repo.delete!(ctx.session)
    assert :error = RunnerCredentials.resolve(token)
    assert Repo.aggregate(RunnerCredentials.Binding, :count) == 0
  end

  test "poll and answer wire contracts persist locally and duplicate answers cannot overwrite",
       ctx do
    req = request(ctx.runner)

    conn =
      connect(ctx.token, :poll, %{
        "wait_ms" => -10,
        "terminal" => true,
        "folders" => ["/work"],
        "version" => "1"
      })

    assert %{"requests" => [%{"id" => id, "op" => "info", "value" => "payload"}]} =
             json_response(conn, 200)

    assert id == req.id
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert Repo.get!(RunnerRequest, id).status == "claimed"

    assert ctx.token |> connect(:poll, %{"wait_ms" => 0}) |> json_response(200) == %{
             "requests" => []
           }

    assert connect(ctx.token, :respond, %{"id" => id, "ok" => true, "result" => %{"answer" => 42}}).status ==
             204

    assert connect(ctx.token, :respond, %{"id" => id, "ok" => false}).status == 410

    assert Repo.get!(RunnerRequest, id).response == %{
             "ok" => true,
             "result" => %{"answer" => 42},
             "error" => nil
           }

    assert connect(ctx.token, :respond, %{"id" => "not-a-uuid"}).status == 410
    assert Runners.online?(Repo.get!(Runner, ctx.runner.id))
  end

  test "request ownership, pending answers and expiry are guarded", ctx do
    req = request(ctx.runner)
    assert {:error, :not_found} = Runners.respond(ctx.runner, req.id, %{"ok" => true})
    {:ok, other, _} = Runners.register(session("99"), %{"name" => "other", "platform" => "linux"})
    Runners.poll(ctx.runner, %{}, 0)
    assert {:error, :not_found} = Runners.respond(other, req.id, %{"ok" => true})

    Repo.update_all(RunnerRequest,
      set: [expires_at: DateTime.shift(DateTime.utc_now(:second), second: -1)]
    )

    assert {:error, :not_found} = Runners.respond(ctx.runner, req.id, %{"ok" => true})
    assert :ok = Runners.delete_expired()
    refute Repo.get(RunnerRequest, req.id)
  end

  test "lost polls reclaim the same request identity, but keep in-flight operations", ctx do
    req = request(ctx.runner)
    assert [%{"id" => id}] = Runners.poll(ctx.runner, %{}, 0)
    assert id == req.id
    old = DateTime.shift(DateTime.utc_now(:second), second: -20)
    Repo.update_all(RunnerRequest, set: [claimed_at: old])
    assert [] = Runners.poll(ctx.runner, %{"in_flight" => [id, "invalid"]}, 0)
    assert [%{"id" => ^id}] = Runners.poll(ctx.runner, %{}, 0)
  end

  test "display claims require the exact execution sessions, not a surviving runner sign-in",
       ctx do
    for session <- [ctx.owner, ctx.author] do
      request = request(ctx.runner, "click")

      Repo.update_all(from(s in Sessions.Session, where: s.id == ^session.id),
        set: [expires_at: DateTime.shift(DateTime.utc_now(:second), second: -1)]
      )

      assert [] = Runners.poll(ctx.runner, %{}, 0)
      assert Repo.get!(RunnerRequest, request.id).status == "cancelled"
      assert {:ok, _} = Runners.authenticate(ctx.token)

      Repo.update_all(from(s in Sessions.Session, where: s.id == ^session.id),
        set: [expires_at: DateTime.shift(DateTime.utc_now(:second), day: 1)]
      )
    end
  end

  test "queued display operations cannot outlive archival, lease loss or attempt replacement",
       ctx do
    request = request(ctx.runner, "type_text")
    Repo.update_all(Thread, set: [status: :archived])
    assert [] = Runners.poll(ctx.runner, %{}, 0)
    assert Repo.get!(RunnerRequest, request.id).status == "cancelled"
    Repo.update_all(Thread, set: [status: :active])

    request = request(ctx.runner, "click")
    Repo.update_all(Run, inc: [attempt: 1])
    assert [] = Runners.poll(ctx.runner, %{}, 0)
    assert Repo.get!(RunnerRequest, request.id).status == "cancelled"
    Repo.update_all(Run, inc: [attempt: -1])

    request = request(ctx.runner, "click")
    Lease.release(ctx.thread.id, ctx.run.attempt)
    assert [] = Runners.poll(ctx.runner, %{}, 0)
    assert Repo.get!(RunnerRequest, request.id).status == "cancelled"
  end

  test "selection reloads explicit account scope and enforces original owner session", ctx do
    pid = self()

    Req.Test.stub(LuftServer.Tuist, fn conn ->
      send(pid, {:scope, conn.request_path})

      Req.Test.json(conn, %{
        "user_id" => 42,
        "account_id" => 1,
        "organization_id" => nil,
        "can_create_threads" => true,
        "people" => []
      })
    end)

    assert {:ok, runner} = Runners.usable(ctx.session, "personal", ctx.runner.id)
    assert runner.id == ctx.runner.id
    assert_received {:scope, "/api/accounts/personal/luft-context"}

    thread = %{
      runner_id: runner.id,
      owner_id: 42,
      owner_session_id: ctx.session.id,
      account_handle: "personal"
    }

    assert {:ok, _} = Runners.for_thread(thread)
    assert_received {:scope, "/api/accounts/personal/luft-context"}
    assert {:error, :runner_not_found} = Runners.for_thread(%{thread | owner_id: 99})
    Req.Test.stub(LuftServer.Tuist, fn conn -> conn |> put_status(403) |> Req.Test.json(%{}) end)
    assert {:error, :runner_not_found} = Runners.for_thread(thread)
    Repo.delete!(ctx.session)
    assert {:error, :runner_not_found} = Runners.for_thread(thread)
  end

  test "call waits for a persisted answer and deletes the operation; timeouts also clean up",
       ctx do
    task = Task.async(fn -> Runners.call(ctx.runner.id, ctx.run, "info", %{}, 2_000) end)
    assert [%{"id" => id}] = Runners.poll(ctx.runner, %{}, 1_000)

    assert :ok =
             Runners.respond(ctx.runner, id, %{"ok" => true, "result" => %{"hello" => "world"}})

    assert {:ok, %{"hello" => "world"}} = Task.await(task)
    refute Repo.get(RunnerRequest, id)
    assert {:error, :timeout} = Runners.call(ctx.runner.id, ctx.run, "info", %{}, 0)
    assert Repo.aggregate(RunnerRequest, :count) == 0
  end

  test "sandbox preserves public operations, binary transport and shell environment", ctx do
    assert {:error, :invalid_runner_sandbox} = RunnerSandbox.init([])

    assert {:error, :invalid_runner_sandbox} =
             RunnerSandbox.init(runner_id: ctx.runner.id, cwd: "/work")

    assert {:ok, state} = RunnerSandbox.init(runner_id: ctx.runner.id, run: ctx.run, cwd: "/work")
    assert RunnerSandbox.cwd(state) == "/work"
    assert :ok = RunnerSandbox.shutdown(state)

    task = Task.async(fn -> RunnerSandbox.write_file(state, "binary", <<0, 255>>) end)

    assert [%{"id" => id, "path" => "/work/binary", "base64" => data}] =
             Runners.poll(ctx.runner, %{}, 1_000)

    assert Base.decode64!(data) == <<0, 255>>
    Runners.respond(ctx.runner, id, %{"ok" => true})
    assert :ok = Task.await(task)

    task =
      Task.async(fn ->
        RunnerSandbox.exec(state, "echo ok", env: [{"SAFE", "a'b"}, {"NOT VALID", "x"}])
      end)

    assert [%{"id" => id, "command" => command, "cwd" => "/work", "timeout_ms" => 120_000}] =
             Runners.poll(ctx.runner, %{}, 1_000)

    assert command == "export SAFE='a'\\''b'; echo ok"

    Runners.respond(ctx.runner, id, %{
      "ok" => true,
      "result" => %{"stdout" => "ok", "stderr" => "!", "exit_code" => 0}
    })

    assert {:ok, %{output: "ok!", exit_code: 0}} = Task.await(task)

    task = Task.async(fn -> RunnerSandbox.read_file(state, "~/binary") end)
    assert [%{"id" => id, "path" => "~/binary"}] = Runners.poll(ctx.runner, %{}, 1_000)
    Runners.respond(ctx.runner, id, %{"ok" => true, "result" => %{"base64" => data}})
    assert {:ok, <<0, 255>>} = Task.await(task)
  end

  test "display dispatch requires a live matching run and preserves the runner wire protocol",
       ctx do
    task =
      Task.async(fn ->
        RunnerSandbox.display(ctx.runner.id, ctx.run, "click", %{"x" => 7, "y" => 19})
      end)

    assert [%{"id" => id, "op" => "click", "x" => 7, "y" => 19} = wire] =
             Runners.poll(ctx.runner, %{}, 1_000)

    refute Map.has_key?(wire, "run_id")
    request = Repo.get!(RunnerRequest, id)
    assert request.run_id == ctx.run.id
    assert request.run_attempt == ctx.run.attempt
    assert :ok = Runners.respond(ctx.runner, id, %{"ok" => true, "result" => %{}})
    assert {:ok, %{}} = Task.await(task)

    {:ok, other, _} = Runners.register(ctx.session, %{"name" => "Other", "platform" => "linux"})
    assert {:error, :runner_not_found} = RunnerSandbox.display(other.id, ctx.run, "click", %{})

    assert {:error, :stale_run} =
             RunnerSandbox.display(
               ctx.runner.id,
               %{ctx.run | attempt: ctx.run.attempt + 1},
               "click",
               %{}
             )

    Repo.delete!(ctx.author)
    assert {:error, :stale_run} = RunnerSandbox.display(ctx.runner.id, ctx.run, "click", %{})
    assert Repo.aggregate(RunnerRequest, :count) == 0
  end

  defp session(sub) do
    {:ok, _, session} =
      Sessions.create(%{
        claims: %{"sub" => sub},
        tokens: %{"access_token" => "access", "refresh_token" => "refresh", "expires_in" => 3600}
      })

    session
  end

  defp request(runner, op \\ "info") do
    run =
      Repo.one!(
        from r in Run,
          join: t in Thread,
          on: t.id == r.thread_id,
          where: t.runner_id == ^runner.id
      )

    Repo.insert!(%RunnerRequest{
      runner_id: runner.id,
      run_id: run.id,
      run_attempt: run.attempt,
      op: op,
      payload: %{"value" => "payload"},
      expires_at: DateTime.shift(DateTime.utc_now(:second), minute: 1)
    })
  end

  defp running(runner, owner, author) do
    thread =
      Repo.insert!(%Thread{
        account_id: 1,
        account_handle: "personal",
        owner_id: 42,
        owner_session_id: owner.id,
        runner_id: runner.id,
        request_id: Ecto.UUID.generate(),
        request_hash: <<1>>,
        title: "Runner",
        goal: "Test runner",
        provider: "chatgpt",
        model: "test-model"
      })

    message =
      Repo.insert!(%Message{
        thread_id: thread.id,
        position: 1,
        kind: "human",
        author_id: 42,
        author_session_id: author.id,
        body: "Run"
      })

    Lease.want(thread.id, "thread")
    [%{epoch: epoch}] = Lease.claim(Ecto.UUID.generate(), 1)

    run =
      Repo.insert!(%Run{
        thread_id: thread.id,
        message_id: message.id,
        status: "running",
        attempt: epoch
      })

    {thread, run}
  end

  defp manage(session, action, params \\ %{}) do
    :post
    |> Plug.Test.conn("/api/me/thread-runners", params)
    |> assign(:session, session)
    |> Management.call(action)
  end

  defp connect(token, action, params) do
    :post
    |> Plug.Test.conn("/api/thread-runner/poll", params)
    |> put_req_header("authorization", "Bearer " <> token)
    |> Connection.call(action)
  end
end
