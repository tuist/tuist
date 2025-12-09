defmodule Tuist.OIDCTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.OIDC

  @jwks_uri "https://token.actions.githubusercontent.com/.well-known/jwks"
  @repository_claim "repository"

  setup do
    Cachex.clear(:tuist)
    :ok
  end

  describe "verify/3" do
    test "successfully verifies a valid OIDC token" do
      {token, jwks} = generate_test_token_and_jwks()

      stub(Req, :get, fn @jwks_uri ->
        {:ok, %{status: 200, body: jwks}}
      end)

      assert {:ok, claims} = OIDC.verify(token, @jwks_uri, @repository_claim)
      assert claims.repository == "tuist/tuist"
    end

    test "returns error for invalid token format" do
      assert {:error, :invalid_token} = OIDC.verify("not-a-valid-jwt", @jwks_uri, @repository_claim)
      assert {:error, :invalid_token} = OIDC.verify("", @jwks_uri, @repository_claim)
    end

    test "returns error for expired token" do
      {token, jwks} = generate_test_token_and_jwks(exp: DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_unix())

      stub(Req, :get, fn @jwks_uri ->
        {:ok, %{status: 200, body: jwks}}
      end)

      assert {:error, :token_expired} = OIDC.verify(token, @jwks_uri, @repository_claim)
    end

    test "returns error when JWKS fetch fails" do
      {token, _jwks} = generate_test_token_and_jwks()

      stub(Req, :get, fn @jwks_uri ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      assert {:error, :jwks_fetch_failed} = OIDC.verify(token, @jwks_uri, @repository_claim)
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

      stub(Req, :get, fn @jwks_uri ->
        {:ok, %{status: 200, body: different_jwks}}
      end)

      assert {:error, :invalid_signature} = OIDC.verify(token, @jwks_uri, @repository_claim)
    end

    test "extracts repository from custom claim name" do
      {token, jwks} = generate_test_token_and_jwks(repository_claim: "project_path", repository: "group/project")

      stub(Req, :get, fn "https://gitlab.com/jwks" ->
        {:ok, %{status: 200, body: jwks}}
      end)

      assert {:ok, claims} = OIDC.verify(token, "https://gitlab.com/jwks", "project_path")
      assert claims.repository == "group/project"
    end
  end

  defp generate_test_token_and_jwks(opts \\ []) do
    jwk = JOSE.JWK.generate_key({:rsa, 2048})
    repository_claim = Keyword.get(opts, :repository_claim, "repository")

    claims = %{
      "iss" => "https://token.actions.githubusercontent.com",
      "exp" => Keyword.get(opts, :exp, DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_unix()),
      repository_claim => Keyword.get(opts, :repository, "tuist/tuist")
    }

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
