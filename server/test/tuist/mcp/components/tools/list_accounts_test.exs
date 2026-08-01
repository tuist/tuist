defmodule Tuist.MCP.Components.Tools.ListAccountsTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.MCP.Components.Tools.ListAccounts
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "list_accounts" do
    test "returns personal and organization handles available to the user" do
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)
      conn = %Plug.Conn{assigns: %{current_user: user}}

      result = ListAccounts.call(conn, %{})

      assert %{"accounts" => accounts} = result["structuredContent"]

      assert %{
               "id" => user_account_id,
               "handle" => user_account_handle,
               "type" => "personal",
               "can_create_projects" => true
             } = Enum.find(accounts, &(&1["type"] == "personal"))

      assert user_account_id == user.account.id
      assert user_account_handle == user.account.name

      assert %{
               "id" => organization_account_id,
               "handle" => organization_account_handle,
               "type" => "organization",
               "can_create_projects" => true
             } = Enum.find(accounts, &(&1["type"] == "organization"))

      assert organization_account_id == organization.account.id
      assert organization_account_handle == organization.account.name
    end

    test "requires user authentication" do
      result = ListAccounts.call(%Plug.Conn{assigns: %{}}, %{})

      assert %{
               "content" => [%{"text" => "You must authenticate as a user to list accounts."}],
               "isError" => true
             } = result
    end
  end
end
