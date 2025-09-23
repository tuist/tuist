defmodule Tuist.GitHubStateTokenTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.GitHubStateToken

  describe "generate_token/1" do
    test "generates a token for a given account ID" do
      # Given
      account_id = 123

      # When
      token = GitHubStateToken.generate_token(account_id)

      # Then
      assert is_binary(token)
      assert String.length(token) > 0
    end

    test "generates different tokens for different account IDs" do
      # Given
      account_id_1 = 123
      account_id_2 = 456

      # When
      token_1 = GitHubStateToken.generate_token(account_id_1)
      token_2 = GitHubStateToken.generate_token(account_id_2)

      # Then
      assert token_1 != token_2
    end
  end

  describe "verify_token/1" do
    test "verifies a valid token and returns the account ID" do
      # Given
      account_id = 123
      token = GitHubStateToken.generate_token(account_id)

      # When
      result = GitHubStateToken.verify_token(token)

      # Then
      assert {:ok, ^account_id} = result
    end

    test "returns error for invalid token format" do
      # Given
      invalid_token = "invalid_token_format"

      # When
      result = GitHubStateToken.verify_token(invalid_token)

      # Then
      assert {:error, _reason} = result
    end

    test "returns error for empty token" do
      # Given
      empty_token = ""

      # When
      result = GitHubStateToken.verify_token(empty_token)

      # Then
      assert {:error, _reason} = result
    end

    test "returns error for nil token" do
      # When
      result = GitHubStateToken.verify_token(nil)

      # Then
      assert {:error, _reason} = result
    end
  end
end
