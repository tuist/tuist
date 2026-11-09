defmodule Tuist.Sandboxes.Anthropic.FederationTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Sandboxes.Anthropic.Federation

  @federation_ids [
    anthropic_organization_id: "00000000-0000-4000-8000-000000000001",
    anthropic_workspace_id: "wrkspc_01Abc",
    anthropic_service_account_id: "svac_01Abc",
    anthropic_federation_rule_id: "fdrl_01Abc"
  ]

  defp federated_environment(opts \\ []) do
    agent_environment_fixture(Keyword.merge(@federation_ids, opts))
  end

  defp verify(token) do
    keys = Enum.map(Federation.jwks()["keys"], &JOSE.JWK.from_map/1)

    Enum.find_value(keys, {:error, :unverified}, fn key ->
      case JOSE.JWT.verify_strict(key, ["ES256"], token) do
        {true, %JOSE.JWT{fields: claims}, _jws} ->
          {:ok, token |> JOSE.JWT.peek_protected() |> JOSE.JWS.to_map() |> elem(1), claims}

        _ ->
          nil
      end
    end)
  end

  defp decode_claims(token) do
    %JOSE.JWT{fields: claims} = JOSE.JWT.peek_payload(token)
    claims
  end

  describe "sign/1" do
    test "signs a token the published JWKS verifies, for the environment's own account" do
      agent_environment = federated_environment()

      assert {:ok, token} = Federation.sign(agent_environment)
      assert {:ok, header, claims} = verify(token)

      [published_key] = Federation.jwks()["keys"]
      assert header["kid"] == published_key["kid"]
      assert header["alg"] == "ES256"
      refute Map.has_key?(published_key, "d")

      assert claims["iss"] =~ ~r{^https?://[^/]+/oidc/accounts/#{agent_environment.account_id}$}
      assert claims["sub"] == "account:#{agent_environment.account_id}:agent-environment:#{agent_environment.id}"
      assert claims["aud"] == "https://api.anthropic.com"
      assert claims["exp"] - claims["iat"] == 300
    end

    test "gives every token its own jti" do
      agent_environment = federated_environment()

      {:ok, first} = Federation.sign(agent_environment)
      {:ok, second} = Federation.sign(agent_environment)

      assert decode_claims(first)["jti"] != decode_claims(second)["jti"]
    end

    test "the key is separate from the auth.md assertion key" do
      [federation_key] = Federation.jwks()["keys"]
      [agent_auth_key] = Tuist.Accounts.AgentAuthSigningKey.jwks()["keys"]

      assert federation_key["kid"] != agent_auth_key["kid"]
    end
  end

  describe "openid_configuration/1" do
    test "names the account's issuer and its JWKS" do
      configuration = Federation.openid_configuration(42)

      assert configuration["issuer"] == Federation.issuer(42)
      assert configuration["jwks_uri"] == Federation.issuer(42) <> "/jwks.json"
      assert configuration["id_token_signing_alg_values_supported"] == ["ES256"]
      refute Federation.issuer(42) == Federation.issuer(43)
    end
  end

  describe "credential/1" do
    test "exchanges a signed token with the environment's ids and caches the result until near expiry" do
      agent_environment = federated_environment()
      now = ~U[2026-11-06 12:00:00Z]
      test_pid = self()

      stub(Tuist.Time, :utc_now, fn -> now end)

      expect(Req, :post, fn url, opts ->
        assert url == "https://api.anthropic.com/v1/oauth/token"
        body = opts[:json]
        send(test_pid, {:assertion, body.assertion})

        assert body.grant_type == "urn:ietf:params:oauth:grant-type:jwt-bearer"
        assert body.organization_id == "00000000-0000-4000-8000-000000000001"
        assert body.workspace_id == "wrkspc_01Abc"
        assert body.service_account_id == "svac_01Abc"
        assert body.federation_rule_id == "fdrl_01Abc"

        {:ok, %Req.Response{status: 200, body: %{"access_token" => "sk-ant-oat01-first", "expires_in" => 600}}}
      end)

      assert {:ok, "sk-ant-oat01-first"} = Federation.credential(agent_environment)
      assert_received {:assertion, first_assertion}
      assert {:ok, _header, %{"sub" => "account:" <> _}} = verify(first_assertion)

      # 7 minutes in, the 10-minute token still has 3 minutes left: cached.
      stub(Tuist.Time, :utc_now, fn -> DateTime.add(now, 7 * 60, :second) end)
      assert {:ok, "sk-ant-oat01-first"} = Federation.credential(agent_environment)

      # Inside the last 2 minutes, a new token is exchanged with a new JWT.
      stub(Tuist.Time, :utc_now, fn -> DateTime.add(now, 8 * 60 + 1, :second) end)

      expect(Req, :post, fn _url, opts ->
        send(test_pid, {:assertion, opts[:json].assertion})
        {:ok, %Req.Response{status: 200, body: %{"access_token" => "sk-ant-oat01-second", "expires_in" => 600}}}
      end)

      assert {:ok, "sk-ant-oat01-second"} = Federation.credential(agent_environment)
      assert_received {:assertion, second_assertion}
      assert decode_claims(first_assertion)["jti"] != decode_claims(second_assertion)["jti"]
    end

    test "turns a rejected exchange into a federation error and caches nothing" do
      agent_environment = federated_environment()

      expect(Req, :post, 2, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 401,
           body: %{
             "type" => "error",
             "error" => %{"type" => "authentication_error", "message" => "Authentication failed"}
           }
         }}
      end)

      assert {:error, {:federation_rejected, %{status: 401, message: "Authentication failed"}}} =
               Federation.credential(agent_environment)

      assert {:error, {:federation_rejected, _}} = Federation.credential(agent_environment)
    end
  end
end
