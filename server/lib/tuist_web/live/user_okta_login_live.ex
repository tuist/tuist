defmodule TuistWeb.UserOktaLoginLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Phoenix.Flash
  alias Tuist.Accounts

  def mount(_params, _session, socket) do
    email = Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")

    socket =
      socket
      |> assign(:head_title, "#{gettext("Okta log in")} · Tuist")
      |> assign(:form, form)

    {
      :ok,
      socket,
      temporary_assigns: [form: form]
    }
  end

  def handle_event("submit", %{"user" => %{"email" => email}}, socket) do
    case Accounts.okta_organization_for_user_email(email) do
      {:ok, organization} ->
        redirect_url = "/users/auth/okta?organization_id=#{organization.id}"
        {:noreply, redirect(socket, external: redirect_url)}

      {:error, :not_found} ->
        socket = put_flash(socket, :error, gettext("Logging in via Okta failed"))

        {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div id="okta-login">
      <div data-part="frame">
        <div data-part="content">
          <img src="/images/tuist_logo_32x32@2x.png" alt={gettext("Tuist Logo")} data-part="logo" />
          <div data-part="dots">
            <.dots_light />
            <.dots_dark />
          </div>
          <div data-part="header">
            <h1 data-part="title">{gettext("Log in to Tuist")}</h1>
            <span data-part="subtitle">
              {gettext("Log in to your enterprise account via Okta")}
            </span>
          </div>
          <.form data-part="form" for={@form} id="okta_login_form" phx-submit="submit">
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
              label={gettext("Email address")}
              type="email"
              placeholder="hello@tuist.dev"
              show_prefix={false}
              error={Flash.get(@flash, :error)}
              show_error_message={false}
              required
            />
            <.button variant="primary" size="large" label={gettext("Log in")} />
          </.form>
        </div>
        <div data-part="bottom-link">
          <span>{gettext("Interested in SSO?")}</span>

          <.link_button
            href="mailto:contact@tuist.dev"
            variant="primary"
            size="large"
            label={gettext("Contact us")}
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
