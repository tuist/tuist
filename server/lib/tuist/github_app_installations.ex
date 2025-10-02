defmodule Tuist.GitHubAppInstallations do
  @moduledoc """
  A module that provides functions to interact with GitHub app installations.
  """

  alias Tuist.Accounts.Account
  alias Tuist.GitHub.Client
  alias Tuist.GitHubAppInstallations.GitHubAppInstallation
  alias Tuist.GitHubStateToken
  alias Tuist.Repo

  @doc """
  Gets a GitHub app installation by its installation ID.
  """
  def get_by_installation_id(installation_id) do
    case Repo.get_by(GitHubAppInstallation, installation_id: to_string(installation_id)) do
      nil -> {:error, :not_found}
      github_app_installation -> {:ok, github_app_installation}
    end
  end

  @doc """
  Updates a GitHub app installation.
  """
  def update(%GitHubAppInstallation{} = github_app_installation, attrs) do
    github_app_installation
    |> GitHubAppInstallation.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Creates a new GitHub app installation.
  """
  def create(attrs) do
    %GitHubAppInstallation{}
    |> GitHubAppInstallation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets repositories for a GitHub app installation.
  """
  def get_repositories(%GitHubAppInstallation{installation_id: installation_id}) do
    Client.get_installation_repositories(installation_id)
  end

  @doc """
  Deletes a GitHub app installation.
  """
  def delete(%GitHubAppInstallation{} = github_app_installation) do
    Repo.delete(github_app_installation, stale_error_field: :id)
  end

  @doc """
  Get GitHub app installation URL with encrypted state parameter for account-specific installation.
  """
  def get_github_app_installation_url(%Account{id: account_id}) do
    app_name = Tuist.Environment.github_app_name()
    state_token = GitHubStateToken.generate_token(account_id)
    "https://github.com/apps/#{app_name}/installations/new?state=#{state_token}"
  end
end
