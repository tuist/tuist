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

      stub(Req, :get, fn _url ->
        {:ok, %{status: 200, body: jwks}}
      end)

      assert {:ok, claims} = OIDC.claims(token)
      assert claims.repository == "tuist/tuist"
    end

    test "returns error for invalid token format" do
      assert {:error, :invalid_token} = OIDC.claims("not-a-valid-jwt")
      assert {:error, :invalid_token} = OIDC.claims("")
    end

    test "returns error for expired token" do
      {token, jwks} =
        generate_test_token_and_jwks(exp: DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_unix())

      stub(Req, :get, fn _url ->
        {:ok, %{status: 200, body: jwks}}
      end)

      assert {:error, :token_expired} = OIDC.claims(token)
    end

    test "returns error when JWKS fetch fails" do
      {token, _jwks} = generate_test_token_and_jwks()

      stub(Req, :get, fn _url ->
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

      stub(Req, :get, fn _url ->
        {:ok, %{status: 200, body: different_jwks}}
      end)

      assert {:error, :invalid_signature} = OIDC.claims(token)
    end

    test "returns error for unsupported CI provider" do
      {token, _jwks} = generate_test_token_and_jwks(issuer: "https://gitlab.com")

      assert {:error, :unsupported_provider, "https://gitlab.com"} = OIDC.claims(token)
    end

    test "successfully verifies a valid CircleCI OIDC token" do
      {token, jwks} =
        generate_test_token_and_jwks(
          issuer: "https://oidc.circleci.com/org/abc-123",
          claims: %{"oidc.circleci.com/vcs-origin" => "github.com/tuist/tuist"}
        )

      stub(Req, :get, fn url ->
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

      stub(Req, :get, fn _url ->
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

      stub(Req, :get, fn url ->
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

      stub(Req, :get, fn _url ->
        {:ok, %{status: 200, body: jwks}}
      end)

      assert {:error, :missing_repository_claim} = OIDC.claims(token)
    end
  end

  defp generate_test_token_and_jwks(opts \\ []) do
    jwk = JOSE.JWK.generate_key({:rsa, 2048})

    base_claims = %{
      "iss" => Keyword.get(opts, :issuer, "https://token.actions.githubusercontent.com"),
      "exp" => Keyword.get(opts, :exp, DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_unix()),
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
