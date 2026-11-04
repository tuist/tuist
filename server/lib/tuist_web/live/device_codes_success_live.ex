defmodule TuistWeb.DeviceCodesSuccessLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.AppAuthComponents

  alias Tuist.Accounts
  alias TuistWeb.Authentication

  def mount(%{"device_code" => device_code, "type" => type} = _conn, _session, socket) do
    user = Authentication.current_user(socket)

    session = socket.assigns[:current_user_session]

    if Accounts.sso_requirement(user, session) == :ok do
      Accounts.authenticate_device_code(device_code, user, session)
      {:ok, assign(socket, type: type)}
    else
      # This page approves the code and its route has no SSO check of its own
      # (it is reached directly or through live navigation), so send the
      # session through the device-code route, which has one.
      {:ok, redirect(socket, to: ~p"/auth/device_codes/#{device_code}?type=#{type}")}
    end
  end

  def render(assigns) do
    ~H"""
    <div id="confirmation">
      <div data-part="wrapper">
        <div data-part="frame">
          <div data-part="content">
            <.tuist_mark data-part="logo" aria-label={dgettext("dashboard_auth", "Tuist Logo")} />
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
      <.terms_and_privacy />
    </div>
    """
  end
end
