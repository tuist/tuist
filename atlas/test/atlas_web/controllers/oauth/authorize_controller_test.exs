defmodule AtlasWeb.Oauth.AuthorizeControllerTest do
  use AtlasWeb.ConnCase, async: true

  alias Atlas.Audit.Activity
  alias Atlas.Guardian
  alias Atlas.OAuth.AccessTokens
  alias Atlas.Repo
  alias Boruta.Ecto.Scope
  alias Boruta.Ecto.Scopes
  alias Boruta.Ecto.Token

  setup do
    Scopes.invalidate(:public)
    :ok
  end

  test "mcp is registered as a public OAuth scope" do
    assert %Scope{public: true, label: "Atlas MCP access"} = Repo.get_by(Scope, name: "mcp")
  end

  test "authorizes a dynamically registered MCP client with the mcp scope", %{conn: conn} do
    redirect_uri = "https://claude.ai/api/mcp/auth_callback"

    registration_conn =
      post(conn, ~p"/oauth2/register", %{
        "client_name" => "Claude",
        "redirect_uris" => [redirect_uri],
        "grant_types" => ["authorization_code", "refresh_token"],
        "response_types" => ["code"],
        "token_endpoint_auth_method" => "none"
      })

    assert %{"client_id" => client_id} = json_response(registration_conn, 201)

    verifier = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    challenge = :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)
    {conn, _user} = log_in_user(build_conn())

    conn =
      approve_oauth_authorization(
        conn,
        ~p"/oauth2/authorize?#{%{"response_type" => "code", "client_id" => client_id, "redirect_uri" => redirect_uri, "scope" => "mcp", "state" => "claude-state", "code_challenge" => challenge, "code_challenge_method" => "S256"}}"
      )

    redirect = redirected_to(conn)
    assert redirect =~ redirect_uri
    assert redirect =~ "code="
    assert redirect =~ "state=claude-state"
    refute redirect =~ "invalid_scope"

    %{"code" => code} = redirect |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    token_conn =
      post(build_conn(), ~p"/oauth2/token", %{
        "grant_type" => "authorization_code",
        "client_id" => client_id,
        "redirect_uri" => redirect_uri,
        "code" => code,
        "code_verifier" => verifier
      })

    assert %{
             "access_token" => access_token,
             "refresh_token" => refresh_token,
             "token_type" => "bearer"
           } = json_response(token_conn, 200)

    assert {:ok, %{"scopes" => ["mcp"]}} = Guardian.decode_and_verify(access_token)
    assert is_binary(refresh_token)

    # A request on another replica must see revocation without relying on the
    # instance that originally minted or looked up the token to evict a cache.
    token = AccessTokens.get_by(value: access_token)
    assert is_nil(token.revoked_at)
    assert {:ok, _revoked} = AccessTokens.revoke(token)
    assert AccessTokens.get_by(value: access_token).revoked_at
    assert {:error, :token_not_found} = Guardian.decode_and_verify(access_token)

    replay_conn =
      post(build_conn(), ~p"/oauth2/token", %{
        "grant_type" => "authorization_code",
        "client_id" => client_id,
        "redirect_uri" => redirect_uri,
        "code" => code,
        "code_verifier" => verifier
      })

    assert %{"error" => "invalid_grant"} = json_response(replay_conn, 400)
  end

  test "preserves long OAuth state through a PKCE authorization code exchange", %{conn: conn} do
    redirect_uri = "http://127.0.0.1:3333/callback"
    resource = "https://atlas.tuist.dev/mcp"
    state = String.duplicate("opaque-state+/=&?", 64)
    verifier = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    challenge = :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)

    registration_conn =
      post(conn, ~p"/oauth2/register", %{
        "client_name" => "Pi",
        "redirect_uris" => [redirect_uri],
        "grant_types" => ["authorization_code", "refresh_token"],
        "response_types" => ["code"],
        "token_endpoint_auth_method" => "none"
      })

    assert %{"client_id" => client_id} = json_response(registration_conn, 201)
    {conn, _user} = log_in_user(build_conn())

    conn =
      approve_oauth_authorization(
        conn,
        ~p"/oauth2/authorize?#{%{"response_type" => "code", "client_id" => client_id, "redirect_uri" => redirect_uri, "scope" => "mcp", "state" => state, "resource" => resource, "code_challenge" => challenge, "code_challenge_method" => "S256"}}"
      )

    assert %{"code" => code, "state" => ^state} =
             conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    assert %Token{state: ^state} = Repo.get_by(Token, value: code)

    token_conn =
      post(build_conn(), ~p"/oauth2/token", %{
        "grant_type" => "authorization_code",
        "client_id" => client_id,
        "redirect_uri" => redirect_uri,
        "code" => code,
        "code_verifier" => verifier,
        "resource" => resource
      })

    assert %{"access_token" => access_token, "refresh_token" => refresh_token} =
             json_response(token_conn, 200)

    assert {:ok, %{"scopes" => ["mcp"]}} = Guardian.decode_and_verify(access_token)
    assert %Token{resource: ^resource, previous_code: ^code} = Repo.get_by(Token, value: access_token)
    assert is_binary(refresh_token)
  end

  test "keeps the resource indicator on the token so refreshes are accepted", %{conn: conn} do
    redirect_uri = "https://claude.ai/api/mcp/auth_callback"
    resource = "https://atlas.tuist.dev/mcp"

    registration_conn =
      post(conn, ~p"/oauth2/register", %{
        "client_name" => "Claude Code",
        "redirect_uris" => [redirect_uri],
        "grant_types" => ["authorization_code", "refresh_token"],
        "response_types" => ["code"],
        "token_endpoint_auth_method" => "none"
      })

    assert %{"client_id" => client_id} = json_response(registration_conn, 201)

    verifier = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    challenge = :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)
    {conn, _user} = log_in_user(build_conn())

    conn =
      approve_oauth_authorization(
        conn,
        ~p"/oauth2/authorize?#{%{"response_type" => "code", "client_id" => client_id, "redirect_uri" => redirect_uri, "scope" => "mcp", "state" => "claude-state", "resource" => resource, "code_challenge" => challenge, "code_challenge_method" => "S256"}}"
      )

    %{"code" => code} =
      conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    token_conn =
      post(build_conn(), ~p"/oauth2/token", %{
        "grant_type" => "authorization_code",
        "client_id" => client_id,
        "redirect_uri" => redirect_uri,
        "code" => code,
        "resource" => resource,
        "code_verifier" => verifier
      })

    assert %{"access_token" => access_token, "refresh_token" => refresh_token} =
             json_response(token_conn, 200)

    assert %Token{resource: ^resource} = Repo.get_by(Token, value: access_token)

    refresh_conn =
      post(build_conn(), ~p"/oauth2/token", %{
        "grant_type" => "refresh_token",
        "client_id" => client_id,
        "refresh_token" => refresh_token,
        "resource" => resource
      })

    assert %{"access_token" => refreshed_access_token, "refresh_token" => _} =
             json_response(refresh_conn, 200)

    assert refreshed_access_token != access_token
    assert {:ok, %{"scopes" => ["mcp"]}} = Guardian.decode_and_verify(refreshed_access_token)

    assert %Token{resource: ^resource, previous_token: ^access_token} =
             Repo.get_by(Token, value: refreshed_access_token)
  end

  describe "consent" do
    setup %{conn: conn} do
      redirect_uri = "http://127.0.0.1:4545/callback"

      %{"client_id" => client_id} =
        conn
        |> post(~p"/oauth2/register", %{
          "client_name" => "Desktop MCP",
          "redirect_uris" => [redirect_uri],
          "grant_types" => ["authorization_code", "refresh_token"],
          "response_types" => ["code"],
          "token_endpoint_auth_method" => "none"
        })
        |> json_response(201)

      challenge = :sha256 |> :crypto.hash("verifier") |> Base.url_encode64(padding: false)

      path =
        ~p"/oauth2/authorize?#{%{"response_type" => "code", "client_id" => client_id, "redirect_uri" => redirect_uri, "scope" => "mcp", "state" => "s1", "code_challenge" => challenge, "code_challenge_method" => "S256"}}"

      {signed_in, user} = log_in_user(build_conn())
      {:ok, client_id: client_id, path: path, signed_in: signed_in, user: user}
    end

    test "a signed-in GET shows the client and destination without issuing a code", context do
      conn = get(context.signed_in, context.path)
      html = html_response(conn, 200)
      document = LazyHTML.from_document(html)

      assert LazyHTML.text(LazyHTML.query(document, "#oauth-consent-client")) =~ "Desktop MCP"
      assert LazyHTML.text(LazyHTML.query(document, "#oauth-consent-destination")) =~ "127.0.0.1:4545"
      assert LazyHTML.text(LazyHTML.query(document, "#oauth-consent-user")) =~ context.user.email
      assert get_resp_header(conn, "cache-control") == ["no-store"]

      for form <- ["#oauth-consent-allow-form", "#oauth-consent-deny-form"] do
        assert [_] = document |> LazyHTML.query(form <> " input[name=_csrf_token]") |> Enum.to_list()
      end

      refute Repo.get_by(Token, client_id: context.client_id)
    end

    test "denying redirects with access_denied and issues no code", context do
      conn = post(context.signed_in, context.path, %{"decision" => "deny"})
      query = conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

      assert %{"error" => "access_denied", "state" => "s1"} = query
      refute Map.has_key?(query, "code")
      refute Repo.get_by(Token, client_id: context.client_id)
    end

    test "a POST without a decision issues no code", context do
      conn = post(context.signed_in, context.path, %{})

      assert %{"error" => "access_denied"} =
               conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

      refute Repo.get_by(Token, client_id: context.client_id)
    end

    test "approval reads the request from the query, not a request object in the form", context do
      # Boruta would build the request from a body `request` JWT if the form's
      # params reached it; this one is malformed, so only ignoring it succeeds.
      conn = post(context.signed_in, context.path, %{"decision" => "allow", "request" => "not-a-jwt"})

      callback = conn |> redirected_to() |> URI.parse()
      assert {callback.host, callback.port, callback.path} == {"127.0.0.1", 4545, "/callback"}
      assert %{"code" => _} = URI.decode_query(callback.query)
    end

    test "request objects in the query are refused before Boruta fetches or reads them", context do
      # A remote request object can name one client on the consent page and
      # another at approval, so neither request step may resolve one.
      {:ok, listener} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false])
      {:ok, port} = :inet.port(listener)
      on_exit(fn -> :gen_tcp.close(listener) end)

      request_jwt =
        Joken.generate_and_sign!(%{}, %{"client_id" => context.client_id}, Joken.Signer.create("HS256", "secret"))

      for extra <- [%{"request_uri" => "http://127.0.0.1:#{port}/req"}, %{"request" => request_jwt}],
          method <- [:get, :post] do
        path = context.path <> "&" <> URI.encode_query(extra)
        conn = dispatch(context.signed_in, @endpoint, method, path, %{"decision" => "allow"})

        assert %{"error" => "invalid_request"} = json_response(conn, 400), inspect({method, extra})
      end

      assert {:error, :timeout} = :gen_tcp.accept(listener, 0)
      refute Repo.get_by(Token, client_id: context.client_id)
    end

    test "approval without a CSRF token issues no code", context do
      conn = %{context.signed_in | private: Map.delete(context.signed_in.private, :plug_skip_csrf_protection)}

      assert_error_sent 403, fn -> post(conn, context.path, %{"decision" => "allow"}) end
      refute Repo.get_by(Token, client_id: context.client_id)
    end

    test "approval is audited with the approving user, client, and destination", context do
      context.signed_in |> post(context.path, %{"decision" => "allow"}) |> redirected_to()

      assert %Activity{interface: "dashboard", target_type: "oauth_client", target_label: "Desktop MCP"} =
               activity = Repo.get_by!(Activity, action: "oauth.client_authorized", target_id: context.client_id)

      assert activity.actor_id == context.user.id
      assert %{"redirect_destination" => "127.0.0.1:4545 (this computer)", "scope" => "mcp"} = activity.metadata
    end
  end

  test "anonymous registration only accepts redirects an outsider cannot receive codes at", %{conn: conn} do
    register = fn redirect_uris ->
      post(conn, ~p"/oauth2/register", %{
        "client_name" => "Client",
        "redirect_uris" => redirect_uris,
        "grant_types" => ["authorization_code"],
        "response_types" => ["code"],
        "token_endpoint_auth_method" => "none"
      })
    end

    for uri <- [
          "http://127.0.0.1:33418/callback",
          "http://localhost:6274/oauth/callback",
          "http://[::1]:8080/cb",
          "dev.tuist.atlas://oauth-callback",
          "cursor://anysphere.cursor-retrieval/oauth/user-atlas/callback",
          "https://claude.ai/api/mcp/auth_callback",
          "https://claude.com/api/mcp/auth_callback",
          "https://chatgpt.com/connector_platform_oauth_redirect",
          "https://chatgpt.com/connector/oauth/AbC_12-x",
          "https://vscode.dev/redirect",
          "https://insiders.vscode.dev/redirect"
        ] do
      assert %{"redirect_uris" => [^uri]} = json_response(register.([uri]), 201)
    end

    for uris <- [
          ["https://attacker.example/callback"],
          ["https://claude.ai.attacker.example/cb"],
          ["https://claude.ai:8443/api/mcp/auth_callback"],
          # Other pages on allowlisted hosts (open redirects, user content).
          ["https://claude.ai/cb"],
          ["https://claude.ai/api/mcp/auth_callback/extra"],
          ["https://claude.ai/api/mcp/auth_callback?next=https://attacker.example"],
          ["https://chatgpt.com/share/abc"],
          ["https://chatgpt.com/connector/oauth/"],
          ["https://chatgpt.com/connector/oauth/a/b"],
          ["https://chatgpt.com/connector/oauth/..%2F..%2Fshare"],
          ["https://chatgpt.com/connector_platform_oauth_redirect?x=1"],
          ["https://vscode.dev/redirect/other"],
          ["https://vscode.dev/github/attacker/repo"],
          ["http://claude.ai/api/mcp/auth_callback"],
          ["https://user@claude.ai/cb"],
          ["javascript:alert(1)"],
          ["http://127.0.0.1:3000/cb", "https://attacker.example/cb"],
          [],
          "https://claude.ai/api/mcp/auth_callback"
        ] do
      assert %{"error" => "invalid_redirect_uri"} = json_response(register.(uris), 400), inspect(uris)
    end
  end
end
