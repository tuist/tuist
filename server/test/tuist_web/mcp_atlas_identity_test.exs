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

  defp get_project(conn, token, project, headers) do
    init_conn =
      conn
      |> mcp_conn(token, headers)
      |> post("/mcp", %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{
          "protocolVersion" => "2025-06-18",
          "capabilities" => %{},
          "clientInfo" => %{"name" => "test", "version" => "0.1.0"}
        }
      })

    case get_resp_header(init_conn, "mcp-session-id") do
      [session_id] ->
        build_conn()
        |> mcp_conn(token, [{"mcp-session-id", session_id} | headers])
        |> post("/mcp", %{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "tools/call",
          "params" => %{
            "name" => "get_project",
            "arguments" => %{"account_handle" => project.account.name, "project_handle" => project.name}
          }
        })

      [] ->
        init_conn
    end
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
