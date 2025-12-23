defmodule TuistWeb.Controllers.Oauth.AuthorizeControllerTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

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

  describe "authorize_error/2" do
    test "redirects to login on unauthorized error", %{conn: conn} do
      error = %Error{
        status: :unauthorized,
        error: :invalid_resource_owner,
        error_description: "User not authenticated"
      }

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> AuthorizeController.authorize_error(error)

      assert conn.status == 302
      assert redirected_to(conn) == "/users/log_in"
    end
  end
end
