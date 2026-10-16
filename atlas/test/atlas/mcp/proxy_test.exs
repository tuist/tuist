defmodule Atlas.MCP.ProxyTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Proxy.Config
  alias Atlas.MCP.Proxy.Server
  alias Atlas.MCP.Tools.GetMCPConnectionStatus
  alias Atlas.Users.User

  setup :verify_on_exit!

  setup do
    stub(Config, :get, fn -> proxy_config() end)
    :ok
  end

  test "lists configured proxy servers without exposing credentials" do
    assert [
             %{
               name: "grafana",
               transport: "streamable_http",
               url: "https://mcp.grafana.example/mcp"
             }
           ] = Proxy.list_servers()
  end

  test "normalizes shared OAuth server configuration" do
    stub(Config, :get, fn ->
      [
        servers: [
          %{
            "name" => "sentry",
            "url" => "https://mcp.sentry.dev/mcp",
            "auth_type" => "oauth2",
            "authorization_url" => "https://mcp.sentry.dev/oauth/authorize",
            "token_url" => "https://mcp.sentry.dev/oauth/token",
            "shared_oauth" => "true",
            "shared_oauth_user_email" => "pedro@tuist.dev"
          }
        ]
      ]
    end)

    assert [
             %Server{
               name: "sentry",
               auth_type: :oauth2,
               shared_oauth: true,
               shared_oauth_user_email: "pedro@tuist.dev"
             }
           ] = Proxy.configured_servers()
  end

  test "lists tools from a streamable HTTP upstream MCP server" do
    expect_initialize()
    expect_initialized_notification()

    expect(Req, :post, fn %Req.Request{} = request ->
      assert URI.to_string(request.url) == "https://mcp.grafana.example/mcp"
      assert request.headers["mcp-session-id"] == ["session-1"]
      assert request.options.json["method"] == "tools/list"

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "jsonrpc" => "2.0",
           "id" => request.options.json["id"],
           "result" => %{
             "tools" => [
               %{
                 "name" => "search_dashboards",
                 "description" => "Search Grafana dashboards",
                 "inputSchema" => %{"type" => "object"}
               }
             ]
           }
         }
       }}
    end)

    assert {:ok, [tool]} = Proxy.list_tools("grafana")
    assert tool["name"] == "search_dashboards"
    assert tool["server"] == "grafana"
    assert tool["proxiedName"] == "grafana/search_dashboards"
  end

  test "lists tools from an upstream server that responds with SSE messages" do
    expect_initialize()
    expect_initialized_notification()

    expect(Req, :post, fn %Req.Request{} = request ->
      assert URI.to_string(request.url) == "https://mcp.grafana.example/mcp"
      assert request.headers["mcp-session-id"] == ["session-1"]
      assert request.options.json["method"] == "tools/list"

      {:ok,
       %Req.Response{
         status: 200,
         body: """
         event: message
         data: {"jsonrpc":"2.0","method":"notifications/tools/list_changed","params":{}}

         event: message
         data: {"jsonrpc":"2.0","id":#{request.options.json["id"]},"result":{"tools":[{"name":"query_prometheus","description":"Query Prometheus","inputSchema":{"type":"object"}}]}}

         """
       }}
    end)

    assert {:ok, [tool]} = Proxy.list_tools("grafana")
    assert tool["name"] == "query_prometheus"
    assert tool["server"] == "grafana"
    assert tool["proxiedName"] == "grafana/query_prometheus"
  end

  test "stops reading an upstream SSE response after the matching JSON-RPC message arrives" do
    expect_initialize()
    expect_initialized_notification()

    expect(Req, :post, fn %Req.Request{} = request ->
      assert request.options.json["method"] == "tools/call"
      assert is_function(request.into, 2)

      response = %Req.Response{status: 200, headers: %{"content-type" => ["text/event-stream"]}}

      {:cont, {request, response}} =
        request.into.(
          {:data, ~s(event: message\ndata: {"jsonrpc":"2.0","method":"notifications/progress","params":{}}\n\n)},
          {request, response}
        )

      {:halt, {_request, response}} =
        request.into.(
          {:data,
           "event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":#{request.options.json["id"]},\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"ok\"}]}}\n\n"},
          {request, response}
        )

      {:ok, response}
    end)

    assert {:ok, %{"content" => [%{"text" => "ok"}]}} =
             Proxy.call_tool("grafana", "query_prometheus", %{"query" => "up"})
  end

  test "calls a tool on a streamable HTTP upstream MCP server" do
    expect_initialize()
    expect_initialized_notification()

    expect(Req, :post, fn %Req.Request{} = request ->
      assert request.headers["mcp-session-id"] == ["session-1"]
      assert request.options.json["method"] == "tools/call"

      assert request.options.json["params"] == %{
               "name" => "query_prometheus",
               "arguments" => %{"query" => "up"}
             }

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "jsonrpc" => "2.0",
           "id" => request.options.json["id"],
           "result" => %{
             "content" => [
               %{"type" => "text", "text" => ~s({"status":"success"})}
             ]
           }
         }
       }}
    end)

    assert {:ok, %{"content" => [%{"text" => text}]}} =
             Proxy.call_tool("grafana", "query_prometheus", %{"query" => "up"})

    assert text == ~s({"status":"success"})
  end

  test "filters upstream observability tools from restricted MCP sessions without observability access" do
    conn = %{assigns: %{mcp_claims: %{"mcp_tool_groups" => []}}}

    assert Proxy.list_hoisted_tools(conn) == []

    assert {:error, message} = Proxy.call_hoisted_tool(conn, "grafana__query_prometheus", %{"query" => "up"})
    assert message =~ "not available"
  end

  test "keeps upstream observability tools available for restricted observability sessions" do
    conn = %{assigns: %{mcp_claims: %{"mcp_tool_groups" => ["observability"]}}}

    expect_initialize()
    expect_initialized_notification()

    expect(Req, :post, fn %Req.Request{} = request ->
      assert request.headers["mcp-session-id"] == ["session-1"]
      assert request.options.json["method"] == "tools/list"

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "jsonrpc" => "2.0",
           "id" => request.options.json["id"],
           "result" => %{
             "tools" => [
               %{
                 "name" => "query_prometheus",
                 "description" => "Query Prometheus",
                 "inputSchema" => %{"type" => "object"}
               }
             ]
           }
         }
       }}
    end)

    assert [%{"name" => "grafana__query_prometheus"}] = Proxy.list_hoisted_tools(conn)
  end

  # The Tuist server's tools read production customer data — test runs, builds,
  # and the artifacts behind them — so they are gated exactly like the Grafana
  # and Sentry tools rather than falling through to the default group. And
  # because the upstream is OAuth2, reaching it needs the Atlas user's own
  # authorization: there is no service credential standing in for everyone.
  test "gates the Tuist upstream on observability access and per-user authorization" do
    stub(Config, :get, fn -> tuist_proxy_config() end)

    without_access = %{assigns: %{mcp_claims: %{"mcp_tool_groups" => []}}}

    assert Proxy.list_hoisted_tools(without_access) == []

    assert {:error, message} =
             Proxy.call_hoisted_tool(without_access, "tuist__get_test_run", %{"test_run_id" => "run-1"})

    assert message =~ "not available"

    with_access = %{assigns: %{mcp_claims: %{"mcp_tool_groups" => ["observability"]}}}

    assert {:error, message} =
             Proxy.call_hoisted_tool(with_access, "tuist__get_test_run", %{"test_run_id" => "run-1"})

    assert message =~ "needs an authenticated Atlas user session"
  end

  # The Tuist registry includes project and organization creation, membership
  # changes and test-case updates. Atlas proxies it to investigate production,
  # so the write tools must not reach an Atlas session even though the upstream
  # token might permit them.
  test "a read-only upstream contributes only its read-only tools" do
    stub(Config, :get, fn -> read_only_proxy_config() end)

    expect_initialize("https://tuist.example/mcp")
    expect_initialized_notification()

    expect_tools_list([
      %{"name" => "get_test_run", "annotations" => %{"readOnlyHint" => true}},
      %{"name" => "create_project", "annotations" => %{"readOnlyHint" => false}},
      %{"name" => "unannotated_tool"}
    ])

    assert {:ok, tools} = Proxy.list_tools("tuist")

    assert Enum.map(tools, & &1["name"]) == ["get_test_run"]
  end

  # Hiding a tool at discovery is not enough: a caller that already knows the
  # name could otherwise dispatch straight to it.
  test "a read-only upstream refuses a write tool at dispatch" do
    stub(Config, :get, fn -> read_only_proxy_config() end)

    expect_initialize("https://tuist.example/mcp")
    expect_initialized_notification()
    expect_tools_list([%{"name" => "create_project", "annotations" => %{"readOnlyHint" => false}}])

    assert {:error, message} = Proxy.call_tool("tuist", "create_project", %{"name" => "app"})
    assert message =~ "restricted tool set"
  end

  # The allowlist is the check for an upstream whose annotation cannot be taken
  # at face value — no server Atlas proxies today needs it, so this covers the
  # mechanism rather than a live configuration. A tool claiming to be read-only
  # is still refused when it was never enumerated.
  test "a tool outside the allowlist is refused even when it claims to be read-only" do
    stub(Config, :get, fn -> allowlisted_proxy_config() end)

    expect_initialize("https://tuist.example/mcp")
    expect_initialized_notification()

    expect_tools_list([
      %{"name" => "get_test_run", "annotations" => %{"readOnlyHint" => true}},
      %{"name" => "delete_everything", "annotations" => %{"readOnlyHint" => true}}
    ])

    assert {:ok, tools} = Proxy.list_tools("tuist")
    assert Enum.map(tools, & &1["name"]) == ["get_test_run"]
  end

  test "a tool outside the allowlist is refused at dispatch" do
    stub(Config, :get, fn -> allowlisted_proxy_config() end)

    expect_initialize("https://tuist.example/mcp")
    expect_initialized_notification()
    expect_tools_list([%{"name" => "delete_everything", "annotations" => %{"readOnlyHint" => true}}])

    assert {:error, message} = Proxy.call_tool("tuist", "delete_everything", %{})
    assert message =~ "restricted tool set"
  end

  test "sends Atlas' workload identity to an upstream configured for it" do
    stub(Config, :get, fn -> atlas_identity_proxy_config() end)
    conn = %{assigns: %{current_user: %User{id: "user-1"}, audit_interface: "mcp"}}

    stub(Atlas.TuistServer, :workload_identity_token, fn -> {:ok, "sa-token"} end)

    expect(Req, :post, fn %Req.Request{} = request ->
      assert request.headers["x-tuist-atlas-identity"] == ["sa-token"]
      initialize_response(request)
    end)

    expect_initialized_notification()
    expect_tools_list([%{"name" => "get_test_run", "annotations" => %{"readOnlyHint" => true}}])

    assert [%{"name" => "tuist__get_test_run"}] = Proxy.list_hoisted_tools(conn)
  end

  test "leaves the workload identity off when no token is available" do
    stub(Config, :get, fn -> atlas_identity_proxy_config() end)
    conn = %{assigns: %{current_user: %User{id: "user-1"}, audit_interface: "mcp"}}

    stub(Atlas.TuistServer, :workload_identity_token, fn -> {:error, "not configured"} end)

    expect(Req, :post, fn %Req.Request{} = request ->
      refute Map.has_key?(request.headers, "x-tuist-atlas-identity")
      initialize_response(request)
    end)

    expect_initialized_notification()
    expect_tools_list([%{"name" => "get_test_run", "annotations" => %{"readOnlyHint" => true}}])

    assert [%{"name" => "tuist__get_test_run"}] = Proxy.list_hoisted_tools(conn)
  end

  for {label, assigns} <- [
        {"the Slack agent", %{audit_interface: "slack"}},
        {"a caller that names no interface", %{}},
        {"an unknown interface", %{audit_interface: "email"}}
      ] do
    @assigns assigns
    test "never sends the workload identity for #{label}" do
      stub(Config, :get, fn -> atlas_identity_proxy_config() end)
      conn = %{assigns: Map.put(@assigns, :current_user, %User{id: "user-1"})}

      reject(Atlas.TuistServer, :workload_identity_token, 0)

      expect(Req, :post, fn %Req.Request{} = request ->
        refute Map.has_key?(request.headers, "x-tuist-atlas-identity")
        initialize_response(request)
      end)

      expect_initialized_notification()
      expect_tools_list([%{"name" => "get_test_run", "annotations" => %{"readOnlyHint" => true}}])

      assert [%{"name" => "tuist__get_test_run"}] = Proxy.list_hoisted_tools(conn)
    end
  end

  test "never sends the workload identity to an upstream not configured for it" do
    stub(Config, :get, fn -> read_only_proxy_config() end)
    conn = %{assigns: %{current_user: %User{id: "user-1"}, audit_interface: "mcp"}}

    reject(Atlas.TuistServer, :workload_identity_token, 0)

    expect(Req, :post, fn %Req.Request{} = request ->
      refute Map.has_key?(request.headers, "x-tuist-atlas-identity")
      initialize_response(request)
    end)

    expect_initialized_notification()
    expect_tools_list([%{"name" => "get_test_run", "annotations" => %{"readOnlyHint" => true}}])

    assert [%{"name" => "tuist__get_test_run"}] = Proxy.list_hoisted_tools(conn)
  end

  test "returns a clear error for an unknown upstream server" do
    assert {:error, "MCP proxy server is not configured: missing"} = Proxy.list_tools("missing")
  end

  test "returns a clear error for invalid direct tool call arguments" do
    assert {:error, "Proxy tool calls require a string server name, string tool name, and map arguments."} =
             Proxy.call_tool("grafana", "query_prometheus", [])
  end

  test "discovers and calls tools on an upstream that does not assign a session ID" do
    stub(Req, :post, fn request ->
      refute Map.has_key?(request.headers, "mcp-session-id")

      result =
        case request.options.json["method"] do
          "initialize" -> %{"protocolVersion" => "2025-03-26"}
          "notifications/initialized" -> nil
          "tools/list" -> %{"tools" => [%{"name" => "query", "inputSchema" => %{"type" => "object"}}]}
          "tools/call" -> %{"content" => [%{"type" => "text", "text" => "ok"}]}
        end

      {:ok,
       %Req.Response{status: 200, body: %{"jsonrpc" => "2.0", "id" => request.options.json["id"], "result" => result}}}
    end)

    assert {:ok, [%{"name" => "query"}]} = Proxy.list_tools("grafana")
    assert {:ok, %{"content" => [%{"text" => "ok"}]}} = Proxy.call_tool("grafana", "query", %{})
  end

  test "an upstream failure stays visible and its diagnostic retries after recovery" do
    conn = %{assigns: %{current_user: %User{id: "user-1"}}}
    expect(Req, :post, fn _ -> {:ok, %Req.Response{status: 503, body: "sensitive-upstream-body"}} end)

    assert [%{"name" => "grafana__atlas_connection_status"} = diagnostic] = Proxy.list_hoisted_tools(conn)
    assert diagnostic["description"] =~ "HTTP 503"
    refute inspect(diagnostic) =~ "sensitive-upstream-body"
    assert diagnostic["inputSchema"]["properties"] == %{}

    expect_initialize()
    expect_initialized_notification()
    expect_tools_list([%{"name" => "query", "inputSchema" => %{"type" => "object"}}])

    assert {:ok, %{"structuredContent" => status}} =
             Proxy.call_hoisted_tool(conn, "grafana__atlas_connection_status", %{})

    assert status["status"] == "available"
    assert [%{"name" => "grafana__query"}] = status["tools"]
  end

  test "a failing upstream does not hide healthy upstream tools" do
    [grafana] = proxy_config()[:servers]
    config = [servers: [grafana, Map.put(grafana, "name", "healthy")]]
    conn = %{assigns: %{current_user: %User{id: "user-1"}}}
    expect(Req, :post, fn _ -> {:error, %Req.TransportError{reason: :timeout}} end)
    expect_initialize()
    expect_initialized_notification()
    expect_tools_list([%{"name" => "query", "inputSchema" => %{"type" => "object"}}])

    assert [%{"name" => "grafana__atlas_connection_status"}, %{"name" => "healthy__query"}] =
             Proxy.list_hoisted_tools(conn, config)
  end

  test "live diagnostics distinguish upstream authorization and transient failures without response bodies" do
    conn = %{assigns: %{current_user: %User{id: "user-1"}}}

    for {status, code, retryable} <- [
          {401, "upstream_unauthorized", false},
          {403, "upstream_forbidden", false},
          {429, "http_error", true},
          {503, "http_error", true}
        ] do
      expect(Req, :post, fn _ -> {:ok, %Req.Response{status: status, body: "secret"}} end)
      assert {:ok, result} = Proxy.connection_status(conn, "grafana")
      assert result.status == code
      assert result.http_status == status
      assert result.stage == "initialize"
      assert result.retryable == retryable
      assert result.tools == []
      refute inspect(result) =~ "secret"
    end
  end

  test "live diagnostics preserve the failed discovery stage and redact JSON-RPC bodies" do
    conn = %{assigns: %{current_user: %User{id: "user-1"}}}
    expect_initialize()
    expect_initialized_notification()

    expect(Req, :post, fn _ ->
      {:ok, %Req.Response{status: 200, body: %{"error" => %{"message" => "secret", "code" => -32_603}}}}
    end)

    assert {:ok, %{status: "rpc_error", stage: "tools/list", tools: []} = result} =
             Proxy.connection_status(conn, "grafana")

    refute inspect(result) =~ "secret"
  end

  test "malformed discovery responses produce diagnostics instead of crashing the catalog" do
    conn = %{assigns: %{current_user: %User{id: "user-1"}}}

    for tools <- [[%{"name" => "query", "_meta" => "invalid"}], [nil], [%{"description" => "missing name"}]] do
      expect_initialize()
      expect_initialized_notification()
      expect_tools_list(tools)
      assert [%{"name" => "grafana__atlas_connection_status"}] = Proxy.list_hoisted_tools(conn)
    end
  end

  test "diagnostics distinguish a temporary refresh outage from required upstream authorization" do
    stub(Config, :get, fn -> tuist_proxy_config() end)
    user = %User{id: "user-1"}
    conn = %{assigns: %{current_user: user}}
    expect(Atlas.MCP, :access_token_for, fn ^user, _ -> {:error, :refresh_unavailable} end)

    assert {:ok, %{status: "refresh_unavailable", stage: "authorization", retryable: true, tools: []}} =
             Proxy.connection_status(conn, "tuist")

    expect(Atlas.MCP, :access_token_for, fn ^user, _ -> {:error, {:refresh_failed, "sensitive-refresh-body"}} end)

    assert {:ok, %{status: "refresh_failed", retryable: false, tools: []} = status} =
             Proxy.connection_status(conn, "tuist")

    assert status.message =~ "/admin/mcps"
    refute inspect(status) =~ "sensitive-refresh-body"
  end

  test "diagnostics require a user and current upstream group access, even for a previously advertised name" do
    conn = %{assigns: %{current_user: %User{id: "user-1"}, mcp_claims: %{"mcp_tool_groups" => []}}}
    reject(Req, :post, 1)

    assert {:error, _} = Proxy.connection_status(nil, "grafana")
    assert {:error, _} = Proxy.connection_status(conn, "grafana")
    assert {:error, _} = Proxy.call_hoisted_tool(conn, "grafana__atlas_connection_status", %{})
    assert {:error, _} = Proxy.connection_status(conn, "not-configured")
  end

  test "diagnostics never reuse another user's schemas or schemas from before revocation" do
    stub(Config, :get, fn -> tuist_proxy_config() end)
    first = %User{id: "user-1"}
    second = %User{id: "user-2"}
    first_conn = %{assigns: %{current_user: first}}
    second_conn = %{assigns: %{current_user: second}}

    expect(Atlas.MCP, :access_token_for, 3, fn ^first, _ -> {:ok, "token-1"} end)
    expect_initialize("https://tuist.example/mcp")
    expect_initialized_notification()

    expect_tools_list([
      %{"name" => "read", "annotations" => %{"readOnlyHint" => true}},
      %{"name" => "write", "annotations" => %{"readOnlyHint" => false}}
    ])

    assert {:ok, %{tools: [%{"name" => "tuist__read"}]}} = Proxy.connection_status(first_conn, "tuist")

    expect(Atlas.MCP, :access_token_for, fn ^second, _ -> {:error, :authorization_required} end)
    assert {:ok, %{status: "authorization_required", tools: []}} = Proxy.connection_status(second_conn, "tuist")

    expect(Atlas.MCP, :access_token_for, fn ^first, _ -> {:error, :authorization_required} end)
    assert {:ok, %{status: "authorization_required", tools: []}} = Proxy.connection_status(first_conn, "tuist")
  end

  test "permanent diagnostic tool checks live state and validates its structured output" do
    conn = %{assigns: %{current_user: %User{id: "user-1"}}}
    expect(Req, :post, fn _ -> {:error, %Req.TransportError{reason: :timeout}} end)
    response = GetMCPConnectionStatus.call(conn, %{"server" => "grafana"})
    assert response["structuredContent"]["status"] == "transport_error"
    assert response["structuredContent"]["retryable"]
    refute response["isError"]
  end

  defp expect_initialize do
    expect(Req, :post, fn %Req.Request{} = request ->
      assert URI.to_string(request.url) == "https://mcp.grafana.example/mcp"
      assert request.headers["accept"] == ["application/json, text/event-stream"]
      assert request.headers["mcp-protocol-version"] == ["2025-03-26"]
      assert request.headers["x-grafana-url"] == ["https://stack.grafana.net"]
      assert request.options.auth == {:bearer, "grafana-token"}
      assert request.options.receive_timeout == 20_000
      assert request.options.json["method"] == "initialize"

      {:ok,
       %Req.Response{
         status: 200,
         headers: %{"mcp-session-id" => ["session-1"]},
         body: %{
           "jsonrpc" => "2.0",
           "id" => request.options.json["id"],
           "result" => %{"protocolVersion" => "2025-03-26"}
         }
       }}
    end)
  end

  defp expect_initialized_notification do
    expect(Req, :post, fn %Req.Request{} = request ->
      assert request.headers["mcp-session-id"] == ["session-1"]

      assert request.options.json == %{
               "jsonrpc" => "2.0",
               "method" => "notifications/initialized"
             }

      {:ok, %Req.Response{status: 202, body: ""}}
    end)
  end

  defp atlas_identity_proxy_config do
    server =
      read_only_proxy_config()
      |> Keyword.fetch!(:servers)
      |> hd()
      |> Map.put("atlas_identity_header", "x-tuist-atlas-identity")

    [servers: [server]]
  end

  defp initialize_response(request) do
    {:ok,
     %Req.Response{
       status: 200,
       headers: %{"mcp-session-id" => ["session-1"]},
       body: %{
         "jsonrpc" => "2.0",
         "id" => request.options.json["id"],
         "result" => %{"protocolVersion" => "2025-03-26"}
       }
     }}
  end

  defp allowlisted_proxy_config do
    [
      servers: [
        read_only_proxy_config() |> Keyword.fetch!(:servers) |> hd() |> Map.put("tool_allowlist", ["get_test_run"])
      ]
    ]
  end

  # Read-only filtering is independent of how the upstream authenticates, so
  # these use a bearer token to keep the per-user OAuth session out of the way.
  defp read_only_proxy_config do
    server =
      tuist_proxy_config()
      |> Keyword.fetch!(:servers)
      |> hd()
      |> Map.merge(%{"auth_type" => "bearer_token", "bearer_token" => "tuist-token"})

    [servers: [server]]
  end

  defp expect_initialize(url) do
    expect(Req, :post, fn %Req.Request{} = request ->
      assert URI.to_string(request.url) == url
      assert request.options.json["method"] == "initialize"

      {:ok,
       %Req.Response{
         status: 200,
         headers: %{"mcp-session-id" => ["session-1"]},
         body: %{
           "jsonrpc" => "2.0",
           "id" => request.options.json["id"],
           "result" => %{"protocolVersion" => "2025-03-26"}
         }
       }}
    end)
  end

  # A tool-level refusal is a successful RPC carrying `isError`, not a transport
  # error, which is why it reaches the enrichment at all.
  #
  # No second handshake: the permission check and the call share one session, so
  # `tools/call` follows `tools/list` directly.
  defp expect_tool_call_refusal(text, result_extra \\ %{}) do
    expect(Req, :post, fn %Req.Request{} = request ->
      assert request.options.json["method"] == "tools/call"

      result =
        Map.merge(%{"content" => [%{"type" => "text", "text" => text}], "isError" => true}, result_extra)

      {:ok,
       %Req.Response{
         status: 200,
         body: %{"jsonrpc" => "2.0", "id" => request.options.json["id"], "result" => result}
       }}
    end)
  end

  defp expect_tools_list(tools) do
    expect(Req, :post, fn %Req.Request{} = request ->
      assert request.options.json["method"] == "tools/list"

      {:ok,
       %Req.Response{
         status: 200,
         body: %{"jsonrpc" => "2.0", "id" => request.options.json["id"], "result" => %{"tools" => tools}}
       }}
    end)
  end

  defp tuist_proxy_config do
    [
      servers: [
        %{
          "name" => "tuist",
          "url" => "https://tuist.example/mcp",
          "auth_type" => "oauth2",
          "authorization_url" => "https://tuist.example/oauth2/authorize",
          "token_url" => "https://tuist.example/oauth2/token",
          "registration_url" => "https://tuist.example/oauth2/register",
          "scopes" => ["mcp"],
          "read_only" => true
        }
      ]
    ]
  end

  defp proxy_config do
    [
      servers: [
        %{
          "name" => "grafana",
          "url" => "https://mcp.grafana.example/mcp",
          "headers" => %{"X-Grafana-URL" => "https://stack.grafana.net"},
          "bearer_token" => "grafana-token",
          "receive_timeout" => 20_000
        }
      ]
    ]
  end
end
