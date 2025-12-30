defmodule TuistWeb.AuthenticationTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Phoenix.LiveView
  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  @remember_me_cookie "_tuist_web_user_remember_me"

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, TuistWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{
      user: user_fixture(preload: [:account]),
      project: ProjectsFixtures.project_fixture(),
      conn: conn
    }
  end

  describe "authenticated_subject_account/1" do
    test "when the authenticated subject is a user", %{user: user, conn: conn} do
      # Given
      conn = assign(conn, :current_user, user)

      # Then
      assert Authentication.authenticated_subject_account(conn) == user.account
    end

    test "when the authenticated subject is a project", %{project: project, conn: conn} do
      # Given
      conn = assign(conn, :current_project, project)

      # Then
      assert Authentication.authenticated_subject_account(conn) == project.account
    end

    test "when the authenticated subject is an authenticated account", %{
      project: project,
      conn: conn
    } do
      # Given
      current_subject = %AuthenticatedAccount{
        account: project.account,
        scopes: ["scope-1", "scope-2"]
      }

      conn = assign(conn, :current_subject, current_subject)

      # Then
      assert Authentication.authenticated_subject_account(conn) == current_subject.account
    end
  end

  describe "log_in_user/3" do
    test "stores the user token in the session", %{conn: conn, user: user} do
      conn = Authentication.log_in_user(conn, user)
      assert token = get_session(conn, :user_token)
      assert get_session(conn, :live_socket_id) == "users_sessions:#{Base.url_encode64(token)}"
      assert redirected_to(conn) == ~p"/#{user.account.name}/projects"
      assert Accounts.get_user_by_session_token(token)
    end

    test "clears everything previously stored in the session", %{conn: conn, user: user} do
      conn = conn |> put_session(:to_be_removed, "value") |> Authentication.log_in_user(user)
      refute get_session(conn, :to_be_removed)
    end

    test "redirects to the configured path", %{conn: conn, user: user} do
      conn = conn |> put_session(:user_return_to, "/hello") |> Authentication.log_in_user(user)
      assert redirected_to(conn) == "/hello"
    end

    test "writes a cookie if remember_me is configured", %{conn: conn, user: user} do
      conn =
        conn |> fetch_cookies() |> Authentication.log_in_user(user, %{"remember_me" => "true"})

      assert get_session(conn, :user_token) == conn.cookies[@remember_me_cookie]

      assert %{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert signed_token != get_session(conn, :user_token)
      assert max_age == 5_184_000
    end
  end

  describe "logout_user/1" do
    test "erases session and cookies", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_session(:user_token, user_token)
        |> put_req_cookie(@remember_me_cookie, user_token)
        |> fetch_cookies()
        |> Authentication.log_out_user()

      refute get_session(conn, :user_token)
      refute conn.cookies[@remember_me_cookie]
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
      refute Accounts.get_user_by_session_token(user_token)
    end

    test "broadcasts to the given live_socket_id", %{conn: conn} do
      live_socket_id = "users_sessions:abcdef-token"
      TuistWeb.Endpoint.subscribe(live_socket_id)

      conn
      |> put_session(:live_socket_id, live_socket_id)
      |> Authentication.log_out_user()

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^live_socket_id}
    end

    test "works even if user is already logged out", %{conn: conn} do
      conn = conn |> fetch_cookies() |> Authentication.log_out_user()
      refute get_session(conn, :user_token)
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "fetch_current_user/2" do
    test "authenticates user from session", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)
      conn = conn |> put_session(:user_token, user_token) |> Authentication.fetch_current_user([])
      assert conn.assigns.current_user.id == user.id
    end

    test "authenticates user from cookies", %{conn: conn, user: user} do
      logged_in_conn =
        conn |> fetch_cookies() |> Authentication.log_in_user(user, %{"remember_me" => "true"})

      user_token = logged_in_conn.cookies[@remember_me_cookie]
      %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

      conn =
        conn
        |> put_req_cookie(@remember_me_cookie, signed_token)
        |> Authentication.fetch_current_user([])

      assert conn.assigns.current_user.id == user.id
      assert get_session(conn, :user_token) == user_token

      assert get_session(conn, :live_socket_id) ==
               "users_sessions:#{Base.url_encode64(user_token)}"
    end

    test "does not authenticate if data is missing", %{conn: conn, user: user} do
      _ = Accounts.generate_user_session_token(user)
      conn = Authentication.fetch_current_user(conn, [])
      refute get_session(conn, :user_token)
      refute conn.assigns.current_user
    end
  end

  describe "on_mount :mount_current_user" do
    test "assigns current_user based on a valid user_token", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        Authentication.on_mount(:mount_current_user, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user.id == user.id
    end

    test "assigns nil to current_user assign if there isn't a valid user_token", %{conn: conn} do
      user_token = "invalid_token"
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        Authentication.on_mount(:mount_current_user, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user == nil
    end

    test "assigns nil to current_user assign if there isn't a user_token", %{conn: conn} do
      session = get_session(conn)

      {:cont, updated_socket} =
        Authentication.on_mount(:mount_current_user, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user == nil
    end
  end

  describe "on_mount :ensure_authenticated" do
    test "authenticates current_user based on a valid user_token", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        Authentication.on_mount(:ensure_authenticated, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_user.id == user.id
    end

    test "redirects to login page if there isn't a valid user_token", %{conn: conn} do
      user_token = "invalid_token"
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: TuistWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} =
        Authentication.on_mount(:ensure_authenticated, %{}, session, socket)

      assert updated_socket.assigns.current_user == nil
    end

    test "redirects to login page if there isn't a user_token", %{conn: conn} do
      session = get_session(conn)

      socket = %LiveView.Socket{
        endpoint: TuistWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} =
        Authentication.on_mount(:ensure_authenticated, %{}, session, socket)

      assert updated_socket.assigns.current_user == nil
    end
  end

  describe "on_mount :redirect_if_user_is_authenticated" do
    test "redirects if there is an authenticated  user ", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      assert {:halt, _updated_socket} =
               Authentication.on_mount(
                 :redirect_if_user_is_authenticated,
                 %{},
                 session,
                 %LiveView.Socket{}
               )
    end

    test "doesn't redirect if there is no authenticated user", %{conn: conn} do
      session = get_session(conn)

      assert {:cont, _updated_socket} =
               Authentication.on_mount(
                 :redirect_if_user_is_authenticated,
                 %{},
                 session,
                 %LiveView.Socket{}
               )
    end
  end

  describe "redirect_if_user_is_authenticated/2" do
    test "redirects if user is authenticated", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_user, user)
        |> Authentication.redirect_if_user_is_authenticated([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/#{user.account.name}/projects"
    end

    test "does not redirect if user is not authenticated", %{conn: conn} do
      conn = Authentication.redirect_if_user_is_authenticated(conn, [])
      refute conn.halted
      refute conn.status
    end
  end

  describe "require_authenticated_user/2" do
    test "redirects if user is not authenticated", %{conn: conn} do
      conn = conn |> fetch_flash() |> Authentication.require_authenticated_user([])
      assert conn.halted

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "stores the path to redirect to on GET", %{conn: conn} do
      halted_conn =
        %{conn | path_info: ["foo"], query_string: ""}
        |> fetch_flash()
        |> Authentication.require_authenticated_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/foo"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar=baz"}
        |> fetch_flash()
        |> Authentication.require_authenticated_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/foo?bar=baz"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar", method: "POST"}
        |> fetch_flash()
        |> Authentication.require_authenticated_user([])

      assert halted_conn.halted
      refute get_session(halted_conn, :user_return_to)
    end

    test "does not redirect if user is authenticated", %{conn: conn, user: user} do
      conn = conn |> assign(:current_user, user) |> Authentication.require_authenticated_user([])
      refute conn.halted
      refute conn.status
    end
  end

  describe "require_authenticated_user_for_private_projects/2" do
    test "does not redirect if a user is authenticated", %{conn: conn, user: user} do
      # Given
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)

      conn = %{
        conn
        | path_params: %{
            "account_handle" => project.account.name,
            "project_handle" => project.name
          }
      }

      # When
      conn =
        conn
        |> assign(:current_user, user)
        |> Authentication.require_authenticated_user_for_private_projects([])

      # Then
      refute conn.halted
      refute conn.status
    end

    test "does not redirect if a user is anonymous and a project is public", %{conn: conn} do
      # Given
      project =
        [visibility: :public]
        |> ProjectsFixtures.project_fixture()
        |> Repo.preload(:account)

      conn = %{
        conn
        | path_params: %{
            "account_handle" => project.account.name,
            "project_handle" => project.name
          }
      }

      # When
      conn = Authentication.require_authenticated_user_for_private_projects(conn, [])

      # Then
      refute conn.halted
      refute conn.status
    end

    test "redirects if a user is anonymous and a project is private", %{conn: conn} do
      # Given
      project =
        [visibility: :private]
        |> ProjectsFixtures.project_fixture()
        |> Repo.preload(:account)

      conn = %{
        conn
        | path_params: %{
            "account_handle" => project.account.name,
            "project_handle" => project.name
          }
      }

      # When
      conn = Authentication.require_authenticated_user_for_private_projects(conn, [])

      # Then
      assert conn.halted
      assert conn.status
    end
  end

  describe "require_authenticated_user_for_previews/2" do
    test "does not redirect if a user is authenticated", %{conn: conn, user: user} do
      # Given
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)

      preview = AppBuildsFixtures.app_build_fixture(project: project)

      conn = %{
        conn
        | path_params: %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "id" => preview.id
          }
      }

      # When
      conn =
        conn
        |> assign(:current_user, user)
        |> Authentication.require_authenticated_user_for_previews([])

      # Then
      refute conn.halted
      refute conn.status
    end

    test "does not redirect if a user is anonymous and a project is public", %{conn: conn} do
      # Given
      project =
        [visibility: :public]
        |> ProjectsFixtures.project_fixture()
        |> Repo.preload(:account)

      preview = AppBuildsFixtures.preview_fixture(project: project)

      conn = %{
        conn
        | path_params: %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "id" => preview.id
          }
      }

      # When
      conn = Authentication.require_authenticated_user_for_previews(conn, [])

      # Then
      refute conn.halted
      refute conn.status
    end

    test "redirects if a user is anonymous, a project is private, and preview type is :app_bundle",
         %{conn: conn} do
      # Given
      project =
        [visibility: :private]
        |> ProjectsFixtures.project_fixture()
        |> Repo.preload(:account)

      preview =
        AppBuildsFixtures.app_build_fixture(
          project: project,
          type: :app_bundle
        )

      conn = %{
        conn
        | path_params: %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "id" => preview.id
          }
      }

      # When
      conn = Authentication.require_authenticated_user_for_previews(conn, [])

      # Then
      assert conn.halted
      assert conn.status
    end

    test "does not redirect if a user is anonymous, a project is private, and preview is public",
         %{conn: conn} do
      # Given
      project =
        [visibility: :private]
        |> ProjectsFixtures.project_fixture()
        |> Repo.preload(:account)

      preview = AppBuildsFixtures.preview_fixture(project: project, visibility: :public)

      conn = %{
        conn
        | path_params: %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "id" => preview.id
          }
      }

      # When
      conn = Authentication.require_authenticated_user_for_previews(conn, [])

      # Then
      refute conn.halted
      refute conn.status
    end

    test "does not redirect when preview.visibility is nil and project.default_previews_visibility is :public",
         %{conn: conn} do
      # Given
      project =
        [visibility: :private, default_previews_visibility: :public]
        |> ProjectsFixtures.project_fixture()
        |> Repo.preload(:account)

      preview = AppBuildsFixtures.preview_fixture(project: project, visibility: nil)

      conn = %{
        conn
        | path_params: %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "id" => preview.id
          }
      }

      # When
      conn = Authentication.require_authenticated_user_for_previews(conn, [])

      # Then
      refute conn.halted
      refute conn.status
    end

    test "redirects when preview.visibility is nil and project.default_previews_visibility is :private",
         %{conn: conn} do
      # Given
      project =
        [visibility: :private, default_previews_visibility: :private]
        |> ProjectsFixtures.project_fixture()
        |> Repo.preload(:account)

      preview = AppBuildsFixtures.preview_fixture(project: project, visibility: nil)

      conn = %{
        conn
        | path_params: %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "id" => preview.id
          }
      }

      # When
      conn = Authentication.require_authenticated_user_for_previews(conn, [])

      # Then
      assert conn.halted
      assert conn.status
    end
  end
end
