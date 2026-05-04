defmodule TuistWeb.GitHubAppSetupController do
  @moduledoc """
  Handles the post-installation callback GitHub redirects to once a user
  finishes installing the Tuist GitHub App. Two flows land here:

  - **github.com**: the App is globally registered for Tuist Cloud, so we
    create a fresh `GitHubAppInstallation` row keyed on `account_id` with
    the `installation_id` GitHub assigned. Per-installation App
    credential columns stay nil and Tuist falls back to the
    `TUIST_GITHUB_APP_*` env vars.

  - **GitHub Enterprise Server (manifest flow)**: a pending row already
    exists — `TuistWeb.GitHubAppManifestController` created it when GHES
    finished the App registration and handed Tuist the new App's
    credentials. We just fill in the `installation_id` (and `html_url`
    from the install webhook later) on that row.

  Calling the setup endpoint twice for the same `(account, installation)`
  is a no-op; reusing an installation that's already linked to a
  *different* account is rejected.
  """

  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.VCS
  alias Tuist.VCS.GitHubAppInstallation
  alias TuistWeb.Errors.BadRequestError

  def setup(conn, params) do
    with {:ok, installation_id} <- extract_installation_id(params),
         {:ok, %{account_id: account_id, client_url: client_url}} <- extract_state(params),
         {:ok, account} <- Accounts.get_account_by_id(account_id),
         {:ok, _installation} <- attach_installation_id(account, client_url, installation_id) do
      redirect(conn, to: ~p"/#{account.name}/integrations")
    else
      {:error, :missing_installation_id} ->
        raise BadRequestError, dgettext("dashboard", "Invalid GitHub app installation. Please try again.")

      {:error, :missing_state} ->
        raise BadRequestError, dgettext("dashboard", "Invalid GitHub app installation. Please try again.")

      {:error, :invalid_state_token} ->
        raise BadRequestError, dgettext("dashboard", "Invalid installation request. Please try again.")

      {:error, :installation_already_connected} ->
        raise BadRequestError, dgettext("dashboard", "This GitHub app installation is already connected.")
    end
  end

  defp attach_installation_id(account, client_url, installation_id) do
    installation_id = to_string(installation_id)

    case VCS.get_github_app_installation_by_installation_id(installation_id) do
      {:ok, %GitHubAppInstallation{account_id: account_id}} when account_id != account.id ->
        {:error, :installation_already_connected}

      {:ok, existing} ->
        # Idempotent re-install for the same account.
        {:ok, existing}

      {:error, :not_found} ->
        case VCS.get_github_app_installation_for_account(account.id) do
          {:ok, pending} ->
            # GHES manifest flow: a pending row already carries the App
            # credentials; fill in the installation_id GitHub just assigned.
            VCS.update_github_app_installation(pending, %{installation_id: installation_id})

          {:error, :not_found} ->
            VCS.create_github_app_installation(%{
              account_id: account.id,
              installation_id: installation_id,
              client_url: client_url || VCS.default_client_url()
            })
        end
    end
  end

  defp extract_installation_id(%{"installation_id" => installation_id}) when is_binary(installation_id) do
    {:ok, installation_id}
  end

  defp extract_installation_id(_params) do
    {:error, :missing_installation_id}
  end

  defp extract_state(%{"state" => state_token}) when is_binary(state_token) do
    case VCS.verify_github_state_token(state_token) do
      {:ok, %{account_id: _, client_url: _} = payload} -> {:ok, payload}
      {:error, _reason} -> {:error, :invalid_state_token}
    end
  end

  defp extract_state(_params) do
    {:error, :missing_state}
  end
end
