defmodule Tuist.GitHub.TokenStorageTest do
  alias Tuist.GitHub.TokenStorage
  use ExUnit.Case, async: false
  use Mimic

  setup do
    JOSE.JWK |> stub(:from_pem, fn _ -> "pem" end)
    JOSE.JWT |> stub(:sign, fn _, _, _ -> "signed_pem" end)
    JOSE.JWS |> stub(:compact, fn _ -> {%{}, "jwt"} end)

    Tuist.Time
    |> stub(:utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)

    :ok
  end

  test "returns token" do
    # Given
    {:ok, _pid} =
      TokenStorage.start_link(%{token: "github_token", expires_at: ~U[2024-04-30 10:30:31Z]})

    # When
    token = TokenStorage.get_token()

    # Then
    assert token == {:ok, %{token: "github_token", expires_at: ~U[2024-04-30 10:30:31Z]}}
  end

  test "refreshes token" do
    # Given
    Req
    |> stub(
      :get,
      fn
        "https://api.github.com/app/installations", _ ->
          {:ok, %Req.Response{status: 200, body: [%{"access_tokens_url" => "access_tokens_url"}]}}
      end
    )

    Req
    |> expect(:post, fn "access_tokens_url", _ ->
      {:ok,
       %Req.Response{
         status: 201,
         body: %{"token" => "new_token", "expires_at" => "2024-04-30T10:30:31Z"}
       }}
    end)

    {:ok, _pid} =
      TokenStorage.start_link(%{token: "old_token", expires_at: ~U[2024-04-30 10:20:29Z]})

    # When
    token = TokenStorage.refresh_token()

    # Then
    assert token == {:ok, %{token: "new_token", expires_at: ~U[2024-04-30 10:30:31Z]}}
  end

  test "automatically refreshes token when the token is expired" do
    # Given
    JOSE.JWT
    |> stub(:peek_payload, fn _ ->
      %JOSE.JWT{fields: %{"exp" => ~U[2024-04-30 10:20:29Z] |> DateTime.to_unix()}}
    end)

    Req
    |> stub(
      :get,
      fn
        "https://api.github.com/app/installations", _ ->
          {:ok, %Req.Response{status: 200, body: [%{"access_tokens_url" => "access_tokens_url"}]}}
      end
    )

    Req
    |> expect(:post, fn "access_tokens_url", _ ->
      {:ok,
       %Req.Response{
         status: 201,
         body: %{"token" => "new_token", "expires_at" => "2024-04-30T10:30:31Z"}
       }}
    end)

    {:ok, _pid} =
      TokenStorage.start_link(%{token: "old_token", expires_at: ~U[2024-04-30 10:20:29Z]})

    # When
    token = TokenStorage.get_token()

    # Then
    assert token == {:ok, %{token: "new_token", expires_at: ~U[2024-04-30 10:30:31Z]}}
  end

  test "returns 503 error when refreshing the token fails" do
    # Given
    Req
    |> stub(:get, fn _, _ ->
      {:ok, %Req.Response{status: 503}}
    end)

    # When
    got = TokenStorage.refresh_token()

    # Then
    assert got ==
             {:error, "Unexpected status code when getting the access token url: 503. Body: \"\""}
  end
end
