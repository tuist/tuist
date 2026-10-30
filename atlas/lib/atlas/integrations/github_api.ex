defmodule Atlas.Integrations.GitHubAPI do
  @moduledoc """
  Handles GitHub App authentication and API requests.

  Generates short-lived installation access tokens using the app's private key,
  then uses those tokens for GitHub API calls.
  """

  alias Atlas.Integrations.GitHubApp

  @github_api_url "https://api.github.com"

  # These endpoints use the person's GitHub App user grant. An installation
  # token alone would disclose repositories that person cannot access.
  def accessible_installations(token) do
    with {:ok, installations} <- user_pages(token, "/user/installations", "installations") do
      {:ok,
       installations
       |> Enum.filter(&(is_integer(&1["id"]) and &1["id"] > 0 and is_nil(&1["suspended_at"])))
       |> Enum.map(&%{id: to_string(&1["id"]), name: get_in(&1, ["account", "login"])})
       |> Enum.filter(&(is_binary(&1.name) and byte_size(&1.name) <= 100))
       |> Enum.sort_by(& &1.name)}
    end
  end

  def accessible_repositories(token, installation_id) do
    if Atlas.CodingRepositories.installation_id?(installation_id) do
      with {:ok, repositories} <-
             user_pages(token, "/user/installations/#{installation_id}/repositories", "repositories") do
        {:ok,
         repositories
         |> Enum.filter(&Atlas.CodingRepositories.repository?(&1["full_name"]))
         |> Enum.map(&%{full_name: String.downcase(&1["full_name"])})
         |> Enum.uniq()
         |> Enum.sort_by(& &1.full_name)}
      end
    else
      {:error, :invalid_params}
    end
  end

  defp user_pages(token, path, key, page \\ 1, pages \\ []) do
    # Fixed-origin requests only: never follow a Link URL or redirect with a
    # personal token. Fail rather than silently returning a partial catalogue.
    case Req.get(github_url(path),
           auth: {:bearer, token},
           headers: [{"accept", "application/vnd.github+json"}, {"x-github-api-version", "2022-11-28"}],
           params: [per_page: 100, page: page],
           redirect: false,
           retry: false,
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200, body: %{"total_count" => total} = body}} when is_integer(total) and total >= 0 ->
        collect_user_page(token, path, key, body, page, pages)

      {:ok, %{status: 401}} ->
        {:error, :github_connection_required}

      _ ->
        {:error, :github_catalog_unavailable}
    end
  end

  defp collect_user_page(token, path, key, body, page, pages) do
    entries = body[key]
    total = body["total_count"]

    cond do
      not valid_page?(entries) ->
        {:error, :github_catalog_unavailable}

      total > 5_000 ->
        {:error, :github_catalog_limit}

      page * 100 >= total ->
        {:ok, pages |> Enum.reverse() |> List.flatten() |> Enum.concat(entries)}

      page >= 50 or entries == [] ->
        {:error, :github_catalog_unavailable}

      true ->
        user_pages(token, path, key, page + 1, [entries | pages])
    end
  end

  defp valid_page?(entries), do: is_list(entries) and length(entries) <= 100 and Enum.all?(entries, &is_map/1)

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
