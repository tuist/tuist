defmodule TuistWeb.SSOLoginLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Phoenix.Flash
  alias Tuist.Accounts
  alias Tuist.OAuth.Okta
  alias Tuist.Environment

  def mount(_params, _session, socket) do
    email = Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")

    socket =
      socket
      |> assign(:head_title, "#{gettext("SSO Log in")} · Tuist")
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
        case Okta.config_for_organization(organization) do
          {:ok, config} ->
            okta_url = build_okta_authorization_url(config, organization.id)
            {:noreply, redirect(socket, external: okta_url)}

          {:error, :okta_not_configured} ->
            socket = put_flash(socket, :error, gettext("SSO is not configured for your organization"))
            {:noreply, socket}
        end

      {:error, :not_found} ->
        socket = put_flash(socket, :error, gettext("No SSO organization found for this email domain"))
        {:noreply, socket}
    end
  end

  defp build_okta_authorization_url(config, organization_id) do
    base_url = "https://#{config.domain}"
    callback_url = Environment.app_url(path: "/users/auth/okta/callback")
    
    # Encode organization ID in state parameter for callback processing
    state_data = %{
      random: Base.url_encode64(:crypto.strong_rand_bytes(16)),
      org_id: organization_id
    }
    state = Base.url_encode64(:erlang.term_to_binary(state_data))

    params = %{
      client_id: config.client_id,
      response_type: "code",
      scope: "openid email profile",
      redirect_uri: callback_url,
      state: state
    }

    query_string = URI.encode_query(params)
    "#{base_url}#{config.authorize_url}?#{query_string}"
  end

  def render(assigns) do
    ~H"""
    <div id="sso-login">
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
              {gettext("Enter your work email to continue with SSO")}
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
              label={gettext("Email address")}
              type="email"
              placeholder="hello@yourcompany.com"
              show_prefix={false}
              error={Flash.get(@flash, :error)}
              show_error_message={false}
              required
            />
            <.button variant="primary" size="large" label={gettext("Continue with SSO")} />
          </.form>
        </div>
        <div data-part="bottom-link">
          <span>{gettext("Need help with SSO?")}</span>
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