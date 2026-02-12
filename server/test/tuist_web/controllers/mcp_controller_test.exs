defmodule TuistWeb.MCPControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "POST /mcp" do
    test "returns a bearer challenge when not authenticated", %{conn: conn} do
      stub(Environment, :app_url, fn -> "https://test.tuist.dev" end)

      conn = post(conn, "/mcp", %{})
      response = json_response(conn, 401)

      [www_authenticate] = get_resp_header(conn, "www-authenticate")

      assert www_authenticate =~ ~s(Bearer realm="tuist-mcp")

      assert www_authenticate =~
               ~s(resource_metadata="https://test.tuist.dev/.well-known/oauth-protected-resource/mcp")

      assert response == %{
               "error" => "invalid_token",
               "error_description" => "Missing or invalid access token."
             }
    end

    test "returns not implemented when authenticated", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{user.token}")
        |> post("/mcp", %{})

      assert json_response(conn, 501) == %{
               "jsonrpc" => "2.0",
               "error" => %{
                 "code" => -32_601,
                 "message" => "Tuist MCP HTTP transport is not implemented yet."
               },
               "id" => nil
             }
    end
  end
end
