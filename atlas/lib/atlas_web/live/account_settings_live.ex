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
      <.card title={gettext("Profile")} icon="user">
        <.card_section data-part="account-profile">
          <dl data-part="profile-details">
            <div data-part="profile-field">
              <dt>{gettext("Name")}</dt>
              <dd id="account-settings-name" data-part="profile-value">
                {@current_user.name || gettext("Not set")}
              </dd>
            </div>
            <div data-part="profile-field">
              <dt>{gettext("Email")}</dt>
              <dd id="account-settings-email" data-part="profile-value">{@current_user.email}</dd>
            </div>
          </dl>
          <p data-part="description">
            {gettext("Your profile is managed by your sign-in provider.")}
          </p>
        </.card_section>
      </.card>
    </section>
    """
  end
end
