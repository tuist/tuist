defmodule Tuist.Runners.CacheTokenTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Runners.CacheToken

  setup :verify_on_exit!

  defp candidate(overrides \\ %{}) do
    Map.merge(
      %{
        workflow_job_id: 42,
        repository: "tuist/tuist",
        fleet_name: "tuist-runners",
        head_branch: "main",
        head_sha: "abc123",
        default_branch: "main",
        base_ref: "",
        untrusted_fork: 0
      },
      overrides
    )
  end

  defp account, do: %{id: 1111, name: "tuist"}

  defp ed25519_pem do
    {_, pem} =
      {:okp, :Ed25519}
      |> JOSE.JWK.generate_key()
      |> JOSE.JWK.to_pem()

    pem
  end

  describe "claims/3" do
    test "builds scoped claims with normalized refs" do
      claims = CacheToken.claims(candidate(), account(), :linux)

      assert claims["account_id"] == 1111
      assert claims["account"] == "tuist"
      assert claims["repo"] == "tuist/tuist"
      assert claims["fleet"] == "tuist-runners"
      assert claims["os"] == "linux"
      assert claims["ref"] == "refs/heads/main"
      assert claims["default_branch"] == "refs/heads/main"
      assert claims["base_ref"] == ""
      assert claims["untrusted_fork"] == false
      assert claims["sub"] == "42"
      assert claims["exp"] == claims["iat"] + 600
    end

    test "marks untrusted forks and carries the PR base ref" do
      claims =
        CacheToken.claims(candidate(%{base_ref: "develop", untrusted_fork: 1}), account(), :macos)

      assert claims["os"] == "macos"
      assert claims["base_ref"] == "refs/heads/develop"
      assert claims["untrusted_fork"] == true
    end
  end

  describe "mint/3" do
    test "signs an EdDSA token verifiable with the public key" do
      pem = ed25519_pem()
      stub(Environment, :cache_token_signing_key, fn -> pem end)
      stub(Environment, :app_url, fn -> "https://tuist.dev" end)

      assert {:ok, token} = CacheToken.mint(candidate(), account(), :linux)

      # The asymmetric contract: a holder of ONLY the public key can verify.
      pub = pem |> JOSE.JWK.from_pem() |> JOSE.JWK.to_public()
      assert {true, jwt, _jws} = JOSE.JWT.verify_strict(pub, ["EdDSA"], token)
      assert jwt.fields["account_id"] == 1111
      assert jwt.fields["ref"] == "refs/heads/main"
    end

    test "uses the EdDSA algorithm in the JWS header" do
      pem = ed25519_pem()
      stub(Environment, :cache_token_signing_key, fn -> pem end)
      stub(Environment, :app_url, fn -> "https://tuist.dev" end)

      {:ok, token} = CacheToken.mint(candidate(), account(), :linux)
      [header_b64 | _] = String.split(token, ".")
      header = header_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!()
      assert header["alg"] == "EdDSA"
    end

    test "returns {:error, :disabled} when no signing key is configured" do
      stub(Environment, :cache_token_signing_key, fn -> nil end)
      assert {:error, :disabled} = CacheToken.mint(candidate(), account(), :linux)
    end
  end

  describe "enabled?/0" do
    test "true only when a signing key is configured" do
      stub(Environment, :cache_token_signing_key, fn -> "pem" end)
      assert CacheToken.enabled?()

      stub(Environment, :cache_token_signing_key, fn -> nil end)
      refute CacheToken.enabled?()
    end
  end
end
