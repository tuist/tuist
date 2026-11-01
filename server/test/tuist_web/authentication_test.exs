defmodule TuistWeb.AuthenticationTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Phoenix.LiveView
  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.UserToken
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.NotFoundError

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

  describe "attributed_user/1" do
    test "when the authenticated subject is a user", %{user: user, conn: conn} do
      # Given
      conn = assign(conn, :current_user, user)

      # Then
      assert Authentication.attributed_user(conn) == user
    end

    test "when the authenticated subject is an account token that carries its issuer", %{
      user: user,
      project: project,
      conn: conn
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{
          account: project.account,
          scopes: ["project:runs:write"],
          issued_by: user
        })

      # Then
      assert Authentication.attributed_user(conn) == user
    end

    test "when the authenticated subject is a long-lived token minted for CI", %{
      user: user,
      project: project,
      conn: conn
    } do
      # The account that created the token is recorded, but nobody authorized the
      # request it is now signing, so the run must not be attributed to them.
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{
          account: project.account,
          scopes: ["ci"],
          all_projects: true,
          token_id: Ecto.UUID.generate(),
          created_by_account_id: user.account.id
        })

      # Then
      assert Authentication.attributed_user(conn) == nil
    end

    test "when the authenticated subject is a CI token obtained through OIDC", %{
      project: project,
      conn: conn
    } do
      # Given
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{
          account: project.account,
          scopes: ["ci"],
          project_ids: [project.id]
        })

      # Then
      assert Authentication.attributed_user(conn) == nil
    end

    test "when the authenticated subject is a project", %{project: project, conn: conn} do
      # Given
      conn = assign(conn, :current_project, project)

      # Then
      assert Authentication.attributed_user(conn) == nil
    end

    test "when there is no authenticated subject", %{conn: conn} do
      assert Authentication.attributed_user(conn) == nil
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

    test "stores auth_method as :password by default", %{conn: conn, user: user} do
      conn = Authentication.log_in_user(conn, user)
      assert get_session(conn, :auth_method) == :password
    end

    test "stores auth_method when provided", %{conn: conn, user: user} do
      conn = Authentication.log_in_user(conn, user, %{auth_method: :google})
      assert get_session(conn, :auth_method) == :google
    end

    test "writes a cookie if remember_me is configured", %{conn: conn, user: user} do
      conn =
        conn |> fetch_cookies() |> Authentication.log_in_user(user, %{"remember_me" => "true"})

      assert get_session(conn, :user_token) == conn.cookies[@remember_me_cookie]

      assert %{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert signed_token != get_session(conn, :user_token)
      assert max_age == 28_800
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

  describe "require_authenticated_user_for_private_accounts/2" do
    test "does not redirect if a user is authenticated", %{conn: conn, user: user} do
      # Given
      %{account: account} = AccountsFixtures.organization_fixture(preload: [:account])
      conn = %{conn | path_params: %{"account_handle" => account.name}}

      # When
      conn =
        conn
        |> assign(:current_user, user)
        |> Authentication.require_authenticated_user_for_private_accounts([])

      # Then
      refute conn.halted
      refute conn.status
    end

    test "does not redirect if a user is anonymous and an account is public", %{conn: conn} do
      # Given
      %{account: account} = AccountsFixtures.organization_fixture(preload: [:account])
      {:ok, _account} = Accounts.update_account_visibility(account, :public)
      conn = %{conn | path_params: %{"account_handle" => account.name}}

      # When
      conn = Authentication.require_authenticated_user_for_private_accounts(conn, [])

      # Then
      refute conn.halted
      refute conn.status
    end

    test "redirects if a user is anonymous and an account is private", %{conn: conn} do
      # Given
      %{account: account} = AccountsFixtures.organization_fixture(preload: [:account])
      conn = %{conn | path_params: %{"account_handle" => account.name}}

      # When
      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> fetch_flash()
        |> Authentication.require_authenticated_user_for_private_accounts([])

      # Then
      assert conn.halted
      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "raises a 404 if the account doesn't exist, signed in or not", %{conn: conn} do
      # Given
      conn = %{conn | path_params: %{"account_handle" => "does-not-exist"}}

      # When/Then
      assert_raise NotFoundError, fn ->
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> fetch_flash()
        |> Authentication.require_authenticated_user_for_private_accounts([])
      end
    end

    test "raises a 404 if the account handle is a wildcard matching many accounts", %{conn: conn} do
      # Given
      AccountsFixtures.organization_fixture()
      AccountsFixtures.organization_fixture()
      conn = %{conn | path_params: %{"account_handle" => "%"}}

      # When/Then
      assert_raise NotFoundError, fn ->
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> fetch_flash()
        |> Authentication.require_authenticated_user_for_private_accounts([])
      end
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

    test "does not redirect if a user is anonymous, a project is private, and preview type is :ipa",
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
  end

  describe "require_sso_authentication/2" do
    test "does not redirect an anonymous visitor when the account is public and enforces SSO", %{conn: conn, user: user} do
      # Given
      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :google,
          sso_organization_id: "example.com",
          preload: [:account]
        )

      Accounts.update_organization(organization, %{sso_enforced: true})
      {:ok, _account} = Accounts.update_account_visibility(organization.account, :public)

      # When
      conn =
        Authentication.require_sso_authentication(
          %{
            conn
            | params: %{"account_handle" => organization.account.name},
              path_info: [organization.account.name, "runners"],
              query_string: ""
          },
          []
        )

      # Then
      refute conn.halted
      refute conn.status
    end

    test "still redirects a signed-in user when the account is public and enforces SSO", %{conn: conn, user: user} do
      # Given — signed-in users can see member-level data on a public account,
      # so the organization's enforcement still applies to them.
      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :google,
          sso_organization_id: "example.com",
          preload: [:account]
        )

      Accounts.update_organization(organization, %{sso_enforced: true})
      {:ok, _account} = Accounts.update_account_visibility(organization.account, :public)

      # When
      conn =
        %{
          conn
          | params: %{"account_handle" => organization.account.name},
            path_info: [organization.account.name, "runners"],
            query_string: ""
        }
        |> assign(:current_user, user)
        |> Authentication.require_sso_authentication([])

      # Then
      assert conn.halted
      assert redirected_to(conn) == "/users/auth/google"
    end

    test "redirects an anonymous visitor when the account is private and enforces SSO", %{conn: conn, user: user} do
      # Given
      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :google,
          sso_organization_id: "example.com",
          preload: [:account]
        )

      Accounts.update_organization(organization, %{sso_enforced: true})

      # When
      conn =
        Authentication.require_sso_authentication(
          %{
            conn
            | params: %{"account_handle" => organization.account.name},
              path_info: [organization.account.name, "runners"],
              query_string: ""
          },
          []
        )

      # Then
      assert conn.halted
      assert redirected_to(conn) == "/users/auth/google"
    end

    test "redirects to Google SSO when org has Google SSO enforced and session auth provider does not match",
         %{conn: conn, user: user} do
      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :google,
          sso_organization_id: "example.com",
          preload: [:account]
        )

      Accounts.update_organization(organization, %{sso_enforced: true})

      conn =
        %{
          conn
          | params: %{"account_handle" => organization.account.name},
            path_info: [organization.account.name, "settings"],
            query_string: ""
        }
        |> assign(:current_user, user)
        |> Authentication.require_sso_authentication([])

      assert conn.halted
      assert redirected_to(conn) == "/users/auth/google"
      assert get_session(conn, :oauth_return_to) == "/#{organization.account.name}/settings"
    end

    test "redirects to Okta SSO when org has Okta SSO enforced and session auth provider does not match",
         %{conn: conn, user: user} do
      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :okta,
          sso_organization_id: "company.okta.com",
          existing_sso_configuration: true,
          oauth2_client_id: "client_id",
          oauth2_client_secret: "client_secret",
          preload: [:account]
        )

      organization = organization |> Ecto.Changeset.change(sso_enforced: true) |> Repo.update!()

      conn =
        %{
          conn
          | params: %{"account_handle" => organization.account.name},
            path_info: [organization.account.name, "projects"],
            query_string: ""
        }
        |> assign(:current_user, user)
        |> Authentication.require_sso_authentication([])

      assert conn.halted
      assert redirected_to(conn) == "/users/auth/okta?organization_id=#{organization.id}"
    end

    test "does not redirect when the current session proves the configured Workspace",
         %{conn: conn, user: user} do
      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :google,
          sso_organization_id: "example.com",
          preload: [:account]
        )

      Accounts.update_organization(organization, %{sso_enforced: true})
      token = Accounts.generate_user_session_token(user, %{auth_method: :google, provider_organization_id: "example.com"})

      conn =
        conn
        |> assign(:current_user_session, Accounts.get_user_session(token))
        |> Map.put(:params, %{"account_handle" => organization.account.name})
        |> assign(:current_user, user)
        |> Authentication.require_sso_authentication([])

      refute conn.halted
    end

    test "does not redirect when org has SSO but enforcement is disabled",
         %{conn: conn, user: user} do
      organization =
        AccountsFixtures.organization_fixture(
          creator: user,
          sso_provider: :google,
          sso_organization_id: "example.com",
          preload: [:account]
        )

      conn =
        %{conn | params: %{"account_handle" => organization.account.name}}
        |> assign(:current_user, user)
        |> Authentication.require_sso_authentication([])

      refute conn.halted
    end

    test "does not redirect when no account_handle param is present",
         %{conn: conn} do
      conn = Authentication.require_sso_authentication(conn, [])
      refute conn.halted
    end
  end

  describe "organization SSO on connected navigation" do
    test "the correct Workspace proof does not grant membership to a nonmember", %{conn: conn} do
      organization = organization_fixture(sso_provider: :google, sso_organization_id: "customer.example")
      {:ok, _} = Accounts.update_organization(organization, %{sso_enforced: true})
      outsider = user_fixture()
      refute Accounts.belongs_to_organization?(outsider, organization)

      token =
        Accounts.generate_user_session_token(outsider, %{
          auth_method: :google,
          provider_organization_id: "customer.example"
        })

      conn = put_session(conn, :user_token, token)
      assert_error_sent 404, fn -> get(conn, ~p"/#{organization.account.name}/projects") end
    end

    test "an authorized account-bound support grant retains its HTTP and connected exception", %{conn: conn} do
      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      organization = organization_fixture(sso_provider: :google, sso_organization_id: "customer.example")
      {:ok, _} = Accounts.update_organization(organization, %{sso_enforced: true})
      operator = user_fixture(email: "operator-proof@tuist.dev")
      oauth2_identity_fixture(user: operator, provider: :google, provider_organization_id: "tuist.dev")
      refute Accounts.belongs_to_organization?(operator, organization)

      grant = %{
        tier: :read,
        account_id: organization.account.id,
        account_handle: organization.account.name,
        sub: operator.email,
        jti: "local-support-proof",
        exp: System.system_time(:second) + 600
      }

      conn = conn |> log_in_user(operator) |> put_session(:operator_grants, %{organization.account.name => grant})
      protected_path = ~p"/#{organization.account.name}/projects"
      assert conn |> get(protected_path) |> html_response(200)
      assert {:ok, _, _} = live(conn, protected_path)
    end

    for scope <- [:public_account, :account, :project] do
      @tag :sso_boundary
      test "enforces the HTTP SSO requirement in the #{scope} live session", %{conn: conn, user: user} do
        organization =
          organization_fixture(creator: user, sso_provider: :google, sso_organization_id: "example.com")

        {:ok, _} = Accounts.update_organization(organization, %{sso_enforced: true})
        personal_project = ProjectsFixtures.project_fixture(account: user.account)
        organization_project = ProjectsFixtures.project_fixture(account: organization.account)

        {allowed_path, protected_path} =
          case unquote(scope) do
            :public_account ->
              {~p"/#{user.account.name}/projects", ~p"/#{organization.account.name}/projects"}

            :account ->
              {~p"/#{user.account.name}/settings", ~p"/#{organization.account.name}/settings"}

            :project ->
              {~p"/#{user.account.name}/#{personal_project.name}/settings",
               ~p"/#{organization.account.name}/#{organization_project.name}/settings"}
          end

        conn = log_in_user(conn, user)
        assert conn |> get(protected_path) |> redirected_to() == ~p"/users/auth/google"

        {:ok, view, _} = live(conn, allowed_path)

        assert {:error, {:redirect, %{to: "/users/auth/google"}}} = live_redirect(view, to: protected_path)

        sso_conn =
          put_session(
            conn,
            :user_token,
            Accounts.generate_user_session_token(user, %{auth_method: :google, provider_organization_id: "example.com"})
          )

        assert {:ok, _, _} = live(sso_conn, protected_path)
      end
    end

    @tag :sso_boundary
    test "a connected join rechecks proof after its initial HTTP render", %{conn: conn, user: user} do
      organization = organization_fixture(creator: user, sso_provider: :google, sso_organization_id: "example.com")
      {:ok, _} = Accounts.update_organization(organization, %{sso_enforced: true})
      token = Accounts.generate_user_session_token(user, %{auth_method: :google, provider_organization_id: "example.com"})
      protected_path = ~p"/#{organization.account.name}/projects"
      rendered = conn |> put_session(:user_token, token) |> get(protected_path)
      assert html_response(rendered, 200)
      Repo.update_all(UserToken, set: [auth_provider: nil, auth_provider_organization_id: nil])
      assert {:error, {:redirect, %{to: "/users/auth/google"}}} = live(rendered)
    end

    @tag :sso_boundary
    test "a provider cookie and historical identity do not upgrade a legacy session", %{conn: conn, user: user} do
      organization = organization_fixture(creator: user, sso_provider: :google, sso_organization_id: "example.com")
      {:ok, _} = Accounts.update_organization(organization, %{sso_enforced: true})
      oauth2_identity_fixture(user: user, provider_organization_id: "example.com")

      conn = conn |> log_in_user(user) |> put_session(:auth_method, :google)
      Repo.update_all(UserToken, set: [auth_provider: nil, auth_provider_organization_id: nil, last_active_at: nil])
      protected_path = ~p"/#{organization.account.name}/projects"
      assert conn |> get(protected_path) |> redirected_to() == ~p"/users/auth/google"

      {:ok, view, _} = live(conn, ~p"/#{user.account.name}/projects")
      assert {:error, {:redirect, %{to: "/users/auth/google"}}} = live_redirect(view, to: protected_path)
    end

    @tag :sso_boundary
    test "checks changed SSO configuration before an already-open socket mutates a project", %{conn: conn, user: user} do
      organization = organization_fixture(creator: user, sso_provider: :google, sso_organization_id: "example.com")
      {:ok, _} = Accounts.update_organization(organization, %{sso_enforced: true})
      project = ProjectsFixtures.project_fixture(account: organization.account)

      conn =
        put_session(
          conn,
          :user_token,
          Accounts.generate_user_session_token(user, %{auth_method: :google, provider_organization_id: "example.com"})
        )

      {:ok, view, _} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")
      {:ok, _} = Accounts.update_organization(organization, %{sso_organization_id: "new.example.com"})

      render_hook(view, "rename_project", %{"project" => %{"name" => "must-not-change"}})
      assert_redirect(view, ~p"/users/auth/google")
      assert Tuist.Projects.get_project_by_id(project.id).name == project.name
    end
  end

  describe "browser session expiry" do
    @tag :browser_session
    test "a remember-me cookie retains proof but cannot revive an idle or absolutely expired session", %{
      conn: conn,
      user: user
    } do
      organization = organization_fixture(creator: user, sso_provider: :google, sso_organization_id: "example.com")
      {:ok, _} = Accounts.update_organization(organization, %{sso_enforced: true})

      logged_in =
        conn
        |> fetch_cookies()
        |> Authentication.log_in_user(user, %{
          "remember_me" => "true",
          :auth_method => :google,
          :provider_organization_id => "example.com"
        })

      %{value: cookie} = logged_in.resp_cookies[@remember_me_cookie]
      remembered = put_req_cookie(conn, @remember_me_cookie, cookie)
      assert remembered |> get(~p"/#{organization.account.name}/projects") |> html_response(200)

      now = DateTime.truncate(Tuist.Time.utc_now(), :second)
      Repo.update_all(UserToken, set: [last_active_at: DateTime.add(now, -900)])
      expired = Authentication.fetch_current_user(remembered, [])
      refute expired.assigns.current_user
      refute get_session(expired, :user_token)
      assert %{max_age: 0} = expired.resp_cookies[@remember_me_cookie]

      Repo.update_all(UserToken,
        set: [inserted_at: now |> DateTime.add(-28_800) |> DateTime.to_naive(), last_active_at: now]
      )

      refute Authentication.fetch_current_user(remembered, []).assigns.current_user
    end

    @tag :browser_session
    test "an expired connected session cannot submit a project mutation", %{conn: conn, user: user} do
      project = ProjectsFixtures.project_fixture(account: user.account)
      conn = log_in_user(conn, user)
      {:ok, view, _} = live(conn, ~p"/#{user.account.name}/#{project.name}/settings")
      now = DateTime.truncate(Tuist.Time.utc_now(), :second)
      Repo.update_all(UserToken, set: [last_active_at: DateTime.add(now, -900)])

      render_hook(view, "rename_project", %{"project" => %{"name" => "must-not-change"}})
      assert_redirect(view, ~p"/users/log_in")
      assert Tuist.Projects.get_project_by_id(project.id).name == project.name
    end
  end

  describe "get_authorization_token_from_conn/1" do
    test "extracts token from Bearer authorization header", %{conn: conn} do
      token = "my_bearer_token_123"

      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      assert Authentication.get_authorization_token_from_conn(conn) == token
    end

    test "returns nil when no authorization header is present", %{conn: conn} do
      assert Authentication.get_authorization_token_from_conn(conn) == nil
    end

    test "returns nil for invalid authorization header format", %{conn: conn} do
      conn = put_req_header(conn, "authorization", "InvalidFormat token123")

      assert Authentication.get_authorization_token_from_conn(conn) == nil
    end
  end
end
