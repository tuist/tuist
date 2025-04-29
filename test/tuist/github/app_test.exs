defmodule Tuist.GitHub.AppTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.GitHub.App
  alias Tuist.KeyValueStore

  setup do
    stub(JOSE.JWK, :from_pem, fn _ -> "pem" end)
    stub(JOSE.JWT, :sign, fn _, _, _ -> "signed_pem" end)
    stub(JOSE.JWS, :compact, fn _ -> {%{}, "jwt"} end)
    stub(Tuist.Time, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
    expect(KeyValueStore, :get_or_update, 1, fn _, _, func -> func.() end)
    :ok
  end

  describe "get_app_installation_token_for_repository/2" do
    test "returns a not found error when the GitHub app is not installed" do
      # Given
      stub(Req, :get, fn _, _ ->
        {:ok, %Req.Response{status: 404}}
      end)

      # When/Then
      assert {:error, error_message} =
               App.get_app_installation_token_for_repository("tuist/tuist")

      assert error_message =~ "The Tuist GitHub app is not installed for tuist/tuist"
    end

    test "returns an error when the token refreshing fails" do
      # Given
      stub(Req, :get, fn _, _ ->
        {:ok, %Req.Response{status: 503}}
      end)

      # When/Then
      assert {:error, error_message} =
               App.get_app_installation_token_for_repository("tuist/tuist")

      assert error_message =~ "Unexpected status code when getting the access token url: 503"
    end
  end
end
