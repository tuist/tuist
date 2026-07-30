defmodule TuistWeb.UserConfirmationInstructionsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.AppAuthComponents

  alias Tuist.Accounts
  alias Tuist.Environment

  def render(assigns) do
    ~H"""
    <div id="confirmation-instructions">
      <div data-part="frame">
        <div data-part="content">
          <img
            src={~p"/images/tuist_logo_32x32@2x.png"}
            alt={dgettext("dashboard_auth", "Tuist Logo")}
            data-part="logo"
            decoding="async"
          />
          <div data-part="dots">
            <.dots_light />
            <.dots_dark />
          </div>
          <div data-part="header">
            <h1 data-part="title">{dgettext("dashboard_auth", "Confirm your email")}</h1>
            <span data-part="subtitle">
              {dgettext("dashboard_auth", "Confirm your email address to finish signing in")}
            </span>
          </div>
          <%= cond do %>
            <% @success -> %>
              <.alert
                id="confirmation-instructions-success"
                type="secondary"
                status="information"
                size="large"
                title={dgettext("dashboard_auth", "Check your email")}
                description={
                  dgettext(
                    "dashboard_auth",
                    "If your email is registered and not yet confirmed, you'll receive a confirmation link shortly."
                  )
                }
              />
            <% @email -> %>
              <.alert
                id="confirmation-instructions-pending"
                type="secondary"
                status="information"
                size="large"
                title={dgettext("dashboard_auth", "Your email isn't confirmed yet")}
                description={
                  dgettext(
                    "dashboard_auth",
                    "We'll send a new confirmation link to %{email}.",
                    email: @email
                  )
                }
              />
              <.button
                variant="primary"
                size="large"
                label={dgettext("dashboard_auth", "Resend confirmation email")}
                phx-click="resend"
              />
            <% true -> %>
              <.form
                data-part="form"
                for={@form}
                id="confirmation_instructions_form"
                phx-submit="send_email"
              >
                <.text_input
                  field={@form[:email]}
                  label={dgettext("dashboard_auth", "Email address")}
                  type="email"
                  placeholder="hello@tuist.dev"
                  show_prefix={false}
                  required
                />
                <.button
                  variant="primary"
                  size="large"
                  label={dgettext("dashboard_auth", "Resend confirmation email")}
                />
              </.form>
          <% end %>
        </div>

        <div data-part="bottom-link">
          <.link_button
            navigate={~p"/users/log_in"}
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

  def mount(_params, session, socket) do
    if Environment.email_auth_enabled?() do
      email = session["unconfirmed_email"]

      {:ok, assign(socket, form: to_form(%{}, as: "user"), email: email, success: false)}
    else
      {:ok, redirect(socket, to: ~p"/users/log_in")}
    end
  end

  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    deliver_confirmation_instructions(email, socket)
  end

  def handle_event("resend", _params, socket) do
    deliver_confirmation_instructions(socket.assigns.email, socket)
  end

  defp deliver_confirmation_instructions(email, socket) do
    if Environment.email_auth_enabled?() do
      email = String.trim(email || "")

      case Accounts.get_user_by_email(email) do
        {:ok, user} ->
          Accounts.deliver_user_confirmation_instructions(%{
            user: user,
            confirmation_url: &url(~p"/users/confirm/#{&1}")
          })

        {:error, :not_found} ->
          :ok
      end

      {:noreply, assign(socket, success: true)}
    else
      {:noreply, redirect(socket, to: ~p"/users/log_in")}
    end
  end
end
