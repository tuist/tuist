defmodule TuistWeb.AuthorizationTest do
  alias TuistWeb.Authorization
  alias Tuist.ProjectsFixtures
  alias Tuist.Accounts
  alias Tuist.AccountsFixtures
  use TuistWeb.ConnCase, async: true

  setup %{conn: conn} do
    %{user: AccountsFixtures.user_fixture(), conn: conn}
  end

  describe "require_user_can_read_project/2" do
    test "raises NotFoundError if a user can't read the given project using a conn", %{user: user} do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      conn =
        build_conn()
        |> get(~p"/#{account.name}/#{project.name}")
        |> assign(:current_user, user)

      # When / Then
      assert_raise TuistWeb.Errors.NotFoundError, fn ->
        Authorization.require_user_can_read_project(conn, [])
      end
    end

    test "returns conn if a user can read the given project using a conn", %{user: user} do
      # Given
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      conn =
        build_conn()
        |> get(~p"/#{account.name}/#{project.name}")
        |> assign(:current_user, user)

      # When
      got = Authorization.require_user_can_read_project(conn, [])

      # Then
      assert conn == got
    end

    test "raises NotFoundError if a user can't read the given project", %{user: user} do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When / Then
      assert_raise TuistWeb.Errors.NotFoundError, fn ->
        Authorization.require_user_can_read_project(%{
          user: user,
          account_handle: account.name,
          project_handle: project.name
        })
      end
    end

    test "returns conn if a user can read the given project", %{user: user} do
      # Given
      account = Accounts.get_account_from_user(user)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When / Then
      Authorization.require_user_can_read_project(%{
        user: user,
        account_handle: account.name,
        project_handle: project.name
      })
    end
  end
end
