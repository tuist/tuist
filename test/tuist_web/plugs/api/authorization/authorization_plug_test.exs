defmodule TuistWeb.API.Authorization.AuthorizationPlugTest do
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Repo
  alias TuistWeb.API.Authorization.AuthorizationPlug
  alias Tuist.Accounts
  alias Tuist.Authorization
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.API.EnsureProjectPresencePlug
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  setup :set_mimic_global

  setup do
    cache = UUIDv7.generate() |> String.to_atom()
    {:ok, _} = Cachex.start_link(name: cache)
    %{cache: cache}
  end

  test "returns the connection when the authenticated account can read its registry" do
    # Given
    account = AccountsFixtures.user_fixture(preload: [:account]).account

    opts = AuthorizationPlug.init(:registry)

    conn =
      build_conn(:get, ~p"/api/accounts/#{account.name}/registry/swift/availability")
      |> assign(:url_account, account)
      |> assign(:current_subject, %AuthenticatedAccount{
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

  describe "caching" do
    test "caches authorization responses", %{cache: cache} do
      # Given
      project =
        %{account: %{name: account_handle}} =
        ProjectsFixtures.project_fixture() |> Repo.preload(:account)

      opts = AuthorizationPlug.init(category: :cache, caching: true, cache_ttl: :timer.minutes(5))

      # We check that the authorization API, which hits the DB, is onnly invoked once.
      Authorization |> expect(:can?, 1, fn :project_cache_read, _, _ -> false end)

      conn =
        build_conn()
        |> assign(:cache, cache)
        |> EnsureProjectPresencePlug.put_project(project)
        |> TuistWeb.Authentication.put_current_project(project)

      # When/Then
      for _ <- 1..10 do
        assert json_response(conn |> AuthorizationPlug.call(opts), :forbidden) == %{
                 "message" => "#{account_handle} is not authorized to read cache"
               }
      end
    end
  end
end
