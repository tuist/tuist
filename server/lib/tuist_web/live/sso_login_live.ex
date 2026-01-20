defmodule TuistWeb.SSOLoginLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Phoenix.Flash
  alias Tuist.Accounts

  def mount(_params, _session, socket) do
    email = Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")

    socket = assign(socket, :form, form)

    {
      :ok,
      socket,
      temporary_assigns: [form: form]
    }
  end

  def handle_event("submit", %{"user" => %{"email" => email}}, socket) do
    email = String.trim(email)

    case Accounts.okta_organization_for_user_email(email) do
      {:ok, organization} ->
        encoded_email = URI.encode_www_form(email)
        redirect_url = "/users/auth/okta?organization_id=#{organization.id}&login_hint=#{encoded_email}"
        {:noreply, redirect(socket, to: redirect_url)}

      {:error, :not_found} ->
        socket = put_flash(socket, :error, dgettext("dashboard_auth", "No SSO organization found for this email"))
        {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div id="sso-login">
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
            <h1 data-part="title">{dgettext("dashboard_auth", "Log in to Tuist")}</h1>
            <span data-part="subtitle">
              {dgettext("dashboard_auth", "Log in to your enterprise account via Okta")}
            </span>
          </div>
          <.form data-part="form" for={@form} id="sso_login_form" phx-submit="submit">
            <.alert
              :if={Flash.get(@flash, :error)}
              id="alert"
              type="secondary"
              status="error"
              size="small"
              title={Flash.get(@flash, :error)}
            />
            <.text_input
              field={@form[:email]}
              id="email"
              label={dgettext("dashboard_auth", "Email address")}
              type="email"
              placeholder="hello@tuist.dev"
              show_prefix={false}
              error={Flash.get(@flash, :error)}
              show_error_message={false}
              required
            />
            <.button variant="primary" size="large" label={dgettext("dashboard_auth", "Log in")} />
          </.form>
        </div>
        <div data-part="bottom-link">
          <span>{dgettext("dashboard_auth", "Interested in SSO?")}</span>
          <.link_button
            href="mailto:contact@tuist.dev"
            variant="primary"
            size="large"
            label={dgettext("dashboard_auth", "Contact us")}
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
end
