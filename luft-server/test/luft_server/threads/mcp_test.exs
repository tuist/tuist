defmodule LuftServer.Threads.MCPTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Plug.Conn

  alias Ecto.Adapters.SQL.Sandbox
  alias LuftServer.Agents.Lease
  alias LuftServer.Repo
  alias LuftServer.Sessions
  alias LuftServer.Threads.MCP
  alias LuftServer.Threads.Message
  alias LuftServer.Threads.Participant
  alias LuftServer.Threads.Run
  alias LuftServer.Threads.Thread
  alias LuftServer.Threads.ToolCall
  alias LuftServer.Threads.TuistTools

  @base "/api/me/mcp-servers/transport"
  @server "019a50ec-f33b-7000-8000-000000000001"
  @endpoint String.duplicate("a", 64)

  setup do
    owner = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    author = session(12, "author-token")
    owner_session = session(11, "owner-token")

    thread =
      Repo.insert!(%Thread{
        owner_id: 11,
        owner_session_id: owner_session.id,
        account_id: 21,
        account_handle: "team",
        request_id: Ecto.UUID.generate(),
        request_hash: <<1>>,
        title: "Test",
        goal: "hello",
        revision: 1,
        provider: "chatgpt",
        model: "model"
      })

    message =
      Repo.insert!(%Message{
        thread_id: thread.id,
        position: 1,
        kind: "human",
        author_id: 12,
        author_session_id: author.id,
        body: "hello"
      })

    Repo.insert!(%Participant{thread_id: thread.id, user_id: 12})
    Lease.want(thread.id, "thread")
    [%{epoch: epoch}] = Lease.claim(Ecto.UUID.generate(), 1)

    run =
      Repo.insert!(%Run{
        thread_id: thread.id,
        message_id: message.id,
        status: "running",
        attempt: epoch
      })

    %{thread: thread, message: message, run: run, author: author}
  end

  test "profile discovery and durable calls use persisted author's session, not owner token",
       ctx do
    test = self()

    upstream(fn conn ->
      assert get_req_header(conn, "authorization") == ["Bearer author-token"]

      case conn.request_path do
        @base ->
          Req.Test.json(conn, metadata())

        @base <> "/" <> @server <> "/tools" ->
          Req.Test.json(conn, %{tools: [definition()]})

        @base <> "/" <> @server <> "/tools/call" ->
          {:ok, body, conn} = read_body(conn)

          assert Jason.decode!(body) == %{
                   "endpoint" => @endpoint,
                   "name" => "read",
                   "arguments" => %{}
                 }

          send(test, :called)
          Req.Test.json(conn, %{result: %{content: [%{type: "text", text: "author-token"}]}})
      end
    end)

    assert {:ok, [tool], []} = MCP.discover(ctx.thread, ctx.message, ctx.run)
    {:env, env} = :erlang.fun_info(tool.call, :env)
    refute inspect(env, limit: :infinity) =~ "author-token"
    assert {:ok, output} = Condukt.Tool.execute(tool, %{}, %{})
    assert output =~ "[REDACTED]"
    refute output =~ "author-token"
    assert_received :called
    assert [%{status: "completed"}] = Repo.all(ToolCall)
  end

  test "missing exact author delegation never falls back to owner's or author's other session",
       ctx do
    _another = session(12, "another-token")
    Repo.delete!(ctx.author)
    Req.Test.stub(LuftServer.Tuist, fn _ -> flunk("no session means no upstream request") end)

    assert {:error, {:not_dispatched, :delegation_unavailable}} =
             MCP.discover(ctx.thread, ctx.message, ctx.run)
  end

  test "scope revocation and tenant mismatch fail closed", ctx do
    for account <- [nil, 99] do
      Req.Test.stub(LuftServer.Tuist, fn conn ->
        if is_nil(account),
          do: conn |> put_status(403) |> Req.Test.json(%{}),
          else: scope(conn, account)
      end)

      assert {:error, {:not_dispatched, :delegation_unavailable}} =
               MCP.discover(ctx.thread, ctx.message, ctx.run)
    end
  end

  test "uncertain external effects remain executing and are never redispatched", ctx do
    test = self()

    upstream(fn conn ->
      case conn.request_path do
        @base ->
          Req.Test.json(conn, metadata())

        @base <> "/" <> @server <> "/tools" ->
          Req.Test.json(conn, %{tools: [definition()]})

        @base <> "/" <> @server <> "/tools/call" ->
          send(test, :effect)
          Req.Test.transport_error(conn, :timeout)
      end
    end)

    assert {:ok, [tool], []} = MCP.discover(ctx.thread, ctx.message, ctx.run)
    assert {:error, :tool_outcome_unknown} = Condukt.Tool.execute(tool, %{}, %{})
    assert_received :effect
    assert [%{status: "executing"}] = Repo.all(ToolCall)
    assert {:error, :tool_outcome_unknown} = Condukt.Tool.execute(tool, %{}, %{})
    refute_received :effect
  end

  test "revocation after discovery completes as a definitive non-effect", ctx do
    upstream(fn conn ->
      if conn.request_path == @base,
        do: Req.Test.json(conn, metadata()),
        else: Req.Test.json(conn, %{tools: [definition()]})
    end)

    assert {:ok, [tool], []} = MCP.discover(ctx.thread, ctx.message, ctx.run)
    # The exact persisted message remains authoritative, not the struct the
    # host originally handed discovery.
    Repo.update!(Ecto.Changeset.change(ctx.message, author_session_id: nil))
    assert {:error, _} = Condukt.Tool.execute(tool, %{}, %{})
    refute Repo.exists?(from c in ToolCall, where: c.status == "completed")
  end

  test "a server whose discovery fails is skipped and named, keeping the others' tools", ctx do
    broken = "019a50ec-f33b-7000-8000-000000000002"

    upstream(fn conn ->
      cond do
        conn.request_path == @base ->
          Req.Test.json(conn, %{
            servers: [
              %{id: broken, name: "Broken", connected: true, endpoint: @endpoint},
              %{id: @server, name: "Profile", connected: true, endpoint: @endpoint}
            ],
            builtin_mcp_allowed: true
          })

        conn.request_path == @base <> "/" <> broken <> "/tools" ->
          conn |> put_status(403) |> Req.Test.json(%{error: %{code: "mcp_unavailable"}})

        conn.request_path == @base <> "/" <> @server <> "/tools" ->
          Req.Test.json(conn, %{tools: [definition()]})
      end
    end)

    assert {:ok, [tool], ["Broken"]} = MCP.discover(ctx.thread, ctx.message, ctx.run)
    assert tool.description =~ "read"
  end

  test "large profile catalogs offer searchable tools rather than silently dropping entries",
       ctx do
    for count <- [65, 101] do
      upstream(fn conn ->
        if conn.request_path == @base,
          do: Req.Test.json(conn, metadata()),
          else:
            Req.Test.json(conn, %{
              tools: for(n <- 1..count, do: Map.put(definition(), "name", "read_#{n}"))
            })
      end)

      assert {:ok, [search, call], []} = MCP.discover(ctx.thread, ctx.message, ctx.run)
      assert search.name == "mcp_search_tools" and call.name == "mcp_call_tool"
      assert {:ok, output} = Condukt.Tool.execute(search, %{"query" => "read_#{count}"}, %{})
      assert [%{"description" => description}] = Jason.decode!(output)["tools"]
      assert description =~ "read_#{count}"

      assert {:error, :inference_tool_budget_exceeded} =
               MCP.discover(ctx.thread, ctx.message, ctx.run, [], 63)
    end
  end

  test "built-ins need an actually granted mcp scope, not only personal-app admission", ctx do
    upstream(fn conn -> Req.Test.json(conn, metadata(false)) end)

    assert {:error, :tuist_mcp_scope_required} =
             TuistTools.tools(ctx.thread, ctx.message, ctx.run)
  end

  test "built-ins discover readOnlyHint only and preserve protocol/session headers over /mcp",
       ctx do
    test = self()

    upstream(fn conn ->
      assert get_req_header(conn, "authorization") == ["Bearer author-token"]

      if conn.request_path == @base do
        Req.Test.json(conn, metadata())
      else
        assert conn.request_path == "/mcp"
        {:ok, body, conn} = read_body(conn)
        envelope = Jason.decode!(body)

        if envelope["method"] != "initialize" do
          assert get_req_header(conn, "mcp-session-id") == ["tuist-session"]
          assert get_req_header(conn, "mcp-protocol-version") == ["2025-03-26"]
        end

        result =
          case envelope["method"] do
            "initialize" ->
              %{protocolVersion: "2025-03-26", capabilities: %{tools: %{}}}

            "notifications/initialized" ->
              %{}

            "tools/list" ->
              %{
                tools: [
                  Map.put(definition(), "annotations", %{"readOnlyHint" => true}),
                  Map.merge(definition(), %{
                    "name" => "write",
                    "annotations" => %{"readOnlyHint" => false}
                  })
                ]
              }

            "tools/call" ->
              assert envelope["params"]["name"] == "read"
              send(test, :tuist_read)
              %{content: [%{type: "text", text: "done"}]}
          end

        conn
        |> put_resp_header("mcp-session-id", "tuist-session")
        |> Req.Test.json(%{jsonrpc: "2.0", id: envelope["id"], result: result})
      end
    end)

    assert {:ok, [{"read", tool}]} = TuistTools.tools(ctx.thread, ctx.message, ctx.run)
    assert tool.name == "tuist_read"
    assert {:ok, output} = Condukt.Tool.execute(tool, %{}, %{})
    assert output =~ "done"
    assert_received :tuist_read
    assert [%{status: "completed"}] = Repo.all(ToolCall)
  end

  defp upstream(handler) do
    Req.Test.stub(LuftServer.Tuist, fn conn ->
      if conn.request_path == "/api/accounts/team/luft-context",
        do: scope(conn, 21),
        else: handler.(conn)
    end)
  end

  defp scope(conn, account) do
    id = if get_req_header(conn, "authorization") == ["Bearer owner-token"], do: 11, else: 12

    Req.Test.json(conn, %{
      user_id: id,
      account_id: account,
      organization_id: account,
      can_create_threads: true,
      people: [
        %{id: 11, handle: "owner", active: true},
        %{id: 12, handle: "author", active: true}
      ]
    })
  end

  defp session(id, token) do
    {:ok, _, session} =
      Sessions.create(%{
        claims: %{"sub" => to_string(id)},
        tokens: %{"access_token" => token, "refresh_token" => "refresh", "expires_in" => 3600}
      })

    session
  end

  defp metadata(builtin \\ true),
    do: %{
      servers: [%{id: @server, name: "Profile", connected: true, endpoint: @endpoint}],
      builtin_mcp_allowed: builtin
    }

  defp definition,
    do: %{"name" => "read", "description" => "Read", "inputSchema" => %{"type" => "object"}}
end
