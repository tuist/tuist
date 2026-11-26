defmodule Tuist.OAuth2.SSOClientAssertionTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.OAuth2.SSOClientAssertion

  @okta_token_url "https://example.okta.com/oauth2/v1/token"
  @entra_token_url "https://login.microsoftonline.com/contoso.onmicrosoft.com/oauth2/v2.0/token"

  setup do
    signing_key = X509.PrivateKey.new_rsa(2048)
    next_key = X509.PrivateKey.new_rsa(2048)
    %{signing_key: signing_key, next_key: next_key}
  end

  describe "sign/2" do
    test "signs an RS256 assertion that verifies against the published JWKS", %{signing_key: signing_key} do
      configure_keys([signing_key])

      assert {:ok, assertion} = SSOClientAssertion.sign("client-123", @okta_token_url)

      [jwk_map] = SSOClientAssertion.jwks()["keys"]
      refute Map.has_key?(jwk_map, "d")

      assert {true, %JOSE.JWT{fields: claims}, %JOSE.JWS{fields: header}} =
               JOSE.JWT.verify_strict(JOSE.JWK.from_map(jwk_map), ["RS256"], assertion)

      assert header["kid"] == jwk_map["kid"]
      assert header["x5t#S256"] == jwk_map["x5t#S256"]
      assert claims["iss"] == "client-123"
      assert claims["sub"] == "client-123"
      assert claims["aud"] == @okta_token_url
      assert claims["exp"] - claims["iat"] == 300
      assert is_binary(claims["jti"])
    end

    test "never reuses a jti, since providers reject a replayed assertion", %{signing_key: signing_key} do
      configure_keys([signing_key])

      {:ok, first} = SSOClientAssertion.sign("client-123", @okta_token_url)
      {:ok, second} = SSOClientAssertion.sign("client-123", @okta_token_url)

      assert JOSE.JWT.peek_payload(first).fields["jti"] != JOSE.JWT.peek_payload(second).fields["jti"]
    end

    test "signs PS256 for Entra ID token endpoints", %{signing_key: signing_key} do
      configure_keys([signing_key])

      assert {:ok, assertion} = SSOClientAssertion.sign("client-123", @entra_token_url)

      jwk = JOSE.JWK.from_map(hd(SSOClientAssertion.jwks()["keys"]))
      assert {true, _, _} = JOSE.JWT.verify_strict(jwk, ["PS256"], assertion)
      assert {false, _, _} = JOSE.JWT.verify_strict(jwk, ["RS256"], assertion)

      # RFC 7518 requires a 32-byte PSS salt; strict verifiers reject any other.
      [encoded_header, encoded_claims, encoded_signature] = String.split(assertion, ".")

      assert :public_key.verify(
               encoded_header <> "." <> encoded_claims,
               :sha256,
               Base.url_decode64!(encoded_signature, padding: false),
               X509.PublicKey.derive(signing_key),
               rsa_padding: :rsa_pkcs1_pss_padding,
               rsa_pss_saltlen: 32
             )
    end

    test "returns an error when no keys are configured" do
      stub(Environment, :sso_client_assertion_private_keys, fn -> nil end)

      refute SSOClientAssertion.available?()
      assert {:error, :sso_client_assertion_not_configured} = SSOClientAssertion.sign("client-123", @okta_token_url)
      assert SSOClientAssertion.jwks() == %{"keys" => []}
    end
  end

  describe "rotation" do
    test "publishes every configured key and signs with the first", %{signing_key: signing_key, next_key: next_key} do
      configure_keys([signing_key, next_key])

      assert [signing_jwk, next_jwk] = SSOClientAssertion.jwks()["keys"]
      assert signing_jwk["kid"] != next_jwk["kid"]

      {:ok, assertion} = SSOClientAssertion.sign("client-123", @okta_token_url)

      assert {true, _, _} = JOSE.JWT.verify_strict(JOSE.JWK.from_map(signing_jwk), ["RS256"], assertion)
      assert {false, _, _} = JOSE.JWT.verify_strict(JOSE.JWK.from_map(next_jwk), ["RS256"], assertion)
    end

    test "keeps a key's kid and certificate when it moves within the bundle",
         %{signing_key: signing_key, next_key: next_key} do
      configure_keys([signing_key, next_key])
      before_rotation = Map.new(SSOClientAssertion.jwks()["keys"], &{&1["kid"], &1})

      configure_keys([next_key, signing_key])
      after_rotation = Map.new(SSOClientAssertion.jwks()["keys"], &{&1["kid"], &1})

      assert before_rotation == after_rotation
    end
  end

  describe "certificate_pem/1" do
    test "serves the same certificate for the same key on every node", %{signing_key: signing_key} do
      # The PKCS#8 encoding of the same key is a different bundle, so this
      # derives the certificate again instead of reading the memoized one.
      configure_keys([signing_key])
      [kid] = SSOClientAssertion.key_ids()
      {:ok, pem} = SSOClientAssertion.certificate_pem(kid)

      stub(Environment, :sso_client_assertion_private_keys, fn ->
        X509.PrivateKey.to_pem(signing_key, wrap: true)
      end)

      assert {:ok, ^pem} = SSOClientAssertion.certificate_pem(kid)
    end

    test "returns a certificate for the published key that Entra's x5t#S256 matches", %{signing_key: signing_key} do
      configure_keys([signing_key])
      [jwk_map] = SSOClientAssertion.jwks()["keys"]

      {:ok, pem} = SSOClientAssertion.certificate_pem(jwk_map["kid"])
      certificate = X509.Certificate.from_pem!(pem)
      der = X509.Certificate.to_der(certificate)

      assert X509.Certificate.public_key(certificate) == X509.PublicKey.derive(signing_key)
      assert Base.url_encode64(:crypto.hash(:sha256, der), padding: false) == jwk_map["x5t#S256"]
      assert jwk_map["x5c"] == [Base.encode64(der)]
    end

    test "returns not found for an unknown key ID", %{signing_key: signing_key} do
      configure_keys([signing_key])

      assert {:error, :not_found} = SSOClientAssertion.certificate_pem("unknown")
    end
  end

  test "leaves the feature unavailable, without raising or logging key material, when the keys cannot be used" do
    rsa_pem = 2048 |> X509.PrivateKey.new_rsa() |> X509.PrivateKey.to_pem()
    [_, rsa_body | _] = String.split(rsa_pem, "\n")

    unusable = %{
      "an EC key" => :secp256r1 |> X509.PrivateKey.new_ec() |> X509.PrivateKey.to_pem(),
      "a short RSA key" => 1024 |> X509.PrivateKey.new_rsa() |> X509.PrivateKey.to_pem(),
      # One bit short, yet the same 256 bytes as a 2048-bit modulus.
      "a 2047-bit RSA key" => 2047 |> X509.PrivateKey.new_rsa() |> X509.PrivateKey.to_pem(),
      "an encrypted key" => 2048 |> X509.PrivateKey.new_rsa() |> X509.PrivateKey.to_pem(password: "secret"),
      "a truncated key" => String.slice(rsa_pem, 0, 200),
      "a public key" => 2048 |> X509.PrivateKey.new_rsa() |> X509.PublicKey.derive() |> X509.PublicKey.to_pem(),
      "escaped newlines" => String.replace(rsa_pem, "\n", "\\n"),
      "text that is not PEM" => "not a key " <> rsa_body
    }

    for {description, pem} <- unusable do
      stub(Environment, :sso_client_assertion_private_keys, fn -> pem end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          refute SSOClientAssertion.available?(), description
          assert SSOClientAssertion.jwks() == %{"keys" => []}, description
          assert {:error, :sso_client_assertion_not_configured} = SSOClientAssertion.sign("client", "https://idp/token")
        end)

      assert log =~ "TUIST_SSO_CLIENT_ASSERTION_PRIVATE_KEYS", description
      refute log =~ rsa_body, description
    end
  end

  defp configure_keys(keys) do
    stub(Environment, :sso_client_assertion_private_keys, fn -> Enum.map_join(keys, &X509.PrivateKey.to_pem/1) end)
  end
end
