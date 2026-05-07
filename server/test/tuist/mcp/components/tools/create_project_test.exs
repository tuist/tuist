defmodule Tuist.MCP.Components.Tools.CreateProjectTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.MCP.Components.Tools.CreateProject
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "create_project" do
    test "creates a project under an accessible account" do
      user = AccountsFixtures.user_fixture()
      project_handle = "mcp-project-#{TuistTestSupport.Utilities.unique_integer()}"

      conn = %Plug.Conn{assigns: %{current_user: user}}

      result =
        CreateProject.call(conn, %{
          "account_handle" => user.account.name,
          "project_handle" => project_handle,
          "build_system" => "gradle"
        })

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result

      assert %{
               "account_handle" => account_handle,
               "build_system" => "gradle",
               "full_handle" => full_handle,
               "name" => ^project_handle
             } = JSON.decode!(text)

      assert account_handle == user.account.name
      assert full_handle == "#{user.account.name}/#{project_handle}"
    end

    test "returns project changeset errors" do
      user = AccountsFixtures.user_fixture()
      project_handle = "mcp-project-#{TuistTestSupport.Utilities.unique_integer()}"

      conn = %Plug.Conn{assigns: %{current_user: user}}

      result =
        CreateProject.call(conn, %{
          "account_handle" => user.account.name,
          "project_handle" => project_handle,
          "build_system" => "unknown"
        })

      assert %{"content" => [%{"type" => "text", "text" => "is invalid"}], "isError" => true} =
               result
    end

    test "does not reveal inaccessible accounts" do
      owner = AccountsFixtures.user_fixture()
      outsider = AccountsFixtures.user_fixture()
      project_handle = "mcp-project-#{TuistTestSupport.Utilities.unique_integer()}"

      conn = %Plug.Conn{assigns: %{current_user: outsider}}

      result =
        CreateProject.call(conn, %{
          "account_handle" => owner.account.name,
          "project_handle" => project_handle
        })

      assert %{
               "content" => [
                 %{
                   "text" => "The authenticated subject is not authorized to perform this action.",
                   "type" => "text"
                 }
               ],
               "isError" => true
             } = result
    end
  end
end
