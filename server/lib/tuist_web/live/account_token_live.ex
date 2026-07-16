defmodule TuistWeb.AccountTokenLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.AccountTokenHelpers

  alias Tuist.Accounts
  alias Tuist.Authorization

  @impl true
  def mount(
        %{"token_id" => token_id},
        _uri,
        %{assigns: %{selected_account: selected_account, current_user: current_user}} = socket
      ) do
    if Authorization.authorize(:account_token_read, current_user, selected_account) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_account", "You are not authorized to perform this action.")
    end

    case Accounts.get_account_token(selected_account, token_id) do
      {:ok, account_token} ->
        {:ok,
         socket
         |> assign(:account_token, account_token)
         |> assign(
           :can_delete_tokens?,
           Authorization.authorize(:account_token_delete, current_user, selected_account) == :ok
         )
         |> assign(
           :head_title,
           "#{account_token.name} · #{dgettext("dashboard_account", "Tokens")} · #{selected_account.name} · Tuist"
         )}

      {:error, :not_found} ->
        raise TuistWeb.Errors.NotFoundError,
              dgettext("dashboard_account", "Account token not found.")
    end
  end

  @impl true
  def handle_event("revoke_account_token", _params, socket) do
    with :ok <- ensure_can_delete(socket),
         {:ok, _token} <- Accounts.delete_account_token(socket.assigns.account_token) do
      {:noreply,
       socket
       |> put_flash(
         :info,
         dgettext("dashboard_account", "%{name} was revoked.", name: socket.assigns.account_token.name)
       )
       |> push_navigate(to: ~p"/#{socket.assigns.selected_account.name}/settings/tokens")}
    else
      {:error, :forbidden} ->
        {:noreply,
         put_flash(socket, :error, dgettext("dashboard_account", "You are not authorized to revoke account tokens."))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("dashboard_account", "Token could not be revoked."))}
    end
  end

  def handle_event("close_revoke_account_token_modal", _params, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "revoke-account-token-modal"})}
  end

  defp ensure_can_delete(%{assigns: %{can_delete_tokens?: true}}), do: :ok
  defp ensure_can_delete(_socket), do: {:error, :forbidden}
end
