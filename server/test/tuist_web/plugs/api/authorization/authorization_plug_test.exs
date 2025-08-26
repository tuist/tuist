defmodule TuistWeb.API.Authorization.AuthorizationPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Authorization
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.API.Authorization.AuthorizationPlug

  setup :set_mimic_global

  setup do
    cache = String.to_atom(UUIDv7.generate())
    {:ok, _} = Cachex.start_link(name: cache)
    %{cache: cache}
  end

  test "returns the connection when the authenticated account can read its registry" do
    # Given
    account = AccountsFixtures.user_fixture(preload: [:account]).account

    opts = AuthorizationPlug.init(:registry)

    conn =
      :get
      |> build_conn(~p"/api/accounts/#{account.name}/registry/swift/availability")
      |> assign(:selected_account, account)
      |> assign(:current_subject, %AuthenticatedAccount{
        account: account,
        scopes: [:registry_read]
      })

    # When
    got = AuthorizationPlug.call(conn, opts)

    # Then
    assert conn == got
  end

  test "returns a 403 and halts the connection if the authenticated subject is not authorized" do
    # Given
    project = ProjectsFixtures.project_fixture()

    user = Repo.preload(AccountsFixtures.user_fixture(), :account)

    account = Accounts.get_account_by_id(project.account_id)
    opts = AuthorizationPlug.init(:cache)

    conn =
      :get
      |> build_conn(~p"/api/cache", project_id: account.name <> "/" <> project.name)
      |> assign(:selected_project, project)
      |> TuistWeb.Authentication.put_current_user(user)

    # When
    conn = AuthorizationPlug.call(conn, opts)

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
      :get
      |> build_conn(~p"/api/cache", project_id: account.name <> "/" <> project.name)
      |> assign(:selected_project, project)
      |> TuistWeb.Authentication.put_current_project(project)

    # When
    got = AuthorizationPlug.call(conn, opts)

    # Then
    assert conn == got
  end

  describe "caching" do
    test "caches authorization responses", %{cache: cache} do
      # Given
      project =
        %{account: %{name: account_handle}} =
        Repo.preload(ProjectsFixtures.project_fixture(), :account)

      opts =
        AuthorizationPlug.init(category: :cache, caching: true, cache_ttl: to_timeout(minute: 5))

      # We check that the authorization API, which hits the DB, is onnly invoked once.
      expect(Authorization, :authorize, 1, fn :cache_read, _, _ ->
        {:error, :forbidden}
      end)

      conn =
        build_conn()
        |> assign(:cache, cache)
        |> assign(:selected_project, project)
        |> TuistWeb.Authentication.put_current_project(project)

      # When/Then
      for _ <- 1..10 do
        assert conn |> AuthorizationPlug.call(opts) |> json_response(:forbidden) == %{
                 "message" => "#{account_handle} is not authorized to read cache"
               }
      end
    end
  end
end
