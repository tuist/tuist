defmodule TuistWeb.API.Authorization.AuthorizationPlugTest do
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Repo
  alias TuistWeb.API.Authorization.AuthorizationPlug
  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.API.EnsureProjectPresencePlug
  use TuistTestSupport.Cases.ConnCase

  test "returns the connection when the authenticated account can read its registry" do
    # Given
    account = AccountsFixtures.user_fixture(preload: [:account]).account

    opts = AuthorizationPlug.init(:registry)

    conn =
      build_conn(:get, ~p"/api/accounts/#{account.name}/registry/swift/availability")
      |> assign(:url_account, account)
      |> TuistWeb.Authentication.put_current_authenticated_account(%AuthenticatedAccount{
        account: account,
        scopes: [:account_registry_read]
      })

    # When
    got = conn |> AuthorizationPlug.call(opts)

    # Then
    assert conn == got
  end

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
      |> TuistWeb.Authentication.put_current_user(user)

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
      |> TuistWeb.Authentication.put_current_project(project)

    # When
    got = conn |> AuthorizationPlug.call(opts)

    # Then
    assert conn == got
  end
end
