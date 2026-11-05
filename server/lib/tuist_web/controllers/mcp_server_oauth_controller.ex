defmodule TuistWeb.MCPServerOAuthController do
  @moduledoc """
  Where an MCP server's authorization server sends the user back after they
  approve (or deny) Tuist. The single-use `state` is bound to the signed-in
  user by `Tuist.Accounts.MCPServers.complete_authorization/2`, so a callback
  opened in another user's session completes nothing.
  """
  use TuistWeb, :controller

  alias Tuist.Accounts.MCPServers
  alias Tuist.FeatureFlags

  def callback(%{assigns: %{current_user: user}} = conn, params) do
    settings_path = ~p"/#{user.account.name}/settings/ai"

    if FeatureFlags.ai_enabled?(user) do
      case MCPServers.complete_authorization(user, params) do
        {:ok, server} ->
          conn
          |> put_flash(:info, dgettext("dashboard_account", "Connected to %{name}.", name: server.name))
          |> redirect(to: settings_path)

        {:error, :access_denied} ->
          conn
          |> put_flash(:error, dgettext("dashboard_account", "The MCP server sign-in was cancelled."))
          |> redirect(to: settings_path)

        {:error, _reason} ->
          conn
          |> put_flash(
            :error,
            dgettext("dashboard_account", "The MCP server sign-in did not complete. Please try again.")
          )
          |> redirect(to: settings_path)
      end
    else
      redirect(conn, to: ~p"/#{user.account.name}/settings")
    end
  end
end
