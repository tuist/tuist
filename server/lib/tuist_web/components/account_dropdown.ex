defmodule TuistWeb.AccountDropdown do
  @moduledoc """
  An account dropdown component shown in the header bar.
  """
  use TuistWeb, :live_component
  use Noora

  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.Authorization

  attr :id, :string, required: true
  attr :latest_app_release, :map, required: true
  attr :current_user, :map, required: true
  attr :avatar_size, :string, default: "medium"

  def account_dropdown(assigns) do
    ~H"""
    <div
      id={@id}
      class="account-dropdown"
      phx-hook="NooraDropdown"
      data-loop-focus
      data-close-on-select
      data-typeahead
      data-positioning-offset-main-axis={6}
    >
      <button data-part="trigger">
        <.avatar
          id={"#{@id}-dropdown-avatar"}
          size={@avatar_size}
          name={@current_user.account.name}
          image_href={User.gravatar_url(@current_user)}
          color={Accounts.avatar_color(@current_user.account)}
        />
      </button>
      <div data-part="positioner">
        <div data-part="content">
          <div data-part="header">
            <.avatar
              id={"#{@id}-dropdown-content-avatar"}
              name={@current_user.account.name}
              image_href={User.gravatar_url(@current_user)}
              color={Accounts.avatar_color(@current_user.account)}
            />
            <div data-part="text">
              <p data-part="title">
                {@current_user.account.name}
              </p>
              <p data-part="subtitle">
                {@current_user.email}
              </p>
            </div>
          </div>
          <div data-part="account_content">
            <.line_divider />
            <div data-part="actions">
              <.button
                navigate={~p"/#{@current_user.account.name}/settings"}
                label={dgettext("dashboard", "Account settings")}
                variant="secondary"
              >
                <:icon_left><.settings /></:icon_left>
              </.button>
              <.button
                :if={Authorization.authorize(:ops_read, @current_user)}
                navigate={~p"/ops/qa"}
                label={dgettext("dashboard", "Operations")}
                variant="secondary"
              >
                <:icon_left><.dashboard /></:icon_left>
              </.button>
              <.button
                :if={latest_app_release = @latest_app_release.ok? && @latest_app_release.result}
                label={dgettext("dashboard", "Download macOS app")}
                variant="secondary"
                href={latest_app_release}
              >
                <:icon_left><.download /></:icon_left>
              </.button>
            </div>
            <div data-part="theme-switcher-section">
              <p data-part="theme-switcher-title">
                {dgettext("dashboard", "Switch to your preferred theme")}
              </p>
              <div data-part="theme-switcher">
                <.theme_light name={@id} id={"#{@id}-theme-switcher-light"} />
                <.theme_dark name={@id} id={"#{@id}-theme-switcher-dark"} />
                <.theme_system name={@id} id={"#{@id}-theme-switcher-system"} />
              </div>
            </div>
            <.link href={~p"/users/log_out"} method="delete">
              <.button label={dgettext("dashboard", "Log out")} size="large" variant="destructive">
                <:icon_left><.logout /></:icon_left>
              </.button>
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :name, :string, required: true

  defp theme_light(assigns) do
    ~H"""
    <input type="radio" id={@id} name={@name} value="light" phx-hook="ThemeSwitcher" />
    <label for={@id}>
      <svg width="122" height="84" viewBox="0 0 122 84" fill="none" xmlns="http://www.w3.org/2000/svg">
        <g clip-path={"url(##{@id}-clip0_856_2618)"}>
          <path
            d="M0 8C0 3.58172 3.58172 0 8 0H114C118.418 0 122 3.58172 122 8V76C122 80.4183 118.418 84 114 84H8C3.58172 84 0 80.4183 0 76V8Z"
            fill="#FDFDFD"
          />
          <path
            d="M0 8C0 3.58172 3.58172 0 8 0H114C118.418 0 122 3.58172 122 8V17H0V8Z"
            fill="#F1F2F4"
          />
          <circle cx="11" cy="8.5" r="2" fill="#E51C01" />
          <circle cx="17" cy="8.5" r="2" fill="#FFC300" />
          <circle cx="23" cy="8.5" r="2" fill="#28A745" />
          <rect width="24" height="67" transform="translate(0 17)" fill="#FDFDFD" />
          <path
            d="M3 22.5C3 21.6716 3.67157 21 4.5 21H20.5C21.3284 21 22 21.6716 22 22.5C22 23.3284 21.3284 24 20.5 24H4.5C3.67157 24 3 23.3284 3 22.5Z"
            fill="#F1F2F4"
          />
          <path
            d="M3 29.5C3 28.6716 3.67157 28 4.5 28H20.5C21.3284 28 22 28.6716 22 29.5C22 30.3284 21.3284 31 20.5 31H4.5C3.67157 31 3 30.3284 3 29.5Z"
            fill="#F1F2F4"
          />
          <path
            d="M3 36.5C3 35.6716 3.67157 35 4.5 35H20.5C21.3284 35 22 35.6716 22 36.5C22 37.3284 21.3284 38 20.5 38H4.5C3.67157 38 3 37.3284 3 36.5Z"
            fill="#F1F2F4"
          />
          <path
            d="M3 43.5C3 42.6716 3.67157 42 4.5 42H20.5C21.3284 42 22 42.6716 22 43.5C22 44.3284 21.3284 45 20.5 45H4.5C3.67157 45 3 44.3284 3 43.5Z"
            fill="#F1F2F4"
          />
          <path
            d="M28 23C28 21.8954 28.8954 21 30 21H45C46.1046 21 47 21.8954 47 23V29C47 30.1046 46.1046 31 45 31H30C28.8954 31 28 30.1046 28 29V23Z"
            fill="#F1F2F4"
          />
          <path
            d="M51 23C51 21.8954 51.8954 21 53 21H68C69.1046 21 70 21.8954 70 23V29C70 30.1046 69.1046 31 68 31H53C51.8954 31 51 30.1046 51 29V23Z"
            fill="#F1F2F4"
          />
          <path
            d="M74 23C74 21.8954 74.8954 21 76 21H91C92.1046 21 93 21.8954 93 23V29C93 30.1046 92.1046 31 91 31H76C74.8954 31 74 30.1046 74 29V23Z"
            fill="#F1F2F4"
          />
          <path
            d="M97 23C97 21.8954 97.8954 21 99 21H114C115.105 21 116 21.8954 116 23V29C116 30.1046 115.105 31 114 31H99C97.8954 31 97 30.1046 97 29V23Z"
            fill="#F1F2F4"
          />
          <path
            d="M28 37C28 35.8954 28.8954 35 30 35H83C84.1046 35 85 35.8954 85 37V49C85 50.1046 84.1046 51 83 51H30C28.8954 51 28 50.1046 28 49V37Z"
            fill="#F1F2F4"
          />
          <path
            d="M89 37C89 35.8954 89.8954 35 91 35H114C115.105 35 116 35.8954 116 37V49C116 50.1046 115.105 51 114 51H91C89.8954 51 89 50.1046 89 49V37Z"
            fill="#F1F2F4"
          />
          <path
            d="M28 57C28 55.8954 28.8954 55 30 55H68C69.1046 55 70 55.8954 70 57V69C70 70.1046 69.1046 71 68 71H30C28.8954 71 28 70.1046 28 69V57Z"
            fill="#F1F2F4"
          />
          <path
            d="M74 57C74 55.8954 74.8954 55 76 55H114C115.105 55 116 55.8954 116 57V69C116 70.1046 115.105 71 114 71H76C74.8954 71 74 70.1046 74 69V57Z"
            fill="#F1F2F4"
          />
          <path
            d="M28 76.5C28 75.6716 28.6716 75 29.5 75H45.5C46.3284 75 47 75.6716 47 76.5C47 77.3284 46.3284 78 45.5 78H29.5C28.6716 78 28 77.3284 28 76.5Z"
            fill="#F1F2F4"
          />
        </g>
        <path
          d="M0.5 8C0.5 3.85786 3.85786 0.5 8 0.5H114C118.142 0.5 121.5 3.85786 121.5 8V76C121.5 80.1421 118.142 83.5 114 83.5H8C3.85786 83.5 0.5 80.1421 0.5 76V8Z"
          stroke="#D8DBDF"
        />
        <defs>
          <clipPath id={"#{@id}-clip0_856_2618"}>
            <path
              d="M0 8C0 3.58172 3.58172 0 8 0H114C118.418 0 122 3.58172 122 8V76C122 80.4183 118.418 84 114 84H8C3.58172 84 0 80.4183 0 76V8Z"
              fill="white"
            />
          </clipPath>
        </defs>
      </svg>
    </label>
    """
  end

  attr :id, :string, required: true
  attr :name, :string, required: true

  defp theme_dark(assigns) do
    ~H"""
    <input type="radio" id={@id} name={@name} value="dark" phx-hook="ThemeSwitcher" />
    <label for={@id}>
      <svg width="122" height="84" viewBox="0 0 122 84" fill="none" xmlns="http://www.w3.org/2000/svg">
        <g clip-path={"url(##{@id}-clip0_856_2644)"}>
          <path
            d="M0 8C0 3.58172 3.58172 0 8 0H114C118.418 0 122 3.58172 122 8V76C122 80.4183 118.418 84 114 84H8C3.58172 84 0 80.4183 0 76V8Z"
            fill="#0E0E0E"
          />
          <path
            d="M0 8C0 3.58172 3.58172 0 8 0H114C118.418 0 122 3.58172 122 8V17H0V8Z"
            fill="#181818"
          />
          <circle cx="11" cy="8.5" r="2" fill="#FF462F" />
          <circle cx="17" cy="8.5" r="2" fill="#FFCE58" />
          <circle cx="23" cy="8.5" r="2" fill="#47BC5C" />
          <rect width="24" height="67" transform="translate(0 17)" fill="#0E0E0E" />
          <path
            d="M3 22.5C3 21.6716 3.67157 21 4.5 21H20.5C21.3284 21 22 21.6716 22 22.5C22 23.3284 21.3284 24 20.5 24H4.5C3.67157 24 3 23.3284 3 22.5Z"
            fill="#181818"
          />
          <path
            d="M3 29.5C3 28.6716 3.67157 28 4.5 28H20.5C21.3284 28 22 28.6716 22 29.5C22 30.3284 21.3284 31 20.5 31H4.5C3.67157 31 3 30.3284 3 29.5Z"
            fill="#181818"
          />
          <path
            d="M3 36.5C3 35.6716 3.67157 35 4.5 35H20.5C21.3284 35 22 35.6716 22 36.5C22 37.3284 21.3284 38 20.5 38H4.5C3.67157 38 3 37.3284 3 36.5Z"
            fill="#181818"
          />
          <path
            d="M3 43.5C3 42.6716 3.67157 42 4.5 42H20.5C21.3284 42 22 42.6716 22 43.5C22 44.3284 21.3284 45 20.5 45H4.5C3.67157 45 3 44.3284 3 43.5Z"
            fill="#181818"
          />
          <path
            d="M28 23C28 21.8954 28.8954 21 30 21H45C46.1046 21 47 21.8954 47 23V29C47 30.1046 46.1046 31 45 31H30C28.8954 31 28 30.1046 28 29V23Z"
            fill="#181818"
          />
          <path
            d="M51 23C51 21.8954 51.8954 21 53 21H68C69.1046 21 70 21.8954 70 23V29C70 30.1046 69.1046 31 68 31H53C51.8954 31 51 30.1046 51 29V23Z"
            fill="#181818"
          />
          <path
            d="M74 23C74 21.8954 74.8954 21 76 21H91C92.1046 21 93 21.8954 93 23V29C93 30.1046 92.1046 31 91 31H76C74.8954 31 74 30.1046 74 29V23Z"
            fill="#181818"
          />
          <path
            d="M97 23C97 21.8954 97.8954 21 99 21H114C115.105 21 116 21.8954 116 23V29C116 30.1046 115.105 31 114 31H99C97.8954 31 97 30.1046 97 29V23Z"
            fill="#181818"
          />
          <path
            d="M28 37C28 35.8954 28.8954 35 30 35H83C84.1046 35 85 35.8954 85 37V49C85 50.1046 84.1046 51 83 51H30C28.8954 51 28 50.1046 28 49V37Z"
            fill="#181818"
          />
          <path
            d="M89 37C89 35.8954 89.8954 35 91 35H114C115.105 35 116 35.8954 116 37V49C116 50.1046 115.105 51 114 51H91C89.8954 51 89 50.1046 89 49V37Z"
            fill="#181818"
          />
          <path
            d="M28 57C28 55.8954 28.8954 55 30 55H68C69.1046 55 70 55.8954 70 57V69C70 70.1046 69.1046 71 68 71H30C28.8954 71 28 70.1046 28 69V57Z"
            fill="#181818"
          />
          <path
            d="M74 57C74 55.8954 74.8954 55 76 55H114C115.105 55 116 55.8954 116 57V69C116 70.1046 115.105 71 114 71H76C74.8954 71 74 70.1046 74 69V57Z"
            fill="#181818"
          />
          <path
            d="M28 76.5C28 75.6716 28.6716 75 29.5 75H45.5C46.3284 75 47 75.6716 47 76.5C47 77.3284 46.3284 78 45.5 78H29.5C28.6716 78 28 77.3284 28 76.5Z"
            fill="#181818"
          />
        </g>
        <path
          d="M8 0.5H114C118.142 0.5 121.5 3.85786 121.5 8V76C121.5 80.1421 118.142 83.5 114 83.5H8C3.85786 83.5 0.5 80.1421 0.5 76V8C0.5 3.98724 3.65139 0.710536 7.61426 0.509766L8 0.5Z"
          stroke="#464646"
        />
        <defs>
          <clipPath id={"#{@id}-clip0_856_2644"}>
            <path
              d="M0 8C0 3.58172 3.58172 0 8 0H114C118.418 0 122 3.58172 122 8V76C122 80.4183 118.418 84 114 84H8C3.58172 84 0 80.4183 0 76V8Z"
              fill="white"
            />
          </clipPath>
        </defs>
      </svg>
    </label>
    """
  end

  attr :id, :string, required: true
  attr :name, :string, required: true

  defp theme_system(assigns) do
    ~H"""
    <input type="radio" id={@id} name={@name} value="system" phx-hook="ThemeSwitcher" />
    <label for={@id}>
      <svg width="122" height="84" viewBox="0 0 122 84" fill="none" xmlns="http://www.w3.org/2000/svg">
        <g clip-path={"url(##{@id}-clip0_856_2670)"}>
          <g clip-path={"url(##{@id}-clip1_856_2670)"}>
            <path d="M0 8a8 8 0 0 1 8-8h53v84H8a8 8 0 0 1-8-8z" fill="#fdfdfd" />
            <g clip-path={"url(##{@id}-clip2_856_2670)"}>
              <path
                d="M0 8a8 8 0 0 1 8-8h106a8 8 0 0 1 8 8v68a8 8 0 0 1-8 8H8a8 8 0 0 1-8-8z"
                fill="#fdfdfd"
              />
              <path d="M0 8a8 8 0 0 1 8-8h106a8 8 0 0 1 8 8v9H0z" fill="#f1f2f4" />
              <circle cx="11" cy="8.5" r="2" fill="#e51c01" />
              <circle cx="17" cy="8.5" r="2" fill="#ffc300" />
              <circle cx="23" cy="8.5" r="2" fill="#28a745" />
              <path fill="#fdfdfd" d="M0 17h24v67H0z" />
              <path
                d="M3 22.5A1.5 1.5 0 0 1 4.5 21h16a1.5 1.5 0 0 1 0 3h-16A1.5 1.5 0 0 1 3 22.5m0 7A1.5 1.5 0 0 1 4.5 28h16a1.5 1.5 0 0 1 0 3h-16A1.5 1.5 0 0 1 3 29.5m0 7A1.5 1.5 0 0 1 4.5 35h16a1.5 1.5 0 0 1 0 3h-16A1.5 1.5 0 0 1 3 36.5m0 7A1.5 1.5 0 0 1 4.5 42h16a1.5 1.5 0 0 1 0 3h-16A1.5 1.5 0 0 1 3 43.5M28 23a2 2 0 0 1 2-2h15a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H30a2 2 0 0 1-2-2zm23 0a2 2 0 0 1 2-2h15a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H53a2 2 0 0 1-2-2zM28 37a2 2 0 0 1 2-2h53a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H30a2 2 0 0 1-2-2zm0 20a2 2 0 0 1 2-2h38a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H30a2 2 0 0 1-2-2zm0 19.5a1.5 1.5 0 0 1 1.5-1.5h16a1.5 1.5 0 0 1 0 3h-16a1.5 1.5 0 0 1-1.5-1.5"
                fill="#f1f2f4"
              />
            </g>
            <path
              d="M8 .5h106a7.5 7.5 0 0 1 7.5 7.5v68a7.5 7.5 0 0 1-7.5 7.5H8A7.5 7.5 0 0 1 .5 76V8A7.5 7.5 0 0 1 7.614.51z"
              stroke="#d8dbdf"
            />
          </g>
          <g clip-path={"url(##{@id}-clip3_856_2670)"}>
            <path d="M61 0h53a8 8 0 0 1 8 8v68a8 8 0 0 1-8 8H61z" fill="#fdfdfd" />
            <g clip-path={"url(##{@id}-clip4_856_2670)"}>
              <path
                d="M0 8a8 8 0 0 1 8-8h106a8 8 0 0 1 8 8v68a8 8 0 0 1-8 8H8a8 8 0 0 1-8-8z"
                fill="#0e0e0e"
              />
              <path
                d="M0 8a8 8 0 0 1 8-8h106a8 8 0 0 1 8 8v9H0zm51 15a2 2 0 0 1 2-2h15a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H53a2 2 0 0 1-2-2zm23 0a2 2 0 0 1 2-2h15a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H76a2 2 0 0 1-2-2zm23 0a2 2 0 0 1 2-2h15a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H99a2 2 0 0 1-2-2zM28 37a2 2 0 0 1 2-2h53a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H30a2 2 0 0 1-2-2zm61 0a2 2 0 0 1 2-2h23a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H91a2 2 0 0 1-2-2zM28 57a2 2 0 0 1 2-2h38a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H30a2 2 0 0 1-2-2zm46 0a2 2 0 0 1 2-2h38a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H76a2 2 0 0 1-2-2z"
                fill="#181818"
              />
            </g>
            <path
              d="M8 .5h106a7.5 7.5 0 0 1 7.5 7.5v68a7.5 7.5 0 0 1-7.5 7.5H8A7.5 7.5 0 0 1 .5 76V8A7.5 7.5 0 0 1 7.614.51z"
              stroke="#464646"
            />
          </g>
        </g>
        <defs>
          <clipPath id={"#{@id}-clip0_856_2670"}>
            <path fill="#fff" d="M0 0h122v84H0z" />
          </clipPath>
          <clipPath id={"#{@id}-clip1_856_2670"}>
            <path d="M0 8a8 8 0 0 1 8-8h53v84H8a8 8 0 0 1-8-8z" fill="#fff" />
          </clipPath>
          <clipPath id={"#{@id}-clip2_856_2670"}>
            <path
              d="M0 8a8 8 0 0 1 8-8h106a8 8 0 0 1 8 8v68a8 8 0 0 1-8 8H8a8 8 0 0 1-8-8z"
              fill="#fff"
            />
          </clipPath>
          <clipPath id={"#{@id}-clip3_856_2670"}>
            <path d="M61 0h53a8 8 0 0 1 8 8v68a8 8 0 0 1-8 8H61z" fill="#fff" />
          </clipPath>
          <clipPath id={"#{@id}-clip4_856_2670"}>
            <path
              d="M0 8a8 8 0 0 1 8-8h106a8 8 0 0 1 8 8v68a8 8 0 0 1-8 8H8a8 8 0 0 1-8-8z"
              fill="#fff"
            />
          </clipPath>
        </defs>
      </svg>
    </label>
    """
  end
end
