defmodule Atlas.Integrations.GitHubAPI do
  @moduledoc """
  Handles GitHub App authentication and API requests.

  Generates short-lived installation access tokens using the app's private key,
  then uses those tokens for GitHub API calls.
  """

  alias Atlas.Integrations.GitHubApp

  @github_api_url "https://api.github.com"

  def find_installation_id(%GitHubApp{} = app, account_login) when is_binary(account_login) do
    with {:ok, jwt} <- generate_jwt(app),
         {:ok, installations} <- list_installations(jwt) do
      installations
      |> Enum.find(fn installation -> get_in(installation, ["account", "login"]) == account_login end)
      |> case do
        %{"id" => installation_id} -> {:ok, to_string(installation_id)}
        _ -> {:error, :github_app_installation_not_found}
      end
    end
  end

  def get_installation_token(%GitHubApp{} = app) do
    with {:ok, jwt} <- generate_jwt(app) do
      Req.post(github_url("/app/installations/#{app.installation_id}/access_tokens"),
        headers: [
          {"authorization", "Bearer #{jwt}"},
          {"accept", "application/vnd.github+json"}
        ]
      )
      |> case do
        {:ok, %{status: 201, body: %{"token" => token}}} ->
          {:ok, token}

        {:ok, %{status: status, body: body}} ->
          {:error, "GitHub API returned #{status}: #{inspect(body)}"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def req(%GitHubApp{} = app) do
    with {:ok, token} <- get_installation_token(app) do
      {:ok,
       Req.new(
         base_url: @github_api_url,
         headers: [
           {"authorization", "token #{token}"},
           {"accept", "application/vnd.github+json"}
         ]
       )}
    end
  end

  defp list_installations(jwt) do
    Req.get(github_url("/app/installations"),
      headers: [
        {"authorization", "Bearer #{jwt}"},
        {"accept", "application/vnd.github+json"}
      ]
    )
    |> case do
      {:ok, %{status: 200, body: installations}} when is_list(installations) ->
        {:ok, installations}

      {:ok, %{status: status, body: body}} ->
        {:error, "GitHub installations request returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp github_url(path) do
    @github_api_url
    |> URI.parse()
    |> URI.append_path(path)
    |> URI.to_string()
  end

  defp generate_jwt(%GitHubApp{app_id: app_id, private_key: private_key}) do
    now = System.system_time(:second)

    header = %{"alg" => "RS256", "typ" => "JWT"}
    payload = %{"iat" => now - 60, "exp" => now + 600, "iss" => app_id}

    with {:ok, key} <- decode_private_key(private_key) do
      header_b64 = Base.url_encode64(Jason.encode!(header), padding: false)
      payload_b64 = Base.url_encode64(Jason.encode!(payload), padding: false)
      signing_input = "#{header_b64}.#{payload_b64}"

      signature =
        :public_key.sign(signing_input, :sha256, key)
        |> Base.url_encode64(padding: false)

      {:ok, "#{signing_input}.#{signature}"}
    end
  end

  defp decode_private_key(pem) do
    case :public_key.pem_decode(pem) do
      [entry | _] ->
        {:ok, :public_key.pem_entry_decode(entry)}

      [] ->
        {:error, :invalid_private_key}
    end
  rescue
    _ -> {:error, :invalid_private_key}
  end
end
