defmodule TuistWeb.AuthMdProtocolControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import Ecto.Query

  alias Tuist.Accounts.AgentRegistration
  alias Tuist.Accounts.AgentRegistrationEvent
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.Workers.ExpireAgentRegistrationWorker
  alias Tuist.Authentication
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Authentication, as: WebAuthentication
  alias TuistWeb.AuthenticationPlug
  alias TuistWeb.RateLimit.AgentAuth, as: AgentAuthRateLimit

  @jwt_bearer_grant "urn:ietf:params:oauth:grant-type:jwt-bearer"
  @claim_grant "urn:workos:agent-auth:grant-type:claim"

  setup do
    stub(Tuist.Environment, :agent_auth_trusted_providers, fn -> [] end)
    stub(Tuist.Environment, :app_url, fn -> "http://www.example.com" end)
    stub(AgentAuthRateLimit, :hit, fn _conn -> {:allow, 1} end)
    stub(AgentAuthRateLimit, :hit, fn _conn, _subject -> {:allow, 1} end)
    stub(AgentAuthRateLimit, :hit_registration, fn _conn, _registration_type -> {:allow, 1} end)
    :ok
  end

  test "completes anonymous registration, browser claim, refresh, and revocation", %{conn: conn} do
    registration = conn |> post("/agent/identity", %{"type" => "anonymous"}) |> json_response(200)

    assert registration["registration_type"] == "anonymous"
    assert registration["identity_assertion"]
    assert registration["claim_token"] =~ "clm_"
    assert registration["pre_claim_scopes"] == ["mcp"]

    internal_registration_id = String.replace_prefix(registration["registration_id"], "reg_", "")
    assert_enqueued(worker: ExpireAgentRegistrationWorker, args: %{registration_id: internal_registration_id})

    pre_claim = exchange_assertion(registration["identity_assertion"])
    assert pre_claim["scope"] == "mcp"
    assert %AuthenticatedAccount{} = Authentication.authenticated_subject(pre_claim["access_token"])

    pre_claim_conn = load_mcp_authentication(pre_claim["access_token"])
    assert WebAuthentication.current_user(pre_claim_conn) == nil

    email = AccountsFixtures.unique_user_email()
    user = AccountsFixtures.user_fixture(email: email)

    claim =
      build_conn()
      |> post("/agent/identity/claim", %{
        "claim_token" => registration["claim_token"],
        "email" => email
      })
      |> json_response(200)

    assert claim["status"] == "initiated"
    assert claim["claim_attempt"]["user_code"] =~ ~r/^\d{6}$/
    assert claim["claim_attempt"]["verification_uri"] =~ "/agent/identity/claim?claim_attempt_token="

    claim_page_conn =
      build_conn()
      |> log_in_user(user)
      |> get(claim["claim_attempt"]["verification_uri"])

    claim_page = html_response(claim_page_conn, 200)
    assert claim_page =~ "Authorize this agent?"
    assert claim_page =~ email
    assert claim_page =~ ~s(id="agent-auth")
    assert claim_page =~ ~s(class="noora-button")
    refute claim_page =~ "<style>"
    refute claim_page =~ claim["claim_attempt"]["user_code"]

    csrf_token = extract_hidden_value(claim_page, "_csrf_token")
    claim_attempt_token = extract_hidden_value(claim_page, "claim_attempt_token")

    authorized_page =
      claim_page_conn
      |> recycle()
      |> post("/agent/identity/claim/complete", %{
        "_csrf_token" => csrf_token,
        "claim_attempt_token" => claim_attempt_token,
        "user_code" => claim["claim_attempt"]["user_code"]
      })
      |> html_response(200)

    assert authorized_page =~ "Agent authorized"
    refute authorized_page =~ ~s(data-part="status-icon")

    already_claimed_page =
      build_conn()
      |> log_in_user(user)
      |> get(claim["claim_attempt"]["verification_uri"])
      |> html_response(200)

    assert already_claimed_page =~ "Already authorized"
    refute already_claimed_page =~ ~s(data-part="status-icon")

    registration_record = Repo.get!(AgentRegistration, internal_registration_id)

    registration_record
    |> Ecto.Changeset.change(
      claim_token_expires_at: DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    claimed = poll_claim(registration["claim_token"])
    assert claimed["scope"] == "mcp"
    assert claimed["identity_assertion"]

    assert Authentication.authenticated_subject(pre_claim["access_token"]) == nil

    assert %AuthenticatedAccount{issued_by: %{id: issued_by_id}} =
             Authentication.authenticated_subject(claimed["access_token"])

    assert issued_by_id == user.id

    claimed_conn = load_mcp_authentication(claimed["access_token"])
    assert WebAuthentication.current_user(claimed_conn).id == user.id

    event_types =
      Repo.all(
        from(e in AgentRegistrationEvent,
          where: e.agent_registration_id == ^internal_registration_id,
          select: e.event_type
        )
      )

    for event_type <- [
          :created,
          :assertion_issued,
          :token_issued,
          :claim_requested,
          :user_code_minted,
          :claim_confirmed
        ] do
      assert event_type in event_types
    end

    refreshed = exchange_assertion(claimed["identity_assertion"])
    assert refreshed["access_token"] != claimed["access_token"]

    revoke_conn =
      post(build_conn(), "/oauth2/revoke", %{"token" => refreshed["access_token"], "token_type_hint" => "access_token"})

    assert response(revoke_conn, 200) == ""
    assert Authentication.authenticated_subject(refreshed["access_token"]) == nil
    assert Authentication.authenticated_subject(claimed["access_token"])

    unsupported_hint =
      build_conn()
      |> post("/oauth2/revoke", %{
        "token" => claimed["access_token"],
        "token_type_hint" => "refresh_token"
      })
      |> json_response(400)

    assert unsupported_hint["error"] == "unsupported_token_type"
  end

  test "service_auth returns the ceremony immediately and completes through a signed-in session" do
    email = AccountsFixtures.unique_user_email()
    user = AccountsFixtures.user_fixture(email: email)

    registration =
      build_conn()
      |> post("/agent/identity", %{"type" => "service_auth", "login_hint" => email})
      |> json_response(200)

    assert registration["registration_type"] == "service_auth"
    refute Map.has_key?(registration, "identity_assertion")
    assert registration["claim"]["user_code"] =~ ~r/^\d{6}$/

    duplicate_claim =
      build_conn()
      |> post("/agent/identity/claim", %{
        "claim_token" => registration["claim_token"],
        "email" => email
      })
      |> json_response(409)

    assert duplicate_claim["error"] == "claimed_or_in_flight"

    complete_browser_claim(user, registration["claim"], registration["claim"]["user_code"])

    claimed = poll_claim(registration["claim_token"])
    assert claimed["identity_assertion"]

    assert %AuthenticatedAccount{issued_by: %{id: issued_by_id}} =
             Authentication.authenticated_subject(claimed["access_token"])

    assert issued_by_id == user.id
  end

  test "requires a recent provider authentication and a user confirmation for first linking", %{conn: conn} do
    email = AccountsFixtures.unique_user_email()
    user = AccountsFixtures.user_fixture(email: email)
    {provider, assertion, jwk} = id_jag(email, "provider-first-link")
    stub(Tuist.Environment, :agent_auth_trusted_providers, fn -> [provider] end)

    identity_conn =
      post(conn, "/agent/identity", %{
        "type" => "identity_assertion",
        "assertion_type" => "urn:ietf:params:oauth:token-type:id-jag",
        "assertion" => assertion
      })

    response = json_response(identity_conn, 401)
    assert response["error"] == "interaction_required"
    assert identity_conn |> get_resp_header("www-authenticate") |> hd() =~ "interaction_required"

    {provider, repeated_assertion, _jwk} = id_jag(email, "provider-first-link-repeated", jwk: jwk)
    stub(Tuist.Environment, :agent_auth_trusted_providers, fn -> [provider] end)

    repeated_response =
      build_conn()
      |> post("/agent/identity", %{
        "type" => "identity_assertion",
        "assertion_type" => "urn:ietf:params:oauth:token-type:id-jag",
        "assertion" => repeated_assertion
      })
      |> json_response(401)

    assert repeated_response["registration_id"] == response["registration_id"]
    assert repeated_response["claim_token"] != response["claim_token"]

    complete_browser_claim(user, repeated_response["claim"], repeated_response["claim"]["user_code"])
    claimed = poll_claim(repeated_response["claim_token"])
    assert claimed["access_token"]

    {provider, stale_assertion, _jwk} = id_jag(AccountsFixtures.unique_user_email(), "stale", auth_age: 7200)
    stub(Tuist.Environment, :agent_auth_trusted_providers, fn -> [provider] end)

    stale_conn =
      post(build_conn(), "/agent/identity", %{
        "type" => "identity_assertion",
        "assertion_type" => "urn:ietf:params:oauth:token-type:id-jag",
        "assertion" => stale_assertion
      })

    stale_response = json_response(stale_conn, 401)
    assert stale_response["error"] == "login_required"
    assert stale_response["max_age"] == 3600
  end

  test "returns a structured error when the identity registration fails unexpectedly", %{conn: conn} do
    email = AccountsFixtures.unique_user_email()
    {provider, assertion, _jwk} = id_jag(email, "provider-insert-failure")
    stub(Tuist.Environment, :agent_auth_trusted_providers, fn -> [provider] end)

    stub(Tuist.Accounts, :create_protocol_agent_registration, fn _attrs ->
      {:error, Ecto.Changeset.change(%AgentRegistration{})}
    end)

    response =
      conn
      |> post("/agent/identity", %{
        "type" => "identity_assertion",
        "assertion_type" => "urn:ietf:params:oauth:token-type:id-jag",
        "assertion" => assertion
      })
      |> json_response(500)

    assert response["error"] == "server_error"
  end

  test "accepts a signed security event and revokes the whole provider delegation", %{conn: conn} do
    email = AccountsFixtures.unique_user_email()
    {provider, assertion, jwk} = id_jag(email, "provider-registration")
    stub(Tuist.Environment, :agent_auth_trusted_providers, fn -> [provider] end)

    identity =
      conn
      |> post("/agent/identity", %{
        "type" => "identity_assertion",
        "assertion_type" => "urn:ietf:params:oauth:token-type:id-jag",
        "assertion" => assertion
      })
      |> json_response(200)

    token = exchange_assertion(identity["identity_assertion"])["access_token"]
    assert Authentication.authenticated_subject(token)

    event = security_event(jwk, "event-1")

    event_conn =
      build_conn()
      |> put_req_header("content-type", "application/secevent+jwt")
      |> post("/agent/event/notify", event)

    assert response(event_conn, 202) == ""
    assert Authentication.authenticated_subject(token) == nil
    assert exchange_assertion_error(identity["identity_assertion"])["error"] == "invalid_grant"

    replay_conn =
      build_conn()
      |> put_req_header("content-type", "application/secevent+jwt")
      |> post("/agent/event/notify", event)

    assert json_response(replay_conn, 400)["err"] == "invalid_request"

    invalid_key_event = security_event(jwk, "event-invalid-key", kid: "unknown-key")

    invalid_key_conn =
      build_conn()
      |> put_req_header("content-type", "application/secevent+jwt")
      |> post("/agent/event/notify", invalid_key_event)

    assert json_response(invalid_key_conn, 400)["err"] == "invalid_key"
  end

  test "publishes the service public signing key" do
    jwks = build_conn() |> get("/.well-known/jwks.json") |> json_response(200)

    assert [%{"kty" => "EC", "crv" => "P-256", "kid" => kid, "alg" => "ES256", "use" => "sig"}] =
             Map.get(jwks, "keys", [])

    assert is_binary(kid)
  end

  defp load_mcp_authentication(access_token) do
    conn = %{build_conn() | request_path: "/mcp"}

    conn
    |> put_req_header("authorization", "Bearer #{access_token}")
    |> AuthenticationPlug.call(:load_authenticated_subject)
  end

  defp complete_browser_claim(user, claim, user_code) do
    claim_page_conn = build_conn() |> log_in_user(user) |> get(claim["verification_uri"])
    body = html_response(claim_page_conn, 200)

    claim_page_conn
    |> recycle()
    |> post("/agent/identity/claim/complete", %{
      "_csrf_token" => extract_hidden_value(body, "_csrf_token"),
      "claim_attempt_token" => extract_hidden_value(body, "claim_attempt_token"),
      "user_code" => user_code
    })
    |> html_response(200)
  end

  defp exchange_assertion(assertion) do
    build_conn()
    |> post("/oauth2/token", %{
      "grant_type" => @jwt_bearer_grant,
      "assertion" => assertion,
      "resource" => "http://www.example.com/mcp"
    })
    |> json_response(200)
  end

  defp exchange_assertion_error(assertion) do
    build_conn()
    |> post("/oauth2/token", %{
      "grant_type" => @jwt_bearer_grant,
      "assertion" => assertion,
      "resource" => "http://www.example.com/mcp"
    })
    |> json_response(400)
  end

  defp poll_claim(claim_token) do
    build_conn()
    |> post("/oauth2/token", %{"grant_type" => @claim_grant, "claim_token" => claim_token})
    |> json_response(200)
  end

  defp extract_hidden_value(html, name) do
    [_, value] = Regex.run(~r/name="#{name}" value="([^"]+)"/, html)
    value
  end

  defp id_jag(email, jti, opts \\ []) do
    jwk = Keyword.get_lazy(opts, :jwk, fn -> JOSE.JWK.generate_key({:rsa, 2048}) end)
    {_, public_jwk} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    public_jwk = Map.put(public_jwk, "kid", "auth-md-provider-test-key")

    provider = %{
      "issuer" => "https://agent-provider.example.com",
      "display_name" => "Example Agent Provider",
      "jwks" => %{"keys" => [public_jwk]},
      "client_ids" => ["test-agent-client"]
    }

    now = DateTime.to_unix(DateTime.utc_now())

    claims = %{
      "iss" => "https://agent-provider.example.com",
      "sub" => "provider-user-1",
      "aud" => "http://www.example.com",
      "client_id" => "test-agent-client",
      "jti" => jti,
      "iat" => now,
      "exp" => now + 300,
      "auth_time" => now - Keyword.get(opts, :auth_age, 0),
      "email" => email,
      "email_verified" => true
    }

    {provider, sign_provider_jwt(jwk, "oauth-id-jag+jwt", claims), jwk}
  end

  defp security_event(jwk, jti, opts \\ []) do
    now = DateTime.to_unix(DateTime.utc_now())

    sign_provider_jwt(
      jwk,
      "secevent+jwt",
      %{
        "iss" => "https://agent-provider.example.com",
        "sub" => "provider-user-1",
        "aud" => "http://www.example.com",
        "jti" => jti,
        "iat" => now,
        "events" => %{
          "https://schemas.workos.com/events/agent/auth/identity/assertion/revoked" => %{}
        }
      },
      kid: Keyword.get(opts, :kid, "auth-md-provider-test-key")
    )
  end

  defp sign_provider_jwt(jwk, typ, claims, opts \\ []) do
    jws = %{"alg" => "RS256", "kid" => Keyword.get(opts, :kid, "auth-md-provider-test-key"), "typ" => typ}
    {_, token} = jwk |> JOSE.JWT.sign(jws, JOSE.JWT.from_map(claims)) |> JOSE.JWS.compact()
    token
  end
end
