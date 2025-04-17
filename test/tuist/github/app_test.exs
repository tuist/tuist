defmodule Tuist.GitHub.AppTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Tuist.GitHub.App

  # This is needed in combination with "async: false" to ensure
  # that mocks are used within the cache process.
  setup :set_mimic_from_context

  setup do
    stub(JOSE.JWK, :from_pem, fn _ -> "pem" end)
    stub(JOSE.JWT, :sign, fn _, _, _ -> "signed_pem" end)
    stub(JOSE.JWS, :compact, fn _ -> {%{}, "jwt"} end)
    stub(Tuist.Time, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
    :ok
  end

  test "caches the result" do
    # Given
    cache = String.to_atom(UUIDv7.generate())
    {:ok, _} = Cachex.start_link(name: cache)

    expect(
      Req,
      :get,
      fn
        "https://api.github.com/repos/tuist/tuist/installation", _ ->
          {:ok, %Req.Response{status: 200, body: %{"access_tokens_url" => "access_tokens_url"}}}
      end
    )

    expect(Req, :post, fn "access_tokens_url", _ ->
      {:ok,
       %Req.Response{
         status: 201,
         body: %{"token" => "new_token", "expires_at" => "2024-04-30T10:30:31Z"}
       }}
    end)

    # When/Then
    assert {:ok, first_token} =
             App.get_app_installation_token_for_repository("tuist/tuist",
               cache: cache,
               ttl: to_timeout(minute: 10)
             )

    assert {:ok, second_token} =
             App.get_app_installation_token_for_repository("tuist/tuist",
               cache: cache,
               ttl: to_timeout(minute: 10)
             )

    assert first_token == second_token
  end

  test "returns a not found error when the GitHub app is not installed" do
    # Given
    cache = String.to_atom(UUIDv7.generate())
    {:ok, _} = Cachex.start_link(name: cache)

    stub(Req, :get, fn _, _ ->
      {:ok, %Req.Response{status: 404}}
    end)

    # When/Then
    assert {:error, error_message} =
             App.get_app_installation_token_for_repository("tuist/tuist",
               cache: cache,
               ttl: to_timeout(minute: 10)
             )

    assert error_message =~ "The Tuist GitHub app is not installed for tuist/tuist"
  end

  test "returns an error when the token refreshing fails" do
    # Given
    cache = String.to_atom(UUIDv7.generate())
    {:ok, _} = Cachex.start_link(name: cache)

    stub(Req, :get, fn _, _ ->
      {:ok, %Req.Response{status: 503}}
    end)

    # When/Then
    assert {:error, error_message} =
             App.get_app_installation_token_for_repository("tuist/tuist",
               cache: cache,
               ttl: to_timeout(minute: 10)
             )

    assert error_message =~ "Unexpected status code when getting the access token url: 503"
  end
end
