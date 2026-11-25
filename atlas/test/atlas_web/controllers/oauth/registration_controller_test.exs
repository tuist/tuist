defmodule AtlasWeb.Oauth.RegistrationControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  alias Atlas.Guardian
  alias Atlas.Repo
  alias Boruta.Ecto.Admin
  alias Boruta.Ecto.Client
  alias Ueberauth.Auth.Extra
  alias Ueberauth.Auth.Info

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
      |> approve_oauth_authorization(
        ~p"/oauth2/authorize?#{%{"response_type" => "code", "client_id" => client_id, "redirect_uri" => @redirect_uri, "scope" => "mcp", "state" => state, "code_challenge" => challenge, "code_challenge_method" => "S256"}}"
      )
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
    return_to = conn |> get_session(:return_to) |> URI.parse()
    assert return_to.path == "/oauth2/authorize"
    assert URI.decode_query(return_to.query) == parameters
  end

  for {provider, login_path} <- [{nil, "/login"}, {"google", "/auth/google"}] do
    @provider provider
    @login_path login_path

    test "#{provider || "default"} native login returns from Google to the app and exchanges the code", %{conn: conn} do
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

      verifier = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

      parameters = %{
        "response_type" => "code",
        "client_id" => registration["client_id"],
        "redirect_uri" => @redirect_uri,
        "scope" => "mcp",
        "state" => state,
        "code_challenge" => :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false),
        "code_challenge_method" => "S256"
      }

      parameters = if @provider, do: Map.put(parameters, "provider", @provider), else: parameters
      conn = get(build_conn(), ~p"/oauth2/authorize", parameters)
      assert redirected_to(conn) == @login_path
      return_to = get_session(conn, :return_to)
      assert URI.decode_query(URI.parse(return_to).query) == parameters

      if @provider == nil do
        login_conn = conn |> recycle() |> get(~p"/login")
        assert html_response(login_conn, 200)
        assert get_session(login_conn, :return_to) == return_to
      end

      {_signed_in_conn, user} = log_in_user(build_conn())

      expect(Ueberauth, :call, fn conn, _opts ->
        assign(conn, :ueberauth_auth, %Ueberauth.Auth{
          provider: :google,
          info: %Info{email: user.email, name: user.name},
          extra: %Extra{
            raw_info: %{user: %{"email" => user.email, "email_verified" => true, "hd" => "tuist.dev"}}
          }
        })
      end)

      conn = conn |> recycle() |> get(~p"/auth/google/callback")
      assert redirected_to(conn) == return_to
      assert get_session(conn, :user_id) == user.id
      assert get_session(conn, :return_to) == nil

      callback = conn |> recycle() |> approve_oauth_authorization(return_to) |> redirected_to() |> URI.parse()
      assert callback.scheme == "dev.tuist.atlas"
      assert callback.host == "oauth-callback"
      assert %{"state" => ^state, "code" => code} = URI.decode_query(callback.query)

      tokens =
        %{
          "grant_type" => "authorization_code",
          "client_id" => registration["client_id"],
          "redirect_uri" => @redirect_uri,
          "code" => code,
          "code_verifier" => verifier
        }
        |> post_form()
        |> json_response(200)

      assert {:ok, %{"sub" => sub, "scopes" => ["mcp"]}} = Guardian.decode_and_verify(tokens["access_token"])
      assert sub == to_string(user.id)
      assert is_binary(tokens["refresh_token"])
    end
  end

  test "an unknown provider cannot redirect authorization to another origin", %{conn: conn} do
    conn = get(conn, ~p"/oauth2/authorize", %{"provider" => "https://untrusted.example"})
    assert redirected_to(conn) == ~p"/login"
  end

  describe "grant types" do
    # Boruta stores every grant it implements when registration names none, and
    # accepts any the registrant lists. Implicit would hand a full MCP token to
    # the redirect URI without PKCE.
    test "registration keeps only the authorization code and refresh grants", %{conn: conn} do
      for grant_types <- [nil, ["implicit", "authorization_code", "client_credentials", "password", "refresh_token"]] do
        params = %{
          "client_name" => "Grants",
          "redirect_uris" => [@redirect_uri],
          "token_endpoint_auth_method" => "none"
        }

        params = if grant_types, do: Map.put(params, "grant_types", grant_types), else: params

        registration = conn |> post(~p"/oauth2/register", params) |> json_response(201)

        assert registration["grant_types"] == ["authorization_code", "refresh_token"]

        assert %Client{supported_grant_types: ["authorization_code", "refresh_token"]} =
                 Repo.get(Client, registration["client_id"])

        refute_implicit_token(registration["client_id"])
      end
    end

    test "clients stored with Boruta's default grants can neither use implicit nor client credentials" do
      {:ok, client} = Admin.create_client(%{name: "Legacy", redirect_uris: [@redirect_uri], confidential: true})
      assert "implicit" in client.supported_grant_types

      refute_implicit_token(client.id)

      conn =
        post_form(%{"grant_type" => "client_credentials", "client_id" => client.id, "client_secret" => client.secret})

      assert %{"error" => "unsupported_grant_type"} = json_response(conn, 400)
    end
  end

  describe "request objects at the token endpoint" do
    # Boruta resolves `request_uri` with an HTTP GET before it authenticates the
    # client, so anyone could make Atlas request an internal address.
    test "are refused before Boruta fetches or reads them" do
      port = start_loopback_fixture()
      request_uri = "http://127.0.0.1:#{port}/request"

      request =
        Enum.map_join(
          [%{"alg" => "none"}, %{"grant_type" => "password"}],
          ".",
          &Base.url_encode64(JSON.encode!(&1), padding: false)
        ) <> "."

      for {query, body} <- [
            {%{}, %{"request_uri" => request_uri}},
            {%{"request_uri" => request_uri}, %{}},
            {%{}, %{"request" => request}}
          ] do
        conn =
          build_conn()
          |> put_req_header("content-type", "application/x-www-form-urlencoded")
          |> post(
            "/oauth2/token?" <> URI.encode_query(query),
            URI.encode_query(Map.put(body, "grant_type", "client_credentials"))
          )

        refute_received {:loopback_fixture_request, _}
        assert %{"error" => "invalid_request"} = json_response(conn, 400)
      end
    end
  end

  describe "client jwks_uri" do
    # Registration is anonymous and Boruta fetches `jwks_uri` with a plain
    # Finch GET, so accepting it would let anyone make the server request an
    # arbitrary internal address.
    test "registration rejects it without fetching it, whether or not the rest of the metadata is valid" do
      port = start_loopback_fixture()
      jwks_uri = "http://127.0.0.1:#{port}/probe"

      for redirect_uris <- [["not a uri"], [@redirect_uri]] do
        conn =
          post(build_conn(), ~p"/oauth2/register", %{
            "client_name" => "Probe",
            "redirect_uris" => redirect_uris,
            "grant_types" => ["authorization_code"],
            "response_types" => ["code"],
            "jwks_uri" => jwks_uri
          })

        refute_received {:loopback_fixture_request, _}

        assert %{"error" => "invalid_client_metadata", "error_description" => "jwks_uri is not supported." <> _} =
                 json_response(conn, 400)
      end

      refute Repo.get_by(Client, name: "Probe")
    end

    test "token requests never fetch one stored on an existing client" do
      port = start_loopback_fixture()
      public_jwk = {:rsa, 2048} |> JOSE.JWK.generate_key() |> JOSE.JWK.to_public_map() |> elem(1)

      {:ok, client} =
        Admin.create_client(%{
          name: "Stored jwks_uri",
          confidential: true,
          redirect_uris: [@redirect_uri],
          supported_grant_types: ["authorization_code"],
          token_endpoint_auth_methods: ["private_key_jwt"],
          token_endpoint_jwt_auth_alg: "RS256",
          jwk: Map.put(public_jwk, "alg", "RS256"),
          jwks_uri: "http://127.0.0.1:#{port}/probe"
        })

      # Signed by a key the client doesn't have, so Boruta's verification
      # fails and it falls back to refreshing the client's key from jwks_uri.
      {_, assertion} =
        {:rsa, 2048}
        |> JOSE.JWK.generate_key()
        |> JOSE.JWT.sign(%{"alg" => "RS256"}, %{
          "iss" => client.id,
          "sub" => client.id,
          "aud" => Boruta.Config.issuer(),
          "exp" => System.system_time(:second) + 60
        })
        |> JOSE.JWS.compact()

      conn =
        post_form(%{
          "grant_type" => "authorization_code",
          "client_id" => client.id,
          "redirect_uri" => @redirect_uri,
          "code" => "unused",
          "client_assertion_type" => "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
          "client_assertion" => assertion
        })

      refute_received {:loopback_fixture_request, _}
      assert %{"error" => "invalid_client"} = json_response(conn, 401)
    end
  end

  defp refute_implicit_token(client_id) do
    {conn, _user} = log_in_user(build_conn())

    for response_type <- ["token", "id_token token"] do
      path =
        ~p"/oauth2/authorize?#{%{"response_type" => response_type, "client_id" => client_id, "redirect_uri" => @redirect_uri, "scope" => "mcp", "state" => "s", "nonce" => "n"}}"

      consent = get(conn, path)
      approval = post(conn, path, %{"decision" => "allow"})

      for response <- [consent, approval], location <- get_resp_header(response, "location") do
        refute location =~ "access_token"
      end

      refute consent.status == 200
    end
  end

  defp post_form(parameters) do
    build_conn()
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> post(~p"/oauth2/token", URI.encode_query(parameters))
  end

  # A loopback HTTP server that reports every request it receives to the test
  # process and answers 404. Requests are synchronous, so a fetch made while
  # handling a call has been reported by the time the call returns.
  defp start_loopback_fixture do
    test_pid = self()
    {:ok, socket} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    spawn_link(fn -> serve_loopback_fixture(socket, test_pid) end)
    port
  end

  defp serve_loopback_fixture(socket, test_pid) do
    with {:ok, client} <- :gen_tcp.accept(socket) do
      # Report the connection even if it never sends a full request.
      request =
        case :gen_tcp.recv(client, 0, 5_000) do
          {:ok, request} -> request
          {:error, reason} -> reason
        end

      send(test_pid, {:loopback_fixture_request, request})
      :gen_tcp.send(client, "HTTP/1.1 404 Not Found\r\ncontent-length: 0\r\nconnection: close\r\n\r\n")
      :gen_tcp.close(client)
      serve_loopback_fixture(socket, test_pid)
    end
  end
end
