defmodule AtlasWeb.LoginLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Ueberauth.Strategy.Google.OAuth

  def mount(_params, session, socket) do
    user_id = session["user_id"]

    if user_id && Atlas.Users.get_user(user_id) do
      {:ok, redirect(socket, to: ~p"/")}
    else
      socket =
        socket
        |> assign(:page_title, "Log in")
        |> assign(:google_configured?, google_configured?())
        |> assign(:dev_routes?, Application.get_env(:atlas, :dev_routes, false))

      {:ok, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div id="login">
      <div data-part="frame">
        <div data-part="content">
          <img src={~p"/images/tuist-logo.svg"} alt="Atlas Logo" data-part="logo" />
          <div data-part="header">
            <h1 data-part="title">{gettext("Log in to Atlas")}</h1>
            <span data-part="subtitle">
              {gettext("Enter the atlas.")}
            </span>
          </div>
          <.alert
            :if={Phoenix.Flash.get(@flash, :error)}
            id="flash-error"
            type="secondary"
            status="error"
            size="small"
            title={Phoenix.Flash.get(@flash, :error)}
          />
          <div :if={@google_configured?} data-part="oauth">
            <.button
              href={~p"/auth/google"}
              variant="secondary"
              size="medium"
              label={gettext("Continue with Google")}
            >
              <:icon_left>
                <.brand_google />
              </:icon_left>
            </.button>
          </div>
          <div :if={!@google_configured? && !@dev_routes?} data-part="no-providers">
            <.alert
              id="no-providers"
              type="secondary"
              status="information"
              size="small"
              title={
                gettext(
                  "No authentication providers are configured. Set the GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET environment variables to enable Google OAuth."
                )
              }
            />
          </div>
          <div :if={@dev_routes?} data-part="oauth">
            <form method="post" action={~p"/dev/login"}>
              <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
              <.button
                type="submit"
                variant="secondary"
                size="medium"
                label={gettext("Log in as test user")}
              />
            </form>
          </div>
        </div>
      </div>
      <div data-part="background">
        <div data-part="top-right-gradient"></div>
        <div data-part="bottom-left-gradient"></div>
      </div>
    </div>
    """
  end

  defp google_configured? do
    Application.get_env(:ueberauth, OAuth)[:client_id] not in [
      nil,
      ""
    ]
  end
end
