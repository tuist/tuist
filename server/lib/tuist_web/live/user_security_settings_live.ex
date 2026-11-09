defmodule TuistWeb.UserSecuritySettingsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Accounts.UserMFA
  alias Tuist.Accounts.UserPasskey
  alias Tuist.Environment

  @impl true
  def mount(_params, _session, socket) do
    %{current_user: user, selected_account: account, live_action: action} = socket.assigns

    if account.user_id != user.id or (action == :passkeys and not Environment.email_auth_enabled?()) do
      raise TuistWeb.Errors.NotFoundError
    end

    title =
      if action == :passkeys,
        do: dgettext("dashboard_auth", "Passkeys"),
        else: dgettext("dashboard_auth", "Two-factor authentication")

    {:ok,
     socket
     |> assign(:title, title)
     |> assign(:head_title, "#{title} · Tuist")
     |> assign(:fresh_session?, UserMFA.fresh_session?(socket.assigns.current_user_session, user))
     |> assign(:passkeys, UserPasskey.list(user))
     |> assign(:enabled, UserMFA.enabled?(user))
     |> assign(:recovery_code_count, UserMFA.recovery_code_count(user)), layout: false}
  end

  @impl true
  def handle_event("close-security-modal", %{"id" => id}, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: id})}
  end
end
