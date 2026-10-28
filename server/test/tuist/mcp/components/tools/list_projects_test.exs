defmodule Tuist.MCP.Components.Tools.ListProjectsTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.MCP.Components.Tools.ListProjects
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "list_projects" do
    test "returns results" do
      user = AccountsFixtures.user_fixture()
      project = ProjectsFixtures.project_fixture(account: user.account)

      conn = %Plug.Conn{assigns: %{current_subject: user}}

      result = ListProjects.call(conn, %{})

      assert %{
               "content" => [%{"type" => "text", "text" => text}],
               "structuredContent" => structured_content
             } = result

      assert %{
               "projects" => [
                 %{
                   "account_handle" => account_handle,
                   "build_system" => "xcode",
                   "full_handle" => full_handle,
                   "id" => project_id,
                   "name" => project_name
                 }
               ]
             } = JSON.decode!(text)

      assert structured_content == JSON.decode!(text)

      assert account_handle == user.account.name
      assert full_handle == "#{user.account.name}/#{project.name}"
      assert project_id == project.id
      assert project_name == project.name
    end

    test "returns build systems added after the output schema was declared" do
      user = AccountsFixtures.user_fixture()
      ProjectsFixtures.project_fixture(account: user.account, build_system: :once)

      conn = %Plug.Conn{assigns: %{current_subject: user}}

      assert %{"structuredContent" => %{"projects" => [%{"build_system" => "once"}]}} =
               ListProjects.call(conn, %{})
    end
  end
end
