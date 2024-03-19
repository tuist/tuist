defmodule TuistCloudWeb.API.Authorization.CachePlugTest do
  alias TuistCloudWeb.API.Authorization.CachePlug
  alias TuistCloud.Accounts
  alias TuistCloud.ProjectsFixtures
  alias TuistCloud.AccountsFixtures
  alias TuistCloudWeb.API.EnsureProjectPresencePlug
  use TuistCloudWeb.ConnCase

  test "returns a 403 and halts the connection if the authenticated subject is not authorized" do
    # Given
    project = ProjectsFixtures.project_fixture()
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_by_id(project.account_id)
    opts = CachePlug.init(:cache)

    conn =
      build_conn(:get, ~p"/api/cache", project_id: account.name <> "/" <> project.name)
      |> EnsureProjectPresencePlug.put_project(project)
      |> TuistCloudWeb.Authentication.put_authenticated_user(user)

    # When
    conn = conn |> CachePlug.call(opts)

    # Then
    assert conn.halted == true

    assert json_response(conn, 403) == %{
             "message" => "The authenticated subject is not authorized to perform this action"
           }
  end

  test "returns the connection when the authenticated project is trying to access itself" do
    # Given
    project = ProjectsFixtures.project_fixture()
    account = Accounts.get_account_by_id(project.account_id)
    opts = CachePlug.init(:cache)

    conn =
      build_conn(:get, ~p"/api/cache", project_id: account.name <> "/" <> project.name)
      |> EnsureProjectPresencePlug.put_project(project)
      |> TuistCloudWeb.Authentication.put_authenticated_project(project)

    # When
    got = conn |> CachePlug.call(opts)

    # Then
    assert conn == got
  end
end
