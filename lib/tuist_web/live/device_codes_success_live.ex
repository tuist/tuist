defmodule TuistWeb.DeviceCodesSuccessLive do
  use TuistWeb, :live_view
  alias Tuist.Accounts
  alias TuistWeb.Authentication

  def mount(%{"device_code" => device_code, "type" => type} = _conn, _session, socket) do
    Accounts.authenticate_device_code(
      device_code,
      Authentication.current_user(socket)
    )

    {:ok, socket |> assign(type: type)}
  end

  def render(assigns) do
    ~H"""
    <.stack class="auth-page" gap="4xl">
      <.auth_header
        title={
          case @type do
            "app" -> gettext("Tuist app is connected")
            "cli" -> gettext("Tuist CLI is connected")
            _ -> gettext("Tuist is connected")
          end
        }
        subtitle={
          case @type do
            "app" -> gettext("You can close the tab and continue in the app 🎉")
            "cli" -> gettext("You can close the tab and continue in the terminal 🎉")
            _ -> gettext("You can close the tab and continue 🎉")
          end
        }
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
