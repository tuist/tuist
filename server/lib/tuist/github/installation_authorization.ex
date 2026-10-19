defmodule Tuist.GitHub.InstallationAuthorization do
  @moduledoc "Verifies access to a github.com installation using GitHub App user authorization."

  alias Tuist.Environment

  def verify(code, installation_id, redirect_uri) do
    with client_id when is_binary(client_id) <- Environment.github_app_client_id(),
         client_secret when is_binary(client_secret) <- Environment.github_app_client_secret(),
         {:ok, %{status: 200, body: %{"access_token" => token}}} when is_binary(token) <-
           Req.post(
             url: "https://github.com/login/oauth/access_token",
             headers: [{"accept", "application/json"}],
             form: [client_id: client_id, client_secret: client_secret, code: code, redirect_uri: redirect_uri],
             finch: Tuist.Finch,
             redirect: false,
             retry: false,
             receive_timeout: 5000
           ) do
      verify_installation(token, installation_id, 1)
    else
      _ -> {:error, :invalid_github_installation}
    end
  end

  defp verify_installation(token, installation_id, page) when page <= 10 do
    case user_request(token, "/user/installations", per_page: 100, page: page) do
      {:ok, %{status: 200, body: %{"installations" => installations}}} when is_list(installations) ->
        app_id = to_string(Environment.github_app_id())

        installation =
          Enum.find(installations, fn installation ->
            to_string(installation["id"]) == installation_id and
              to_string(installation["app_id"]) == app_id and
              not is_nil(installation["app_id"]) and is_nil(installation["suspended_at"])
          end)

        cond do
          installation -> verify_administrator(token, installation["account"])
          length(installations) == 100 -> verify_installation(token, installation_id, page + 1)
          true -> {:error, :invalid_github_installation}
        end

      _ ->
        {:error, :invalid_github_installation}
    end
  end

  defp verify_installation(_token, _installation_id, _page), do: {:error, :invalid_github_installation}

  defp verify_administrator(token, %{"type" => "User", "id" => account_id}) when is_integer(account_id) do
    case user_request(token, "/user") do
      {:ok, %{status: 200, body: %{"id" => ^account_id}}} -> :ok
      _ -> {:error, :invalid_github_installation}
    end
  end

  defp verify_administrator(token, %{"type" => "Organization", "login" => login}) when is_binary(login) do
    case user_request(token, "/user/memberships/orgs/" <> URI.encode_www_form(login)) do
      {:ok, %{status: 200, body: %{"state" => "active", "role" => "admin"}}} -> :ok
      _ -> {:error, :invalid_github_installation}
    end
  end

  defp verify_administrator(_token, _account), do: {:error, :invalid_github_installation}

  defp user_request(token, path, params \\ []) do
    Req.get(
      url: "https://api.github.com" <> path,
      params: params,
      headers: [
        {"accept", "application/vnd.github+json"},
        {"authorization", "Bearer #{token}"},
        {"x-github-api-version", "2022-11-28"}
      ],
      finch: Tuist.Finch,
      redirect: false,
      retry: false,
      receive_timeout: 5000
    )
  end
end
