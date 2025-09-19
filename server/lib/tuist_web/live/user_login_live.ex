defmodule TuistWeb.UserLoginLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Phoenix.Flash
  alias Tuist.Environment

  def mount(_params, _session, socket) do
    email = Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")

    socket =
      socket
      |> assign(:head_title, "#{gettext("Log in")} · Tuist")
      |> assign(:form, form)
      |> assign(:mail_configured?, Environment.mail_configured?())
      |> assign(:github_configured?, Environment.github_oauth_configured?())
      |> assign(:google_configured?, Environment.google_oauth_configured?())
      |> assign(:okta_configured?, Environment.okta_oauth_configured?())
      |> assign(:apple_configured?, Environment.apple_oauth_configured?())

    {
      :ok,
      socket,
      temporary_assigns: [form: form]
    }
  end

  def render(assigns) do
    ~H"""
    <div id="login">
      <div data-part="frame">
        <div data-part="content">
          <img src="/images/tuist_logo_32x32@2x.png" alt={gettext("Tuist Logo")} data-part="logo" />
          <div data-part="dots">
            <.dots_light />
            <.dots_dark />
          </div>
          <div data-part="header">
            <h1 data-part="title">{gettext("Log in to Tuist")}</h1>
            <span data-part="subtitle">{gettext("Welcome back! Please log in to continue")}</span>
          </div>
          <div
            :if={oauth_configured?()}
            data-part="oauth"
            data-compact={
              @github_configured? and @apple_configured? and @google_configured? and
                @okta_configured?
            }
          >
            <.button
              :if={@github_configured?}
              href={~p"/users/auth/github"}
              variant="secondary"
              size="medium"
              label="GitHub"
            >
              <:icon_left>
                <.brand_github />
              </:icon_left>
            </.button>
            <.button
              :if={@google_configured?}
              href={~p"/users/auth/google"}
              variant="secondary"
              size="medium"
              label="Google"
            >
              <:icon_left>
                <.brand_google />
              </:icon_left>
            </.button>
            <.button
              :if={@okta_configured?}
              href={~p"/users/log_in/okta"}
              variant="secondary"
              size="medium"
              label="Okta"
            >
              <:icon_left>
                <.brand_okta />
              </:icon_left>
            </.button>
            <.button
              :if={@apple_configured?}
              href={~p"/users/auth/apple"}
              variant="secondary"
              size="medium"
              label="Apple"
            >
              <:icon_left>
                <.brand_apple />
              </:icon_left>
            </.button>
          </div>
          <.line_divider :if={oauth_configured?() and @mail_configured?} text="OR" />
          <.alert
            :if={Flash.get(@flash, :info)}
            id="flash"
            type="secondary"
            status="information"
            size="small"
            title={Flash.get(@flash, :info)}
          />
          <.form
            :if={@mail_configured?}
            data-part="form"
            for={@form}
            id="login_form"
            action={~p"/users/log_in"}
            phx-update="ignore"
          >
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
              tabindex={1}
            />
            <.text_input
              field={@form[:password]}
              label={gettext("Password")}
              id="password"
              input_type="password"
              show_prefix={false}
              error={Flash.get(@flash, :error)}
              show_error_message={false}
              required
              tabindex={2}
            />
            <div data-part="remember-me">
              <.checkbox
                id="remember_me"
                field={@form[:remember_me]}
                label={gettext("Keep me logged in")}
                tabindex={3}
              />
              <.link_button
                navigate={~p"/users/reset_password"}
                variant="primary"
                size="large"
                label={gettext("Forgot password?")}
              />
            </div>
            <.button variant="primary" size="large" label={gettext("Log in")} tabindex={4} />
          </.form>
        </div>
        <div :if={@mail_configured?} data-part="bottom-link">
          <span>{gettext("Don’t have an account?")}</span>
          <.link_button
            navigate={~p"/users/register"}
            variant="primary"
            size="large"
            label={gettext("Sign up")}
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

  defp oauth_configured? do
    Environment.github_oauth_configured?() || Environment.google_oauth_configured?() ||
      Environment.okta_oauth_configured?() || Environment.apple_oauth_configured?()
  end
end
