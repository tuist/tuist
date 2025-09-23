defmodule TuistWeb.GitHubAppSetupController do
  @moduledoc """
  Controller for handling GitHub App post-installation setup.

  This controller is called by GitHub after a user installs the Tuist GitHub App.
  The setup URL should be configured in the GitHub App settings as:
  https://yourdomain.com/integrations/github/setup
  """

  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Accounts.GitHubAppInstallation
  alias Tuist.GitHubStateToken
  alias Tuist.Repo

  require Logger

  def setup(conn, params) do
    Logger.info("GitHub App setup initiated with params: #{inspect(params)}")

    with {:ok, installation_id} <- extract_installation_id(params),
         {:ok, account_id} <- extract_account_id(params),
         {:ok, account} <- get_account(account_id),
         {:ok, _github_app_installation} <- create_github_app_installation(account, installation_id) do
      Logger.info("Successfully created GitHub App installation for account #{account.id}")

      conn
      |> put_flash(:info, gettext("GitHub App successfully installed and configured!"))
      |> redirect(to: ~p"/#{account.name}/integrations")
    else
      {:error, :missing_installation_id} ->
        Logger.warning("GitHub App setup attempted without installation_id")
        redirect_with_error(conn, gettext("Invalid GitHub App installation. Please try again."))

      {:error, :missing_account_id} ->
        Logger.warning("GitHub App setup attempted without state parameter")
        redirect_with_error(conn, gettext("Installation session expired. Please try installing again."))

      {:error, :invalid_state_token} ->
        Logger.warning("GitHub App setup attempted with invalid state token")
        redirect_with_error(conn, gettext("Invalid installation request. Please try installing again."))

      {:error, :account_not_found} ->
        Logger.warning("GitHub App setup attempted for non-existent account")
        redirect_with_error(conn, gettext("Account not found. Please contact support."))

      {:error, changeset} ->
        Logger.error("Failed to create GitHub App installation: #{inspect(changeset.errors)}")

        case changeset.errors do
          [installation_id: {_, [constraint: :unique]}] ->
            redirect_with_error(conn, gettext("GitHub App is already installed for this account."))

          [account_id: {_, [constraint: :unique]}] ->
            redirect_with_error(conn, gettext("This account already has a GitHub App installation."))

          _ ->
            redirect_with_error(conn, gettext("Failed to set up GitHub App. Please try again."))
        end

      error ->
        Logger.error("Unexpected error during GitHub App setup: #{inspect(error)}")
        redirect_with_error(conn, gettext("An unexpected error occurred. Please try again."))
    end
  end

  defp extract_installation_id(%{"installation_id" => installation_id}) when is_binary(installation_id) do
    {:ok, installation_id}
  end

  defp extract_installation_id(_params) do
    {:error, :missing_installation_id}
  end

  defp extract_account_id(%{"state" => state_token}) when is_binary(state_token) do
    case GitHubStateToken.verify_token(state_token) do
      {:ok, account_id} -> {:ok, account_id}
      {:error, _reason} -> {:error, :invalid_state_token}
    end
  end

  defp extract_account_id(_params) do
    {:error, :missing_account_id}
  end

  defp get_account(account_id) do
    case Accounts.get_account_by_id(account_id) do
      nil -> {:error, :account_not_found}
      account -> {:ok, account}
    end
  end

  defp create_github_app_installation(account, installation_id) do
    attrs = %{
      account_id: account.id,
      installation_id: installation_id
    }

    %GitHubAppInstallation{}
    |> GitHubAppInstallation.changeset(attrs)
    |> Repo.insert()
  end

  defp redirect_with_error(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/users/log_in")
  end
end
