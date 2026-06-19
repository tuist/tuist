defmodule TuistWeb.Oauth.TokenControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Environment

  @service_client_id "00000000-0000-0000-0000-000000000099"
  @service_client_secret "service-secret"
  @service_scope "account:service:read:any"

  setup :set_mimic_from_context

  describe "POST /oauth2/token" do
    test "issues service tokens for configured service clients", %{conn: conn} do
      stub(Environment, :kura_control_plane_configured?, fn -> false end)
      stub(Environment, :oauth_client_id, fn -> "tuist-cli" end)
      stub(Environment, :oauth_client_secret, fn -> "tuist-cli-secret" end)
      stub(Environment, :oauth_client_name, fn -> "Tuist CLI" end)
      stub(Environment, :oauth_jwt_public_key, fn -> nil end)
      stub(Environment, :oauth_private_key, fn -> nil end)

      stub(Environment, :oauth_service_clients, fn ->
        [
          %{
            "id" => @service_client_id,
            "secret" => @service_client_secret,
            "scopes" => [@service_scope],
            "access_token_ttl" => 120
          }
        ]
      end)

      conn =
        conn
        |> put_req_header("authorization", "Basic " <> Base.encode64("#{@service_client_id}:#{@service_client_secret}"))
        |> post("/oauth2/token", %{
          "client_id" => @service_client_id,
          "grant_type" => "client_credentials",
          "scope" => @service_scope
        })

      assert %{
               "access_token" => access_token,
               "expires_in" => expires_in,
               "refresh_token" => refresh_token,
               "token_type" => "bearer"
             } = json_response(conn, 200)

      assert expires_in <= 120
      assert is_binary(refresh_token)

      assert {:ok,
              %{
                "client_id" => @service_client_id,
                "scopes" => [@service_scope],
                "sub" => @service_client_id,
                "type" => "service"
              }} = Tuist.Guardian.decode_and_verify(access_token)
    end
  end
end
