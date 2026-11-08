defmodule AtlasWeb.AccountSettingsLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Account settings"))}
  end

  def render(assigns) do
    ~H"""
    <section id="account-settings" data-part="account-settings-page">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("General")}</h1>
          <p data-part="description">{gettext("Your personal Atlas account.")}</p>
        </div>
      </div>
      <div data-part="settings-sections">
        <.card_section id="account-profile" data-part="settings-section">
          <div data-part="header">
            <span data-part="title">{gettext("Profile")}</span>
            <span data-part="subtitle">
              {gettext("Your profile is managed by your sign-in provider.")}
            </span>
          </div>
          <dl data-part="content">
            <div data-part="field">
              <dt>{gettext("Name")}</dt>
              <dd id="account-settings-name">{@current_user.name || gettext("Not set")}</dd>
            </div>
            <div data-part="field">
              <dt>{gettext("Email")}</dt>
              <dd id="account-settings-email">{@current_user.email}</dd>
            </div>
          </dl>
        </.card_section>
      </div>
    </section>
    """
  end
end
