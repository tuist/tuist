defmodule TuistWeb.MCPOAuthSessionTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.Accounts
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.RateLimit

  # Drives `/mcp` through the router with access tokens minted by the OAuth
  # token generator, the credential a client receives from the browser
  # authorization flow, so authentication and tool authorization run unstubbed.

  setup do
    stub(RateLimit.MCP, :hit, fn _conn -> {:allow, 1} end)
    stub(Clients, :get_client, fn _ -> %{access_token_ttl: 3600, refresh_token_ttl: 86_400} end)

    admin = AccountsFixtures.user_fixture(preload: [:account])
    organization = AccountsFixtures.organization_fixture(creator: admin, preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: organization.account.id, preload: [:account])

    {:ok, admin: admin, organization: organization, project: project}
  end

  defp oauth_access_token(user, scope) do
    TokenGenerator.generate(:access_token, %Token{
      sub: Integer.to_string(user.id),
      client_id: UUIDv7.generate(),
      scope: scope
    })
  end

  defp call_tool(conn, token, name, arguments) do
    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("accept", "application/json, text/event-stream")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("mcp-protocol-version", "2026-07-28")
      |> put_req_header("mcp-method", "tools/call")
      |> put_req_header("mcp-name", name)
      |> post(
        "/mcp",
        JSON.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => %{
            "name" => name,
            "arguments" => arguments,
            "_meta" => %{
              "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
              "io.modelcontextprotocol/clientCapabilities" => %{}
            }
          }
        })
      )

    assert conn.status == 200
    [_, json] = String.split(conn.resp_body, "data: ", parts: 2)
    JSON.decode!(String.trim(json))["result"]
  end

  defp stub_test_case(project) do
    stub(Tests, :get_test_case_by_id, fn "test-case-id" -> {:ok, %{id: "test-case-id", project_id: project.id}} end)
  end

  describe "a session authorized with the mcp scope" do
    test "lets an organization admin read the organization's webhook endpoints", %{
      conn: conn,
      admin: admin,
      organization: organization
    } do
      result =
        call_tool(conn, oauth_access_token(admin, "mcp"), "list_webhook_endpoints", %{
          "account_handle" => organization.account.name
        })

      refute result["isError"]
    end

    test "lets a project member mark a test case as flaky, attributing the change to the user", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      member = AccountsFixtures.user_fixture(preload: [:account])
      Accounts.add_user_to_organization(member, organization, role: :user)
      stub_test_case(project)

      expect(Tests, :update_test_case, fn "test-case-id", %{is_flaky: true}, opts ->
        assert opts[:actor_id] == member.account.id

        {:ok,
         %{
           id: "test-case-id",
           name: "testExample",
           module_name: "AppTests",
           suite_name: "AppTests",
           is_flaky: true,
           state: "enabled"
         }}
      end)

      result =
        call_tool(conn, oauth_access_token(member, "mcp"), "update_test_case", %{
          "test_case_id" => "test-case-id",
          "is_flaky" => true
        })

      refute result["isError"]
      assert result["structuredContent"]["is_flaky"] == true
    end

    test "lets the user run the account setup tools", %{conn: conn, admin: admin, organization: organization} do
      result = call_tool(conn, oauth_access_token(admin, "mcp"), "list_accounts", %{})

      refute result["isError"]
      handles = Enum.map(result["structuredContent"]["accounts"], & &1["handle"])
      assert organization.account.name in handles
    end

    test "refuses a member who is not an admin the webhook endpoints", %{conn: conn, organization: organization} do
      member = AccountsFixtures.user_fixture(preload: [:account])
      Accounts.add_user_to_organization(member, organization, role: :user)

      result =
        call_tool(conn, oauth_access_token(member, "mcp"), "list_webhook_endpoints", %{
          "account_handle" => organization.account.name
        })

      assert result["isError"]
    end

    test "refuses a user outside the organization a test case update", %{conn: conn, project: project} do
      outsider = AccountsFixtures.user_fixture(preload: [:account])
      stub_test_case(project)
      reject(&Tests.update_test_case/3)

      result =
        call_tool(conn, oauth_access_token(outsider, "mcp"), "update_test_case", %{
          "test_case_id" => "test-case-id",
          "is_flaky" => true
        })

      assert result["isError"]
    end
  end

  test "a session without the mcp scope keeps to its token scopes", %{
    conn: conn,
    admin: admin,
    organization: organization
  } do
    result =
      call_tool(conn, oauth_access_token(admin, nil), "list_webhook_endpoints", %{
        "account_handle" => organization.account.name
      })

    assert result["isError"]
  end
end
