defmodule TuistWeb.AuthorizationTest do
  use Gettext, backend: TuistWeb.Gettext
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Phoenix.LiveView.Socket
  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication
  alias TuistWeb.Authorization
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Errors.UnauthorizedError

  setup %{conn: conn} do
    %{user: AccountsFixtures.user_fixture(preload: [:account]), conn: conn}
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
      conn = Authentication.put_current_user(conn, user)
      expect(Tuist.Authorization, :authorize, fn :ops_read, ^user, :ops -> :ok end)

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
      conn = Authentication.put_current_user(conn, user)

      expect(Tuist.Authorization, :authorize, fn :ops_read, ^user, :ops ->
        {:error, :forbidden}
      end)

      # When/Then
      assert_raise UnauthorizedError,
                   gettext("Only operations roles can access this page."),
                   fn ->
                     Authorization.call(conn, Authorization.init([:current_user, :read, :ops]))
                   end
    end
  end

  describe "authorization plug with options [:current_user, :read, :preview]" do
    test "raises an error when the user is not authenticated", %{conn: conn} do
      # Given
      preview = AppBuildsFixtures.preview_fixture()
      conn = assign(conn, :current_preview, preview)

      # When/Then
      assert_raise UnauthorizedError,
                   gettext("You need to be authenticated to access this page."),
                   fn ->
                     Authorization.call(
                       conn,
                       Authorization.init([:current_user, :read, :preview])
                     )
                   end
    end

    test "returns the same connection when the authenticated user is authorized", %{
      conn: conn,
      user: user
    } do
      # Given
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      preview = AppBuildsFixtures.preview_fixture(project: project)

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> assign(:current_preview, preview)

      # When
      got = Authorization.call(conn, Authorization.init([:current_user, :read, :preview]))

      # Then
      assert got == conn
    end

    test "raises an unauthorized error when the user is not authorized", %{
      conn: conn,
      user: user
    } do
      # Given
      preview = AppBuildsFixtures.preview_fixture()

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> assign(:current_preview, preview)

      # When/Then
      assert_raise NotFoundError,
                   gettext("The page you are looking for doesn't exist or has been moved."),
                   fn ->
                     Authorization.call(
                       conn,
                       Authorization.init([:current_user, :read, :preview])
                     )
                   end
    end
  end

  describe "on_mount with options [:current_user, :read, :ops]" do
    test "raises an error if the socket doesn't have an authenticated user" do
      # Given
      socket = %Socket{assigns: %{}}

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
      socket = %Socket{assigns: Authentication.put_current_user(%{}, user)}
      expect(Tuist.Authorization, :authorize, fn :ops_read, ^user, :ops -> :ok end)

      # When/Then
      assert Authorization.on_mount([:current_user, :read, :ops], %{}, %{}, socket) ==
               {:cont, socket}
    end

    test "raises an error if the socket has an authenticated user and they don't have access to ops",
         %{user: user} do
      # Given
      socket = %Socket{assigns: Authentication.put_current_user(%{}, user)}

      expect(Tuist.Authorization, :authorize, fn :ops_read, ^user, :ops ->
        {:error, :forbidden}
      end)

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
      assert_raise NotFoundError, fn ->
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
      assert_raise NotFoundError, fn ->
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
