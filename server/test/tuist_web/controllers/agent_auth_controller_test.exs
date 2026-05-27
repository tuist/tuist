defmodule TuistWeb.AgentAuthControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Bamboo.Test
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.AgentRegistration
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Authentication
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.RateLimit.AgentAuth
  alias TuistWeb.RateLimit.MCP

  @initialize_params %{
    "protocolVersion" => "2025-03-26",
    "capabilities" => %{},
    "clientInfo" => %{"name" => "test", "version" => "0.1.0"}
  }

  setup do
    stub(Tuist.Environment, :mailing_from_address, fn -> "noreply@tuist.dev" end)
    stub(Tuist.Environment, :email_icon_url, fn -> "https://tuist.dev/icon.png" end)
    stub(Tuist.Environment, :agent_auth_trusted_providers, fn -> [] end)
    stub(AgentAuth, :hit, fn _conn, _subject -> {:allow, 1} end)
    :ok
  end

  describe "GET /auth.md" do
    test "returns the auth.md document", %{conn: conn} do
      conn = get(conn, "/auth.md")

      body = response(conn, 200)

      assert get_resp_header(conn, "content-type") == ["text/markdown; charset=utf-8"]
      assert body =~ "# auth.md"
      assert body =~ "## Discover"
      assert body =~ "## Pick a method"
      assert body =~ "## Claim ceremony"
      assert body =~ "WWW-Authenticate: Bearer resource_metadata="
      assert body =~ "http://www.example.com/agent/auth"
      assert body =~ "https://tuist.dev/pricing"
      assert body =~ "mailto:contact@tuist.dev"
    end
  end

  describe "POST /agent/auth" do
    test "registers an email-required claim and sends the claim email", %{conn: conn} do
      email = AccountsFixtures.unique_user_email()

      conn =
        post(conn, "/agent/auth", %{
          "type" => "identity_assertion",
          "assertion_type" => "verified_email",
          "assertion" => String.upcase(email),
          "requested_credential_type" => "access_token"
        })

      response = json_response(conn, 200)

      assert response["registration_id"] =~ "reg_"
      assert response["registration_type"] == "email-verification"
      assert response["claim_url"] == "http://www.example.com/agent/auth/claim"
      assert response["claim_token"] =~ "clm_"
      assert response["post_claim_scopes"] == ["mcp"]

      assert_delivered_email_matches(%{
        to: [{_, ^email}],
        subject: "Your Tuist agent sign-in code",
        html_body: html_body
      })

      assert html_body =~ "/agent/auth/claim/view?token="
      refute html_body =~ response["claim_token"]
      refute html_body =~ "<div class=\"otp\">"

      assert %AgentRegistration{email: ^email, registration_ip: "127.0.0.1"} =
               Repo.get!(AgentRegistration, String.replace_prefix(response["registration_id"], "reg_", ""))
    end

    test "registers an anonymous API key and claims it later", %{conn: conn} do
      email = AccountsFixtures.unique_user_email()

      conn =
        post(conn, "/agent/auth", %{
          "type" => "anonymous",
          "requested_credential_type" => "api_key"
        })

      response = json_response(conn, 200)

      assert response["registration_type"] == "anonymous"
      assert response["credential_type"] == "api_key"
      assert response["credential"] =~ "tuist_"
      assert response["scopes"] == ["mcp"]
      assert response["claim_token"] =~ "clm_"

      claim_conn =
        post(build_conn(), "/agent/auth/claim", %{
          "claim_token" => response["claim_token"],
          "email" => email
        })

      assert json_response(claim_conn, 200)["status"] == "initiated"

      assert_delivered_email_matches(%{
        to: [{_, ^email}],
        subject: "Your Tuist agent sign-in code",
        html_body: html_body
      })

      claim_view_token = extract_claim_view_token(html_body)
      claim_view_conn = get(build_conn(), "/agent/auth/claim/view", %{"token" => claim_view_token})
      otp = claim_view_conn |> html_response(200) |> extract_otp()

      complete_conn =
        post(build_conn(), "/agent/auth/claim/complete", %{
          "claim_token" => response["claim_token"],
          "otp" => otp
        })

      assert json_response(complete_conn, 200) == %{
               "registration_id" => response["registration_id"],
               "status" => "claimed"
             }

      assert %AuthenticatedAccount{account: %{user_id: claimed_user_id}, scopes: ["mcp"]} =
               Authentication.authenticated_subject(response["credential"])

      {:ok, claimed_user} = Accounts.get_user_by_email(email)
      assert claimed_user_id == claimed_user.id
    end

    test "rejects anonymous access token registration", %{conn: conn} do
      conn = post(conn, "/agent/auth", %{"type" => "anonymous"})

      assert json_response(conn, 400) == %{
               "error" => "unsupported_credential_type",
               "message" => "Anonymous auth.md registrations require api_key."
             }
    end

    test "registers an agent-verified ID-JAG and returns an access token", %{conn: conn} do
      email = AccountsFixtures.unique_user_email()
      {provider, assertion} = id_jag(email, "jti-agent-verified")
      stub(Tuist.Environment, :agent_auth_trusted_providers, fn -> [provider] end)

      conn =
        post(conn, "/agent/auth", %{
          "type" => "identity_assertion",
          "assertion_type" => "urn:ietf:params:oauth:token-type:id-jag",
          "assertion" => assertion,
          "requested_credential_type" => "access_token"
        })

      response = json_response(conn, 200)

      assert response["registration_type"] == "agent-provider"
      assert response["credential_type"] == "access_token"
      assert response["scopes"] == ["mcp"]

      assert %AuthenticatedAccount{issued_by: %{email: ^email}} =
               Authentication.authenticated_subject(response["credential"])
    end

    test "rejects replayed ID-JAG assertions", %{conn: conn} do
      email = AccountsFixtures.unique_user_email()
      {provider, assertion} = id_jag(email, "jti-replayed")
      stub(Tuist.Environment, :agent_auth_trusted_providers, fn -> [provider] end)

      body = %{
        "type" => "identity_assertion",
        "assertion_type" => "urn:ietf:params:oauth:token-type:id-jag",
        "assertion" => assertion,
        "requested_credential_type" => "access_token"
      }

      assert conn |> post("/agent/auth", body) |> json_response(200)
      assert %{"error" => "replay_detected"} = build_conn() |> post("/agent/auth", body) |> json_response(409)
    end
  end

  describe "POST /agent/auth/claim" do
    test "re-sends the pending claim email", %{conn: conn} do
      email = AccountsFixtures.unique_user_email()
      %{claim_token: claim_token, claim_view_token: first_claim_view_token} = register_agent(email)

      conn =
        post(conn, "/agent/auth/claim", %{
          "claim_token" => claim_token,
          "email" => email
        })

      response = json_response(conn, 200)

      assert response["registration_id"] =~ "reg_"
      assert response["status"] == "initiated"
      assert is_binary(response["claim_attempt_id"])
      assert is_binary(response["expires_at"])

      assert_delivered_email_matches(%{
        to: [{_, ^email}],
        subject: "Your Tuist agent sign-in code",
        html_body: html_body
      })

      second_claim_view_token = extract_claim_view_token(html_body)
      assert second_claim_view_token != first_claim_view_token
    end
  end

  describe "claim completion" do
    test "renders the OTP page and exchanges the OTP for an access token", %{conn: conn} do
      email = AccountsFixtures.unique_user_email()
      %{claim_token: claim_token, claim_view_token: claim_view_token} = register_agent(email)

      claim_view_conn = get(conn, "/agent/auth/claim/view", %{"token" => claim_view_token})
      claim_view_body = html_response(claim_view_conn, 200)
      otp = extract_otp(claim_view_body)

      complete_conn = post(build_conn(), "/agent/auth/claim/complete", %{"claim_token" => claim_token, "otp" => otp})

      response = json_response(complete_conn, 200)

      assert response["registration_id"] =~ "reg_"
      assert response["status"] == "claimed"
      assert response["credential_type"] == "access_token"
      assert response["scopes"] == ["mcp"]
      assert is_binary(response["credential"])

      assert %AuthenticatedAccount{
               account: %{user_id: user_id},
               scopes: ["mcp"],
               all_projects: true,
               issued_by: %{id: issued_by_user_id, email: ^email}
             } = Authentication.authenticated_subject(response["credential"])

      assert user_id == issued_by_user_id
    end

    test "issues an access token that can initialize the MCP session", %{conn: conn} do
      email = AccountsFixtures.unique_user_email()
      %{claim_token: claim_token, claim_view_token: claim_view_token} = register_agent(email)
      stub(MCP, :hit, fn _conn -> {:allow, 1} end)

      claim_view_conn = get(conn, "/agent/auth/claim/view", %{"token" => claim_view_token})
      claim_view_body = html_response(claim_view_conn, 200)
      otp = extract_otp(claim_view_body)

      complete_conn = post(build_conn(), "/agent/auth/claim/complete", %{"claim_token" => claim_token, "otp" => otp})
      access_token = json_response(complete_conn, 200)["credential"]

      mcp_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{access_token}")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> put_req_header("content-type", "application/json")
        |> post(
          "/mcp",
          JSON.encode!(%{
            "jsonrpc" => "2.0",
            "id" => 1,
            "method" => "initialize",
            "params" => @initialize_params
          })
        )

      response = json_response(mcp_conn, 200)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert is_map(response["result"])
      assert is_binary(response["result"]["protocolVersion"])
      assert [session_id] = get_resp_header(mcp_conn, "mcp-session-id")
      assert is_binary(session_id)
    end
  end

  describe "POST /agent/auth/revoke" do
    test "revokes credentials issued for an agent-verified delegation", %{conn: conn} do
      email = AccountsFixtures.unique_user_email()
      {provider, assertion, jwk} = id_jag_with_jwk(email, "jti-to-revoke")
      stub(Tuist.Environment, :agent_auth_trusted_providers, fn -> [provider] end)

      register_conn =
        post(conn, "/agent/auth", %{
          "type" => "identity_assertion",
          "assertion_type" => "urn:ietf:params:oauth:token-type:id-jag",
          "assertion" => assertion,
          "requested_credential_type" => "access_token"
        })

      access_token = json_response(register_conn, 200)["credential"]
      assert %AuthenticatedAccount{} = Authentication.authenticated_subject(access_token)

      logout_token = logout_token(jwk, "jti-logout")

      revoke_conn =
        build_conn()
        |> put_req_header("content-type", "application/logout+jwt")
        |> post("/agent/auth/revoke", logout_token)

      assert json_response(revoke_conn, 200) == %{"revoked_count" => 1}
      assert Authentication.authenticated_subject(access_token) == nil
    end
  end

  defp register_agent(email) do
    {:ok, result} =
      Accounts.create_agent_registration(%{
        email: email,
        requested_credential_type: :access_token,
        claim_view_url: &"https://tuist.dev/agent/auth/claim/view?token=#{&1}",
        registration_ip: "127.0.0.1"
      })

    assert_delivered_email_matches(%{
      to: [{_, ^email}],
      subject: "Your Tuist agent sign-in code",
      html_body: html_body
    })

    %{
      claim_token: result.claim_token,
      claim_view_token: extract_claim_view_token(html_body)
    }
  end

  defp extract_claim_view_token(html_body) do
    [_, encoded_token] = Regex.run(~r{/agent/auth/claim/view\?token=([^"&]+)}, html_body)
    URI.decode_www_form(encoded_token)
  end

  defp extract_otp(html_body) do
    [_, otp] = Regex.run(~r/<div class="otp">(\d{6})<\/div>/, html_body)
    otp
  end

  defp id_jag(email, jti) do
    {provider, assertion, _jwk} = id_jag_with_jwk(email, jti)
    {provider, assertion}
  end

  defp id_jag_with_jwk(email, jti) do
    jwk = JOSE.JWK.generate_key({:rsa, 2048})
    {_, public_jwk} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    public_jwk = Map.put(public_jwk, "kid", "agent-auth-test-key")

    provider = %{
      "issuer" => "https://agent-provider.example.com",
      "jwks" => %{"keys" => [public_jwk]},
      "client_ids" => ["test-agent-client"]
    }

    {provider, sign_agent_auth_jwt(jwk, "oauth-id-jag+jwt", claims(email, jti)), jwk}
  end

  defp logout_token(jwk, jti) do
    sign_agent_auth_jwt(jwk, "logout+jwt", %{
      "iss" => "https://agent-provider.example.com",
      "sub" => "provider-user-1",
      "aud" => "http://www.example.com",
      "client_id" => "test-agent-client",
      "jti" => jti,
      "iat" => DateTime.to_unix(DateTime.utc_now()),
      "exp" => DateTime.utc_now() |> DateTime.add(300, :second) |> DateTime.to_unix(),
      "events" => %{
        "https://schemas.workos.com/events/agent/auth/identity/assertion/revoked" => %{}
      }
    })
  end

  defp claims(email, jti) do
    %{
      "iss" => "https://agent-provider.example.com",
      "sub" => "provider-user-1",
      "aud" => "http://www.example.com",
      "client_id" => "test-agent-client",
      "jti" => jti,
      "iat" => DateTime.to_unix(DateTime.utc_now()),
      "exp" => DateTime.utc_now() |> DateTime.add(300, :second) |> DateTime.to_unix(),
      "email" => email,
      "email_verified" => true
    }
  end

  defp sign_agent_auth_jwt(jwk, typ, claims) do
    jwt = JOSE.JWT.from_map(claims)
    jws = %{"alg" => "RS256", "kid" => "agent-auth-test-key", "typ" => typ}
    {_, token} = jwk |> JOSE.JWT.sign(jws, jwt) |> JOSE.JWS.compact()
    token
  end
end
