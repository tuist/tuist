defmodule TuistWeb.SSOLinkHTML do
  @moduledoc false

  use TuistWeb, :html
  use Noora

  embed_templates "sso_link_html/*"

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  slot :inner_block, required: true

  def security_settings_frame(assigns) do
    ~H"""
    <.link_frame title={@title} subtitle={@subtitle} show_terms={false}>
      <div id="user-security-settings">
        {render_slot(@inner_block)}
      </div>
    </.link_frame>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :show_terms, :boolean, default: true
  slot :inner_block

  def link_frame(assigns) do
    ~H"""
    <div id="sso-link">
      <div data-part="wrapper">
        <div data-part="frame">
          <div data-part="content">
            <.tuist_mark data-part="logo" aria-label={dgettext("dashboard_auth", "Tuist logo")} />
            <div data-part="dots">
              <.dots_light />
              <.dots_dark />
            </div>
            <div data-part="header">
              <h1 data-part="title">{@title}</h1>
              <span data-part="subtitle">{@subtitle}</span>
            </div>
            {render_slot(@inner_block)}
          </div>
        </div>
      </div>

      <div data-part="background">
        <div data-part="top-right-gradient"></div>
        <div data-part="bottom-left-gradient"></div>
        <div data-part="shell"><.shell /></div>
      </div>
      <.terms_and_privacy :if={@show_terms} />
    </div>
    """
  end

  attr :return_to, :string, required: true

  def reauthentication_notice(assigns) do
    ~H"""
    <p data-part="reauthentication-explanation">
      {dgettext(
        "dashboard_auth",
        "To protect your account, confirm your identity before changing security settings. You'll return here after signing in."
      )}
    </p>
    <.form
      for={%{}}
      action={~p"/users/log_out?#{%{return_to: @return_to}}"}
      method="delete"
      data-part="form"
    >
      <.button
        type="submit"
        variant="primary"
        size="large"
        label={dgettext("dashboard_auth", "Sign in again")}
      />
    </.form>
    """
  end
end
