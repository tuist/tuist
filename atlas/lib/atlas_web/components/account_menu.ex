defmodule AtlasWeb.AccountMenu do
  @moduledoc "Shared Atlas header with context-aware account navigation."
  use AtlasWeb, :html
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Users.User

  attr :current_user, :any, required: true
  attr :account_settings?, :boolean, default: false

  def headerbar(assigns) do
    ~H"""
    <header class="headerbar">
      <div data-part="left-section">
        <.link navigate={~p"/"} class="headerbar__brand">
          <img src={~p"/images/tuist-logo.svg"} alt="Atlas" data-part="logo" />
          <span class="headerbar__title">Atlas</span>
        </.link>
      </div>
      <div data-part="right-section">
        <div
          id="account-dropdown"
          class="account-dropdown"
          phx-hook="NooraDropdown"
          data-loop-focus
          data-close-on-select
          data-positioning-offset-main-axis={6}
        >
          <button data-part="trigger" aria-label={gettext("Account menu")}>
            <.avatar
              id="account-dropdown-avatar"
              size="small"
              name={@current_user.name || @current_user.email}
              image_href={User.avatar_url(@current_user)}
            />
          </button>
          <div data-part="positioner">
            <div data-part="content">
              <div data-part="header">
                <.avatar
                  id="account-dropdown-content-avatar"
                  size="small"
                  name={@current_user.name || @current_user.email}
                  image_href={User.avatar_url(@current_user)}
                />
                <div data-part="text">
                  <p data-part="title">{@current_user.name || @current_user.email}</p>
                  <p data-part="subtitle">{@current_user.email}</p>
                </div>
              </div>
              <.line_divider />
              <div data-part="actions">
                <.button
                  :if={!Atlas.Demo.enabled?() and !@account_settings?}
                  id="personal-account-settings-link"
                  label={gettext("Account settings")}
                  size="large"
                  variant="secondary"
                  navigate={~p"/settings"}
                >
                  <:icon_left><.settings /></:icon_left>
                </.button>
                <.button
                  :if={@account_settings?}
                  id="account-menu-dashboard-link"
                  label={gettext("Dashboard")}
                  size="large"
                  variant="secondary"
                  navigate={~p"/"}
                >
                  <:icon_left><.layout_grid /></:icon_left>
                </.button>
                <.link href={~p"/logout"} method="delete">
                  <.button label={gettext("Log out")} size="large" variant="destructive">
                    <:icon_left><.logout /></:icon_left>
                  </.button>
                </.link>
              </div>
            </div>
          </div>
        </div>
      </div>
    </header>
    """
  end
end
