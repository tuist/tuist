defmodule Tuist.MCP.Components.Tools.ProjectRepositoryToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.GitHub.Client
  alias Tuist.MCP.Components.Tools.ConnectProjectRepository
  alias Tuist.MCP.Components.Tools.DisconnectProjectRepository
  alias Tuist.Projects
  alias Tuist.Projects.VCSConnection
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.VCSFixtures

  setup do
    admin = AccountsFixtures.user_fixture(preload: [:account])
    organization = AccountsFixtures.organization_fixture(creator: admin, preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: organization.account.id)
    installation = VCSFixtures.github_app_installation_fixture(account: organization)

    stub(Client, :list_installation_repositories, fn _installation, _opts ->
      {:ok,
       %{
         meta: %{next_url: nil},
         repositories: [%{id: 1, name: "app", full_name: "acme/app", private: true, default_branch: "trunk"}]
       }}
    end)

    %{
      admin: admin,
      organization: organization,
      project: project,
      installation: installation,
      args: %{"account_handle" => organization.account.name, "project_handle" => project.name}
    }
  end

  defp user_conn(user), do: %Plug.Conn{assigns: %{current_user: user}}

  describe "connect_project_repository" do
    test "links the project for an admin", %{admin: admin, project: project, args: args} do
      result = ConnectProjectRepository.call(user_conn(admin), Map.put(args, "repository_full_handle", "acme/app"))

      refute result["isError"]
      assert result["structuredContent"] == %{"provider" => "github", "repository_full_handle" => "acme/app"}
      assert Repo.get_by!(VCSConnection, project_id: project.id).created_by_id == admin.id
      assert Projects.get_project_by_id(project.id).default_branch == "trunk"
    end

    test "reports a repository the installation can't access", %{admin: admin, project: project, args: args} do
      result = ConnectProjectRepository.call(user_conn(admin), Map.put(args, "repository_full_handle", "acme/other"))

      assert %{"isError" => true, "content" => [%{"text" => text}]} = result
      assert text =~ "acme/other"
      refute Repo.get_by(VCSConnection, project_id: project.id)
    end

    test "refuses a member who isn't an admin", %{organization: organization, project: project, args: args} do
      member = AccountsFixtures.user_fixture(preload: [:account])
      Accounts.add_user_to_organization(member, organization, role: :user)

      result = ConnectProjectRepository.call(user_conn(member), Map.put(args, "repository_full_handle", "acme/app"))

      assert result["isError"]
      refute Repo.get_by(VCSConnection, project_id: project.id)
    end

    test "refuses a token without project:admin:write", %{organization: organization, project: project, args: args} do
      subject = %AuthenticatedAccount{account: organization.account, scopes: ["project:admin:read"], all_projects: true}
      conn = %Plug.Conn{assigns: %{current_subject: subject}}

      result = ConnectProjectRepository.call(conn, Map.put(args, "repository_full_handle", "acme/app"))

      assert result["isError"]
      refute Repo.get_by(VCSConnection, project_id: project.id)
    end
  end

  describe "disconnect_project_repository" do
    test "unlinks the project for an admin", %{admin: admin, project: project, installation: installation, args: args} do
      {:ok, _} =
        Projects.create_vcs_connection(%{
          project_id: project.id,
          provider: :github,
          repository_full_handle: "acme/app",
          github_app_installation_id: installation.id
        })

      result = DisconnectProjectRepository.call(user_conn(admin), args)

      refute result["isError"]
      assert result["structuredContent"] == %{"disconnected" => true}
      refute Repo.get_by(VCSConnection, project_id: project.id)
    end

    test "reports a project that isn't linked", %{admin: admin, args: args} do
      assert %{"isError" => true} = DisconnectProjectRepository.call(user_conn(admin), args)
    end
  end
end
