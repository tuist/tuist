defmodule Tuist.Threads.MCPTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.MCPServers
  alias Tuist.Accounts.User
  alias Tuist.OAuth2.PinnedHTTP
  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.Threads
  alias Tuist.Threads.MCP
  alias Tuist.Threads.Run

  @url "https://mcp.example.com/mcp"
  @pinned "https://93.184.216.34/mcp"
  @server_id "019a50ec-f33b-7000-8000-000000000001"
  @token "private-profile-access-token"

  setup do
    user = %User{id: 1}
    run = %Run{id: Ecto.UUID.generate(), attempt: 2}
    parent = self()

    stub(Threads, :owns_run?, fn id, attempt ->
      assert {id, attempt} == {run.id, 2}
      true
    end)

    stub(MCPServers, :list, fn ^user -> [server()] end)

    stub(MCPServers, :credentials, fn %User{id: 1}, @server_id ->
      send(parent, :credentials)
      {:ok, %{url: @url, access_token: @token}}
    end)

    stub(SSRFGuard, :pin, fn @url -> {:ok, @pinned, "mcp.example.com"} end)

    stub(Threads, :call_external_tool, fn ^run, invocation_id, name, args, call ->
      assert {:ok, _} = Ecto.UUID.cast(invocation_id)
      send(parent, {:ledger, invocation_id, name, args})
      call.()
    end)

    %{user: user, run: run}
  end

  test "discovers namespaced tools, paginates and refreshes credentials before every POST", context do
    stub_protocol(fn
      %{"params" => %{"cursor" => "page-2"}} -> %{"tools" => [definition("second")]}
      _ -> %{"tools" => [definition()], "nextCursor" => "page-2"}
    end)

    assert {:ok, [first, second]} = MCP.discover(context.user, context.run)
    assert String.match?(first.name, ~r/\Amcp_[0-9a-f]{60}\z/)
    refute first.name == second.name
    assert {:ok, [same, _]} = MCP.discover(context.user, context.run)
    assert same.name == first.name
    assert first.parameters == definition()["inputSchema"]
    assert first.description =~ "untrusted"

    for _ <- 1..8, do: assert_received(:credentials)
    refute_received :credentials

    assert_received {:post, %{"method" => "initialize"}, initial}
    refute List.keymember?(initial[:headers], "mcp-session-id", 0)
    assert_received {:post, %{"method" => "notifications/initialized"} = notification, initialized}
    refute Map.has_key?(notification, "id")
    assert initialized[:headers_only]
    assert {"mcp-session-id", "session-1"} in initialized[:headers]
    assert initialized[:max_body_bytes] == 262_144
    assert initialized[:total_timeout] == 15_000
    assert initialized[:receive_timeout] == 10_000
    assert initialized[:accept_status] == [200, 202, 204]
    assert initialized[:connect_options][:hostname] == "mcp.example.com"
    assert initialized[:connect_options][:transport_opts][:verify] == :verify_peer

    {:env, env} = :erlang.fun_info(first.call, :env)
    refute inspect(env, limit: :infinity) =~ @token
    refute inspect(env, limit: :infinity) =~ "session-1"
  end

  test "same remote name on different servers has a different stable name", context do
    other_id = Ecto.UUID.generate()
    stub(MCPServers, :list, fn _ -> [server(), %{server() | id: other_id}] end)
    stub(MCPServers, :credentials, fn _, _ -> {:ok, %{url: @url, access_token: @token}} end)
    stub_protocol()

    assert {:ok, [first, second]} = MCP.discover(context.user, context.run)
    refute first.name == second.name
  end

  test "calls use fresh credentials and sessions inside the durable ledger without a repository", context do
    stub_protocol()
    assert {:ok, [tool]} = MCP.discover(context.user, context.run)

    stub(MCPServers, :credentials, fn _, _ -> {:ok, %{url: @url, access_token: "rotated-token"}} end)
    assert {:ok, %{"content" => [%{"text" => "done"}]}} = execute(tool, %{"id" => "42"})
    assert_received {:ledger, invocation_id, name, %{"id" => "42"}}
    assert name == tool.name
    assert_received {:post, %{"method" => "tools/call", "params" => %{"name" => "lookup"}}, opts}
    assert {"authorization", "Bearer rotated-token"} in opts[:headers]

    assert {:ok, _} = Condukt.Tool.execute(tool, %{"id" => "42"}, %{})
    assert_received {:ledger, second_id, ^name, _}
    refute invocation_id == second_id
  end

  test "ledger refusal never dispatches", context do
    stub_protocol()
    {:ok, [tool]} = MCP.discover(context.user, context.run)
    stub(Threads, :call_external_tool, fn _, _, _, _, _ -> {:error, :tool_outcome_unknown} end)
    reject(MCPServers, :credentials, 2)
    reject(PinnedHTTP, :request, 3)

    assert {:error, :tool_outcome_unknown} = Condukt.Tool.execute(tool, %{}, %{})
  end

  test "disconnects and endpoint edits are rechecked for every invocation", context do
    stub_protocol()
    {:ok, [tool]} = MCP.discover(context.user, context.run)
    reject(PinnedHTTP, :request, 3)

    stub(MCPServers, :credentials, fn _, _ -> {:error, :not_found} end)
    assert {:ok, %{"isError" => true, "content" => [%{"text" => "mcp_not_connected"}]}} = execute(tool)

    stub(MCPServers, :credentials, fn _, _ -> {:ok, %{url: "https://different.example/mcp", access_token: @token}} end)
    assert {:ok, %{"isError" => true, "content" => [%{"text" => "mcp_connection_changed"}]}} = execute(tool)
  end

  test "ownership is rechecked after refresh and pinning before initialize, initialized, list and call", context do
    for stop_at <- ["initialize", "notifications/initialized", "tools/list", "tools/call"] do
      stub_protocol()
      {:ok, [tool]} = MCP.discover(context.user, context.run)
      {:ok, counter} = Agent.start_link(fn -> 0 end)
      target = Enum.find_index(["initialize", "notifications/initialized", "tools/list", "tools/call"], &(&1 == stop_at))
      # Invocations do not need tools/list, so discovery covers that request.
      dispatches = if stop_at == "tools/list", do: 2, else: min(target, 2)

      stub(SSRFGuard, :pin, fn @url ->
        Agent.update(counter, &(&1 + 1))
        {:ok, @pinned, "mcp.example.com"}
      end)

      stub(Threads, :owns_run?, fn _, _ -> Agent.get(counter, &(&1 <= dispatches)) end)

      if stop_at == "tools/list" do
        assert {:error, :stale_run} = MCP.discover(context.user, context.run)
      else
        assert {:ok, %{"isError" => true, "content" => [%{"text" => "stale_run"}]}} = execute(tool)
      end

      stub(Threads, :owns_run?, fn _, _ -> true end)
      stub(SSRFGuard, :pin, fn @url -> {:ok, @pinned, "mcp.example.com"} end)
    end
  end

  test "disconnected entries are ignored but any connected server failure fails discovery", context do
    stub(MCPServers, :list, fn _ -> [%{server() | connected: false}] end)
    reject(PinnedHTTP, :request, 3)
    assert {:ok, []} = MCP.discover(context.user, context.run)

    stub(MCPServers, :list, fn _ -> [server()] end)
    stub(SSRFGuard, :pin, fn _ -> {:error, {:private_ip_resolved, "sensitive-internal-host"}} end)
    assert {:error, :mcp_unsafe_endpoint} = MCP.discover(context.user, context.run)
  end

  test "refuses non-HTTPS, embedded credentials and fragments before pinning", context do
    reject(SSRFGuard, :pin, 1)
    reject(PinnedHTTP, :request, 3)

    for url <- ["http://mcp.example.com/mcp", "https://user:pass@mcp.example.com/mcp", @url <> "#fragment"] do
      stub(MCPServers, :list, fn _ -> [%{server() | url: url}] end)
      stub(MCPServers, :credentials, fn _, _ -> {:ok, %{url: url, access_token: @token}} end)
      assert {:error, :mcp_unsafe_endpoint} = MCP.discover(context.user, context.run)
    end
  end

  test "sanitizes errors and token echoes", context do
    stub_protocol()
    {:ok, [tool]} = MCP.discover(context.user, context.run)

    stub_protocol(fn _ -> %{"tools" => [definition()]} end, %{
      "content" => [%{"text" => "Bearer " <> @token}],
      "structuredContent" => %{@token => @token}
    })

    assert {:ok, result} = execute(tool)
    refute inspect(result) =~ @token
    assert result["structuredContent"] == %{"[REDACTED]" => "[REDACTED]"}

    stub(PinnedHTTP, :request, fn _, _, _ -> raise "transport body with #{@token}" end)
    assert {:ok, %{"isError" => true, "content" => [%{"text" => "mcp_unavailable"}]}} = execute(tool)
    assert {:error, :mcp_unavailable} = MCP.discover(context.user, context.run)
  end

  test "rejects malformed and oversized names and schemas, duplicates and pagination loops", context do
    for definitions <- [
          [%{definition() | "name" => "invalid tool name"}],
          [%{definition() | "name" => String.duplicate("a", 129)}],
          [%{definition() | "inputSchema" => %{"type" => "string"}}],
          [%{definition() | "inputSchema" => %{"type" => "object", "properties" => "invalid"}}],
          [%{definition() | "inputSchema" => %{"type" => "object", "$ref" => "https://private/schema"}}],
          [%{definition() | "description" => String.duplicate("a", 4097)}],
          [definition(), definition()],
          List.duplicate(definition(), 101)
        ] do
      stub_protocol(fn _ -> %{"tools" => definitions} end)
      assert {:error, :mcp_invalid_response} = MCP.discover(context.user, context.run)
    end

    stub_protocol(fn _ -> %{"tools" => [], "nextCursor" => "loop"} end)
    assert {:error, :mcp_invalid_response} = MCP.discover(context.user, context.run)
  end

  test "bounds distinct pagination cursors and rejects deep or oversized schemas and arguments", context do
    stub_protocol(fn envelope ->
      %{"tools" => [], "nextCursor" => Integer.to_string(envelope["id"])}
    end)

    assert {:error, :mcp_limit_exceeded} = MCP.discover(context.user, context.run)

    deep = Enum.reduce(1..15, %{"type" => "string"}, fn _, schema -> %{"items" => schema} end)

    for schema <- [
          %{"type" => "object", "properties" => %{"deep" => deep}},
          %{"type" => "object", "description" => String.duplicate("a", 32_769)}
        ] do
      stub_protocol(fn _ -> %{"tools" => [%{definition() | "inputSchema" => schema}]} end)
      assert {:error, :mcp_invalid_response} = MCP.discover(context.user, context.run)
    end

    stub_protocol()
    {:ok, [tool]} = MCP.discover(context.user, context.run)
    reject(PinnedHTTP, :request, 3)
    assert {:error, :invalid_arguments} = Condukt.Tool.execute(tool, %{"data" => String.duplicate("a", 65_537)}, %{})
    assert {:error, :invalid_arguments} = Condukt.Tool.execute(tool, %{"id" => 42}, %{})
  end

  test "real PinnedHTTP accepts chunked JSON without a session ID", context do
    stub_mint(fn envelope ->
      data = JSON.encode!(%{jsonrpc: "2.0", id: envelope["id"], result: protocol_result(envelope)})
      <<first::binary-size(10), rest::binary>> = data
      {200, [{"content-type", "application/json"}], [first, rest]}
    end)

    assert {:ok, [tool]} = MCP.discover(context.user, context.run)
    assert {:ok, %{"content" => []}} = execute(tool)
    for _ <- 1..6, do: assert_received(:closed)
  end

  test "protocol failures complete the ledger but malformed replies after tools/call remain uncertain", context do
    parent = self()

    for mode <- [:tool_error, :rpc_error, :broken, :null_error, :invalid_code, :missing_message, :result_and_error] do
      stub_mint(fn envelope ->
        data =
          if envelope["method"] == "tools/call" do
            send(parent, {:remote_call, mode})

            case mode do
              :tool_error ->
                JSON.encode!(%{
                  jsonrpc: "2.0",
                  id: envelope["id"],
                  result: %{isError: true, content: [%{type: "text", text: @token}]}
                })

              :rpc_error ->
                JSON.encode!(%{jsonrpc: "2.0", id: envelope["id"], error: %{code: -32_603, message: @token}})

              :broken ->
                "invalid upstream reply with " <> @token

              :null_error ->
                JSON.encode!(%{jsonrpc: "2.0", id: envelope["id"], error: nil})

              :invalid_code ->
                JSON.encode!(%{jsonrpc: "2.0", id: envelope["id"], error: %{code: "invalid", message: @token}})

              :missing_message ->
                JSON.encode!(%{jsonrpc: "2.0", id: envelope["id"], error: %{code: -32_603}})

              :result_and_error ->
                JSON.encode!(%{jsonrpc: "2.0", id: envelope["id"], error: %{code: -32_603, message: @token}, result: nil})
            end
          else
            JSON.encode!(%{jsonrpc: "2.0", id: envelope["id"], result: protocol_result(envelope)})
          end

        {200, [{"content-type", "application/json"}], [data]}
      end)

      assert {:ok, [tool]} = MCP.discover(context.user, context.run)

      if mode in [:tool_error, :rpc_error] do
        assert {:ok, %{"isError" => true} = result} = execute(tool)
        refute inspect(result) =~ @token
      else
        assert {:error, :mcp_invalid_response} = execute(tool)
      end

      assert_received {:remote_call, ^mode}
      refute_received {:remote_call, ^mode}
    end
  end

  test "real PinnedHTTP rejects mismatched JSON-RPC IDs and unsafe session headers", context do
    for headers <- [
          [{"mcp-session-id", "unsafe\r\nAuthorization: secret"}],
          [{"mcp-session-id", @token}],
          [{"mcp-session-id", String.duplicate("s", 257)}],
          []
        ] do
      stub_mint(fn envelope ->
        id = if headers == [], do: "wrong-id", else: envelope["id"]
        data = JSON.encode!(%{jsonrpc: "2.0", id: id, result: protocol_result(envelope)})
        {200, [{"content-type", "application/json"} | headers], [data]}
      end)

      assert {:error, :mcp_invalid_response} = MCP.discover(context.user, context.run)
    end
  end

  test "real PinnedHTTP closes an open SSE stream after the matching response", context do
    stub_mint(fn envelope ->
      data = JSON.encode!(%{jsonrpc: "2.0", id: envelope["id"], result: protocol_result(envelope)})
      notification = ~s(data: {"jsonrpc":"2.0","method":"notifications/progress"}\r\n\r\n)

      {200, [{"content-type", "text/event-stream"}, {"mcp-session-id", "session-1"}],
       [notification, "data: " <> data <> "\r\n\r\n"]}
    end)

    assert {:ok, [tool]} = MCP.discover(context.user, context.run)
    assert {:ok, %{"content" => []}} = execute(tool)
    for _ <- 1..6, do: assert_received(:closed)
    refute_received :done_read
  end

  test "real PinnedHTTP refuses redirects without following or reading their bodies", context do
    stub_mint(fn _ -> {302, [{"location", "https://127.0.0.1/private"}], [@token]} end)
    assert {:error, :mcp_unavailable} = MCP.discover(context.user, context.run)
    assert_received :closed
    refute_received :body_read
    refute_received :closed
  end

  test "real PinnedHTTP bounds oversized streams and read failures", context do
    stub_mint(fn _ -> {200, [{"content-type", "text/event-stream"}], [String.duplicate("a", 262_145)]} end)
    assert {:error, :mcp_invalid_response} = MCP.discover(context.user, context.run)
    assert_received :closed

    stub(Mint.HTTP, :recv, fn _, _, _ -> {:error, :conn, :timeout, []} end)
    assert {:error, :mcp_unavailable} = MCP.discover(context.user, context.run)
    assert_received :closed
  end

  defp server, do: %{id: @server_id, url: @url, name: "Profile", connected: true}

  defp execute(tool, args \\ %{}) do
    case Condukt.Tool.execute(tool, args, %{}) do
      {:ok, encoded} ->
        assert is_binary(encoded)
        {:ok, JSON.decode!(encoded)}

      error ->
        error
    end
  end

  defp definition(name \\ "lookup"),
    do: %{
      "name" => name,
      "description" => "Look up an item",
      "inputSchema" => %{"type" => "object", "properties" => %{"id" => %{"type" => "string"}}}
    }

  defp stub_protocol(
         list \\ fn _ -> %{"tools" => [definition()]} end,
         call_result \\ %{"content" => [%{"text" => "done"}]}
       ) do
    parent = self()

    stub(PinnedHTTP, :request, fn "POST", @pinned, opts ->
      envelope = JSON.decode!(opts[:body])
      send(parent, {:post, envelope, opts})

      result =
        case envelope["method"] do
          "tools/list" -> list.(envelope)
          "tools/call" -> call_result
          _ -> protocol_result(envelope)
        end

      {:ok,
       %{
         status: if(envelope["method"] == "notifications/initialized", do: 202, else: 200),
         headers: [{"content-type", "application/json"}, {"mcp-session-id", "session-1"}],
         body: JSON.encode!(%{jsonrpc: "2.0", id: envelope["id"], result: result})
       }}
    end)
  end

  defp protocol_result(%{"method" => "initialize"}),
    do: %{"protocolVersion" => "2025-06-18", "capabilities" => %{"tools" => %{}}}

  defp protocol_result(%{"method" => "tools/list"}), do: %{"tools" => [definition()]}
  defp protocol_result(_), do: %{"content" => []}

  defp stub_mint(response) do
    parent = self()
    {:ok, batches} = Agent.start_link(fn -> [] end)

    stub(Mint.HTTP, :connect, fn :https, "93.184.216.34", 443, opts ->
      assert opts[:hostname] == "mcp.example.com"
      assert opts[:transport_opts][:verify] == :verify_peer
      {:ok, :conn}
    end)

    stub(Mint.HTTP, :request, fn :conn, "POST", "/mcp", _, body ->
      envelope = JSON.decode!(body)
      {status, headers, chunks} = response.(envelope)
      initial = [{:status, :ref, status}, {:headers, :ref, headers}]
      Agent.update(batches, fn _ -> [initial | Enum.map(chunks, &[{:data, :ref, &1}])] ++ [[{:done, :ref}]] end)
      {:ok, :conn, :ref}
    end)

    stub(Mint.HTTP, :recv, fn :conn, 0, timeout ->
      assert timeout <= 10_000
      batch = Agent.get_and_update(batches, fn [batch | rest] -> {batch, rest} end)
      if match?([{:data, _, _}], batch), do: send(parent, :body_read)
      if batch == [{:done, :ref}], do: send(parent, :done_read)
      {:ok, :conn, batch}
    end)

    stub(Mint.HTTP, :close, fn :conn ->
      send(parent, :closed)
      {:ok, :conn}
    end)
  end
end
