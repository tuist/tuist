defmodule TuistWeb.CLISuccessLive do
  use TuistWeb, :live_view
  alias Tuist.Accounts
  alias TuistWeb.Authentication

  def mount(%{"device_code" => device_code}, _session, socket) do
    Accounts.authenticate_device_code(
      device_code,
      Authentication.current_user(socket)
    )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.stack class="auth-page" gap="4xl">
      <.auth_header
        title={gettext("Tuist CLI is connected")}
        subtitle={gettext("You can close the tab and continue in the terminal 🎉")}
      />
      <div>
        <.button>
          <a href={~p"/"} class="color--text-primary">
            <%= gettext("Dashboard") %>
          </a>
        </.button>
      </div>
    </.stack>
    """
  end
end
