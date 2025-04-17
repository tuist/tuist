defmodule Tuist.VCS.Repositories do
  @moduledoc """
  A module that provides functions to interact with VCS repositories.
  """
  alias Tuist.GitHub
  alias Tuist.Repo
  alias Tuist.VCS

  def get_repository_from_repository_url(repository_url) do
    vcs_uri = URI.parse(repository_url)
    host = Map.get(vcs_uri, :host)

    if host == "github.com" do
      client = get_client_for_provider(:github)

      repository_url
      |> get_repository_full_handle_from_url()
      |> client.get_repository()
    else
      {:error, :unsupported_vcs}
    end
  end

  def get_user_permission(%{
        user: user,
        repository: %VCS.Repositories.Repository{provider: provider, full_handle: full_handle}
      }) do
    user = Repo.preload(user, :oauth2_identities)

    github_identity = Enum.find(user.oauth2_identities, &(&1.provider == provider))

    client = get_client_for_provider(provider)

    if is_nil(github_identity) do
      nil
    else
      with {:user, {:ok, %VCS.User{username: username}}} <-
             {:user,
              client.get_user_by_id(%{
                id: github_identity.id_in_provider,
                repository_full_handle: full_handle
              })},
           {:permission, {:ok, %VCS.Repositories.Permission{} = permission}} <-
             {:permission,
              Tuist.GitHub.Client.get_user_permission(%{
                username: username,
                repository_full_handle: full_handle
              })} do
        {:ok, permission}
      else
        {:user, {:error, error_message}} ->
          {:error, "Could not fetch user: #{error_message}"}

        {:permission, {:error, error_message}} ->
          {:error, "Could not fetch user permission: #{error_message}"}
      end
    end
  end

  defp get_client_for_provider(:github) do
    GitHub.Client
  end

  defp get_repository_full_handle_from_url(repository_url) do
    repository_url |> URI.parse() |> Map.get(:path) |> String.replace_leading("/", "")
  end
end
