defmodule TuistWeb.UserLoginLive do
  use TuistWeb, :live_view
  alias Tuist.Environment

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")

    {
      :ok,
      socket
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
                <.button type="submit" variant="primary" class="auth-form__primary-action">
                  {gettext("Sign in")}
                </.button>
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
