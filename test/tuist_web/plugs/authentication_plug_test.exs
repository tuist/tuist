defmodule TuistWeb.AuthenticationPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  import Plug.Test
  use Mimic
  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias TuistWeb.Headers
  alias Tuist.Projects
  alias TuistWeb.AuthenticationPlug
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  # This is needed in combination with "async: false" to ensure
  # that mocks are used within the cache process.
  setup :set_mimic_from_context

  setup do
    cache = UUIDv7.generate() |> String.to_atom()
    {:ok, _} = Cachex.start_link(name: cache)
    {:ok, cache: cache}
  end

  describe "load_authenticated_subject" do
    test "caches the loading of the authenticated subject", %{cache: cache} do
      # Given
      opts = AuthenticationPlug.init(:load_authenticated_subject)
      user = AccountsFixtures.user_fixture(preload: [:account])

      {account_token, account_token_value} =
        Accounts.create_account_token(
          %{
            account: user.account,
            scopes: [:account_registry_read]
          },
          preload: [:account]
        )

      authenticated_account = %AuthenticatedAccount{
        account: account_token.account,
        scopes: [:account_registry_read]
      }

      Tuist.Authentication
      # It's only invoked once
      |> expect(:authenticated_subject, 1, fn ^account_token_value ->
        authenticated_account
      end)

      conn =
        conn(:get, "/")
        |> assign(:caching, true)
        |> assign(:cache, cache)
        |> assign(:cache_ttl, :timer.minutes(1))
        |> put_req_header("authorization", "Bearer " <> account_token_value)

      # When/Then
      for _n <- 1..10 do
        got = conn |> AuthenticationPlug.call(opts)
        assert got.assigns[:current_subject] == authenticated_account
        assert(TuistWeb.Authentication.authenticated?(got) == true)
      end
    end

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
      assert got.assigns[:current_subject] == %AuthenticatedAccount{
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
  end

  describe "require_authentication" do
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
end
