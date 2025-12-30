defmodule TuistWeb.DeviceCodesSuccessLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Accounts
  alias TuistWeb.Authentication

  def mount(%{"device_code" => device_code, "type" => type} = _conn, _session, socket) do
    Accounts.authenticate_device_code(
      device_code,
      Authentication.current_user(socket)
    )

    {:ok, assign(socket, type: type)}
  end

  def render(assigns) do
    ~H"""
    <div id="confirmation">
      <div data-part="wrapper">
        <div data-part="frame">
          <div data-part="content">
            <img
              src="/images/tuist_logo_32x32@2x.png"
              alt={dgettext("dashboard_auth", "Tuist Logo")}
              data-part="logo"
            />
            <div data-part="dots">
              <.dots_light />
              <.dots_dark />
            </div>
            <div data-part="header">
              <h1 data-part="title">
                <%= case @type do %>
                  <% "app" -> %>
                    {dgettext("dashboard_auth", "Tuist app is connected!")}
                  <% "cli" -> %>
                    {dgettext("dashboard_auth", "Tuist CLI is connected!")}
                  <% _ -> %>
                    {dgettext("dashboard_auth", "Tuist is connected!")}
                <% end %>
              </h1>
              <span data-part="subtitle">
                <%= case @type do %>
                  <% "app" -> %>
                    {dgettext("dashboard_auth", "You can close the tab and continue in the app")}
                  <% "cli" -> %>
                    {dgettext("dashboard_auth", "You can close the tab and continue in the terminal")}
                  <% _ -> %>
                    {dgettext("dashboard_auth", "You can close the tab and continue")}
                <% end %>
              </span>
            </div>
            <.button
              data-part="dashboard-button"
              variant="primary"
              size="large"
              label={dgettext("dashboard_auth", "Dashboard")}
              href={
                TuistWeb.Authentication.signed_in_path(TuistWeb.Authentication.current_user(assigns))
              }
            />
          </div>
        </div>
      </div>

      <div data-part="background">
        <div data-part="top-right-gradient"></div>
        <div data-part="bottom-left-gradient"></div>
        <div data-part="shell"><.shell /></div>
      </div>
    </div>
    """
  end
end
