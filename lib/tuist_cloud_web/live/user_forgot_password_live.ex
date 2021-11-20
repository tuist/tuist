defmodule TuistCloudWeb.UserForgotPasswordLive do
  use TuistCloudWeb, :live_view

  alias TuistCloud.Accounts

  def render(assigns) do
    ~H"""
    <link phx-track-static rel="stylesheet" href={~p"/css/auth.css"} />

    <.stack class="auth-page" gap="4xl">
      <.auth_header
        title={gettext("Forgot your password?")}
        subtitle={gettext("We'll send a password reset link to your inbox")}
      >
        <:icon>
          <div class="auth-header-icon">
            <.key />
          </div>
        </:icon>
      </.auth_header>

      <.simple_form for={@form} id="reset_password_form" phx-submit="send_email" class="auth-form">
        <.stack gap="3xl">
          <.input
            field={@form[:email]}
            type="email"
            label={gettext("Email")}
            placeholder={gettext("Enter your email")}
            required
          />
          <.stack gap="xl">
            <.button type="submit" variant="primary" class="auth-form__primary-action">
              <%= gettext("Reset password") %>
            </.button>
          </.stack>
        </.stack>
      </.simple_form>

      <.link href={~p"/users/log_in"} class="text--small font--semibold">
        <%= gettext("Back to log in") %>
      </.link>

      <.flash_group flash={@flash} />
    </.stack>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"))}
  end

  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/users/reset_password/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions to reset your password shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/users/log_in")}
  end
end
