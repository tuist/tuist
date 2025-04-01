defmodule TuistWeb.UserRegistrationLive do
  use TuistWeb, :live_view
  use TuistWeb.Noora
  import TuistWeb.AppAuthComponents
  alias Tuist.Accounts
  alias Phoenix.Flash
  alias Tuist.Environment

  def render(assigns) do
    ~H"""
    <%= if FunWithFlags.enabled?(:noora) do %>
      <.noora_registration {assigns} />
    <% else %>
      <.legacy_registration {assigns} />
    <% end %>
    """
  end

  def noora_registration(assigns) do
    ~H"""
    <div id="signup">
      <div data-part="wrapper">
        <div data-part="frame">
          <div data-part="features">
            <div data-part="feature">
              <div>
                <div data-part="icon"><.subtask /></div>
                <span data-part="title">{gettext("Selective testing")}</span>
              </div>
              <span data-part="description">
                {gettext("Discover how selective testing is reducing your test time.")}
              </span>
            </div>
            <div data-part="feature">
              <div>
                <div data-part="icon"><.database /></div>
                <span data-part="title">{gettext("Binary caching")}</span>
              </div>
              <span data-part="description">
                {gettext("Explore how binary caching is enhancing your build times.")}
              </span>
            </div>
            <div data-part="feature">
              <div>
                <div data-part="icon"><.devices /></div>
                <span data-part="title">{gettext("Previews")}</span>
              </div>
              <span data-part="description">{gettext("Instantly share your app using a URL.")}</span>
            </div>
          </div>
          <div data-part="image" data-oauth-enabled={oauth_configured?()}>
            <img data-theme="light" src="/app/images/signup-light.png" />
            <img data-theme="dark" src="/app/images/signup-dark.png" />
          </div>
        </div>
        <div data-part="frame">
          <div data-part="content">
            <img src="/images/tuist_logo_32x32@2x.png" alt={gettext("Tuist Logo")} data-part="logo" />
            <div data-part="dots">
              <.dots_light />
              <.dots_dark />
            </div>
            <div data-part="header">
              <h1 data-part="title">{gettext("Sign up for Tuist")}</h1>
              <span data-part="subtitle">{gettext("Welcome! Create an account to continue")}</span>
            </div>
            <div :if={oauth_configured?()} data-part="oauth">
              <.button
                :if={@github_auth_configured}
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
                :if={@google_configured}
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
                :if={@okta_configured}
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
            <.line_divider :if={oauth_configured?()} text="OR" />
            <.form data-part="form" for={@form} id="login_form" phx-submit="save">
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
                required
              />
              <.text_input
                field={@form[:password]}
                label={gettext("Password")}
                id="password"
                type="password"
                error={Map.get(@errors, :password)}
                show_prefix={false}
                required
              />
              <.text_input
                field={@form[:username]}
                label={gettext("Username")}
                id="Username"
                type="basic"
                hint={gettext("Username may only contain alphanumeric characters")}
                error={Map.get(@errors, :name)}
                show_prefix={false}
                required
              />
              <.button variant="primary" size="large" label={gettext("Sign up")} />
            </.form>
          </div>
          <div data-part="signup-link">
            <span>{gettext("Already have an account?")}</span>
            <.link_button
              navigate={~p"/users/log_in"}
              variant="primary"
              size="large"
              label={gettext("Log in")}
            />
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

  defp oauth_configured? do
    Environment.github_auth_configured?() || Environment.google_oauth_configured?() ||
      Environment.okta_configured?()
  end

  def legacy_registration(assigns) do
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
            {gettext("Create an account")}
          </h5>
          <p class="auth-header__subtitle text--medium color--text-tertiary">
            {gettext("Start your Tuist journey.")}
          </p>
        </.stack>
      </.stack>

      <.stack gap="xl">
        <.simple_form
          for={@form}
          id="registration_form"
          phx-submit="save"
          method="post"
          class="auth-form"
        >
          <.stack gap="3xl">
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
            <.stack gap="xl">
              <.legacy_button type="submit" variant="primary" class="auth-form__primary-action">
                {gettext("Sign up")}
              </.legacy_button>
            </.stack>
          </.stack>
        </.simple_form>

        <%= if @github_auth_configured do %>
          <.social_button>
            <a href={~p"/users/auth/github"}>
              {gettext("Sign up with GitHub")}
            </a>
            <:icon><.github_icon /></:icon>
          </.social_button>
        <% end %>
        <%= if @google_configured do %>
          <.social_button>
            <a href={~p"/users/auth/google"}>
              {gettext("Sign up with Google")}
            </a>
            <:icon><.google_icon /></:icon>
          </.social_button>
        <% end %>
        <%= if @okta_configured do %>
          <.social_button>
            <a href={~p"/users/auth/okta"}>
              {gettext("Sign up with Okta")}
            </a>
            <:icon><.okta_icon /></:icon>
          </.social_button>
        <% end %>
      </.stack>
      <.stack direction="horizontal" gap="xs">
        <span class="text--small font--regular color--text-tertiary">
          {gettext("Already an account?")}
        </span>
        <a href={~p"/users/log_in"} class="text--small font--semibold">
          {gettext("Sign in")}
        </a>
      </.stack>

      <.flash_group flash={@flash} />
    </.stack>
    """
  end

  def mount(_params, _session, socket) do
    form =
      to_form(%{}, as: "user")

    {
      :ok,
      socket
      |> assign(:head_title, "#{gettext("Sign up")} · Tuist")
      |> assign(:form, form)
      |> assign(:errors, %{})
      |> assign(:github_auth_configured, Environment.github_auth_configured?())
      |> assign(:google_configured, Environment.google_oauth_configured?())
      |> assign(:okta_configured, Environment.okta_configured?()),
      temporary_assigns: [form: nil]
    }
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.create_user(
           Map.get(user_params, "email"),
           password: Map.get(user_params, "password"),
           name: Map.get(user_params, "username")
         ) do
      {:ok, user} ->
        Accounts.deliver_user_confirmation_instructions(%{
          user: user,
          confirmation_url: &url(~p"/users/confirm/#{&1}")
        })

        {:noreply,
         socket
         |> assign(trigger_submit: true)
         |> put_flash(
           :info,
           gettext("A confirmation email has been sent to you, check your inbox")
         )
         |> redirect(to: ~p"/")}

      {:error, :account_handle_taken} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           gettext("Account name is already taken")
         )}

      {:error, :email_taken} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           gettext("Email is already taken")
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        socket =
          assign(socket,
            form: to_form(user_params, as: :user),
            errors: Tuist.Ecto.Utils.errors_on(changeset)
          )

        {:noreply, socket}

      {:error, errors} ->
        socket = assign(socket, form: to_form(user_params, as: :user), errors: errors)
        {:noreply, socket}
    end
  end
end
