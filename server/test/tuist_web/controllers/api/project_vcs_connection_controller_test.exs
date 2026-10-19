defmodule TuistWeb.API.ProjectVCSConnectionControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import OpenApiSpex.TestAssertions, only: [assert_schema: 3]

  alias Tuist.Accounts
  alias Tuist.GitHub.Client
  alias Tuist.Projects
  alias Tuist.Projects.VCSConnection
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.VCSFixtures
  alias TuistWeb.API.Spec
  alias TuistWeb.Authentication

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    organization = AccountsFixtures.organization_fixture(creator: user, preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: organization.account.id, default_branch: "main")

    %{user: user, organization: organization, account: organization.account, project: project}
  end

  defp stub_installation_repositories(repositories) do
    stub(Client, :list_installation_repositories, fn _installation, _opts ->
      {:ok, %{meta: %{next_url: nil}, repositories: repositories}}
    end)
  end

  defp repository(full_name, default_branch \\ "trunk") do
    %{
      id: 1,
      name: full_name |> String.split("/") |> List.last(),
      full_name: full_name,
      private: true,
      default_branch: default_branch
    }
  end

  defp as_user(conn, user) do
    conn
    |> Authentication.put_current_user(user)
    |> put_req_header("content-type", "application/json")
  end

  defp as_token(conn, account, scopes) do
    {:ok, {_account_token, token}} =
      Accounts.create_account_token(%{
        account: account,
        scopes: scopes,
        name: "token-#{TuistTestSupport.Utilities.unique_integer()}",
        all_projects: true,
        project_ids: []
      })

    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
  end

  defp vcs_path(account, project), do: "/api/projects/#{account.name}/#{project.name}/vcs-connection"

  describe "PUT /api/projects/:account_handle/:project_handle/vcs-connection" do
    test "links the project to a repository the GitHub App installation can access", %{
      conn: conn,
      user: user,
      organization: organization,
      account: account,
      project: project
    } do
      installation = VCSFixtures.github_app_installation_fixture(account: organization)
      stub_installation_repositories([repository("Acme/App")])

      conn = conn |> as_user(user) |> put(vcs_path(account, project), %{repository_full_handle: "acme/app"})

      response = json_response(conn, :ok)
      assert response == %{"provider" => "github", "repository_full_handle" => "Acme/App"}
      assert_schema(response, "ProjectVCSConnection", Spec.spec())

      project = Projects.get_project_by_id(project.id)
      assert project.default_branch == "trunk"

      connection = Tuist.Repo.get_by!(VCSConnection, project_id: project.id)
      assert connection.github_app_installation_id == installation.id
      assert connection.created_by_id == user.id
    end

    test "links with an account token holding project:admin:write", %{
      conn: conn,
      organization: organization,
      account: account,
      project: project
    } do
      VCSFixtures.github_app_installation_fixture(account: organization)
      stub_installation_repositories([repository("acme/app")])

      conn =
        conn
        |> as_token(account, ["project:admin:write"])
        |> put(vcs_path(account, project), %{repository_full_handle: "acme/app"})

      assert json_response(conn, :ok)["repository_full_handle"] == "acme/app"
    end

    test "refuses an account token with project:admin:read", %{
      conn: conn,
      organization: organization,
      account: account,
      project: project
    } do
      VCSFixtures.github_app_installation_fixture(account: organization)
      reject(&Client.list_installation_repositories/2)

      conn =
        conn
        |> as_token(account, ["project:admin:read"])
        |> put(vcs_path(account, project), %{repository_full_handle: "acme/app"})

      assert json_response(conn, :forbidden)
      refute Tuist.Repo.get_by(VCSConnection, project_id: project.id)
    end

    test "refuses a repository the installation can't access", %{
      conn: conn,
      user: user,
      organization: organization,
      account: account,
      project: project
    } do
      VCSFixtures.github_app_installation_fixture(account: organization)
      stub_installation_repositories([repository("acme/other")])

      conn = conn |> as_user(user) |> put(vcs_path(account, project), %{repository_full_handle: "acme/app"})

      assert json_response(conn, :unprocessable_entity)["message"] =~ "acme/app"
      refute Tuist.Repo.get_by(VCSConnection, project_id: project.id)
    end

    test "refuses when the account has no GitHub App installation", %{
      conn: conn,
      user: user,
      account: account,
      project: project
    } do
      reject(&Client.list_installation_repositories/2)

      conn = conn |> as_user(user) |> put(vcs_path(account, project), %{repository_full_handle: "acme/app"})

      assert json_response(conn, :unprocessable_entity)["message"] =~ "GitHub App"
    end

    test "refuses when the GitHub App installation is still pending", %{
      conn: conn,
      user: user,
      organization: organization,
      account: account,
      project: project
    } do
      VCSFixtures.github_app_installation_fixture(
        account: organization,
        installation_id: nil,
        app_id: "#{TuistTestSupport.Utilities.unique_integer()}",
        private_key: "pending-private-key"
      )

      reject(&Client.list_installation_repositories/2)

      conn = conn |> as_user(user) |> put(vcs_path(account, project), %{repository_full_handle: "acme/app"})

      assert json_response(conn, :unprocessable_entity)["message"] =~ "GitHub App"
    end

    test "returns the existing link when the project is already linked to the repository", %{
      conn: conn,
      user: user,
      organization: organization,
      account: account,
      project: project
    } do
      installation = VCSFixtures.github_app_installation_fixture(account: organization)

      {:ok, _} =
        Projects.create_vcs_connection(%{
          project_id: project.id,
          provider: :github,
          repository_full_handle: "Acme/App",
          github_app_installation_id: installation.id
        })

      reject(&Client.list_installation_repositories/2)

      conn = conn |> as_user(user) |> put(vcs_path(account, project), %{repository_full_handle: "acme/app"})

      assert json_response(conn, :ok) == %{"provider" => "github", "repository_full_handle" => "Acme/App"}
    end

    test "refuses to replace a link to another repository", %{
      conn: conn,
      user: user,
      organization: organization,
      account: account,
      project: project
    } do
      installation = VCSFixtures.github_app_installation_fixture(account: organization)

      {:ok, _} =
        Projects.create_vcs_connection(%{
          project_id: project.id,
          provider: :github,
          repository_full_handle: "acme/other",
          github_app_installation_id: installation.id
        })

      reject(&Client.list_installation_repositories/2)

      conn = conn |> as_user(user) |> put(vcs_path(account, project), %{repository_full_handle: "acme/app"})

      assert json_response(conn, :conflict)["message"] =~ "acme/other"
    end

    test "rejects a malformed repository handle", %{conn: conn, user: user, account: account, project: project} do
      conn = conn |> as_user(user) |> put(vcs_path(account, project), %{repository_full_handle: "not a repository"})

      assert json_response(conn, :bad_request)
    end
  end

  describe "DELETE /api/projects/:account_handle/:project_handle/vcs-connection" do
    test "unlinks the project", %{conn: conn, user: user, organization: organization, account: account, project: project} do
      installation = VCSFixtures.github_app_installation_fixture(account: organization)

      {:ok, _} =
        Projects.create_vcs_connection(%{
          project_id: project.id,
          provider: :github,
          repository_full_handle: "acme/app",
          github_app_installation_id: installation.id
        })

      conn = conn |> as_user(user) |> delete(vcs_path(account, project))

      assert response(conn, :no_content) == ""
      refute Tuist.Repo.get_by(VCSConnection, project_id: project.id)
    end

    test "returns not found when the project isn't linked", %{conn: conn, user: user, account: account, project: project} do
      conn = conn |> as_user(user) |> delete(vcs_path(account, project))

      assert json_response(conn, :not_found)
    end

    test "refuses a member who isn't an admin", %{
      conn: conn,
      organization: organization,
      account: account,
      project: project
    } do
      member = AccountsFixtures.user_fixture(preload: [:account])
      Accounts.add_user_to_organization(member, organization, role: :user)
      installation = VCSFixtures.github_app_installation_fixture(account: organization)

      {:ok, _} =
        Projects.create_vcs_connection(%{
          project_id: project.id,
          provider: :github,
          repository_full_handle: "acme/app",
          github_app_installation_id: installation.id
        })

      conn = conn |> as_user(member) |> delete(vcs_path(account, project))

      assert json_response(conn, :forbidden)
      assert Tuist.Repo.get_by(VCSConnection, project_id: project.id)
    end
  end
end
