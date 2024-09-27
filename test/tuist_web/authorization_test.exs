defmodule TuistWeb.AuthorizationTest do
  alias TuistWeb.Authorization
  alias Tuist.ProjectsFixtures
  alias Tuist.Accounts
  alias Tuist.AccountsFixtures
  alias TuistWeb.Authentication
  import TuistWeb.Gettext
  alias TuistWeb.Errors.UnauthorizedError
  use TuistWeb.ConnCase, async: true

  use Mimic

  setup %{conn: conn} do
    %{user: AccountsFixtures.user_fixture(preloads: [:account]), conn: conn}
  end

  describe "authorization plug with options [:current_user, :read, :ops]" do
    test "raises an error when the user is not authenticated", %{conn: conn} do
      # Given/When/Then
      assert_raise UnauthorizedError,
                   gettext("You need to be authenticated to access this page."),
                   fn ->
                     Authorization.call(conn, Authorization.init([:current_user, :read, :ops]))
                   end
    end

    test "returns the same connection when the authenticated user is authorized", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = conn |> Authentication.put_current_user(user)
      Tuist.Authorization |> expect(:can, fn ^user, :read, :ops -> true end)

      # When
      got = Authorization.call(conn, Authorization.init([:current_user, :read, :ops]))

      # Then
      assert got == conn
    end

    test "raises an unauthorized error when the user is not authorized", %{
      conn: conn,
      user: user
    } do
      # Given
      conn = conn |> Authentication.put_current_user(user)
      Tuist.Authorization |> expect(:can, fn ^user, :read, :ops -> false end)

      # When/Then
      assert_raise UnauthorizedError,
                   gettext("Only operations roles can access this page."),
                   fn ->
                     Authorization.call(conn, Authorization.init([:current_user, :read, :ops]))
                   end
    end
  end

  describe "on_mount with options [:current_user, :read, :ops]" do
    test "raises an error if the socket doesn't have an authenticated user" do
      # Given
      socket = %Phoenix.LiveView.Socket{assigns: %{}}

      # When/Then
      assert_raise UnauthorizedError,
                   gettext("You need to be authenticated to access this page."),
                   fn ->
                     Authorization.on_mount([:current_user, :read, :ops], %{}, %{}, socket)
                   end
    end

    test "continues the socket connection if the user is authorized to read the ops page",
         %{user: user} do
      # Given
      socket = %Phoenix.LiveView.Socket{assigns: %{} |> Authentication.put_current_user(user)}
      Tuist.Authorization |> expect(:can, fn ^user, :read, :ops -> true end)

      # When/Then
      assert Authorization.on_mount([:current_user, :read, :ops], %{}, %{}, socket) ==
               {:cont, socket}
    end

    test "raises an error if the socket has an authenticated user and they don't have access to ops",
         %{user: user} do
      # Given
      socket = %Phoenix.LiveView.Socket{assigns: %{} |> Authentication.put_current_user(user)}
      Tuist.Authorization |> expect(:can, fn ^user, :read, :ops -> false end)

      # When/Then
      assert_raise UnauthorizedError,
                   gettext("Only operations roles can access this page."),
                   fn ->
                     Authorization.on_mount([:current_user, :read, :ops], %{}, %{}, socket)
                   end
    end
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
