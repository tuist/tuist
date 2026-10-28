defmodule TuistWeb.MCPAtlasIdentityTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Plug.Conn

  alias Tuist.AtlasWorkloadIdentity
  alias Tuist.Authentication
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  # Drives `/mcp` through the router with a real OAuth access token, the shape
  # Atlas proxies every call in, so the plug and the authorization fallback are
  # exercised together.

  setup :set_mimic_from_context

  setup do
    stub(Tuist.Environment, :tuist_hosted?, fn -> false end)

    project = ProjectsFixtures.project_fixture(preload: [:account])

    operator =
      AccountsFixtures.user_fixture(
        email: "operator-#{System.unique_integer([:positive])}@tuist.dev",
        preload: [:account]
      )

    {:ok, project: project, operator: operator}
  end

  defp oauth_token(user) do
    {:ok, token, _claims} =
      Authentication.encode_and_sign(
        user.account,
        %{"type" => "account", "scopes" => ["mcp"], "all_projects" => true, "user_id" => user.id},
        token_type: :access,
        ttl: {1, :hour}
      )

    token
  end

  # Mirrors `Atlas.MCP.Proxy.with_session/3`: initialize, notifications/initialized,
  # then the call, on separate connections, forwarding `mcp-session-id` only when
  # the server returns one.
  defp get_project(conn, token, project, headers) do
    headers = [{"mcp-protocol-version", "2025-03-26"} | headers]

    init_conn =
      conn
      |> mcp_conn(token, headers)
      |> post("/mcp", %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{
          "protocolVersion" => "2025-03-26",
          "capabilities" => %{},
          "clientInfo" => %{"name" => "atlas", "version" => "0.1.0"}
        }
      })

    if init_conn.status == 200, do: call_after_initialize(init_conn, token, project, headers), else: init_conn
  end

  defp call_after_initialize(init_conn, token, project, headers) do
    assert %{"protocolVersion" => "2025-03-26"} = tool_result(init_conn)

    headers =
      case get_resp_header(init_conn, "mcp-session-id") do
        [session_id] -> [{"mcp-session-id", session_id} | headers]
        [] -> headers
      end

    initialized_conn =
      build_conn()
      |> mcp_conn(token, headers)
      |> post("/mcp", %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

    assert initialized_conn.status in 200..299

    build_conn()
    |> mcp_conn(token, headers)
    |> post("/mcp", %{
      "jsonrpc" => "2.0",
      "id" => 2,
      "method" => "tools/call",
      "params" => %{
        "name" => "get_project",
        "arguments" => %{"account_handle" => project.account.name, "project_handle" => project.name}
      }
    })
  end

  defp mcp_conn(conn, token, headers) do
    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")

    Enum.reduce(headers, conn, fn {name, value}, acc -> put_req_header(acc, name, value) end)
  end

  defp tool_result(conn) do
    conn.resp_body
    |> String.split("\n")
    |> Enum.find_value(conn.resp_body, fn
      "data: " <> data -> data
      _ -> nil
    end)
    |> JSON.decode!()
    |> Map.fetch!("result")
  end

  defp stub_identity(result) do
    stub(AtlasWorkloadIdentity, :verify, fn "atlas-token" -> result end)
  end

  @atlas_header {"x-tuist-atlas-identity", "atlas-token"}

  test "an operator reads a customer project through Atlas", %{conn: conn, project: project, operator: operator} do
    stub_identity({:ok, %{namespace: "atlas-production", name: "atlas", uid: "uid"}})

    conn = get_project(conn, oauth_token(operator), project, [@atlas_header])

    result = tool_result(conn)
    refute result["isError"]
    assert result["structuredContent"]["full_handle"] == "#{project.account.name}/#{project.name}"
    assert Logger.metadata()[:atlas_operator_email] == operator.email
    assert Logger.metadata()[:atlas_operator_read_account_id] == project.account_id
  end

  test "the same operator calling directly is refused", %{conn: conn, project: project, operator: operator} do
    conn = get_project(conn, oauth_token(operator), project, [])

    assert %{"isError" => true} = tool_result(conn)
  end

  test "a non-operator calling through Atlas is refused", %{conn: conn, project: project} do
    stub_identity({:ok, %{namespace: "atlas-production", name: "atlas", uid: "uid"}})

    user =
      AccountsFixtures.user_fixture(
        email: "someone-#{System.unique_integer([:positive])}@example.com",
        preload: [:account]
      )

    conn = get_project(conn, oauth_token(user), project, [@atlas_header])

    assert %{"isError" => true} = tool_result(conn)
  end

  test "rejects an identity that fails verification", %{conn: conn, project: project, operator: operator} do
    stub_identity({:error, :invalid_signature})

    conn = get_project(conn, oauth_token(operator), project, [@atlas_header])

    assert conn.status == 401
    assert JSON.decode!(conn.resp_body)["error"] == "atlas_identity_rejected"
  end

  test "continues without elevation when the verifier is not configured", %{
    conn: conn,
    project: project,
    operator: operator
  } do
    stub_identity({:error, :not_configured})

    conn = get_project(conn, oauth_token(operator), project, [@atlas_header])

    assert %{"isError" => true} = tool_result(conn)
  end
end
