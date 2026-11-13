defmodule TuistWeb.MCPAgentIdentityTest do
  # Drives `/mcp` through the router with the identity tokens coding agents hold
  # in sandboxes: an Amp orb's `${amp:id-token}` and a Claude Code session token.
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Plug.Conn

  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.SandboxesFixtures

  @workspace_id "0284a29c-b50a-41f8-b83f-94e5c9b32f5f"
  @amp_jwks_uri "https://ampcode.com/api/workload-identity/jwks.json"
  @claude_jwks_uri "https://api.anthropic.com/v1/code/.well-known/jwks.json"

  setup :set_mimic_from_context

  setup do
    stub(Tuist.KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)
    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _account -> true end)

    account = AccountsFixtures.organization_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id, preload: [:account])
    other_project = ProjectsFixtures.project_fixture(preload: [:account])

    %{account: account, project: project, other_project: other_project}
  end

  describe "an Amp orb's ID token" do
    setup %{account: account} do
      {:ok, _} = Accounts.create_amp_workspace_connection(account, %{workspace_id: @workspace_id})
      :ok
    end

    test "reads the connected account's projects", %{project: project} do
      token = amp_token()

      assert %{"projects" => [%{"full_handle" => full_handle}]} = structured(call_tool(token, "list_projects", %{}))
      assert full_handle == "#{project.account.name}/#{project.name}"

      for tool <- ["get_project", "list_test_runs", "list_test_cases", "list_xcode_builds", "list_previews"] do
        refute call_tool(token, tool, handles(project))["isError"], "#{tool} was refused"
      end
    end

    test "cannot write, nor read another account's project", %{project: project, other_project: other_project} do
      token = amp_token()

      assert error_text(
               token,
               "update_test_case",
               Map.merge(handles(project), %{"identifier" => "A/b", "state" => "muted"})
             ) =~
               "You do not have access"

      assert error_text(token, "get_project", handles(other_project)) =~ "You do not have access"
    end

    test "is refused when minted for another origin than this instance's" do
      conn = mcp(amp_token(%{"aud" => "https://tuist.dev"}), "tools/list")

      assert conn.status == 401
      assert json_response(conn, 401)["error_description"] == "Missing or invalid access token."
    end

    test "is refused unless printed by `amp orb id-token`" do
      assert mcp(amp_token(%{"token_use" => "mcp"}), "tools/list").status == 401
    end

    test "is refused when its subject names another workspace than its claims" do
      subject = "workspace:#{Ecto.UUID.generate()}:user:user_1:thread:T-#{Ecto.UUID.generate()}"

      assert mcp(amp_token(%{"sub" => subject}), "tools/list").status == 401
    end

    test "explains why an unconnected workspace is refused" do
      workspace_id = Ecto.UUID.generate()

      conn =
        mcp(
          amp_token(%{
            "workspace_id" => workspace_id,
            "sub" => "workspace:#{workspace_id}:user:user_1:thread:T-#{Ecto.UUID.generate()}"
          }),
          "tools/list"
        )

      assert json_response(conn, 401)["error_description"] =~ "not connected to a Tuist account"
    end
  end

  describe "a Claude Code session token" do
    setup %{account: account} do
      SandboxesFixtures.agent_environment_fixture(
        account: account,
        kind: :claude_code,
        anthropic_environment_id: "ccpool_01connected"
      )

      :ok
    end

    test "reads the connected account's projects but cannot write", %{project: project} do
      token = claude_token()

      refute call_tool(token, "list_test_runs", handles(project))["isError"]

      assert error_text(
               token,
               "update_test_case",
               Map.merge(handles(project), %{"identifier" => "A/b", "state" => "muted"})
             ) =~
               "You do not have access"
    end

    test "explains why a session of an unconnected environment is refused" do
      token = claude_token(%{"ccr:pool_id" => "ccpool_01other", "aud" => ["anthropic-api", "ccpool_01other"]})

      assert json_response(mcp(token, "tools/list"), 401)["error_description"] =~
               "Claude Code environment is not connected"
    end
  end

  defp handles(project), do: %{"account_handle" => project.account.name, "project_handle" => project.name}

  defp call_tool(token, name, arguments) do
    token
    |> mcp("tools/call", %{"name" => name, "arguments" => arguments})
    |> result()
  end

  defp error_text(token, name, arguments) do
    assert %{"isError" => true, "content" => [%{"text" => text}]} = call_tool(token, name, arguments)
    text
  end

  defp structured(result), do: result["structuredContent"]

  defp mcp(token, method, params \\ %{}) do
    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json, text/event-stream")
    |> put_req_header("mcp-protocol-version", "2025-06-18")
    |> post("/mcp", %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params})
  end

  defp result(conn) do
    assert conn.status == 200

    conn.resp_body
    |> String.split("\n")
    |> Enum.find_value(conn.resp_body, fn
      "data: " <> data -> data
      _ -> nil
    end)
    |> JSON.decode!()
    |> Map.fetch!("result")
  end

  defp amp_token(claims \\ %{}) do
    thread_id = "T-" <> Ecto.UUID.generate()

    claims =
      Map.merge(
        %{
          "iss" => "https://ampcode.com/api/workload-identity",
          "aud" => "http://localhost:8080",
          "exp" => DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_unix(),
          "token_use" => "exchanged",
          "workspace_id" => @workspace_id,
          "user_id" => "user_1",
          "thread_id" => thread_id,
          "sub" => "workspace:#{@workspace_id}:user:user_1:thread:#{thread_id}"
        },
        claims
      )

    sign(claims, {:rsa, 2048}, "RS256", @amp_jwks_uri)
  end

  defp claude_token(claims \\ %{}) do
    claims =
      Map.merge(
        %{
          "iss" => "ccr",
          "sub" => "ccr:session:cse_01abc",
          "aud" => ["anthropic-api", "ccpool_01connected"],
          "exp" => DateTime.utc_now() |> DateTime.add(4 * 3600) |> DateTime.to_unix(),
          "ccr:role" => "session_worker",
          "ccr:pool_id" => "ccpool_01connected"
        },
        claims
      )

    "sk-ant-cc-" <> sign(claims, {:ec, "P-256"}, "ES256", @claude_jwks_uri)
  end

  defp sign(claims, key_type, alg, jwks_uri) do
    jwk = JOSE.JWK.generate_key(key_type)
    {_, public_jwk} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    jwks = %{"keys" => [Map.merge(public_jwk, %{"use" => "sig", "alg" => alg, "kid" => "test-key"})]}

    stub(Req, :get, fn ^jwks_uri, _opts -> {:ok, %{status: 200, body: jwks}} end)

    {_, token} =
      jwk |> JOSE.JWT.sign(%{"alg" => alg, "kid" => "test-key"}, JOSE.JWT.from_map(claims)) |> JOSE.JWS.compact()

    token
  end
end
