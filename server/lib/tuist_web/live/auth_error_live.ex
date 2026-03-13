defmodule TuistWeb.AuthErrorLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.AppAuthComponents

  def mount(_params, session, socket) do
    error_message =
      session["auth_error_message"] ||
        dgettext("dashboard_auth", "An unknown authentication error occurred.")

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_auth", "Authentication error")} · Tuist")
      |> assign(:error_message, error_message)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div id="auth-error">
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
            <h1 data-part="title">{dgettext("dashboard_auth", "Authentication failed")}</h1>
            <span data-part="subtitle">
              {@error_message}
            </span>
          </div>
          <.button
            href={~p"/users/log_in"}
            variant="primary"
            size="large"
            label={dgettext("dashboard_auth", "Back to log in")}
          />
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
