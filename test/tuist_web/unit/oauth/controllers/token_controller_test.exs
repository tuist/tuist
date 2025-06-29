defmodule TuistWeb.Controllers.Oauth.TokenControllerTest do
  use ExUnit.Case, async: true
  use Mimic

  import Phoenix.ConnTest

  alias Boruta.Oauth.Error
  alias Boruta.Oauth.TokenResponse
  alias TuistWeb.Oauth.TokenController

  setup do
    conn = build_conn()
    {:ok, conn: conn}
  end

  describe "token/2" do
    test "calls oauth module token function", %{conn: conn} do
      expect(Boruta.Oauth, :token, 1, fn conn, module ->
        response = %TokenResponse{
          token_type: "Bearer",
          access_token: "access_token",
          expires_in: 3600
        }

        module.token_success(conn, response)
      end)

      conn = TokenController.token(conn, %{})

      assert json_response(conn, 200) == %{
               "token_type" => "Bearer",
               "access_token" => "access_token",
               "expires_in" => 3600
             }
    end
  end

  describe "token_success/2" do
    test "returns JSON response with all token fields", %{conn: conn} do
      response = %TokenResponse{
        token_type: "Bearer",
        access_token: "access_token",
        expires_in: 3600,
        refresh_token: "refresh_token",
        id_token: "id_token"
      }

      conn = TokenController.token_success(conn, response)

      assert json_response(conn, 200) == %{
               "token_type" => "Bearer",
               "access_token" => "access_token",
               "expires_in" => 3600,
               "refresh_token" => "refresh_token",
               "id_token" => "id_token"
             }
    end
  end

  describe "token_error/2" do
    test "returns JSON error response with correct status", %{conn: conn} do
      error = %Error{
        status: 400,
        error: "invalid_request",
        error_description: "The request is missing a required parameter"
      }

      conn = TokenController.token_error(conn, error)

      assert json_response(conn, 400) == %{
               "error" => "invalid_request",
               "error_description" => "The request is missing a required parameter"
             }
    end
  end
end
