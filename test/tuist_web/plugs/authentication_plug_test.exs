defmodule TuistWeb.AuthenticationPlugTest do
  use TuistWeb.ConnCase
  use Plug.Test
  use Mimic
  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias TuistWeb.Headers
  alias Tuist.Projects
  alias TuistWeb.AuthenticationPlug
  alias Tuist.AccountsFixtures
  alias Tuist.ProjectsFixtures

  test "loads the authenticated account" do
    # Given
    opts = AuthenticationPlug.init(:load_authenticated_subject)

    {account_token, account_token_value} =
      Accounts.create_account_token(
        %{
          account: AccountsFixtures.user_fixture(preload: [:account]).account,
          scopes: [:account_registry_read]
        },
        preload: [:account]
      )

    conn = conn(:get, "/") |> put_req_header("authorization", "Bearer " <> account_token_value)

    # When
    got = conn |> AuthenticationPlug.call(opts)

    # Then
    assert TuistWeb.Authentication.current_authenticated_account(got) == %AuthenticatedAccount{
             account: account_token.account,
             scopes: [:account_registry_read]
           }

    assert TuistWeb.Authentication.authenticated?(got) == true
  end

  test "loads the authenticated user" do
    # Given
    opts = AuthenticationPlug.init(:load_authenticated_subject)
    user = AccountsFixtures.user_fixture()
    conn = conn(:get, "/") |> put_req_header("authorization", "Bearer " <> user.token)

    # When
    got = conn |> AuthenticationPlug.call(opts)

    # Then
    assert TuistWeb.Authentication.current_user(got).id == user.id
    assert TuistWeb.Authentication.authenticated?(got) == true
  end

  test "loads the authenticated project with a legacy token" do
    # Given
    opts = AuthenticationPlug.init(:load_authenticated_subject)
    project = ProjectsFixtures.project_fixture(preload: [:account])
    conn = conn(:get, "/") |> put_req_header("authorization", "Bearer " <> project.token)

    # When
    got =
      conn
      |> Plug.Conn.put_req_header(Headers.cli_version_header(), "4.21.0")
      |> AuthenticationPlug.call(opts)

    # Then
    assert TuistWeb.Authentication.current_project(got).id == project.id
    assert TuistWeb.Authentication.authenticated?(got) == true

    assert TuistWeb.WarningsHeaderPlug.get_warnings(got) ==
             [
               "The project token you are using is deprecated. Please create a new token by running `tuist projects token create #{project.account.name}/#{project.name}."
             ]
  end

  test "loads the authenticated project with a legacy token without warnings if the version is lower than 4.21.0" do
    # Given
    opts = AuthenticationPlug.init(:load_authenticated_subject)
    project = ProjectsFixtures.project_fixture(preload: [:account])

    conn =
      conn(:get, "/")
      |> Plug.Conn.put_req_header(Headers.cli_version_header(), "4.20.0")
      |> put_req_header("authorization", "Bearer " <> project.token)

    # When
    got = conn |> AuthenticationPlug.call(opts)

    # Then
    assert TuistWeb.Authentication.current_project(got).id == project.id
    assert TuistWeb.Authentication.authenticated?(got) == true

    assert TuistWeb.WarningsHeaderPlug.get_warnings(got) == []
  end

  test "loads the authenticated project" do
    # Given
    opts = AuthenticationPlug.init(:load_authenticated_subject)
    project = ProjectsFixtures.project_fixture(preload: [:account])
    token = Projects.create_project_token(project)
    conn = conn(:get, "/") |> put_req_header("authorization", "Bearer " <> token)

    # When
    got = conn |> AuthenticationPlug.call(opts)

    # Then
    assert TuistWeb.Authentication.current_project(got).id == project.id
    assert TuistWeb.Authentication.authenticated?(got) == true
    assert TuistWeb.WarningsHeaderPlug.get_warnings(got) == []
  end

  test "doesn't load anything if the token is absent" do
    # Given
    opts = AuthenticationPlug.init(:load_authenticated_subject)
    conn = conn(:get, "/")

    # When
    got = conn |> AuthenticationPlug.call(opts)

    # Then
    assert TuistWeb.Authentication.current_project(got) == nil
    assert TuistWeb.Authentication.current_user(got) == nil
    assert TuistWeb.Authentication.authenticated?(got) == false
  end

  test "doesn't load anything if the the token is invalid" do
    # Given
    opts = AuthenticationPlug.init(:load_authenticated_subject)
    conn = conn(:get, "/") |> put_req_header("authorization", "Bearer " <> "invalid-token")

    # When
    got = conn |> AuthenticationPlug.call(opts)

    # Then
    assert TuistWeb.Authentication.current_project(got) == nil
    assert TuistWeb.Authentication.current_user(got) == nil
    assert TuistWeb.Authentication.authenticated?(got) == false
  end

  test "returns :unauthorized if the user is not authenticated" do
    # Given
    opts = AuthenticationPlug.init({:require_authentication, response_type: :open_api})
    conn = build_conn(:get, "/")

    # # When
    conn = conn |> AuthenticationPlug.call(opts)

    # # Then
    assert conn.halted == true

    assert json_response(conn, :unauthorized) == %{
             "message" => "You need to be authenticated to access this resource."
           }
  end
end
