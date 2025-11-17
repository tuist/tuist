defmodule Tuist.GitHub.AppTest do
  use ExUnit.Case, async: true
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.GitHub.App
  alias Tuist.KeyValueStore

  setup do
    stub(JOSE.JWK, :from_pem, fn _ -> "pem" end)
    stub(JOSE.JWT, :sign, fn _, _, _ -> "signed_pem" end)
    stub(JOSE.JWS, :compact, fn _ -> {%{}, "jwt"} end)
    stub(Tuist.Time, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
    stub(KeyValueStore, :get_or_update, fn _, _, func -> func.() end)
    :ok
  end

  describe "get_installation_token/2" do
    test "returns installation token when request succeeds" do
      # Given
      installation_id = "12345"
      token = "ghs_16C7e42F292c6912E7710c838347Ae178B4a"
      expires_at = "2024-04-30T11:20:30Z"

      stub(Req, :post, fn opts ->
        assert Keyword.get(opts, :url) =~ "/app/installations/#{installation_id}/access_tokens"
        assert opts |> Keyword.get(:headers) |> Enum.member?({"Authorization", "Bearer jwt"})

        {:ok,
         %Req.Response{
           status: 201,
           body: %{
             "token" => token,
             "expires_at" => expires_at
           }
         }}
      end)

      # When
      result = App.get_installation_token(installation_id)

      # Then
      assert {:ok, %{token: ^token, expires_at: expires_at_datetime}} = result
      assert expires_at_datetime == ~U[2024-04-30 11:20:30Z]
    end

    test "returns error when request fails with non-201 status" do
      # Given
      installation_id = "12345"

      stub(Req, :post, fn _opts ->
        {:ok,
         %Req.Response{
           status: 401,
           body: %{"message" => "Bad credentials"}
         }}
      end)

      # When
      result = App.get_installation_token(installation_id)

      # Then
      assert {:error, "Failed to get installation token"} = result
    end

    test "returns error when HTTP connection fails after retries" do
      # Given
      installation_id = "12345"

      # Note: The actual Req client will retry this error 3 times with exponential backoff
      # before returning the error. This test simulates the final error state after retries.
      stub(Req, :post, fn _opts ->
        {:error, %Req.HTTPError{protocol: :http2, reason: :closed_for_writing}}
      end)

      # When
      result = App.get_installation_token(installation_id)

      # Then
      assert {:error, error_message} = result
      assert error_message =~ "GitHub API connection error"
      assert error_message =~ "closed_for_writing"
    end

    test "returns error when unexpected error occurs" do
      # Given
      installation_id = "12345"

      stub(Req, :post, fn _opts ->
        {:error, :timeout}
      end)

      # When
      result = App.get_installation_token(installation_id)

      # Then
      assert {:error, error_message} = result
      assert error_message =~ "Unexpected error getting installation token"
      assert error_message =~ "timeout"
    end
  end
end
