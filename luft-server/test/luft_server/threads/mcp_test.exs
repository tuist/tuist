defmodule LuftServer.Threads.MCPTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  import Plug.Conn

  alias Ecto.Adapters.SQL.Sandbox
  alias LuftServer.Agents.Lease
  alias LuftServer.MCPServers.Server
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

  test "discovery and durable calls use the server's own credentials, never a session token",
       ctx do
    test = self()
    server = mcp_server("user:12")

    mcp(fn
      conn, "tools/call", params ->
        assert get_req_header(conn, "authorization") == ["Bearer mcp-token"]
        assert params == %{"name" => "read", "arguments" => %{}}
        send(test, :called)
        %{content: [%{type: "text", text: "mcp-token"}]}

      _conn, _method, _params ->
        nil
    end)

    assert {:ok, [tool], []} = MCP.discover(ctx.thread, ctx.message, ctx.run)
    {:env, env} = :erlang.fun_info(tool.call, :env)
    refute inspect(env, limit: :infinity) =~ "mcp-token"
    refute inspect(env, limit: :infinity) =~ "author-token"
    assert {:ok, output} = Condukt.Tool.execute(tool, %{}, %{})
    assert output =~ "[REDACTED]"
    refute output =~ "mcp-token"
    assert_received :called
    assert [%{status: "completed"}] = Repo.all(ToolCall)
    assert server.owner == "user:12"
  end

  test "a stored call still names the server it went to after the server is removed", ctx do
    server = mcp_server("account:21", "Team", "https://team.example/mcp")

    mcp(fn
      _conn, "tools/call", _params -> %{content: [%{type: "text", text: "secret notes"}]}
      _conn, _method, _params -> nil
    end)

    assert {:ok, [tool], []} = MCP.discover(ctx.thread, ctx.message, ctx.run)
    assert {:ok, _output} = Condukt.Tool.execute(tool, %{}, %{})
    Repo.delete!(server)

    assert [
             %{
               status: "completed",
               mcp_server_id: server.id,
               mcp_server_owner: "account:21",
               mcp_server_host: "team.example"
             }
           ] ==
             Repo.all(
               from c in "thread_tool_calls",
                 select: %{
                   status: c.status,
                   mcp_server_id: type(c.mcp_server_id, Ecto.UUID),
                   mcp_server_owner: c.mcp_server_owner,
                   mcp_server_host: c.mcp_server_host
                 }
             )
  end

  test "only the author's own servers and the thread account's are offered", ctx do
    mcp_server("user:12", "Mine", "https://mine.example/mcp")
    mcp_server("account:21", "Team", "https://team.example/mcp")
    mcp_server("user:11", "Owner's", "https://owner.example/mcp")
    mcp_server("account:99", "Other team", "https://other.example/mcp")
    test = self()

    mcp(fn conn, _method, _params ->
      send(test, {:host, conn.host})
      nil
    end)

    assert {:ok, tools, []} = MCP.discover(ctx.thread, ctx.message, ctx.run)
    assert length(tools) == 2
    assert_received {:host, "mine.example"}
    assert_received {:host, "team.example"}
    refute_received {:host, "owner.example"}
    refute_received {:host, "other.example"}
  end

  test "invalid tools are dropped one by one and logged with the rule they broke", ctx do
    server = mcp_server("user:12")

    tools = [
      definition(),
      Map.put(definition(), "name", "bad name"),
      Map.merge(definition(), %{
        "name" => "refs",
        "inputSchema" => %{"type" => "object", "$ref" => "#/x"}
      }),
      Map.put(definition(), "description", String.duplicate("d", 5000)),
      Map.put(definition(), "name", "write")
    ]

    mcp(fn _conn, _method, _params -> nil end, tools)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, offered, []} = MCP.discover(ctx.thread, ctx.message, ctx.run)
        assert length(offered) == 2
      end)

    assert log =~ "MCP server #{server.id} dropped 3 tools: bad?name: name has characters"
    assert log =~ "; refs: inputSchema uses $ref"
    assert log =~ "; read: description over 4096 bytes"
  end

  test "a server listing too many tools is skipped before any is checked", ctx do
    mcp_server("user:12", "Huge")
    tools = for i <- 1..2001, do: Map.put(definition(), "name", "tool#{i}")

    mcp(fn _conn, _method, _params -> nil end, tools)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, [], ["Huge"]} = MCP.discover(ctx.thread, ctx.message, ctx.run)
      end)

    assert log =~ "tools/list returned over 2000 tools"
    refute log =~ "dropped"
  end

  test "missing exact author delegation never falls back to owner's or author's other session",
       ctx do
    mcp_server("user:12")
    _another = session(12, "another-token")
    Repo.delete!(ctx.author)
    Req.Test.stub(LuftServer.Tuist, fn _ -> flunk("no session means no upstream request") end)
    Req.Test.stub(LuftServer.MCPServers, fn _ -> flunk("no session means no MCP request") end)

    assert {:error, :delegation_unavailable} = MCP.discover(ctx.thread, ctx.message, ctx.run)
  end

  test "scope revocation and tenant mismatch fail closed", ctx do
    mcp_server("user:12")
    Req.Test.stub(LuftServer.MCPServers, fn _ -> flunk("revoked scope means no MCP request") end)

    for account <- [nil, 99] do
      Req.Test.stub(LuftServer.Tuist, fn conn ->
        if is_nil(account),
          do: conn |> put_status(403) |> Req.Test.json(%{}),
          else: scope(conn, account)
      end)

      assert {:error, :delegation_unavailable} = MCP.discover(ctx.thread, ctx.message, ctx.run)
    end
  end

  test "uncertain external effects remain executing and are never redispatched", ctx do
    test = self()
    mcp_server("user:12")

    mcp(fn
      conn, "tools/call", _params ->
        send(test, :effect)
        Req.Test.transport_error(conn, :timeout)

      _conn, _method, _params ->
        nil
    end)

    assert {:ok, [tool], []} = MCP.discover(ctx.thread, ctx.message, ctx.run)
    assert {:error, :tool_outcome_unknown} = Condukt.Tool.execute(tool, %{}, %{})
    assert_received :effect
    assert [%{status: "executing"}] = Repo.all(ToolCall)
    assert {:error, :tool_outcome_unknown} = Condukt.Tool.execute(tool, %{}, %{})
    refute_received :effect
  end

  test "revocation after discovery completes as a definitive non-effect", ctx do
    mcp_server("user:12")

    mcp(fn
      _conn, "tools/call", _params -> flunk("revoked calls are never dispatched")
      _conn, _method, _params -> nil
    end)

    assert {:ok, [tool], []} = MCP.discover(ctx.thread, ctx.message, ctx.run)
    # The exact persisted message remains authoritative, not the struct the
    # host originally handed discovery.
    Repo.update!(Ecto.Changeset.change(ctx.message, author_session_id: nil))
    assert {:error, _} = Condukt.Tool.execute(tool, %{}, %{})
    refute Repo.exists?(from c in ToolCall, where: c.status == "completed")
  end

  test "a server whose discovery fails is skipped and named, keeping the others' tools", ctx do
    mcp_server("user:12", "Broken", "https://broken.example/mcp")
    mcp_server("user:12", "Profile", "https://profile.example/mcp")

    mcp(fn conn, method, _params ->
      if conn.host == "broken.example" and method == "tools/list",
        do: conn |> put_status(500) |> Req.Test.json(%{})
    end)

    assert {:ok, [tool], ["Broken"]} = MCP.discover(ctx.thread, ctx.message, ctx.run)
    assert tool.description =~ "read"
  end

  test "large profile catalogs offer searchable tools rather than silently dropping entries",
       ctx do
    mcp_server("user:12")

    for count <- [65, 101] do
      tools = for n <- 1..count, do: Map.put(definition(), "name", "read_#{n}")
      mcp(fn _conn, _method, _params -> nil end, tools)

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

  defp mcp_server(owner, name \\ "Profile", url \\ "https://mcp.example/mcp") do
    Repo.insert!(%Server{owner: owner, name: name, url: url, access_token: "mcp-token"})
  end

  # A Streamable HTTP MCP server listing `tools`. `handler` answers any
  # method it returns a result or a conn for; nil falls back to the defaults.
  defp mcp(handler, tools \\ [definition()]) do
    upstream(&scope(&1, 21))

    Req.Test.stub(LuftServer.MCPServers, fn conn ->
      {:ok, body, conn} = read_body(conn)
      rpc = Jason.decode!(body)

      case handler.(conn, rpc["method"], rpc["params"]) do
        %Plug.Conn{} = answered ->
          answered

        result ->
          result =
            result ||
              case rpc["method"] do
                "initialize" ->
                  %{protocolVersion: "2025-06-18", capabilities: %{tools: %{}}}

                "tools/list" ->
                  %{tools: tools}

                _ ->
                  %{}
              end

          Req.Test.json(conn, %{jsonrpc: "2.0", id: rpc["id"], result: result})
      end
    end)
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
