defmodule Tuist.GitHub.TokenStorage do
  @moduledoc """
  A module that manages the GitHub token storage.
  """

  alias Tuist.Environment

  use Agent

  def start_link(initial_value) do
    Agent.start_link(fn -> initial_value end, name: __MODULE__)
  end

  def get_token do
    token =
      if Process.whereis(__MODULE__) do
        Agent.get(__MODULE__, & &1)
      else
        raise "GitHub API interactions through #{__MODULE__} need to be mocked in tests."
      end

    cond do
      is_nil(token) ->
        refresh_token()

      token_expired?(token) ->
        refresh_token()

      true ->
        {:ok, token}
    end
  end

  def refresh_token() do
    private_key =
      Environment.github_app_private_key()
      |> JOSE.JWK.from_pem()

    now = DateTime.utc_now() |> DateTime.to_unix()

    # JSON Web Token (JWT)
    claims = %{
      "iat" => now,
      # The token expires after 10 minutes
      "exp" => now + 600,
      "iss" => Environment.github_app_client_id()
    }

    {_, jwt} =
      JOSE.JWT.sign(private_key, %{"alg" => "RS256"}, claims)
      |> JOSE.JWS.compact()

    headers =
      [
        {"Accept", "application/vnd.github.v3+json"},
        {"Authorization", "Bearer #{jwt}"}
      ]

    with {:access_tokens_url,
          {:ok, %Req.Response{status: 200, body: [%{"access_tokens_url" => access_tokens_url}]}}} <-
           {:access_tokens_url,
            Req.get("https://api.github.com/app/installations", headers: headers)},
         {:token,
          {:ok,
           %Req.Response{
             status: 201,
             body: %{"token" => token, "expires_at" => expires_at}
           }}} <-
           {:token, Req.post(access_tokens_url, headers: headers)} do
      expires_at =
        expires_at
        |> DateTime.from_iso8601()
        |> case do
          {:ok, date, _} -> date
          # Fallback in case of error
          {:error, _} -> DateTime.utc_now()
        end

      update_token(%{token: token, expires_at: expires_at})
      {:ok, %{token: token, expires_at: expires_at}}
    else
      {:access_tokens_url, {:ok, %Req.Response{status: status, body: body}}} ->
        {:error,
         "Unexpected status code when getting the access token url: #{status}. Body: #{Jason.encode!(body)}"}

      {:access_tokens_url, {:error, reason}} ->
        {:error, "Request failed when getting the access token url: #{inspect(reason)}"}

      {:token, {:ok, %Req.Response{status: status, body: body}}} ->
        {:error,
         "Unexpected status code when getting the token: #{status}. Body: #{Jason.encode!(body)}"}

      {:token, {:error, reason}} ->
        {:error, "Request failed when getting the token: #{inspect(reason)}"}
    end
  end

  defp token_expired?(token) do
    Time.compare(Tuist.Time.utc_now(), token.expires_at) == :gt
  end

  defp update_token(new_token) do
    Agent.update(__MODULE__, fn _ ->
      new_token
    end)
  end
end
