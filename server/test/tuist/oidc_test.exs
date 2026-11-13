defmodule Tuist.OIDCTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.KeyValueStore
  alias Tuist.OIDC

  setup do
    stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)
    :ok
  end

  describe "claims/1" do
    test "successfully verifies a valid GitHub Actions OIDC token" do
      {token, jwks} = generate_test_token_and_jwks()

      stub(Req, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: jwks}}
      end)

      assert {:ok, claims} = OIDC.claims(token)
      assert claims.repository == "tuist/tuist"
    end

    test "returns error for GitHub Actions token with invalid audience" do
      {token, jwks} = generate_test_token_and_jwks(claims: %{"aud" => "other-service"})

      stub(Req, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: jwks}}
      end)

      assert {:error, :invalid_audience} = OIDC.claims(token)
    end

    test "returns error for invalid token format" do
      assert {:error, :invalid_token} = OIDC.claims("not-a-valid-jwt")
      assert {:error, :invalid_token} = OIDC.claims("")
    end

    test "returns error for expired token" do
      {token, jwks} =
        generate_test_token_and_jwks(exp: DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_unix())

      stub(Req, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: jwks}}
      end)

      assert {:error, :token_expired} = OIDC.claims(token)
    end

    test "returns error when JWKS fetch fails" do
      {token, _jwks} = generate_test_token_and_jwks()

      stub(Req, :get, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      assert {:error, :jwks_fetch_failed, _jwks_uri} = OIDC.claims(token)
    end

    test "returns error for invalid signature" do
      {token, _jwks} = generate_test_token_and_jwks()

      different_jwks = %{
        "keys" => [
          %{
            "kty" => "RSA",
            "use" => "sig",
            "alg" => "RS256",
            "kid" => "test-key-1",
            "n" => "xxxxxxxxxxxxxxxxxxxxxxxxxxx",
            "e" => "AQAB"
          }
        ]
      }

      stub(Req, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: different_jwks}}
      end)

      assert {:error, :invalid_signature} = OIDC.claims(token)
    end

    test "returns error for unsupported CI provider" do
      {token, _jwks} = generate_test_token_and_jwks(issuer: "https://gitlab.com")

      assert {:error, :oidc_account_required} = OIDC.claims(token)
    end

    test "successfully verifies a valid CircleCI OIDC token" do
      {token, jwks} =
        generate_test_token_and_jwks(
          issuer: "https://oidc.circleci.com/org/abc-123",
          claims: %{"oidc.circleci.com/vcs-origin" => "github.com/tuist/tuist"}
        )

      stub(Req, :get, fn url, _opts ->
        assert url == "https://oidc.circleci.com/org/abc-123/.well-known/jwks-pub.json"
        {:ok, %{status: 200, body: jwks}}
      end)

      assert {:ok, claims} = OIDC.claims(token)
      assert claims.repository == "tuist/tuist"
    end

    test "returns error for CircleCI token with non-GitHub repository" do
      {token, jwks} =
        generate_test_token_and_jwks(
          issuer: "https://oidc.circleci.com/org/abc-123",
          claims: %{"oidc.circleci.com/vcs-origin" => "bitbucket.org/tuist/tuist"}
        )

      stub(Req, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: jwks}}
      end)

      assert {:error, :missing_repository_claim} = OIDC.claims(token)
    end

    test "successfully verifies a valid Bitrise OIDC token" do
      {token, jwks} =
        generate_test_token_and_jwks(
          issuer: "https://token.builds.bitrise.io",
          claims: %{
            "repository_owner" => "tuist",
            "repository_slug" => "tuist",
            "repository_url" => "https://github.com/tuist/tuist"
          }
        )

      stub(Req, :get, fn url, _opts ->
        assert url == "https://token.builds.bitrise.io/.well-known/jwks"
        {:ok, %{status: 200, body: jwks}}
      end)

      assert {:ok, claims} = OIDC.claims(token)
      assert claims.repository == "tuist/tuist"
    end

    test "returns error for Bitrise token with non-GitHub repository" do
      {token, jwks} =
        generate_test_token_and_jwks(
          issuer: "https://token.builds.bitrise.io",
          claims: %{
            "repository_owner" => "tuist",
            "repository_slug" => "tuist",
            "repository_url" => "https://gitlab.com/tuist/tuist"
          }
        )

      stub(Req, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: jwks}}
      end)

      assert {:error, :missing_repository_claim} = OIDC.claims(token)
    end

    test "successfully verifies a GitHub Actions token from an enterprise-scoped issuer" do
      {token, jwks} =
        generate_test_token_and_jwks(issuer: "https://token.actions.githubusercontent.com/my-enterprise")

      stub(Req, :get, fn url, _opts ->
        assert url == "https://token.actions.githubusercontent.com/.well-known/jwks"
        {:ok, %{status: 200, body: jwks}}
      end)

      assert {:ok, claims} = OIDC.claims(token)
      assert claims.repository == "tuist/tuist"
    end

    test "returns error for an enterprise-scoped GitHub Actions token with invalid audience" do
      {token, jwks} =
        generate_test_token_and_jwks(
          issuer: "https://token.actions.githubusercontent.com/my-enterprise",
          claims: %{"aud" => "other-service"}
        )

      stub(Req, :get, fn _url, _opts ->
        {:ok, %{status: 200, body: jwks}}
      end)

      assert {:error, :invalid_audience} = OIDC.claims(token)
    end

    test "returns error for a GitHub Actions issuer with a multi-segment path" do
      {token, _jwks} =
        generate_test_token_and_jwks(issuer: "https://token.actions.githubusercontent.com/my-enterprise/evil")

      assert {:error, :unsupported_provider, "https://token.actions.githubusercontent.com/my-enterprise/evil"} =
               OIDC.claims(token)
    end
  end

  describe "github_actions_claims/2" do
    test "returns every claim of a GitHub Actions token minted for the audience" do
      {token, jwks} =
        generate_test_token_and_jwks(claims: %{"aud" => "tuist-runner-cache", "check_run_id" => "123"})

      stub(Req, :get, fn _url, _opts -> {:ok, %{status: 200, body: jwks}} end)

      assert {:ok, %{"check_run_id" => "123", "repository" => "tuist/tuist"}} =
               OIDC.github_actions_claims(token, "tuist-runner-cache")
    end

    test "rejects a token minted for another audience, including Tuist login" do
      {token, jwks} = generate_test_token_and_jwks()
      stub(Req, :get, fn _url, _opts -> {:ok, %{status: 200, body: jwks}} end)

      assert {:error, :invalid_audience} = OIDC.github_actions_claims(token, "tuist-runner-cache")
    end

    test "rejects tokens of other providers" do
      {token, _jwks} =
        generate_test_token_and_jwks(issuer: "https://token.builds.bitrise.io", claims: %{"aud" => "tuist-runner-cache"})

      assert {:error, :unsupported_provider} = OIDC.github_actions_claims(token, "tuist-runner-cache")
      assert {:error, :unsupported_provider} = OIDC.github_actions_claims(gitlab_token(), "tuist-runner-cache")
    end

    test "rejects expired tokens and malformed input" do
      {token, jwks} =
        generate_test_token_and_jwks(
          exp: DateTime.utc_now() |> DateTime.add(-60) |> DateTime.to_unix(),
          claims: %{"aud" => "tuist-runner-cache"}
        )

      stub(Req, :get, fn _url, _opts -> {:ok, %{status: 200, body: jwks}} end)

      assert {:error, :token_expired} = OIDC.github_actions_claims(token, "tuist-runner-cache")
      assert {:error, :invalid_token} = OIDC.github_actions_claims("not-a-jwt", "tuist-runner-cache")
      assert {:error, :invalid_token} = OIDC.github_actions_claims(nil, "tuist-runner-cache")
    end
  end

  describe "amp_creator/2" do
    test "verifies the creator, not the operator, against Amp's fixed issuer and keys" do
      claims = amp_creator_claims()
      {token, jwks} = generate_test_token_and_jwks(claims: claims)

      stub(Req, :get, fn url, _ ->
        assert url == "https://ampcode.com/api/workload-identity/jwks.json"
        {:ok, %{status: 200, body: jwks}}
      end)

      assert {:ok, %{user_id: "user_creator", thread_id: thread_id, name: "amp-creator"}} =
               OIDC.amp_creator(token, "https://tuist.dev")

      assert thread_id == claims["thread_id"]
    end

    test "uses today's email-only creator claims without requiring an Amp username" do
      base =
        amp_creator_claims()
        |> Map.delete("preferred_username")
        |> Map.merge(%{"email" => "creator@example.com", "email_verified" => true})

      for {claims, label, username} <- [
            {base, "creator@example.com", nil},
            {Map.put(base, "preferred_username", "amp-handle"), "amp-handle", "amp-handle"},
            {Map.put(base, "preferred_username", ""), "creator@example.com", nil}
          ] do
        {token, jwks} = generate_test_token_and_jwks(claims: claims)
        stub(Req, :get, fn _, _ -> {:ok, %{status: 200, body: jwks}} end)

        assert {:ok, %{user_id: "user_creator", name: ^label, username: ^username, email: "creator@example.com"}} =
                 OIDC.amp_creator(token, "https://tuist.dev")
      end
    end

    test "does not extract unverified emails or infer emails from display labels" do
      base =
        amp_creator_claims()
        |> Map.delete("preferred_username")
        |> Map.put("email", "creator@example.com")

      for verified <- [nil, false, "true", 1] do
        claims = Map.put(base, "email_verified", verified)
        {token, jwks} = generate_test_token_and_jwks(claims: claims)
        stub(Req, :get, fn _, _ -> {:ok, %{status: 200, body: jwks}} end)

        assert {:ok, %{name: "creator@example.com", email: nil}} = OIDC.amp_creator(token, "https://tuist.dev")
      end

      claims = %{"name" => "creator@example.com", "email_verified" => true}
      {token, jwks} = generate_test_token_and_jwks(claims: Map.merge(amp_creator_claims(), claims))
      stub(Req, :get, fn _, _ -> {:ok, %{status: 200, body: jwks}} end)
      assert {:ok, %{email: nil}} = OIDC.amp_creator(token, "https://tuist.dev")
    end

    test "extracts only bounded valid email strings" do
      longest_email = String.duplicate("a", 242) <> "@example.com"

      for {email, expected} <- [
            {longest_email, longest_email},
            {longest_email <> "m", nil},
            {"not-an-email", nil},
            {"", nil},
            {nil, nil},
            {42, nil},
            {["creator@example.com"], nil}
          ] do
        claims = Map.merge(amp_creator_claims(), %{"email" => email, "email_verified" => true})
        {token, jwks} = generate_test_token_and_jwks(claims: claims)
        stub(Req, :get, fn _, _ -> {:ok, %{status: 200, body: jwks}} end)

        assert {:ok, %{email: ^expected}} = OIDC.amp_creator(token, "https://tuist.dev")
      end
    end

    test "rejects wrong issuer, audience, subject, scope, expiry, and setup tokens" do
      base = amp_creator_claims()

      for override <- [
            %{"iss" => "https://attacker.example"},
            %{"aud" => "another-audience"},
            %{"sub" => "user:someone-else:thread:#{base["thread_id"]}"},
            %{"sub" => "user:user_creator"},
            %{"sub" => nil, "workspace_id" => "invalid"},
            %{"workspace_id" => "invalid"},
            %{"project_id" => "invalid"},
            %{"thread_id" => nil},
            %{"user_id" => nil},
            %{"token_use" => "request"},
            %{"exp" => System.os_time(:second) - 10},
            %{"nbf" => System.os_time(:second) + 3600}
          ] do
        {token, jwks} = generate_test_token_and_jwks(claims: Map.merge(base, override))
        stub(Req, :get, fn _, _ -> {:ok, %{status: 200, body: jwks}} end)
        assert {:error, :invalid_token} = OIDC.amp_creator(token, "https://tuist.dev")
      end

      assert {:error, :invalid_token} = OIDC.amp_creator("malformed", "https://tuist.dev")
    end

    test "supports workspace creators and rejects mismatched workspace or project subjects" do
      workspace = Ecto.UUID.generate()
      project = Ecto.UUID.generate()
      base = amp_creator_claims()

      claims =
        Map.merge(base, %{
          "workspace_id" => workspace,
          "project_id" => project,
          "sub" => "workspace:#{workspace}:project:#{project}:user:user_creator:thread:#{base["thread_id"]}"
        })

      {token, jwks} = generate_test_token_and_jwks(claims: claims)
      stub(Req, :get, fn _, _ -> {:ok, %{status: 200, body: jwks}} end)
      assert {:ok, %{user_id: "user_creator"}} = OIDC.amp_creator(token, "https://tuist.dev")

      for key <- ["workspace_id", "project_id"] do
        {token, jwks} = generate_test_token_and_jwks(claims: Map.put(claims, key, Ecto.UUID.generate()))
        stub(Req, :get, fn _, _ -> {:ok, %{status: 200, body: jwks}} end)
        assert {:error, :invalid_token} = OIDC.amp_creator(token, "https://tuist.dev")
      end
    end

    test "checks the signature and falls back to the stable ID without a display claim" do
      claims = Map.delete(amp_creator_claims(), "preferred_username")
      {token, jwks} = generate_test_token_and_jwks(claims: claims)
      stub(Req, :get, fn _, _ -> {:ok, %{status: 200, body: jwks}} end)
      assert {:ok, %{name: "user_creator", username: nil}} = OIDC.amp_creator(token, "https://tuist.dev")

      {_, other_keys} = generate_test_token_and_jwks()
      stub(Req, :get, fn _, _ -> {:ok, %{status: 200, body: other_keys}} end)
      assert {:error, :invalid_token} = OIDC.amp_creator(token, "https://tuist.dev")
    end
  end

  defp amp_creator_claims do
    thread_id = "T-" <> Ecto.UUID.generate()

    %{
      "iss" => "https://ampcode.com/api/workload-identity",
      "aud" => "https://tuist.dev",
      "token_use" => "exchanged",
      "user_id" => "user_creator",
      "thread_id" => thread_id,
      "sub" => "user:user_creator:thread:#{thread_id}",
      "preferred_username" => "amp-creator"
    }
  end

  defp gitlab_token do
    {token, _jwks} = generate_test_token_and_jwks(issuer: "https://gitlab.com", claims: %{"aud" => "tuist-runner-cache"})
    token
  end

  defp generate_test_token_and_jwks(opts \\ []) do
    jwk = JOSE.JWK.generate_key({:rsa, 2048})

    base_claims = %{
      "iss" => Keyword.get(opts, :issuer, "https://token.actions.githubusercontent.com"),
      "exp" => Keyword.get(opts, :exp, DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_unix()),
      "aud" => "tuist",
      "repository" => Keyword.get(opts, :repository, "tuist/tuist")
    }

    additional_claims = Keyword.get(opts, :claims, %{})
    claims = Map.merge(base_claims, additional_claims)

    jws = %{"alg" => "RS256", "kid" => "test-key-1"}
    jwt = JOSE.JWT.from_map(claims)
    {_, token} = jwk |> JOSE.JWT.sign(jws, jwt) |> JOSE.JWS.compact()

    {_, public_jwk_map} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()

    jwks = %{
      "keys" => [
        public_jwk_map
        |> Map.put("use", "sig")
        |> Map.put("alg", "RS256")
        |> Map.put("kid", "test-key-1")
      ]
    }

    {token, jwks}
  end
end
