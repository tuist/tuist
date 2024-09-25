defmodule Tuist.Storage.OptionsTest do
  use ExUnit.Case, async: false
  use Mimic
  alias Tuist.Storage.Options
  alias Tuist.Environment

  # This is needed in combination with "async: false" to ensure
  # that mocks are used within the cache process.
  setup :set_mimic_from_context

  describe "get/0" do
    test "returns the right value when no token file present and session token shouldn't be used" do
      # Given
      Environment |> stub(:s3_endpoint, fn -> "https://s3.amazonaws.com" end)
      Environment |> stub(:aws_web_identity_token_file, fn -> nil end)
      Environment |> stub(:s3_access_key_id, fn -> "s3_access_key_id" end)
      Environment |> stub(:s3_secret_access_key, fn -> "s3_secret_access_key" end)
      Environment |> stub(:aws_region, fn -> "auto" end)

      # When/Then
      assert Options.get() == [
               access_key_id: "s3_access_key_id",
               secret_access_key: "s3_secret_access_key",
               scheme: "https://",
               host: "s3.amazonaws.com",
               region: "auto"
             ]
    end

    test "returns the right value when no token file is present and the session token should be used" do
      # Given
      Environment |> stub(:s3_endpoint, fn -> "https://s3.amazonaws.com" end)
      Environment |> stub(:aws_web_identity_token_file, fn -> nil end)
      Environment |> stub(:s3_access_key_id, fn -> "s3_access_key_id" end)
      Environment |> stub(:s3_secret_access_key, fn -> "s3_secret_access_key" end)
      Environment |> stub(:aws_region, fn -> "auto" end)
      Environment |> stub(:aws_use_session_token?, fn -> true end)
      Environment |> stub(:aws_session_token, fn -> "session_token" end)

      # When/Then
      assert Options.get() == [
               access_key_id: "s3_access_key_id",
               secret_access_key: "s3_secret_access_key",
               scheme: "https://",
               host: "s3.amazonaws.com",
               region: "auto",
               session_token: "session_token"
             ]
    end
  end
end
