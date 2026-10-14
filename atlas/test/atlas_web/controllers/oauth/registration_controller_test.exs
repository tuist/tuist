defmodule AtlasWeb.Oauth.RegistrationControllerTest do
  use AtlasWeb.ConnCase, async: true

  alias Atlas.Guardian
  alias Atlas.Repo
  alias Boruta.Ecto.Client

  @redirect_uri "dev.tuist.atlas://oauth-callback"

  test "a dynamically registered native public client signs in and refreshes with PKCE", %{conn: conn} do
    discovery = conn |> get(~p"/.well-known/oauth-authorization-server") |> json_response(200)
    assert URI.parse(discovery["registration_endpoint"]).path == ~p"/oauth2/register"
    assert "S256" in discovery["code_challenge_methods_supported"]

    registration =
      conn
      |> post(~p"/oauth2/register", %{
        "client_name" => "Atlas Native",
        "redirect_uris" => [@redirect_uri],
        "grant_types" => ["authorization_code", "refresh_token"],
        "response_types" => ["code"],
        "token_endpoint_auth_method" => "none"
      })
      |> json_response(201)

    assert %{
             "client_id" => client_id,
             "redirect_uris" => [@redirect_uri],
             "token_endpoint_auth_method" => "none"
           } = registration

    assert %Client{confidential: false, public_refresh_token: true, pkce: true} = Repo.get(Client, client_id)
    verifier = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    challenge = :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)
    state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    {conn, _user} = log_in_user(build_conn())

    callback =
      conn
      |> get(~p"/oauth2/authorize", %{
        "response_type" => "code",
        "client_id" => client_id,
        "redirect_uri" => @redirect_uri,
        "scope" => "mcp",
        "state" => state,
        "code_challenge" => challenge,
        "code_challenge_method" => "S256"
      })
      |> redirected_to()
      |> URI.parse()

    assert callback.scheme == "dev.tuist.atlas"
    assert callback.host == "oauth-callback"
    assert %{"state" => ^state, "code" => code} = URI.decode_query(callback.query)

    parameters = %{
      "grant_type" => "authorization_code",
      "client_id" => client_id,
      "redirect_uri" => @redirect_uri,
      "code" => code
    }

    assert %{"error" => "invalid_request"} = parameters |> post_form() |> json_response(400)

    invalid = parameters |> Map.put("code_verifier", "wrong-verifier") |> post_form()

    assert %{"error" => "invalid_request", "error_description" => "Code verifier is invalid."} =
             json_response(invalid, 400)

    tokens = parameters |> Map.put("code_verifier", verifier) |> post_form() |> json_response(200)
    assert %{"access_token" => access_token, "refresh_token" => refresh_token, "expires_in" => expires_in} = tokens
    assert expires_in > 0
    assert {:ok, %{"scopes" => ["mcp"]}} = Guardian.decode_and_verify(access_token)

    refreshed =
      %{"grant_type" => "refresh_token", "client_id" => client_id, "refresh_token" => refresh_token}
      |> post_form()
      |> json_response(200)

    assert refreshed["access_token"] != access_token
    assert is_binary(refreshed["refresh_token"])
    assert {:ok, %{"scopes" => ["mcp"]}} = Guardian.decode_and_verify(refreshed["access_token"])
  end

  test "signed-out native authorization resumes through the existing browser login", %{conn: conn} do
    parameters = %{"response_type" => "code", "client_id" => Ecto.UUID.generate(), "redirect_uri" => @redirect_uri}
    conn = get(conn, ~p"/oauth2/authorize", parameters)
    assert redirected_to(conn) == ~p"/login"
    return_to = conn |> get_session(:user_return_to) |> URI.parse()
    assert return_to.path == "/oauth2/authorize"
    assert URI.decode_query(return_to.query) == parameters
  end

  defp post_form(parameters) do
    build_conn()
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> post(~p"/oauth2/token", URI.encode_query(parameters))
  end
end
