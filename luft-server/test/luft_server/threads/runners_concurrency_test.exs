defmodule LuftServer.Threads.RunnersConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias LuftServer.Agents.Lease
  alias LuftServer.Repo
  alias LuftServer.Sessions
  alias LuftServer.Threads.Message
  alias LuftServer.Threads.Run
  alias LuftServer.Threads.RunnerRequest
  alias LuftServer.Threads.Runners
  alias LuftServer.Threads.Thread

  setup do
    # Independent committed connections are necessary to exercise row locking.
    :ok = Sandbox.checkout(Repo, sandbox: false)
    sessions = for role <- ~w(registration owner author), do: session(role)
    [registration, owner, author] = sessions

    {:ok, runner, _} =
      Runners.register(registration, %{"name" => "Concurrent runner", "platform" => "linux"})

    thread =
      Repo.insert!(%Thread{
        account_id: 1,
        account_handle: "personal",
        owner_id: 42,
        owner_session_id: owner.id,
        runner_id: runner.id,
        request_id: Ecto.UUID.generate(),
        request_hash: <<1>>,
        title: "Runner concurrency",
        goal: "Test execution authority",
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

    session_ids = Enum.map(sessions, & &1.id)

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      Repo.delete_all(from t in Thread, where: t.id == ^thread.id)
      Repo.delete_all(from s in "agent_sessions", where: s.id == ^thread.id)
      Repo.delete!(runner)
      Repo.delete_all(from s in Sessions.Session, where: s.id in ^session_ids)
      Sandbox.checkin(Repo)
    end)

    Req.Test.set_req_test_to_shared()
    %{runner: runner, thread: thread, run: run, author: author, registration: registration}
  end

  test "author logout cannot commit in the middle of a runner claim", ctx do
    request = request(ctx)
    parent = self()

    stub_scope(fn ->
      [[backend]] = Repo.query!("SELECT pg_backend_pid()").rows
      send(parent, {:author_scope, self(), backend})

      receive do
        :continue -> :ok
      after
        5_000 -> raise "author scope was not released"
      end
    end)

    claim = independent(fn -> Runners.poll(ctx.runner, %{}, 0) end)
    assert_receive {:author_scope, scope_pid, claim_backend}, 5_000

    # Both execution and registration sessions must permit credential rotation.
    refreshes =
      for session <- [ctx.author, ctx.registration], do: Task.await(refresh_session(session))

    logout =
      independent(fn ->
        [[backend]] = Repo.query!("SELECT pg_backend_pid()").rows
        send(parent, {:logout_started, backend})
        Sessions.delete(ctx.author)
      end)

    assert_receive {:logout_started, logout_backend}, 5_000

    blocked =
      try do
        blocked_by?(logout_backend, claim_backend, System.monotonic_time(:millisecond) + 1_000)
      after
        send(scope_pid, :continue)
      end

    claimed = Task.await(claim)
    assert :ok = Task.await(logout)
    assert refreshes == List.duplicate({:ok, {:ok, "access-refreshed"}}, 2)
    assert blocked, "logout must wait for the authorizing claim to commit"
    assert [%{"id" => id}] = claimed
    assert id == request.id
    assert Repo.get!(RunnerRequest, id).status == "claimed"
    refute Sessions.get_by_id(ctx.author.id)

    # A subsequent operation cannot inherit authority from the runner sign-in.
    next = request(ctx)
    assert [] = Runners.poll(ctx.runner, %{}, 0)
    assert Repo.get!(RunnerRequest, next.id).status == "cancelled"
  end

  test "refresh works when registration, owner and author use the same session", ctx do
    Repo.update_all(from(t in Thread, where: t.id == ^ctx.thread.id),
      set: [owner_session_id: ctx.registration.id]
    )

    Repo.update_all(from(m in Message, where: m.id == ^ctx.run.message_id),
      set: [author_session_id: ctx.registration.id]
    )

    request = request(ctx)
    parent = self()

    stub_scope(
      fn ->
        send(parent, {:scope_locked, self()})

        receive do
          :continue -> :ok
        after
          5_000 -> raise "shared-session scope was not released"
        end
      end,
      "registration-access"
    )

    claim = independent(fn -> Runners.poll(ctx.runner, %{}, 0) end)
    assert_receive {:scope_locked, scope_pid}, 5_000

    refreshed =
      try do
        Task.await(refresh_session(ctx.registration))
      after
        send(scope_pid, :continue)
      end

    assert [%{"id" => id}] = Task.await(claim)
    assert id == request.id
    assert refreshed == {:ok, {:ok, "access-refreshed"}}
    assert Repo.get!(RunnerRequest, id).status == "claimed"
  end

  test "concurrent polls with session references hand out each operation once", ctx do
    request = request(ctx)
    stub_scope(fn -> :ok end)
    parent = self()

    polls =
      for _ <- 1..2 do
        independent(fn ->
          try do
            Repo.transaction(fn ->
              # Execution transactions already hold session references before
              # checking registration. Reproduce that state on both replicas.
              Repo.one!(
                from s in Sessions.Session,
                  where: s.id == ^ctx.registration.id,
                  lock: "FOR KEY SHARE"
              )

              send(parent, {:poll_ready, self()})

              receive do
                :go -> Runners.poll(ctx.runner, %{}, 0)
              after
                5_000 -> raise "concurrent poll was not started"
              end
            end)
          rescue
            error in Postgrex.Error -> {:error, error.postgres.code}
          end
        end)
      end

    workers =
      for _ <- polls do
        assert_receive {:poll_ready, pid}, 5_000
        pid
      end

    Enum.each(workers, &send(&1, :go))
    results = Enum.map(polls, &Task.await(&1, 10_000))
    assert Enum.all?(results, &match?({:ok, _}, &1)), inspect(results)
    assert [%{"id" => id}] = Enum.flat_map(results, fn {:ok, requests} -> requests end)
    assert id == request.id
    assert Repo.get!(RunnerRequest, id).status == "claimed"
  end

  test "a lease expiring during upstream authorization cannot hand out an operation", ctx do
    request = request(ctx)
    parent = self()

    Repo.query!(
      "UPDATE agent_sessions SET lease_expires_at = clock_timestamp() + interval '2 seconds' WHERE id = $1",
      [ctx.thread.id]
    )

    stub_scope(fn ->
      # Let wall time cross the actual expiry while the claim transaction stays
      # open. CURRENT_TIMESTAMP would still see its earlier transaction start.
      Repo.query!(
        """
        SELECT pg_sleep((GREATEST(0, EXTRACT(EPOCH FROM (lease_expires_at - clock_timestamp()))) + 0.02)::double precision)
        FROM agent_sessions WHERE id = $1
        """,
        [ctx.thread.id]
      )

      send(parent, :lease_expired_during_authorization)
    end)

    assert [] = Runners.poll(ctx.runner, %{}, 0)
    assert_received :lease_expired_during_authorization
    assert Repo.get!(RunnerRequest, request.id).status == "cancelled"
  end

  defp stub_scope(during_claim, access_token \\ "author-access") do
    Req.Test.stub(LuftServer.Tuist, fn conn ->
      if String.ends_with?(conn.request_path, "/luft-context") do
        if Repo.in_transaction?() and
             Plug.Conn.get_req_header(conn, "authorization") == ["Bearer " <> access_token] and
             not Process.get(:runner_scope_paused, false) do
          Process.put(:runner_scope_paused, true)
          during_claim.()
        end

        Req.Test.json(conn, %{
          user_id: 42,
          account_id: 1,
          organization_id: nil,
          can_create_threads: true,
          people: []
        })
      else
        case conn.request_path do
          "/.well-known/openid-configuration" ->
            Req.Test.json(conn, %{
              issuer: "https://tuist.test",
              token_endpoint: "https://tuist.test/oauth2/token",
              revocation_endpoint: "https://tuist.test/oauth2/revoke"
            })

          "/oauth2/token" ->
            Req.Test.json(conn, %{
              access_token: "access-refreshed",
              refresh_token: "refresh-rotated",
              expires_in: 3_600
            })

          _ ->
            Req.Test.json(conn, %{})
        end
      end
    end)
  end

  defp refresh_session(session) do
    independent(fn ->
      try do
        Repo.transaction(fn ->
          Repo.query!("SET LOCAL lock_timeout = '500ms'")

          Repo.update_all(from(s in Sessions.Session, where: s.id == ^session.id),
            set: [access_token_expires_at: DateTime.shift(DateTime.utc_now(:second), second: -1)]
          )

          Sessions.access_token(Sessions.get_by_id(session.id))
        end)
      rescue
        error in Postgrex.Error -> {:error, error.postgres.code}
      end
    end)
  end

  defp independent(fun) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      fun.()
    end)
  end

  defp blocked_by?(backend, blocker, deadline) do
    [[blocked]] =
      Repo.query!("SELECT $1::integer = ANY(pg_blocking_pids($2::integer))", [blocker, backend]).rows

    cond do
      blocked ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(10)
        blocked_by?(backend, blocker, deadline)
    end
  end

  defp session(role) do
    {:ok, _, session} =
      Sessions.create(%{
        claims: %{"sub" => "42"},
        tokens: %{
          "access_token" => "#{role}-access",
          "refresh_token" => "refresh",
          "expires_in" => 3_600
        }
      })

    session
  end

  defp request(ctx) do
    Repo.insert!(%RunnerRequest{
      runner_id: ctx.runner.id,
      run_id: ctx.run.id,
      run_attempt: ctx.run.attempt,
      op: "click",
      payload: %{"x" => 7, "y" => 19},
      expires_at: DateTime.shift(DateTime.utc_now(:second), minute: 1)
    })
  end
end
