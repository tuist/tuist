defmodule Tuist.GitHub.App do
  @moduledoc """
  A module that manages the GitHub token storage.
  """

  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.Projects.VCSConnection
  alias Tuist.Repo
  alias Tuist.VCS.GitHubAppInstallation

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

  def get_app_installation_token_by_id(installation_id, opts \\ []) do
    get_installation_token(installation_id, opts)
  end

  @doc """
  Gets an app installation token for a specific project.
  This ensures deterministic token retrieval in monorepo setups.
  """
  def get_app_installation_token_by_project(%Project{} = project, opts \\ []) do
    project = Repo.preload(project, vcs_connection: :github_app_installation)

    case project do
      %{vcs_connection: %{github_app_installation: %{installation_id: installation_id}}} ->
        get_installation_token(installation_id, opts)

      _ ->
        {:error, "The Tuist GitHub app is not installed for project #{project.name}."}
    end
  end

  @doc """
  Gets an app installation token for a specific VCS connection.
  This ensures deterministic token retrieval in monorepo setups.
  """
  def get_app_installation_token_by_vcs_connection(%VCSConnection{} = vcs_connection, opts \\ []) do
    vcs_connection = Repo.preload(vcs_connection, :github_app_installation)

    case vcs_connection do
      %{github_app_installation: %{installation_id: installation_id}} ->
        get_installation_token(installation_id, opts)

      _ ->
        {:error, "The Tuist GitHub app is not installed for this VCS connection."}
    end
  end

  @doc """
  Gets an app installation token for a specific GitHub app installation.
  This ensures deterministic token retrieval in monorepo setups.
  """
  def get_app_installation_token_by_github_app_installation(%GitHubAppInstallation{} = github_app_installation, opts \\ []) do
    get_installation_token(github_app_installation.installation_id, opts)
  end

  # Temporary compatibility function for GitHub client
  # TODO: Refactor GitHub client to pass installation_id directly
  def get_app_installation_token_for_repository(repository_full_handle, opts \\ []) do
    # With monorepo support, multiple projects can connect to the same repository.
    # We just need one installation ID since it's the same for all projects in a repository.
    projects =
      Projects.projects_by_vcs_repository_full_handle(repository_full_handle,
        preload: [vcs_connection: :github_app_installation]
      )

    case projects do
      [project | _] ->
        case project do
          %{vcs_connection: %{github_app_installation: %{installation_id: installation_id}}} ->
            get_installation_token(installation_id, opts)

          _ ->
            {:error, "The Tuist GitHub app is not installed in the repository #{repository_full_handle}."}
        end

      [] ->
        {:error, "The Tuist GitHub app is not installed in the repository #{repository_full_handle}."}
    end
  end

  def clear_token(opts \\ []) do
    opts |> get_cache() |> Cachex.clear()
  end

  def get_cache(opts) do
    Keyword.get(opts, :cache, :tuist)
  end

  defp generate_app_jwt(opts) do
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
