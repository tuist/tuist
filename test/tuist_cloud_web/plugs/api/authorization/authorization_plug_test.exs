defmodule TuistCloudWeb.API.Authorization.AuthorizationPlugTest do
  alias TuistCloud.Repo
  alias TuistCloudWeb.API.Authorization.AuthorizationPlug
  alias TuistCloud.Accounts
  alias TuistCloud.ProjectsFixtures
  alias TuistCloud.AccountsFixtures
  alias TuistCloudWeb.API.EnsureProjectPresencePlug
  use TuistCloudWeb.ConnCase

  test "returns a 403 and halts the connection if the authenticated subject is not authorized" do
    # Given
    project = ProjectsFixtures.project_fixture()

    user =
      AccountsFixtures.user_fixture()
      |> Repo.preload(:account)

    account = Accounts.get_account_by_id(project.account_id)
    opts = AuthorizationPlug.init(:cache)

    conn =
      build_conn(:get, ~p"/api/cache", project_id: account.name <> "/" <> project.name)
      |> EnsureProjectPresencePlug.put_project(project)
      |> TuistCloudWeb.Authentication.put_current_user(user)

    # When
    conn = conn |> AuthorizationPlug.call(opts)

    # Then
    assert conn.halted == true

    assert json_response(conn, :forbidden) == %{
             "message" => "#{user.account.name} is not authorized to read cache"
           }
  end

  test "returns the connection when the authenticated project is trying to access itself" do
    # Given
    project = ProjectsFixtures.project_fixture()
    account = Accounts.get_account_by_id(project.account_id)
    opts = AuthorizationPlug.init(:cache)

    conn =
      build_conn(:get, ~p"/api/cache", project_id: account.name <> "/" <> project.name)
      |> EnsureProjectPresencePlug.put_project(project)
      |> TuistCloudWeb.Authentication.put_current_project(project)

    # When
    got = conn |> AuthorizationPlug.call(opts)

    # Then
    assert conn == got
  end
end
