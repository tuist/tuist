defmodule AtlasWeb.ConnectionsLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Audit
  alias Atlas.Connections
  alias Atlas.Connections.Gmail

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Connections"))
     |> stream_configure(:connections, dom_id: &"connection-#{&1.provider}")
     |> load_connections()}
  end

  def handle_event("disconnect", %{"provider" => provider}, socket) do
    result =
      Audit.with_context(%{actor: socket.assigns.current_user, interface: "dashboard"}, fn ->
        Connections.disconnect(socket.assigns.current_user, provider)
      end)

    case result do
      {:ok, :ok} ->
        {:noreply, socket |> put_flash(:info, gettext("Account disconnected from Atlas.")) |> load_connections()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not disconnect your account. Please try again."))}
    end
  end

  defp load_connections(socket) do
    stream(socket, :connections, Connections.list(socket.assigns.current_user), reset: true)
  end

  def render(assigns) do
    ~H"""
    <section id="connections" data-part="account-settings-page">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Connections")}</h1>
          <p data-part="description">
            {gettext(
              "Connect your own accounts so Atlas tools can act with your access. These are separate from your Atlas sign-in."
            )}
          </p>
        </div>
      </div>
      <div id="personal-connections" data-part="settings-sections" phx-update="stream">
        <.card_section
          :for={{id, entry} <- @streams.connections}
          id={id}
          data-part="settings-section"
        >
          <div data-part="header">
            <span data-part="title">
              <span data-part="icon"><.icon name={"brand_#{entry.provider}"} /></span>
              {entry.name}
            </span>
            <span data-part="subtitle">{description(entry.provider)}</span>
          </div>
          <div data-part="content">
            <div data-part="connection-row">
              <span id={"connection-account-#{entry.provider}"} data-part="account">
                {entry.account_name || gettext("Account")}
              </span>
              <.status_badge
                id={"connection-status-#{entry.provider}"}
                type="dot"
                status={status_color(entry.status)}
                label={status_label(entry.status)}
              />
            </div>
            <div
              :if={entry.provider == "google" && entry.status != "not_connected"}
              id="connection-gmail"
              data-part="connection-row"
            >
              <span data-part="account">{gettext("Gmail")}</span>
              <.status_badge
                id="connection-gmail-status"
                type="dot"
                status={if(gmail?(entry), do: "success", else: "disabled")}
                label={
                  if(gmail?(entry), do: gettext("Read access granted"), else: gettext("Not granted"))
                }
              />
            </div>
            <.alert
              :if={!entry.configured}
              id={"connection-unconfigured-#{entry.provider}"}
              status="information"
              type="secondary"
              size="small"
              title={gettext("An administrator needs to configure this connection.")}
            />
            <div :if={entry.configured} data-part="actions">
              <.button
                :if={entry.status != "not_connected"}
                id={"connection-disconnect-#{entry.provider}"}
                label={gettext("Disconnect")}
                variant="destructive"
                size="medium"
                phx-click="disconnect"
                phx-value-provider={entry.provider}
                data-confirm={gettext("Remove this account's stored credentials from Atlas?")}
              />
              <.button
                :if={entry.provider == "google" && entry.status != "not_connected" && !gmail?(entry)}
                id="connection-gmail-consent"
                href={~p"/connections/google/authorize?gmail=read"}
                label={gettext("Allow Gmail access")}
                variant="secondary"
                size="medium"
              />
              <.button
                id={"connection-connect-#{entry.provider}"}
                href={authorize_path(entry)}
                label={
                  if(entry.status == "not_connected",
                    do: gettext("Connect"),
                    else: gettext("Reconnect")
                  )
                }
                variant={if(entry.status == "connected", do: "secondary", else: "primary")}
                size="medium"
              />
            </div>
          </div>
        </.card_section>
      </div>
      <p data-part="footnote">
        {gettext(
          "Credentials are encrypted and never shown to agents. Your connections are only used for your own requests: other people and shared Pip threads cannot use them. Disconnecting removes stored credentials; revoke app access in your provider settings to invalidate the grant there too. Gmail monitoring starts only after you configure and enable a signal source."
        )}
      </p>
    </section>
    """
  end

  defp description("github"),
    do: gettext("Lets Atlas list the repositories you can access when you start coding conversations.")

  defp description("slack"),
    do:
      gettext(
        "Search the messages, channels and DMs you can see in Slack from Atlas tools (search_my_slack). This is separate from the Atlas bot."
      )

  defp description("google"),
    do:
      gettext(
        "Drive files and read-only calendar access. Allow Gmail access to search and read your mail from Atlas tools (search_my_gmail, get_my_gmail_message)."
      )

  defp description(_provider), do: nil

  # Google returns only the scopes requested by the latest consent, so a plain
  # reconnect would silently drop a previously granted Gmail scope.
  defp authorize_path(%{provider: "google"} = entry) do
    if gmail?(entry), do: ~p"/connections/google/authorize?gmail=read", else: ~p"/connections/google/authorize"
  end

  defp authorize_path(entry), do: ~p"/connections/#{entry.provider}/authorize"

  defp gmail?(entry), do: Gmail.scope() in entry.scopes

  defp status_color("connected"), do: "success"
  defp status_color("needs_authorization"), do: "warning"
  defp status_color(_), do: "disabled"

  defp status_label("connected"), do: gettext("Connected")
  defp status_label("needs_authorization"), do: gettext("Reconnect needed")
  defp status_label(_), do: gettext("Not connected")
end
