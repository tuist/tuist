defmodule TuistWeb.UserRegistrationLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.AppAuthComponents

  alias Phoenix.Flash
  alias Tuist.Accounts
  alias Tuist.Environment

  def render(assigns) do
    ~H"""
    <.noora_registration {assigns} />
    """
  end

  def noora_registration(assigns) do
    ~H"""
    <div :if={!@success} id="signup">
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
            <div
              :if={oauth_configured?()}
              data-part="oauth"
              data-compact={
                @github_configured? and @apple_configured? and
                  @google_configured? and
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
                href={~p"/users/auth/okta"}
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
              <% password_errors =
                case Map.get(@errors, :password) do
                  nil ->
                    nil

                  errors when is_binary(errors) ->
                    String.trim_trailing(errors, ".")

                  errors when is_list(errors) ->
                    (errors
                     |> Enum.map(&String.trim_trailing(&1, "."))
                     |> Enum.join(". ")) <> "."
                end %>
              <.text_input
                field={@form[:password]}
                label={gettext("Password")}
                id="password"
                input_type="password"
                error={password_errors}
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
          <div data-part="bottom-link">
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
    <div :if={@success} id="signup-success">
      <div data-part="wrapper">
        <div data-part="frame">
          <div data-part="content">
            <img src="/images/tuist_logo_32x32@2x.png" alt={gettext("Tuist Logo")} data-part="logo" />
            <div data-part="dots">
              <.dots_light />
              <.dots_dark />
            </div>
            <div data-part="header">
              <h1 data-part="title">{gettext("Confirm your account")}</h1>
              <span data-part="subtitle">
                {gettext("Check your inbox for a confirmation email and click the link to continue.")}
              </span>
            </div>
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
    Environment.github_oauth_configured?() || Environment.google_oauth_configured?() ||
      Environment.okta_oauth_configured?() || Environment.apple_oauth_configured?()
  end

  def mount(_params, _session, socket) do
    form =
      to_form(%{}, as: "user")

    socket =
      socket
      |> assign(:head_title, "#{gettext("Sign up")} · Tuist")
      |> assign(:form, form)
      |> assign(:success, false)
      |> assign(:errors, %{})
      |> assign(:github_configured?, Environment.github_oauth_configured?())
      |> assign(:google_configured?, Environment.google_oauth_configured?())
      |> assign(:okta_configured?, Environment.okta_oauth_configured?())
      |> assign(:apple_configured?, Environment.apple_oauth_configured?())

    {
      :ok,
      socket,
      temporary_assigns: [form: nil]
    }
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.create_user(
           Map.get(user_params, "email"),
           password: Map.get(user_params, "password"),
           handle: Map.get(user_params, "username")
         ) do
      {:ok, user} ->
        Accounts.deliver_user_confirmation_instructions(%{
          user: user,
          confirmation_url: &url(~p"/users/confirm/#{&1}")
        })

        {:noreply, assign(socket, :success, true)}

      {:error, :account_handle_taken} ->
        {:noreply, put_flash(socket, :error, gettext("Account name is already taken"))}

      {:error, :email_taken} ->
        {:noreply, put_flash(socket, :error, gettext("Email is already taken"))}

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
