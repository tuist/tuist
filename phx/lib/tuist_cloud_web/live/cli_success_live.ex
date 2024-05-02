defmodule TuistCloudWeb.CLISuccessLive do
  use TuistCloudWeb, :live_view
  alias TuistCloud.Accounts
  alias TuistCloudWeb.Authentication

  def mount(%{"device_code" => device_code}, _session, socket) do
    Accounts.authenticate_device_code(
      device_code,
      Authentication.current_user(socket)
    )

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <link phx-track-static rel="stylesheet" href={~p"/v2/css/auth.css"} />

    <.stack class="auth-page" gap="4xl">
      <.auth_header
        title={gettext("Tuist CLI is connected")}
        subtitle={gettext("You can close the tab and continue in the terminal 🎉")}
      />
      <div>
        <.button>
          <a href={~p"/v2"} class="color--text-primary">
            <%= gettext("Dashboard") %>
          </a>
        </.button>
      </div>
    </.stack>
    """
  end
end
