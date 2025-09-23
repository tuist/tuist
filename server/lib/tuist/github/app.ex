defmodule Tuist.GitHub.App do
  @moduledoc """
  A module that manages the GitHub token storage.
  """

  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Projects

  def get_organization_installation(organization_name, _opts \\ []) do
    jwt = generate_app_jwt()

    headers = [
      {"Accept", "application/vnd.github+json"},
      {"Authorization", "Bearer #{jwt}"},
      {"X-GitHub-Api-Version", "2022-11-28"}
    ]

    case Req.get(
           url: "https://api.github.com/orgs/#{organization_name}/installation",
           headers: headers,
           finch: Tuist.Finch
         ) do
      {:ok, %Req.Response{status: 200, body: installation}} ->
        tuist_app_id = Environment.github_app_client_id()

        if installation["client_id"] == tuist_app_id do
          {:ok, installation}
        else
          {:error, "Tuist GitHub app is not installed for organization #{organization_name}"}
        end

      {:ok, %Req.Response{status: 404}} ->
        {:error, "Organization #{organization_name} not found or GitHub app not installed"}
    end
  end

  def get_installation_token(installation_id, opts \\ []) do
    ttl = to_timeout(minute: 10)

    case KeyValueStore.get_or_update(
           [__MODULE__, "installation_token", installation_id],
           [
             cache: get_cache(opts),
             ttl: Keyword.get(opts, :ttl, ttl)
           ],
           fn ->
             refresh_installation_token(installation_id, expires_in: ttl)
           end
         ) do
      {:ok, token} ->
        {:ok, token}

      {:error, error} ->
        {:error, error}
    end
  end

  def get_app_installation_token_for_repository(repository_full_handle, opts \\ []) do
    case get_installation_id_for_repository(repository_full_handle) do
      {:ok, installation_id} ->
        get_installation_token(installation_id, opts)

      {:error, error} ->
        {:error, error}
    end
  end

  defp get_installation_id_for_repository(repository_full_handle) do
    case Projects.project_by_vcs_repository_full_handle(repository_full_handle,
           preload: [vcs_connection: :github_app_installation]
         ) do
      {:ok, %{vcs_connection: %{github_app_installation: %{installation_id: installation_id}}}} ->
        {:ok, installation_id}

      {:error, :not_found} ->
        {:error, "The Tuist GitHub app is not installed for #{repository_full_handle}."}
    end
  end

  def clear_token(opts \\ []) do
    opts |> get_cache() |> Cachex.clear()
  end

  def get_cache(opts) do
    Keyword.get(opts, :cache, :tuist)
  end

  defp generate_app_jwt(opts \\ []) do
    private_key = JOSE.JWK.from_pem(Environment.github_app_private_key())

    now = DateTime.to_unix(DateTime.utc_now())

    # Converted to seconds
    expires_in = trunc(Keyword.get(opts, :expires_in, to_timeout(minute: 10)) / 1000)

    # JSON Web Token (JWT)
    claims = %{
      "iat" => now,
      "exp" => now + expires_in,
      "iss" => Environment.github_app_client_id()
    }

    {_, jwt} =
      private_key
      |> JOSE.JWT.sign(%{"alg" => "RS256"}, claims)
      |> JOSE.JWS.compact()

    jwt
  end

  defp refresh_installation_token(installation_id, opts) do
    jwt = generate_app_jwt(opts)

    headers = [
      {"Accept", "application/vnd.github+json"},
      {"Authorization", "Bearer #{jwt}"},
      {"X-GitHub-Api-Version", "2022-11-28"}
    ]

    case Req.post(
           url: "https://api.github.com/app/installations/#{installation_id}/access_tokens",
           headers: headers,
           finch: Tuist.Finch
         ) do
      {:ok, %Req.Response{status: 201, body: %{"token" => token, "expires_at" => expires_at}}} ->
        {:ok, expires_at, _} = DateTime.from_iso8601(expires_at)
        {:ok, %{token: token, expires_at: expires_at}}

      {:ok, %Req.Response{status: _status, body: _body}} ->
        {:error, "Failed to get installation token"}
    end
  end
end
