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
          <img src="/images/tuist_logo_32x32@2x.png" alt={gettext("Tuist Icon")} />
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
      <div data-part="top-right-gradient"></div>
      <div data-part="bottom-left-gradient"></div>
      <div data-part="shell"><.shell /></div>
    </div>
    """
  end

  defp dots_light(assigns) do
    ~H"""
    <svg
      data-theme="light"
      width="342"
      height="52"
      viewBox="0 0 342 52"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <mask
        id="mask0_891_55872"
        style="mask-type:alpha"
        maskUnits="userSpaceOnUse"
        x="0"
        y="0"
        width="342"
        height="52"
      >
        <rect width="341.12" height="52" fill="url(#paint0_radial_891_55872)" fill-opacity="0.4" />
      </mask>
      <g mask="url(#mask0_891_55872)">
        <rect x="6.5603" y="8" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="14.5603" y="8" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="22.5603" y="8" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="30.5603" y="8" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="38.5603" y="8" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="46.5603" y="8" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="54.5603" y="8" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="62.5603" y="8" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="70.5603" y="8" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="78.5603" y="8" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="86.5603" y="8" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="94.5603" y="8" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="102.56" y="8" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="110.56" y="8" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="118.56" y="8" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="126.56" y="8" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="134.56" y="8" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="142.56" y="8" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="150.56" y="8" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="158.56" y="8" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="166.56" y="8" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="174.56" y="8" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="182.56" y="8" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="190.56" y="8" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="198.56" y="8" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="206.56" y="8" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="214.56" y="8" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="222.56" y="8" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="230.56" y="8" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="238.56" y="8" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="246.56" y="8" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="254.56" y="8" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="262.56" y="8" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="270.56" y="8" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="278.56" y="8" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="286.56" y="8" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="294.56" y="8" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="302.56" y="8" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="310.56" y="8" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="318.56" y="8" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="6.5603" y="16" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="14.5603" y="16" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="22.5603" y="16" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="30.5603" y="16" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="38.5603" y="16" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="46.5603" y="16" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="54.5603" y="16" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="62.5603" y="16" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="70.5603" y="16" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="78.5603" y="16" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="86.5603" y="16" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="94.5603" y="16" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="102.56" y="16" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="110.56" y="16" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="118.56" y="16" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="126.56" y="16" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="134.56" y="16" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="142.56" y="16" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="150.56" y="16" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="158.56" y="16" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="166.56" y="16" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="174.56" y="16" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="182.56" y="16" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="190.56" y="16" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="198.56" y="16" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="206.56" y="16" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="214.56" y="16" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="222.56" y="16" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="230.56" y="16" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="238.56" y="16" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="246.56" y="16" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="254.56" y="16" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="262.56" y="16" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="270.56" y="16" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="278.56" y="16" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="286.56" y="16" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="294.56" y="16" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="302.56" y="16" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="310.56" y="16" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="318.56" y="16" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="6.5603" y="24" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="14.5603" y="24" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="22.5603" y="24" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="30.5603" y="24" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="38.5603" y="24" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="46.5603" y="24" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="54.5603" y="24" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="62.5603" y="24" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="70.5603" y="24" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="78.5603" y="24" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="86.5603" y="24" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="94.5603" y="24" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="102.56" y="24" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="110.56" y="24" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="118.56" y="24" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="126.56" y="24" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="134.56" y="24" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="142.56" y="24" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="150.56" y="24" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="158.56" y="24" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="166.56" y="24" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="174.56" y="24" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="182.56" y="24" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="190.56" y="24" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="198.56" y="24" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="206.56" y="24" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="214.56" y="24" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="222.56" y="24" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="230.56" y="24" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="238.56" y="24" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="246.56" y="24" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="254.56" y="24" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="262.56" y="24" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="270.56" y="24" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="278.56" y="24" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="286.56" y="24" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="294.56" y="24" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="302.56" y="24" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="310.56" y="24" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="318.56" y="24" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="6.5603" y="32" width="3" height="3" rx="0.5" fill="#D8DBDF" />
        <rect x="14.5603" y="32" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="22.5603" y="32" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="30.5603" y="32" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="38.5603" y="32" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="46.5603" y="32" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="54.5603" y="32" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="62.5603" y="32" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="70.5603" y="32" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="78.5603" y="32" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="86.5603" y="32" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="94.5603" y="32" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="102.56" y="32" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="110.56" y="32" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="118.56" y="32" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="126.56" y="32" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="134.56" y="32" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="142.56" y="32" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="150.56" y="32" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="158.56" y="32" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="166.56" y="32" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="174.56" y="32" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="182.56" y="32" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="190.56" y="32" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="198.56" y="32" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="206.56" y="32" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="214.56" y="32" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="222.56" y="32" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="230.56" y="32" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="238.56" y="32" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="246.56" y="32" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="254.56" y="32" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="262.56" y="32" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="270.56" y="32" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="278.56" y="32" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="286.56" y="32" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="294.56" y="32" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="302.56" y="32" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="310.56" y="32" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="318.56" y="32" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="6.5603" y="40" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="14.5603" y="40" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="22.5603" y="40" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="30.5603" y="40" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="38.5603" y="40" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="46.5603" y="40" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="54.5603" y="40" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="62.5603" y="40" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="70.5603" y="40" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="78.5603" y="40" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="86.5603" y="40" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="94.5603" y="40" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="102.56" y="40" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="110.56" y="40" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="118.56" y="40" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="126.56" y="40" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="134.56" y="40" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="142.56" y="40" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="150.56" y="40" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="158.56" y="40" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="166.56" y="40" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="174.56" y="40" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="182.56" y="40" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="190.56" y="40" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="198.56" y="40" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="206.56" y="40" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="214.56" y="40" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="222.56" y="40" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="230.56" y="40" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="238.56" y="40" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="246.56" y="40" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="254.56" y="40" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="262.56" y="40" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="270.56" y="40" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="278.56" y="40" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="286.56" y="40" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="294.56" y="40" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="302.56" y="40" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="310.56" y="40" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="318.56" y="40" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="6.5603" y="48" width="3" height="3" rx="0.5" fill="#D8DBDF" />
        <rect x="14.5603" y="48" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="22.5603" y="48" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="30.5603" y="48" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="38.5603" y="48" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="46.5603" y="48" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="54.5603" y="48" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="62.5603" y="48" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="70.5603" y="48" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="78.5603" y="48" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="86.5603" y="48" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="94.5603" y="48" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="102.56" y="48" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="110.56" y="48" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="118.56" y="48" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="126.56" y="48" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="134.56" y="48" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="142.56" y="48" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="150.56" y="48" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="158.56" y="48" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="166.56" y="48" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="174.56" y="48" width="3" height="3" rx="0.5" fill="#C7CCD1" />
        <rect x="182.56" y="48" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="190.56" y="48" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="198.56" y="48" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="206.56" y="48" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="214.56" y="48" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="222.56" y="48" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="230.56" y="48" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="238.56" y="48" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="246.56" y="48" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="254.56" y="48" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="262.56" y="48" width="3" height="3" rx="0.5" fill="#9DA6AF" />
        <rect x="270.56" y="48" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="278.56" y="48" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="286.56" y="48" width="3" height="3" rx="0.5" fill="#F1F2F4" />
        <rect x="294.56" y="48" width="3" height="3" rx="0.5" fill="#E6E8EA" />
        <rect x="302.56" y="48" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="310.56" y="48" width="3" height="3" rx="0.5" fill="#F9FAFA" />
        <rect x="318.56" y="48" width="3" height="3" rx="0.5" fill="#9DA6AF" />
      </g>
      <defs>
        <radialGradient
          id="paint0_radial_891_55872"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(171.101 26) rotate(90.1136) scale(273.001 146.098)"
        >
          <stop stop-opacity="0" />
          <stop offset="1" />
        </radialGradient>
      </defs>
    </svg>
    """
  end

  defp dots_dark(assigns) do
    ~H"""
    <svg
      data-theme="dark"
      width="342"
      height="52"
      viewBox="0 0 342 52"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <mask
        id="mask0_891_56363"
        style="mask-type:alpha"
        maskUnits="userSpaceOnUse"
        x="0"
        y="0"
        width="342"
        height="52"
      >
        <rect width="341.12" height="52" fill="url(#paint0_radial_891_56363)" fill-opacity="0.4" />
      </mask>
      <g mask="url(#mask0_891_56363)">
        <rect x="6.56018" y="8" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="14.5602" y="8" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="22.5602" y="8" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="30.5602" y="8" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="38.5602" y="8" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="46.5602" y="8" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="54.5602" y="8" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="62.5602" y="8" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="70.5602" y="8" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="78.5602" y="8" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="86.5602" y="8" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="94.5602" y="8" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="102.56" y="8" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="110.56" y="8" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="118.56" y="8" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="126.56" y="8" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="134.56" y="8" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="142.56" y="8" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="150.56" y="8" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="158.56" y="8" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="166.56" y="8" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="174.56" y="8" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="182.56" y="8" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="190.56" y="8" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="198.56" y="8" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="206.56" y="8" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="214.56" y="8" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="222.56" y="8" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="230.56" y="8" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="238.56" y="8" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="246.56" y="8" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="254.56" y="8" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="262.56" y="8" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="270.56" y="8" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="278.56" y="8" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="286.56" y="8" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="294.56" y="8" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="302.56" y="8" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="310.56" y="8" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="318.56" y="8" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="6.56018" y="16" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="14.5602" y="16" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="22.5602" y="16" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="30.5602" y="16" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="38.5602" y="16" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="46.5602" y="16" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="54.5602" y="16" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="62.5602" y="16" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="70.5602" y="16" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="78.5602" y="16" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="86.5602" y="16" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="94.5602" y="16" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="102.56" y="16" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="110.56" y="16" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="118.56" y="16" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="126.56" y="16" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="134.56" y="16" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="142.56" y="16" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="150.56" y="16" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="158.56" y="16" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="166.56" y="16" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="174.56" y="16" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="182.56" y="16" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="190.56" y="16" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="198.56" y="16" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="206.56" y="16" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="214.56" y="16" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="222.56" y="16" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="230.56" y="16" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="238.56" y="16" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="246.56" y="16" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="254.56" y="16" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="262.56" y="16" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="270.56" y="16" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="278.56" y="16" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="286.56" y="16" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="294.56" y="16" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="302.56" y="16" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="310.56" y="16" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="318.56" y="16" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="6.56018" y="24" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="14.5602" y="24" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="22.5602" y="24" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="30.5602" y="24" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="38.5602" y="24" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="46.5602" y="24" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="54.5602" y="24" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="62.5602" y="24" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="70.5602" y="24" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="78.5602" y="24" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="86.5602" y="24" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="94.5602" y="24" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="102.56" y="24" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="110.56" y="24" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="118.56" y="24" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="126.56" y="24" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="134.56" y="24" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="142.56" y="24" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="150.56" y="24" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="158.56" y="24" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="166.56" y="24" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="174.56" y="24" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="182.56" y="24" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="190.56" y="24" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="198.56" y="24" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="206.56" y="24" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="214.56" y="24" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="222.56" y="24" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="230.56" y="24" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="238.56" y="24" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="246.56" y="24" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="254.56" y="24" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="262.56" y="24" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="270.56" y="24" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="278.56" y="24" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="286.56" y="24" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="294.56" y="24" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="302.56" y="24" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="310.56" y="24" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="318.56" y="24" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="6.56018" y="32" width="3" height="3" rx="0.5" fill="#45484D" />
        <rect x="14.5602" y="32" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="22.5602" y="32" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="30.5602" y="32" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="38.5602" y="32" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="46.5602" y="32" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="54.5602" y="32" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="62.5602" y="32" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="70.5602" y="32" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="78.5602" y="32" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="86.5602" y="32" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="94.5602" y="32" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="102.56" y="32" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="110.56" y="32" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="118.56" y="32" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="126.56" y="32" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="134.56" y="32" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="142.56" y="32" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="150.56" y="32" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="158.56" y="32" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="166.56" y="32" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="174.56" y="32" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="182.56" y="32" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="190.56" y="32" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="198.56" y="32" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="206.56" y="32" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="214.56" y="32" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="222.56" y="32" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="230.56" y="32" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="238.56" y="32" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="246.56" y="32" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="254.56" y="32" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="262.56" y="32" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="270.56" y="32" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="278.56" y="32" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="286.56" y="32" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="294.56" y="32" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="302.56" y="32" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="310.56" y="32" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="318.56" y="32" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="6.56018" y="40" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="14.5602" y="40" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="22.5602" y="40" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="30.5602" y="40" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="38.5602" y="40" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="46.5602" y="40" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="54.5602" y="40" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="62.5602" y="40" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="70.5602" y="40" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="78.5602" y="40" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="86.5602" y="40" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="94.5602" y="40" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="102.56" y="40" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="110.56" y="40" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="118.56" y="40" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="126.56" y="40" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="134.56" y="40" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="142.56" y="40" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="150.56" y="40" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="158.56" y="40" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="166.56" y="40" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="174.56" y="40" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="182.56" y="40" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="190.56" y="40" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="198.56" y="40" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="206.56" y="40" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="214.56" y="40" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="222.56" y="40" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="230.56" y="40" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="238.56" y="40" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="246.56" y="40" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="254.56" y="40" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="262.56" y="40" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="270.56" y="40" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="278.56" y="40" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="286.56" y="40" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="294.56" y="40" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="302.56" y="40" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="310.56" y="40" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="318.56" y="40" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="6.56018" y="48" width="3" height="3" rx="0.5" fill="#45484D" />
        <rect x="14.5602" y="48" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="22.5602" y="48" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="30.5602" y="48" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="38.5602" y="48" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="46.5602" y="48" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="54.5602" y="48" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="62.5602" y="48" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="70.5602" y="48" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="78.5602" y="48" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="86.5602" y="48" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="94.5602" y="48" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="102.56" y="48" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="110.56" y="48" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="118.56" y="48" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="126.56" y="48" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="134.56" y="48" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="142.56" y="48" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="150.56" y="48" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="158.56" y="48" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="166.56" y="48" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="174.56" y="48" width="3" height="3" rx="0.5" fill="#2E3338" />
        <rect x="182.56" y="48" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="190.56" y="48" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="198.56" y="48" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="206.56" y="48" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="214.56" y="48" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="222.56" y="48" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="230.56" y="48" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="238.56" y="48" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="246.56" y="48" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="254.56" y="48" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="262.56" y="48" width="3" height="3" rx="0.5" fill="#2F3237" />
        <rect x="270.56" y="48" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="278.56" y="48" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="286.56" y="48" width="3" height="3" rx="0.5" fill="#3A3D43" />
        <rect x="294.56" y="48" width="3" height="3" rx="0.5" fill="#1F2126" />
        <rect x="302.56" y="48" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="310.56" y="48" width="3" height="3" rx="0.5" fill="#16181C" />
        <rect x="318.56" y="48" width="3" height="3" rx="0.5" fill="#2F3237" />
      </g>
      <defs>
        <radialGradient
          id="paint0_radial_891_56363"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(171.101 26) rotate(90.1136) scale(273.001 146.098)"
        >
          <stop stop-opacity="0" />
          <stop offset="1" />
        </radialGradient>
      </defs>
    </svg>
    """
  end

  defp shell(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width="694"
      height="1024"
      viewBox="0 0 694 1024"
      fill="none"
    >
      <path
        d="M927.881 881.669C997.789 849.23 1064.32 807.836 1126.6 760.197C1149.79 792.553 1170.1 827.069 1187.17 863.508C869.522 1216.21 318.308 1216.15 0.725732 863.508C17.7743 827.07 38.1071 792.556 61.2958 760.201C123.692 807.957 190.34 849.402 260.411 881.89L261.135 880.94C188.779 795.142 127.678 698.95 75.1273 606.041C50.5087 560.8 27.6649 514.945 6.26809 468.496C26.4298 427.561 50.7856 389.074 78.7041 353.492L79.1148 353.299C144.064 480.798 219.391 604.392 310.889 713.591L310.889 713.592C322.054 726.87 333.438 739.884 345.02 752.677L346.053 752.071C276.556 546.152 233.805 332.86 201.064 119.3C233.888 94.677 269.085 73.0133 306.334 54.8001C340.031 224.958 381.876 393.558 435.377 556.653L435.378 556.658C459.019 626.965 484.184 696.868 513.909 764.201L515.08 763.968L535.405 -100.778C554.709 -102.547 574.231 -103.388 593.97 -103.388C613.708 -103.388 633.23 -102.525 652.535 -100.777L672.837 763.704L674.009 763.936C703.38 697.134 729.183 627.387 752.541 556.632L752.541 556.631C806.042 393.558 847.887 224.958 881.584 54.7781C918.833 72.9913 954.03 94.655 986.854 119.278C954.134 332.684 911.428 545.8 842.018 751.586L843.051 752.193C854.611 739.444 865.928 726.542 877.025 713.574L877.029 713.569C968.548 604.37 1043.85 480.776 1108.8 353.277L1109.21 353.47C1137.07 388.986 1161.42 427.407 1181.58 468.319C1117.14 606.926 1032.69 756.387 927.157 880.719L927.881 881.669Z"
        stroke-width="1.22337"
      />
      <defs>
        <linearGradient
          id="light"
          x1="593.948"
          y1="-104"
          x2="593.948"
          y2="1128.62"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="white" />
          <stop offset="1" stop-color="#B8A2E6" stop-opacity="0.1" />
        </linearGradient>
        <linearGradient
          id="dark"
          x1="593.948"
          y1="-104"
          x2="593.948"
          y2="1128.62"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="white" stop-opacity="0.2" />
          <stop offset="1" stop-color="#5B448C" stop-opacity="0.1" />
        </linearGradient>
      </defs>
    </svg>
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
