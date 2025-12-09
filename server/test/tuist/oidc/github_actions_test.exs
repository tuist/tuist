defmodule Tuist.OIDC.GitHubActionsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.OIDC.GitHubActions

  setup do
    # Clear the JWKS cache before each test
    Cachex.clear(:tuist)
    :ok
  end

  describe "verify/1" do
    test "successfully verifies a valid GitHub Actions OIDC token" do
      {token, jwks} = generate_test_token_and_jwks()

      stub(Req, :get, fn url ->
        if String.contains?(url, "token.actions.githubusercontent.com") do
          {:ok, %{status: 200, body: jwks}}
        else
          {:error, :not_found}
        end
      end)

      assert {:ok, claims} = GitHubActions.verify(token)
      assert claims.repository == "tuist/tuist"
      assert claims.repository_owner == "tuist"
      assert claims.ref == "refs/heads/main"
    end

    test "returns error for invalid token format" do
      assert {:error, :invalid_token} = GitHubActions.verify("not-a-valid-jwt")
      assert {:error, :invalid_token} = GitHubActions.verify("")
      assert {:error, :invalid_token} = GitHubActions.verify(nil)
    end

    test "returns error for wrong issuer" do
      {token, jwks} = generate_test_token_and_jwks(issuer: "https://wrong-issuer.com")

      stub(Req, :get, fn _url ->
        {:ok, %{status: 200, body: jwks}}
      end)

      assert {:error, :invalid_issuer} = GitHubActions.verify(token)
    end

    test "returns error for expired token" do
      {token, jwks} = generate_test_token_and_jwks(exp: DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_unix())

      stub(Req, :get, fn _url ->
        {:ok, %{status: 200, body: jwks}}
      end)

      assert {:error, :token_expired} = GitHubActions.verify(token)
    end

    test "returns error for missing repository claim" do
      {token, jwks} = generate_test_token_and_jwks(repository: nil)

      stub(Req, :get, fn _url ->
        {:ok, %{status: 200, body: jwks}}
      end)

      assert {:error, :missing_repository_claim} = GitHubActions.verify(token)
    end

    test "returns error when JWKS fetch fails" do
      {token, _jwks} = generate_test_token_and_jwks()

      stub(Req, :get, fn _url ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      assert {:error, :jwks_fetch_failed} = GitHubActions.verify(token)
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

      assert {:error, :invalid_signature} = GitHubActions.verify(token)
    end
  end

  describe "issuer/0" do
    test "returns the GitHub Actions OIDC issuer URL" do
      assert GitHubActions.issuer() == "https://token.actions.githubusercontent.com"
    end
  end

  defp generate_test_token_and_jwks(opts \\ []) do
    jwk = JOSE.JWK.generate_key({:rsa, 2048})

    claims =
      %{
        "iss" => Keyword.get(opts, :issuer, "https://token.actions.githubusercontent.com"),
        "sub" => "repo:tuist/tuist:ref:refs/heads/main",
        "aud" => "tuist",
        "exp" => Keyword.get(opts, :exp, DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_unix()),
        "iat" => DateTime.utc_now() |> DateTime.to_unix(),
        "repository" => Keyword.get(opts, :repository, "tuist/tuist"),
        "repository_owner" => "tuist",
        "ref" => "refs/heads/main",
        "workflow" => "CI",
        "actor" => "test-user",
        "run_id" => "123456789"
      }
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

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
