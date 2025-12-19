defmodule TuistWeb.UserConfirmationLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Accounts

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
            <%= if @success do %>
              <div data-part="header">
                <h1 data-part="title">{dgettext("dashboard_auth", "Account confirmed!")}</h1>
                <span data-part="subtitle">
                  {dgettext("dashboard_auth", "Your account has been confirmed.")}
                </span>
              </div>
              <.alert
                id="confirmation-success"
                type="secondary"
                status="success"
                size="small"
                title={
                  dgettext(
                    "dashboard_auth",
                    "Your account has been confirmed. You will be redirected shortly..."
                  )
                }
              />
            <% else %>
              <div data-part="header">
                <h1 data-part="title">{dgettext("dashboard_auth", "Confirmation failed")}</h1>
                <span data-part="subtitle">
                  {dgettext("dashboard_auth", "Your account could not be confirmed.")}
                </span>
              </div>
              <.alert
                id="confirmation-failure"
                type="secondary"
                status="error"
                size="small"
                title={
                  dgettext("dashboard_auth", "User confirmation link is invalid or it has expired.")
                }
              />
            <% end %>
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

  def mount(%{"token" => token}, _session, socket) do
    if connected?(socket) do
      case Accounts.confirm_user(token) do
        {:ok, _} ->
          Process.send_after(self(), :redirect, 5000)
          {:ok, assign(socket, success: true)}

        :error ->
          {:ok, assign(socket, success: false)}
      end
    else
      {:ok, assign(socket, success: true)}
    end
  end

  def handle_info(:redirect, socket) do
    {:noreply, redirect(socket, to: ~p"/projects/new")}
  end
end
