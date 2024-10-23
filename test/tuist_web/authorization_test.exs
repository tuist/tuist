defmodule TuistWeb.AuthorizationTest do
  alias Tuist.PreviewsFixtures
  alias TuistWeb.Errors.NotFoundError
  alias Tuist.CommandEventsFixtures
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

  describe "authorization plug with options [:current_user, :read, :preview]" do
    test "raises an error when the user is not authenticated", %{conn: conn} do
      # Given
      preview = PreviewsFixtures.preview_fixture()
      conn = conn |> assign(:current_preview, preview)

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
      preview = PreviewsFixtures.preview_fixture()

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> assign(:current_preview, preview)

      Tuist.Authorization |> expect(:can, fn ^user, :read, ^preview -> true end)

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
      preview = PreviewsFixtures.preview_fixture()

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> assign(:current_preview, preview)

      Tuist.Authorization |> expect(:can, fn ^user, :read, ^preview -> false end)

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

  describe "on_mount with options [:current_user, :read, :command_event]" do
    test "raises an error if the socket doesn't have an authenticated user" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()
      socket = %Phoenix.LiveView.Socket{assigns: %{current_command_event: command_event}}

      # When/Then
      assert_raise UnauthorizedError,
                   gettext("You need to be authenticated to access this page."),
                   fn ->
                     Authorization.on_mount(
                       [:current_user, :read, :command_event],
                       %{},
                       %{},
                       socket
                     )
                   end
    end

    test "continues the socket connection if the user is authorized to read the current command_event",
         %{user: user} do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      socket = %Phoenix.LiveView.Socket{
        assigns: %{current_command_event: command_event} |> Authentication.put_current_user(user)
      }

      Tuist.Authorization |> expect(:can, fn ^user, :read, ^command_event -> true end)

      # When/Then
      assert Authorization.on_mount([:current_user, :read, :command_event], %{}, %{}, socket) ==
               {:cont, socket}
    end

    test "raises an error if the socket has an authenticated user and they are not authorized to read the current command event",
         %{user: user} do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      socket = %Phoenix.LiveView.Socket{
        assigns: %{current_command_event: command_event} |> Authentication.put_current_user(user)
      }

      Tuist.Authorization |> expect(:can, fn ^user, :read, ^command_event -> false end)

      # When/Then
      assert_raise NotFoundError,
                   gettext("The page you are looking for doesn't exist or has been moved."),
                   fn ->
                     Authorization.on_mount(
                       [:current_user, :read, :command_event],
                       %{},
                       %{},
                       socket
                     )
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
