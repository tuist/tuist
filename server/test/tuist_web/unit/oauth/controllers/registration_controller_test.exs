defmodule TuistWeb.Controllers.Oauth.RegistrationControllerTest do
  use ExUnit.Case, async: true
  use Mimic

  import Ecto.Changeset
  import Phoenix.ConnTest

  alias Boruta.Oauth.Client
  alias TuistWeb.Oauth.RegistrationController

  setup do
    {:ok, conn: build_conn()}
  end

  describe "register/2" do
    test "normalizes registration params before calling openid register_client", %{conn: conn} do
      expect(Boruta.Openid, :register_client, 1, fn conn, params, module ->
        assert Enum.all?(Map.keys(params), &is_atom/1)
        assert params[:client_name] == "tuist-mcp-client"
        assert params[:redirect_uris] == ["http://localhost/callback"]
        assert params[:supported_grant_types] == ["authorization_code", "refresh_token"]
        assert params[:response_types] == ["code"]
        assert params[:public_refresh_token]
        assert params[:public_revoke]
        assert params[:metadata]["token_endpoint_auth_method"] == "none"
        refute Map.has_key?(params, :token_endpoint_auth_method)

        module.client_registered(conn, %Client{
          id: "dynamic-client-id",
          secret: "dynamic-client-secret",
          name: "tuist-mcp-client",
          redirect_uris: ["http://localhost/callback"],
          supported_grant_types: ["authorization_code"],
          token_endpoint_auth_methods: ["client_secret_basic"],
          metadata: %{"token_endpoint_auth_method" => "none"}
        })
      end)

      conn =
        RegistrationController.register(conn, %{
          "client_name" => "tuist-mcp-client",
          "redirect_uris" => ["http://localhost/callback"],
          "grant_types" => ["authorization_code", "refresh_token"],
          "response_types" => ["code"],
          "token_endpoint_auth_method" => "none"
        })

      assert json_response(conn, 201)["client_id"] == "dynamic-client-id"
    end
  end

  describe "client_registered/2" do
    test "returns dynamic registration response", %{conn: conn} do
      conn =
        RegistrationController.client_registered(conn, %Client{
          id: "dynamic-client-id",
          secret: "dynamic-client-secret",
          name: "tuist-mcp-client",
          redirect_uris: ["http://localhost/callback"],
          supported_grant_types: ["authorization_code", "refresh_token"],
          token_endpoint_auth_methods: ["none"]
        })

      response = json_response(conn, 201)

      assert response["client_id"] == "dynamic-client-id"
      assert response["client_secret"] == "dynamic-client-secret"
      assert response["client_name"] == "tuist-mcp-client"
      assert response["redirect_uris"] == ["http://localhost/callback"]
      assert response["grant_types"] == ["authorization_code", "refresh_token"]
      assert response["token_endpoint_auth_method"] == "none"
      assert is_integer(response["client_id_issued_at"])
      assert response["client_secret_expires_at"] == 0
    end

    test "returns public auth method from metadata when present", %{conn: conn} do
      conn =
        RegistrationController.client_registered(conn, %Client{
          id: "dynamic-client-id",
          secret: "dynamic-client-secret",
          name: "tuist-mcp-client",
          redirect_uris: ["http://localhost/callback"],
          supported_grant_types: ["authorization_code", "refresh_token"],
          token_endpoint_auth_methods: ["client_secret_basic"],
          metadata: %{"token_endpoint_auth_method" => "none"}
        })

      response = json_response(conn, 201)
      assert response["token_endpoint_auth_method"] == "none"
    end
  end

  describe "registration_failure/2" do
    test "returns invalid_client_metadata error response", %{conn: conn} do
      changeset =
        {%{}, %{redirect_uris: {:array, :string}}}
        |> cast(%{}, [:redirect_uris])
        |> validate_required([:redirect_uris])

      conn = RegistrationController.registration_failure(conn, changeset)

      assert json_response(conn, 400) == %{
               "error" => "invalid_client_metadata",
               "error_description" => "redirect_uris: can't be blank"
             }
    end
  end
end
