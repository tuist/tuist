defmodule TuistWeb.UserLoginLive do
  use TuistWeb, :live_view
  use TuistWeb.Noora
  alias Tuist.Environment
  alias Phoenix.Flash

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")

    {
      :ok,
      socket
      |> assign(:head_title, "#{gettext("Log in")} · Tuist")
      |> assign(:form, form)
      |> assign(:mail_configured?, Environment.mail_configured?())
      |> assign(:github_auth_configured?, Environment.github_auth_configured?())
      |> assign(:google_configured?, Environment.google_oauth_configured?())
      |> assign(:okta_configured?, Environment.okta_configured?()),
      temporary_assigns: [form: form]
    }
  end

  def render(assigns) do
    ~H"""
    <%= if FunWithFlags.enabled?(:noora) do %>
      <.noora_login {assigns} />
    <% else %>
      <.legacy_login {assigns} />
    <% end %>
    """
  end

  def noora_login(assigns) do
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
          <div :if={oauth_configured?()} data-part="oauth">
            <.button
              :if={@github_auth_configured?}
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
              href={~p"/users/auth/okta"}
              variant="secondary"
              size="medium"
              label="Okta"
            >
              <:icon_left>
                <.brand_okta />
              </:icon_left>
            </.button>
          </div>
          <.line_divider :if={oauth_configured?() and @mail_configured?} text="OR" />
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
              required
            />
            <.text_input
              field={@form[:password]}
              label={gettext("Password")}
              id="password"
              type="password"
              show_prefix={false}
              error={Flash.get(@flash, :error)}
              required
            />
            <div data-part="remember-me">
              <.checkbox
                id="remember_me"
                field={@form[:remember_me]}
                label={gettext("Keep me logged in")}
              />
              <.link_button
                navigate={~p"/users/reset_password"}
                variant="primary"
                size="large"
                label={gettext("Forgot password?")}
              />
            </div>
            <.button variant="primary" size="large" label={gettext("Log in")} />
          </.form>
        </div>
        <div :if={@mail_configured?} data-part="signup-link">
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

  defp oauth_configured?() do
    Environment.github_auth_configured?() || Environment.google_oauth_configured?() ||
      Environment.okta_configured?()
  end

  def legacy_login(assigns) do
    ~H"""
    <.stack class="auth-page" gap="4xl">
      <.decorative_background class="auth-page__background" />
      <.stack class="auth-header" gap="3xl">
        <img
          class="auth-header__logo"
          src="/images/tuist_logo_32x32@2x.png"
          alt={gettext("Tuist Icon")}
        />
        <.stack gap="lg">
          <h5 class="auth-header__title font--semibold color--text-primary">
            {gettext("Log in to your account")}
          </h5>
          <p class="text--medium color--text-tertiary">
            {gettext("Welcome back! Please enter your details.")}
          </p>
        </.stack>
      </.stack>
      <.stack gap="xl">
        <.simple_form
          for={@form}
          id="login_form"
          action={~p"/users/log_in"}
          phx-update="ignore"
          class="auth-form"
        >
          <.stack gap="3xl">
            <%= if @mail_configured? do %>
              <.stack gap="2xl">
                <.input
                  field={@form[:email]}
                  type="email"
                  label={gettext("Email")}
                  placeholder={gettext("Enter your email")}
                  required
                />
                <.input
                  field={@form[:password]}
                  type="password"
                  label={gettext("Password")}
                  placeholder={gettext("Enter your password")}
                  required
                />
              </.stack>
              <.stack direction="horizontal">
                <.input
                  field={@form[:remember_me]}
                  type="checkbox"
                  label={gettext("Keep me logged in")}
                />
                <a href={~p"/users/reset_password"} class="text--small font--semibold">
                  {gettext("Forgot your password?")}
                </a>
              </.stack>
            <% end %>
            <.stack gap="xl">
              <%= if @mail_configured? do %>
                <.legacy_button type="submit" variant="primary" class="auth-form__primary-action">
                  {gettext("Sign in")}
                </.legacy_button>
              <% end %>
            </.stack>
          </.stack>
        </.simple_form>
        <%= if @github_auth_configured? do %>
          <.social_button>
            <a href={~p"/users/auth/github"}>
              {gettext("Sign in with GitHub")}
            </a>
            <:icon><.github_icon /></:icon>
          </.social_button>
        <% end %>
        <%= if @google_configured? do %>
          <.social_button>
            <a href={~p"/users/auth/google"}>
              {gettext("Sign in with Google")}
            </a>
            <:icon><.google_icon /></:icon>
          </.social_button>
        <% end %>
        <%= if @okta_configured? do %>
          <.social_button>
            <a href={~p"/users/auth/okta"}>
              {gettext("Sign in with Okta")}
            </a>
            <:icon><.okta_icon /></:icon>
          </.social_button>
        <% end %>
      </.stack>

      <%= if @mail_configured? do %>
        <.stack direction="horizontal" gap="xs">
          <span class="text--small font--regular color--text-tertiary">
            {gettext("Don't have an account?")}
          </span>
          <a href={~p"/users/register"} class="text--small font--semibold">
            {gettext("Sign up")}
          </a>
        </.stack>
      <% end %>

      <.flash_group flash={@flash} />
    </.stack>
    """
  end
end
