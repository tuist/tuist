defmodule Tuist.MCP.Components.Tools.CreateOrganizationTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.MCP.Components.Tools.CreateOrganization
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "create_organization" do
    test "creates an organization for the authenticated user" do
      user = AccountsFixtures.user_fixture()
      handle = "acme-mcp-#{TuistTestSupport.Utilities.unique_integer()}"

      conn = %Plug.Conn{assigns: %{current_user: user}}
      result = CreateOrganization.call(conn, %{"handle" => handle})

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      assert %{"name" => ^handle, "account_handle" => ^handle} = JSON.decode!(text)
    end

    test "returns account changeset errors" do
      user = AccountsFixtures.user_fixture()

      conn = %Plug.Conn{assigns: %{current_user: user}}
      result = CreateOrganization.call(conn, %{"handle" => "acme.mcp"})

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} = result
      assert text == "must contain only alphanumeric characters"
    end
  end
end
