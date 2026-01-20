defmodule TuistWeb.GitHubAppSetupController do
  @moduledoc """
  Controller for handling GitHub App post-installation setup.

  This controller is called by GitHub after a user installs the Tuist GitHub App.
  The setup URL should be configured in the GitHub App settings as:
  https://yourdomain.com/integrations/github/setup
  """

  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.VCS
  alias TuistWeb.Errors.BadRequestError

  def setup(conn, params) do
    with {:ok, installation_id} <- extract_installation_id(params),
         {:ok, account_id} <- extract_account_id(params),
         {:ok, account} <- Accounts.get_account_by_id(account_id),
         {:ok, _github_app_installation} <-
           VCS.create_github_app_installation(%{account_id: account.id, installation_id: installation_id}) do
      redirect(conn, to: ~p"/#{account.name}/integrations")
    else
      {:error, :missing_installation_id} ->
        raise BadRequestError, dgettext("dashboard", "Invalid GitHub app installation. Please try again.")

      {:error, :missing_account_id} ->
        raise BadRequestError, dgettext("dashboard", "Invalid GitHub app installation. Please try again.")

      {:error, :invalid_state_token} ->
        raise BadRequestError, dgettext("dashboard", "Invalid installation request. Please try again.")
    end
  end

  defp extract_installation_id(%{"installation_id" => installation_id}) when is_binary(installation_id) do
    {:ok, installation_id}
  end

  defp extract_installation_id(_params) do
    {:error, :missing_installation_id}
  end

  defp extract_account_id(%{"state" => state_token}) when is_binary(state_token) do
    case VCS.verify_github_state_token(state_token) do
      {:ok, account_id} -> {:ok, account_id}
      {:error, _reason} -> {:error, :invalid_state_token}
    end
  end

  defp extract_account_id(_params) do
    {:error, :missing_account_id}
  end
end
