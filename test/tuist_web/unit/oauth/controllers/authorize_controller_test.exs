defmodule TuistWeb.Controllers.Oauth.AuthorizeControllerTest do
  use ExUnit.Case, async: true
  use Mimic

  import Phoenix.ConnTest
  import Plug.Conn

  alias Boruta.Oauth.AuthorizeResponse
  alias Tuist.Accounts.User
  alias TuistWeb.Oauth.AuthorizeController

  setup do
    conn = init_test_session(%{build_conn() | query_params: %{}}, %{})

    {:ok, conn: conn}
  end

  describe "authorize/2" do
    test "redirects to user login without current_user", %{conn: conn} do
      conn = AuthorizeController.authorize(conn, %{})
      assert redirected_to(conn) == "/users/log_in"
    end

    test "redirects with an access_token", %{conn: conn} do
      current_user = %User{}
      conn = assign(conn, :current_user, current_user)

      response = %AuthorizeResponse{
        type: :token,
        redirect_uri: "http://redirect.uri",
        access_token: "access_token",
        expires_in: 10
      }

      expect(Boruta.Oauth, :authorize, 1, fn conn, _resource_owner, module ->
        module.authorize_success(conn, response)
      end)

      conn = AuthorizeController.authorize(conn, %{})

      redirect_url = redirected_to(conn)
      assert redirect_url =~ ~r/http:\/\/redirect\.uri#/
      assert redirect_url =~ ~r/access_token=access_token/
      assert redirect_url =~ ~r/expires_in=10/
    end

    test "redirects with an access_token and a state", %{conn: conn} do
      current_user = %User{}
      conn = assign(conn, :current_user, current_user)

      response = %AuthorizeResponse{
        type: :token,
        redirect_uri: "http://redirect.uri",
        access_token: "access_token",
        expires_in: 10,
        state: "state"
      }

      expect(Boruta.Oauth, :authorize, 1, fn conn, _resource_owner, module ->
        module.authorize_success(conn, response)
      end)

      conn = AuthorizeController.authorize(conn, %{})

      redirect_url = redirected_to(conn)
      assert redirect_url =~ ~r/http:\/\/redirect\.uri#/
      assert redirect_url =~ ~r/access_token=access_token/
      assert redirect_url =~ ~r/expires_in=10/
      assert redirect_url =~ ~r/state=state/
    end
  end
end
