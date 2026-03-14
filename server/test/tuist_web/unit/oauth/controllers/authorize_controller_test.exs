defmodule TuistWeb.Controllers.Oauth.AuthorizeControllerTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  import ExUnit.CaptureLog
  import Phoenix.ConnTest
  import Plug.Conn

  alias Boruta.Oauth.Error
  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Errors.BadRequestError
  alias TuistWeb.Oauth.AuthorizeController

  setup do
    conn = Plug.Test.init_test_session(build_conn(), %{})
    stub(Environment, :oauth_client_id, fn -> "00000000-0000-0000-0000-000000000001" end)

    {:ok, conn: conn}
  end

  describe "authorize/2 with logged in user" do
    test "raises BadRequestError when state parameter exceeds 10000 characters", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      long_state = String.duplicate("a", 10_001)

      params = %{
        "client_id" => Environment.oauth_client_id(),
        "redirect_uri" => "tuist://oauth-callback",
        "response_type" => "code",
        "scope" => "",
        "state" => long_state,
        "code_challenge" => "test_challenge",
        "code_challenge_method" => "S256"
      }

      conn =
        conn
        |> Map.put(:query_params, params)
        |> Map.put(:params, params)
        |> assign(:current_user, user)

      assert_raise BadRequestError, ~r/state/, fn ->
        AuthorizeController.authorize(conn, params)
      end
    end

    test "successfully authorizes with state under 10000 characters", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      valid_state = String.duplicate("a", 501)

      params = %{
        "client_id" => Environment.oauth_client_id(),
        "redirect_uri" => "tuist://oauth-callback",
        "response_type" => "code",
        "scope" => "",
        "state" => valid_state,
        "code_challenge" => "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
        "code_challenge_method" => "S256"
      }

      conn =
        conn
        |> Map.put(:query_params, params)
        |> Map.put(:params, params)
        |> assign(:current_user, user)

      conn = AuthorizeController.authorize(conn, params)

      assert conn.status == 302
      assert redirected_to(conn) =~ "tuist://oauth-callback"
    end
  end

  describe "authorize_with_apple/2" do
    test "stores the OAuth return URL in session and redirects to Apple auth", %{conn: conn} do
      params = %{
        "client_id" => Environment.oauth_client_id(),
        "redirect_uri" => "tuist://oauth-callback",
        "response_type" => "code",
        "state" => "test_state"
      }

      conn = AuthorizeController.authorize_with_apple(conn, params)

      assert conn.status == 302
      assert redirected_to(conn) == "/users/auth/apple"

      assert get_session(conn, :oauth_return_to) =~
               "/oauth2/authorize?"
    end
  end

  describe "authorize_with_github/2" do
    test "stores the OAuth return URL in session and redirects to GitHub auth", %{conn: conn} do
      params = %{
        "client_id" => Environment.oauth_client_id(),
        "redirect_uri" => "tuist://oauth-callback",
        "response_type" => "code",
        "state" => "test_state"
      }

      conn = AuthorizeController.authorize_with_github(conn, params)

      assert conn.status == 302
      assert redirected_to(conn) == "/users/auth/github"

      assert get_session(conn, :oauth_return_to) =~
               "/oauth2/authorize?"
    end
  end

  describe "authorize_with_google/2" do
    test "stores the OAuth return URL in session and redirects to Google auth", %{conn: conn} do
      params = %{
        "client_id" => Environment.oauth_client_id(),
        "redirect_uri" => "tuist://oauth-callback",
        "response_type" => "code",
        "state" => "test_state"
      }

      conn = AuthorizeController.authorize_with_google(conn, params)

      assert conn.status == 302
      assert redirected_to(conn) == "/users/auth/google"

      assert get_session(conn, :oauth_return_to) =~
               "/oauth2/authorize?"
    end
  end

  describe "authorize_error/2" do
    test "redirects to login on unauthorized error when user is not logged in", %{conn: conn} do
      error = %Error{
        status: :unauthorized,
        error: :invalid_resource_owner,
        error_description: "User not authenticated"
      }

      {conn, _log} =
        with_log(fn ->
          conn
          |> Plug.Test.init_test_session(%{})
          |> AuthorizeController.authorize_error(error)
        end)

      assert conn.status == 302
      assert redirected_to(conn) == "/users/log_in"
    end

    test "returns JSON error when user is logged in and error has no redirect_uri", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      error = %Error{
        status: :unauthorized,
        error: :invalid_client,
        error_description: "Invalid client_id or redirect_uri."
      }

      {conn, _log} =
        with_log(fn ->
          conn
          |> Plug.Test.init_test_session(%{})
          |> assign(:current_user, user)
          |> AuthorizeController.authorize_error(error)
        end)

      assert conn.status == 401
      body = json_response(conn, 401)
      assert body["error"] == "invalid_client"
      assert body["error_description"] == "Invalid client_id or redirect_uri."
    end

    test "redirects to client with error when user is logged in and error has redirect_uri", %{
      conn: conn
    } do
      user = AccountsFixtures.user_fixture()

      error = %Error{
        status: :bad_request,
        error: :invalid_scope,
        error_description: "Given scopes are unknown or unauthorized.",
        format: :query,
        redirect_uri: "http://127.0.0.1:3000/callback"
      }

      {conn, _log} =
        with_log(fn ->
          conn
          |> Plug.Test.init_test_session(%{})
          |> assign(:current_user, user)
          |> AuthorizeController.authorize_error(error)
        end)

      assert conn.status == 302
      location = redirected_to(conn)
      assert location =~ "http://127.0.0.1:3000/callback?"
      assert location =~ "error=invalid_scope"
    end
  end
end
