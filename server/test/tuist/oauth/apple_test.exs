defmodule Tuist.OAuth.AppleTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.OAuth.Apple
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @apple_client_id "test.app.client.id"
  @signing_key_id "test-signing-key"
  @default_sub "apple_user_id"
  @default_email "testuser@example.com"

  setup do
    stub(Environment, :apple_app_client_id, fn -> @apple_client_id end)
    stub(Environment, :apple_private_key_id, fn -> "test_key_id" end)
    stub(Environment, :apple_team_id, fn -> "test_team_id" end)
    stub(Environment, :apple_private_key, fn -> "test_private_key" end)
    stub(UeberauthApple, :generate_client_secret, fn _config -> "test_client_secret" end)

    signing_key = JOSE.JWK.generate_key({:rsa, 2048})

    # By default Apple's JWKS endpoint returns the public half of the key the
    # tests sign identity tokens with.
    stub(Req, :get, fn _url ->
      {:ok, %{status: 200, body: %{"keys" => [public_jwks_entry(signing_key, @signing_key_id)]}}}
    end)

    # By default the authorization code exchange returns an identity token for
    # the same identity the happy-path tests submit, so the subjects match.
    stub_authorization_code_exchange(signing_key, %{"sub" => @default_sub, "email" => @default_email})

    %{signing_key: signing_key}
  end

  describe "verify_apple_identity_token_and_create_user/2" do
    test "creates a new user when the identity token is valid", %{signing_key: signing_key} do
      # Given
      identity_token =
        sign_identity_token(signing_key, @signing_key_id, %{"sub" => @default_sub, "email" => @default_email})

      # When
      {:ok, user} = Apple.verify_apple_identity_token_and_create_user(identity_token, "valid_auth_code")

      # Then
      assert user.email == @default_email
    end

    test "returns the existing user when the identity token is valid", %{signing_key: signing_key} do
      # Given
      AccountsFixtures.user_fixture(email: "apple.test@example.com")
      claims = %{"sub" => "apple_user_id_123", "email" => "apple.test@example.com"}
      stub_authorization_code_exchange(signing_key, claims)
      identity_token = sign_identity_token(signing_key, @signing_key_id, claims)

      # When
      {:ok, user} = Apple.verify_apple_identity_token_and_create_user(identity_token, "valid_auth_code")

      # Then
      assert user.email == "apple.test@example.com"
    end

    test "returns an error when the identity token is replayed with an unrelated authorization code", %{
      signing_key: signing_key
    } do
      # Given the attacker exchanges their own authorization code (identity A)...
      stub_authorization_code_exchange(signing_key, %{"sub" => "attacker_sub", "email" => "attacker@example.com"})

      # ...but submits a genuine, stolen victim identity token (identity B).
      victim_identity_token =
        sign_identity_token(signing_key, @signing_key_id, %{"sub" => "victim_sub", "email" => "victim@example.com"})

      # When
      result = Apple.verify_apple_identity_token_and_create_user(victim_identity_token, "attacker_auth_code")

      # Then
      assert {:error, :token_subject_mismatch} = result
    end

    test "returns an error when the token signature does not match Apple's keys" do
      # Given the submitted token is signed with a different key than Apple publishes for this kid.
      attacker_key = JOSE.JWK.generate_key({:rsa, 2048})

      identity_token =
        sign_identity_token(attacker_key, @signing_key_id, %{"sub" => @default_sub, "email" => @default_email})

      # When
      result = Apple.verify_apple_identity_token_and_create_user(identity_token, "valid_auth_code")

      # Then
      assert {:error, :invalid_signature} = result
    end

    test "returns an error when the audience does not match the app client id", %{signing_key: signing_key} do
      # Given
      identity_token =
        sign_identity_token(signing_key, @signing_key_id, %{
          "aud" => "com.attacker.other-app",
          "sub" => @default_sub,
          "email" => @default_email
        })

      # When
      result = Apple.verify_apple_identity_token_and_create_user(identity_token, "valid_auth_code")

      # Then
      assert {:error, :invalid_audience} = result
    end

    test "returns an error when the issuer is not Apple", %{signing_key: signing_key} do
      # Given
      identity_token =
        sign_identity_token(signing_key, @signing_key_id, %{
          "iss" => "https://evil.example.com",
          "sub" => @default_sub,
          "email" => @default_email
        })

      # When
      result = Apple.verify_apple_identity_token_and_create_user(identity_token, "valid_auth_code")

      # Then
      assert {:error, :invalid_issuer} = result
    end

    test "returns an error when the token is expired", %{signing_key: signing_key} do
      # Given
      now = DateTime.to_unix(DateTime.utc_now())

      identity_token =
        sign_identity_token(signing_key, @signing_key_id, %{
          "exp" => now - 3600,
          "iat" => now - 7200,
          "sub" => @default_sub,
          "email" => @default_email
        })

      # When
      result = Apple.verify_apple_identity_token_and_create_user(identity_token, "valid_auth_code")

      # Then
      assert {:error, :token_expired} = result
    end

    test "returns an error when the signing key is unknown", %{signing_key: signing_key} do
      # Given the token references a kid that is not present in Apple's JWKS.
      identity_token =
        sign_identity_token(signing_key, "unknown-kid", %{"sub" => @default_sub, "email" => @default_email})

      # When
      result = Apple.verify_apple_identity_token_and_create_user(identity_token, "valid_auth_code")

      # Then
      assert {:error, :unknown_signing_key} = result
    end

    test "returns an error when Apple's token response omits the identity token", %{signing_key: signing_key} do
      # Given
      stub(Req, :post, fn _url, _opts -> {:ok, %{status: 200, body: %{"access_token" => "token"}}} end)

      identity_token =
        sign_identity_token(signing_key, @signing_key_id, %{"sub" => @default_sub, "email" => @default_email})

      # When
      result = Apple.verify_apple_identity_token_and_create_user(identity_token, "valid_auth_code")

      # Then
      assert {:error, "Apple authorization code response did not include an identity token."} = result
    end

    test "returns an error when authorization code validation fails", %{signing_key: signing_key} do
      # Given
      stub(Req, :post, fn _url, _opts ->
        {:ok, %{status: 400, body: %{"error" => "invalid_grant"}}}
      end)

      identity_token =
        sign_identity_token(signing_key, @signing_key_id, %{"sub" => @default_sub, "email" => @default_email})

      # When
      result = Apple.verify_apple_identity_token_and_create_user(identity_token, "invalid_auth_code")

      # Then
      assert {:error, "Apple authorization code validation failed with 400 error code."} = result
    end

    test "returns an error when the request to Apple fails", %{signing_key: signing_key} do
      # Given
      stub(Req, :post, fn _url, _opts ->
        {:error, %{reason: :timeout}}
      end)

      identity_token =
        sign_identity_token(signing_key, @signing_key_id, %{"sub" => @default_sub, "email" => @default_email})

      # When
      result = Apple.verify_apple_identity_token_and_create_user(identity_token, "valid_auth_code")

      # Then
      assert {:error, "The request to Apple to validate the token has failed."} = result
    end
  end

  defp stub_authorization_code_exchange(signing_key, claims) do
    exchanged_identity_token = sign_identity_token(signing_key, @signing_key_id, claims)

    stub(Req, :post, fn _url, _opts ->
      {:ok, %{status: 200, body: %{"id_token" => exchanged_identity_token}}}
    end)
  end

  defp sign_identity_token(signing_key, key_id, claims) do
    now = DateTime.to_unix(DateTime.utc_now())

    claims =
      Map.merge(
        %{
          "iss" => "https://appleid.apple.com",
          "aud" => @apple_client_id,
          "exp" => now + 600,
          "iat" => now
        },
        claims
      )

    header = %{"alg" => "RS256", "kid" => key_id}

    {_meta, token} =
      signing_key
      |> JOSE.JWT.sign(header, claims)
      |> JOSE.JWS.compact()

    token
  end

  defp public_jwks_entry(signing_key, key_id) do
    {_meta, public_key_map} =
      signing_key
      |> JOSE.JWK.to_public()
      |> JOSE.JWK.to_map()

    Map.merge(public_key_map, %{"kid" => key_id, "use" => "sig", "alg" => "RS256"})
  end
end
