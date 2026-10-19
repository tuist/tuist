defmodule Tuist.OIDCTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.KeyValueStore
  alias Tuist.OIDC
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.ProjectsFixtures

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

      assert {:error, :unsupported_provider, "https://gitlab.com"} = OIDC.claims(token)
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

  describe "Fly.io workload identities" do
    setup do
      project = ProjectsFixtures.project_fixture()

      {:ok, _} =
        Projects.create_fly_oidc_trust_policy(project, %{
          issuer: "https://oidc.fly.io/example-org",
          organization_id: "123",
          application_id: "456"
        })

      :ok
    end

    test "unconfigured Fly identities cause no outbound JWKS fetch or cache entry" do
      reject(Req, :get, 2)
      reject(KeyValueStore, :get_or_update, 3)
      {token, _} = fly_token(%{"app_id" => "999"})
      assert {:error, :invalid_signature} = OIDC.claims(token)
    end

    test "allows at most sixty seconds of signer clock skew" do
      now = DateTime.to_unix(DateTime.utc_now())
      {token, jwks} = fly_token(%{"nbf" => now + 60})
      stub(Req, :get, fn _, _ -> {:ok, %{status: 200, body: jwks}} end)
      stub(DateTime, :utc_now, fn -> DateTime.from_unix!(now) end)
      assert {:ok, %{provider: :fly}} = OIDC.claims(token)
      {future_token, future_jwks} = fly_token(%{"nbf" => now + 61})
      stub(Req, :get, fn _, _ -> {:ok, %{status: 200, body: future_jwks}} end)
      assert {:error, :token_not_yet_valid} = OIDC.claims(future_token)
    end

    test "verifies the organization-specific issuer and returns stable workload IDs, not a repository" do
      {token, jwks} = fly_token()

      expect(Req, :get, fn url, opts ->
        assert url == "https://oidc.fly.io/example-org/.well-known/jwks"
        assert opts[:redirect] == false
        {:ok, %{status: 200, body: jwks}}
      end)

      assert {:ok,
              %{
                provider: :fly,
                issuer: "https://oidc.fly.io/example-org",
                organization_id: "123",
                application_id: "456"
              } = identity} = OIDC.claims(token)

      refute Map.has_key?(identity, :repository)
    end

    test "accepts an audience array containing tuist" do
      {token, jwks} = fly_token(%{"aud" => ["another-service", "tuist"]})
      stub(Req, :get, fn _, _ -> {:ok, %{status: 200, body: jwks}} end)
      assert {:ok, %{provider: :fly}} = OIDC.claims(token)
    end

    for {claim, value, error} <- [
          {"aud", "other-service", :invalid_audience},
          {"aud", nil, :invalid_audience},
          {"aud", ["other-service"], :invalid_audience},
          {"org_id", nil, :missing_workload_claim},
          {"org_id", "", :missing_workload_claim},
          {"org_id", 123, :missing_workload_claim},
          {"app_id", nil, :missing_workload_claim},
          {"app_id", "", :missing_workload_claim},
          {"app_id", "*", :missing_workload_claim},
          {"exp", 0, :token_expired},
          {"nbf", 99_999_999_999, :token_not_yet_valid},
          {"nbf", "invalid", :invalid_token}
        ] do
      test "rejects #{claim}=#{inspect(value)}" do
        {token, jwks} = fly_token(%{unquote(claim) => unquote(Macro.escape(value))})
        stub(Req, :get, fn _, _ -> {:ok, %{status: 200, body: jwks}} end)
        assert {:error, unquote(error)} = OIDC.claims(token)
      end
    end

    test "rejects untrusted issuer URLs without making a network request" do
      reject(Req, :get, 2)

      for issuer <- [
            "https://oidc.fly.io/",
            "https://oidc.fly.io/example-org/extra",
            "https://oidc.fly.io/../internal",
            "https://oidc.fly.io/example-org?redirect=evil",
            "https://oidc.fly.io/example-org#fragment",
            "https://oidc.fly.io.evil.com/example-org",
            "http://oidc.fly.io/example-org"
          ] do
        {token, _} = generate_test_token_and_jwks(issuer: issuer)
        assert {:error, :unsupported_provider, ^issuer} = OIDC.claims(token)
      end
    end

    test "rejects a Fly token signed by a different key" do
      {token, _} = fly_token()
      {_, jwks} = fly_token()
      stub(Req, :get, fn _, _ -> {:ok, %{status: 200, body: jwks}} end)
      assert {:error, :invalid_signature} = OIDC.claims(token)
    end
  end

  defp fly_token(claims \\ %{}) do
    generate_test_token_and_jwks(
      issuer: "https://oidc.fly.io/example-org",
      claims: Map.merge(%{"org_id" => "123", "app_id" => "456", "nbf" => 0}, claims)
    )
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
