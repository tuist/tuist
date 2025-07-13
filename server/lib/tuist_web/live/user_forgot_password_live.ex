defmodule TuistWeb.UserForgotPasswordLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Accounts

  def render(assigns) do
    ~H"""
    <.noora_forgot_password {assigns} />
    """
  end

  def noora_forgot_password(assigns) do
    ~H"""
    <div id="forgot-password">
      <div data-part="frame">
        <div data-part="content">
          <img src="/images/tuist_logo_32x32@2x.png" alt={gettext("Tuist Logo")} data-part="logo" />
          <div data-part="dots">
            <.dots_light />
            <.dots_dark />
          </div>
          <div data-part="header">
            <h1 data-part="title">{gettext("Forgot your password?")}</h1>
            <span data-part="subtitle">
              {gettext("We'll send a password reset link to your inbox")}
            </span>
          </div>
          <%= if @success do %>
            <.alert
              id="forgot-password-success"
              type="secondary"
              status="information"
              size="large"
              title={gettext("Check your email")}
              description={
                gettext(
                  "If your email exists in our records, you'll receive reset instructions shortly."
                )
              }
            />
          <% else %>
            <.form data-part="form" for={@form} id="login_form" phx-submit="send_email">
              <.text_input
                field={@form[:email]}
                label={gettext("Email address")}
                type="email"
                placeholder="hello@tuist.dev"
                show_prefix={false}
                required
              />
              <.button variant="primary" size="large" label={gettext("Reset password")} />
            </.form>
          <% end %>
        </div>

        <div data-part="bottom-link">
          <.link_button
            navigate={~p"/users/log_in"}
            variant="primary"
            size="large"
            label={gettext("Back to log in")}
          />
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

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"), success: false)}
  end

  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(%{
        user: user,
        reset_password_url: &url(~p"/users/reset_password/#{&1}")
      })
    end

    {:noreply, assign(socket, success: true)}
  end
end
