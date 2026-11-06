defmodule Tuist.OriginTest do
  use ExUnit.Case, async: false
  use TuistTestSupport.Cases.StubCase, billing: true
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Environment
  alias Tuist.Origin
  alias Tuist.Origin.Client
  alias Tuist.Origin.Installation
  alias Tuist.Projects
  alias Tuist.VCS
  alias Tuist.VCS.Comment
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    stub(Environment, :origin_app_id, fn -> "app_tuist" end)
    user = AccountsFixtures.user_fixture()
    project = ProjectsFixtures.project_fixture(account: user.account)

    snapshot = %{
      "id" => "i_test",
      "appId" => "app_tuist",
      "target" => %{"id" => "ns_test"},
      "scopes" => Client.scopes()
    }

    stub(Client, :get_installation, fn "i_test" -> {:ok, snapshot} end)
    claims = %{"sub" => "i_test", "namespace_id" => "ns_test"}
    {:ok, installation} = Origin.attach_installation(user.account, claims)

    %{
      user: user,
      account: user.account,
      project: project,
      installation: installation,
      claims: claims
    }
  end

  test "discovers sorted native repositories and the connected namespace without persisting profile data", %{
    account: account,
    user: user,
    installation: installation
  } do
    stub(Client, :get_installation, fn "i_test" ->
      {:ok,
       %{
         "id" => "i_test",
         "appId" => "app_tuist",
         "scopes" => Client.scopes(),
         "target" => %{"id" => "ns_test", "slug" => "acme"},
         "installedBy" => %{"email" => "private@example.com"}
       }}
    end)

    expect(Client, :list_repositories, fn ^installation ->
      {:ok,
       [
         %{"fullName" => "acme/zebra", "defaultBranch" => "develop"},
         %{"fullName" => "acme/mirror", "mirror" => %{"source" => "github"}},
         %{"fullName" => "acme/apple"},
         %{"name" => "incomplete"}
       ]}
    end)

    assert {:ok,
            %{
              namespace: "acme",
              repositories: [
                %{full_name: "acme/apple", default_branch: nil},
                %{full_name: "acme/zebra", default_branch: "develop"}
              ]
            }} = Origin.installation_details(account, user, installation.id)

    assert Repo.get!(Installation, installation.id) == installation
  end

  test "repository discovery rejects foreign installations, unauthorized users, and other app identities before HTTP", %{
    account: account,
    user: user,
    installation: installation
  } do
    other = AccountsFixtures.user_fixture()
    reject(&Client.list_repositories/1)
    reject(&Client.get_installation/1)
    assert {:error, _} = Origin.installation_details(other.account, other, installation.id)
    assert {:error, _} = Origin.installation_details(account, other, installation.id)
    assert {:error, _} = Origin.installation_details(account, user, "invalid")
    installation |> Ecto.Changeset.change(app_id: "app_other") |> Repo.update!()
    assert {:error, _} = Origin.installation_details(account, user, installation.id)
  end

  test "repeat setup is idempotent but cannot transfer installation ownership", %{
    account: account,
    claims: claims,
    installation: installation
  } do
    assert {:ok, %{id: id}} = Origin.attach_installation(account, claims)
    assert id == installation.id
    other = AccountsFixtures.user_fixture()

    assert {:error, :installation_already_connected} =
             Origin.attach_installation(other.account, claims)

    assert Repo.get!(Installation, id).account_id == account.id
  end

  test "only an account-owned project and installation can be linked", %{
    account: account,
    user: user,
    project: project,
    installation: installation
  } do
    other = AccountsFixtures.user_fixture()
    other_project = ProjectsFixtures.project_fixture(account: other.account)
    reject(&Client.get_repository/2)

    assert {:error, _} =
             Origin.connect_project(
               account,
               user,
               installation.id,
               other_project.id,
               "acme/rocket"
             )

    assert {:error, _} =
             Origin.connect_project(
               other.account,
               other,
               installation.id,
               project.id,
               "acme/rocket"
             )

    assert {:error, _} =
             Origin.connect_project(account, other, installation.id, project.id, "acme/rocket")
  end

  test "links a native repository and adopts its default branch", %{
    account: account,
    user: user,
    project: project,
    installation: installation
  } do
    stub(Client, :get_repository, fn ^installation, "acme/rocket" ->
      {:ok, %{"defaultBranch" => "develop"}}
    end)

    assert {:ok, %{provider: :origin}} =
             Origin.connect_project(account, user, installation.id, project.id, "acme/rocket")

    assert Projects.get_project_by_id(project.id).default_branch == "develop"
    assert Projects.get_repository_url(project) == "https://cursor.com/codebase/acme/rocket"
  end

  test "does not link GitHub mirrors", %{
    account: account,
    user: user,
    project: project,
    installation: installation
  } do
    stub(Client, :get_repository, fn _, _ -> {:ok, %{"mirror" => %{"source" => "github"}}} end)

    assert {:error, :invalid_origin_connection} =
             Origin.connect_project(account, user, installation.id, project.id, "acme/rocket")
  end

  test "disconnect cascades project connections and rejects foreign accounts", %{
    account: account,
    user: user,
    project: project,
    installation: installation
  } do
    {:ok, connection} = connect(project, installation)
    other = AccountsFixtures.user_fixture()
    assert {:error, :not_found} = Origin.disconnect(other.account, other, installation.id)
    assert {:ok, _} = Origin.disconnect(account, user, installation.id)
    assert {:error, :not_found} = Projects.get_vcs_connection(connection.id)
  end

  test "posts the shared preview report and updates only this app's existing report", %{
    project: project,
    installation: installation
  } do
    connect(project, installation)
    sha = String.duplicate("a", 40)
    AppBuildsFixtures.preview_fixture(project: project, git_ref: "feature", git_commit_sha: sha)
    stub(Client, :get_pull_request_number, fn _ -> {:ok, 7} end)
    stub(Client, :get_comments, fn _ -> {:ok, []} end)

    expect(Client, :create_comment, fn params ->
      assert params.issue_id == 7
      assert params.installation.id == installation.id
      assert String.starts_with?(params.body, "### 🛠️ Tuist Run Report 🛠️")
      assert params.body =~ "#### Previews"
      {:ok, %{}}
    end)

    assert {:ok, %{}} = VCS.post_vcs_pull_request_comment(report_args(project, sha))

    stub(Client, :get_comments, fn _ ->
      {:ok,
       [
         %Comment{id: "foreign", client_id: "app_other", body: "### 🛠️ Tuist Run Report 🛠️"},
         %Comment{id: "own", client_id: "app_tuist", body: "### 🛠️ Tuist Run Report 🛠️"}
       ]}
    end)

    expect(Client, :update_comment, fn params ->
      assert params.comment_id == "own"
      {:ok, %{}}
    end)

    assert {:ok, %{}} = VCS.post_vcs_pull_request_comment(report_args(project, sha))
  end

  test "failed comment discovery is retryable and never creates a duplicate", %{
    project: project,
    installation: installation
  } do
    connect(project, installation)
    stub(Client, :get_pull_request_number, fn _ -> {:ok, 7} end)
    stub(Client, :get_comments, fn _ -> {:error, {:origin_http_error, 503}} end)
    reject(&Client.create_comment/1)

    assert {:error, {:origin_http_error, 503}} =
             VCS.post_vcs_pull_request_comment(report_args(project, String.duplicate("a", 40)))
  end

  test "does not send Origin credentials for a same-named GitHub repository", %{
    project: project,
    installation: installation
  } do
    connect(project, installation)
    reject(&Client.get_pull_request_number/1)

    args =
      project
      |> report_args(String.duplicate("a", 40))
      |> Map.put(:git_remote_url_origin, "https://github.com/acme/rocket.git")

    assert :ok = VCS.post_vcs_pull_request_comment(args)
  end

  test "GitHub CI repository lookup does not authorize Origin projects", %{
    project: project,
    installation: installation
  } do
    connect(project, installation)
    assert [] = Projects.projects_by_vcs_repository_full_handle("acme/rocket")

    assert [found] =
             Projects.projects_by_vcs_repository_full_handle("acme/rocket", provider: :origin)

    assert found.id == project.id

    assert {:error, :not_found} =
             Projects.project_by_name_and_vcs_repository_full_handle(project.name, "acme/rocket")
  end

  test "recognizes Origin clone and browser URLs without treating unrelated Cursor URLs as repositories" do
    for url <- [
          "https://origin.cursor.com/acme/rocket.git",
          "https://ORIGIN.CURSOR.COM/git/acme/rocket.git",
          "https://origin.cursor.com/git/acme/rocket.git",
          "https://cursor.com/codebase/acme/rocket",
          "git@origin.cursor.com:git/acme/rocket.git"
        ] do
      assert {:ok, :origin} = VCS.get_provider_from_repository_url(url)
      assert {:ok, "acme/rocket"} = VCS.get_repository_full_handle_from_url(url)
    end

    assert {:error, :unsupported_vcs} =
             VCS.get_provider_from_repository_url("https://cursor.com/settings")

    assert {:error, :invalid_repository_url} = VCS.get_repository_full_handle_from_url(nil)
  end

  defp connect(project, installation) do
    Projects.create_vcs_connection(%{
      provider: :origin,
      repository_full_handle: "acme/rocket",
      project_id: project.id,
      origin_app_installation_id: installation.id
    })
  end

  defp report_args(project, sha) do
    %{
      git_ref: "feature",
      git_remote_url_origin: "https://origin.cursor.com/git/acme/rocket.git",
      git_commit_sha: sha,
      project: project,
      preview_url: fn _ -> "https://tuist.dev/preview" end,
      preview_qr_code_url: fn _ -> nil end,
      test_run_url: fn _ -> "" end,
      bundle_url: fn _ -> "" end,
      build_url: fn _ -> "" end
    }
  end
end
