defmodule TuistCloudWeb.UserRegistrationLive do
  use TuistCloudWeb, :live_view

  alias TuistCloud.Accounts
  alias TuistCloud.Environment

  def render(assigns) do
    ~H"""
    <.stack class="auth-page" gap="4xl">
      <.decorative_background class="auth-page__background" />
      <.stack class="auth-header" gap="3xl">
        <img class="auth-header__logo" src="/images/tuist_logo_32x32@2x.png" alt="Tuist Icon" />
        <.stack gap="lg">
          <h5 class="auth-header__title font--semibold color--text-primary">
            <%= gettext("Create an account") %>
          </h5>
          <p class="auth-header__subtitle text--medium color--text-tertiary">
            <%= gettext("Start your Tuist journey.") %>
          </p>
        </.stack>
      </.stack>

      <.stack gap="xl">
        <.simple_form
          for={@form}
          id="registration_form"
          phx-submit="save"
          action={~p"/users/log_in?_action=registered"}
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
              <.button type="submit" variant="primary" class="auth-form__primary-action">
                <%= gettext("Sign up") %>
              </.button>
            </.stack>
          </.stack>
        </.simple_form>

        <%= if @github_configured do %>
          <.social_button>
            <a href={~p"/users/auth/github"}>
              <%= gettext("Sign up with GitHub") %>
            </a>
            <:icon><.github_icon /></:icon>
          </.social_button>
        <% end %>
        <%= if @google_configured do %>
          <.social_button>
            <a href={~p"/users/auth/google"}>
              <%= gettext("Sign up with Google") %>
            </a>
            <:icon><.google_icon /></:icon>
          </.social_button>
        <% end %>
        <%= if @okta_configured do %>
          <.social_button>
            <a href={~p"/users/auth/okta"}>
              <%= gettext("Sign up with Okta") %>
            </a>
            <:icon><.okta_icon /></:icon>
          </.social_button>
        <% end %>
      </.stack>
      <.stack direction="horizontal" gap="xs">
        <span class="text--small font--regular color--text-tertiary">
          <%= gettext("Already an account?") %>
        </span>
        <a href={~p"/users/log_in"} class="text--small font--semibold">
          <%= gettext("Sign in") %>
        </a>
      </.stack>

      <.flash_group flash={@flash} />
    </.stack>
    """
  end

  def mount(_params, _session, socket) do
    form = to_form(%{}, as: "user")

    {
      :ok,
      socket
      |> assign(:form, form)
      |> assign(:github_configured, Environment.github_configured?())
      |> assign(:google_configured, Environment.google_oauth_configured?())
      |> assign(:okta_configured, Environment.okta_configured?()),
      temporary_assigns: [form: nil]
    }
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.create_user(user_params |> Map.get("email"),
           password: user_params |> Map.get("password")
         ) do
      {:ok, user} ->
        Accounts.deliver_user_confirmation_instructions(
          user,
          &url(~p"/users/confirm/#{&1}")
        )

        {:noreply,
         socket
         |> assign(trigger_submit: true)
         |> put_flash(
           :info,
           gettext("A confirmation email has been sent to you, check your inbox")
         )
         |> redirect(to: ~p"/")}

      {:error, :account_name_taken} ->
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
    end
  end
end
