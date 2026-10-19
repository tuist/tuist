defmodule Tuist.GitHub.Installations do
  @moduledoc "Attaches verified GitHub installations without transferring ownership or mixing host credentials."

  alias Tuist.VCS
  alias Tuist.VCS.GitHubAppInstallation

  def attach(account, client_url, installation_id) do
    installation_id = to_string(installation_id)
    client_url = client_url || VCS.default_client_url()

    case VCS.get_github_app_installation_by_installation_id(installation_id, client_url: client_url) do
      {:ok, %GitHubAppInstallation{account_id: account_id}} when account_id != account.id ->
        {:error, :installation_already_connected}

      {:ok, existing} ->
        {:ok, existing}

      {:error, :not_found} ->
        attach_to_pending_or_create(account, client_url, installation_id)
    end
  end

  defp attach_to_pending_or_create(account, client_url, installation_id) do
    ghes? = client_url != VCS.default_client_url()

    case VCS.get_github_app_installation_for_account(account.id) do
      {:ok, %GitHubAppInstallation{client_url: ^client_url} = pending} ->
        VCS.update_github_app_installation(pending, %{installation_id: installation_id})

      {:ok, _other_host_pending} ->
        # Never retarget credentials registered for another GitHub host.
        {:error, :github_host_conflict}

      {:error, :not_found} when ghes? ->
        {:error, :ghes_setup_without_manifest}

      {:error, :not_found} ->
        VCS.create_github_app_installation(%{
          account_id: account.id,
          installation_id: installation_id,
          client_url: client_url
        })
    end
  end
end
