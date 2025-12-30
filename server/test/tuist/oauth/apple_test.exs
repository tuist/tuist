defmodule Tuist.OAuth.AppleTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.OAuth.Apple
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    stub(Environment, :apple_app_client_id, fn -> "test.app.client.id" end)
    stub(Environment, :apple_private_key_id, fn -> "test_key_id" end)
    stub(Environment, :apple_team_id, fn -> "test_team_id" end)
    stub(Environment, :apple_private_key, fn -> "test_private_key" end)
    stub(UeberauthApple, :generate_client_secret, fn _config -> "test_client_secret" end)
    :ok
  end

  describe "verify_apple_identity_token_and_create_user/2" do
    test "creates a new user when Apple token is valid" do
      # Given
      identity_token = "valid_identity_token"
      authorization_code = "valid_auth_code"

      stub(Req, :post, fn _url, _opts ->
        {:ok, %{status: 200, body: %{"access_token" => "token"}}}
      end)

      stub(JOSE.JWT, :peek_payload, fn _token ->
        %JOSE.JWT{
          fields: %{
            "sub" => "apple_user_id",
            "email" => "testuser@example.com"
          }
        }
      end)

      # When
      {:ok, user} = Apple.verify_apple_identity_token_and_create_user(identity_token, authorization_code)

      # Then
      assert user.email == "testuser@example.com"
    end

    test "returns existing user when Apple token is valid and user already exists" do
      # Given
      AccountsFixtures.user_fixture(email: "apple.test@example.com")
      identity_token = "valid_identity_token"
      authorization_code = "valid_auth_code"

      stub(Req, :post, fn _url, _opts ->
        {:ok, %{status: 200, body: %{"access_token" => "token"}}}
      end)

      stub(JOSE.JWT, :peek_payload, fn _token ->
        %JOSE.JWT{
          fields: %{
            "sub" => "apple_user_id_123",
            "email" => "apple.test@example.com"
          }
        }
      end)

      # When
      {:ok, user} = Apple.verify_apple_identity_token_and_create_user(identity_token, authorization_code)

      # Then
      assert user.email == "apple.test@example.com"
    end

    test "returns error when authorization code validation fails" do
      # Given
      identity_token = "valid_identity_token"
      authorization_code = "invalid_auth_code"

      stub(Req, :post, fn _url, _opts ->
        {:ok, %{status: 400, body: %{"error" => "invalid_grant"}}}
      end)

      # When
      result = Apple.verify_apple_identity_token_and_create_user(identity_token, authorization_code)

      # Then
      assert {:error, "Apple authorization code validation failed with 400 error code."} = result
    end

    test "returns error when HTTP request to Apple fails" do
      # Given
      identity_token = "valid_identity_token"
      authorization_code = "valid_auth_code"

      stub(Req, :post, fn _url, _opts ->
        {:error, %{reason: :timeout}}
      end)

      # When
      result = Apple.verify_apple_identity_token_and_create_user(identity_token, authorization_code)

      # Then
      assert {:error, "The request to Apple to validate the token has failed."} = result
    end
  end
end
