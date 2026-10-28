defmodule AtlasWeb.ConnectionsLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Audit
  alias Atlas.Connections

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
            {gettext("Personal GitHub, Slack and Google accounts, separate from your Atlas sign-in.")}
          </p>
        </div>
      </div>
      <div id="personal-connections" phx-update="stream">
        <div :for={{id, entry} <- @streams.connections} id={id}>
          <.card title={entry.name} icon="server">
            <.card_section>
              <p :if={entry.account_name} id={"connection-account-#{entry.provider}"}>
                {entry.account_name}
              </p>
              <p :if={!entry.configured}>
                {gettext("An administrator needs to configure this connection.")}
              </p>
              <.badge
                id={"connection-status-#{entry.provider}"}
                label={status_label(entry.status)}
                color={if(entry.status == "connected", do: "success", else: "neutral")}
                style="light-fill"
              />
              <.button
                :if={entry.configured}
                id={"connection-connect-#{entry.provider}"}
                href={~p"/connections/#{entry.provider}/authorize"}
                label={
                  if(entry.status == "not_connected",
                    do: gettext("Connect"),
                    else: gettext("Reconnect")
                  )
                }
                variant="secondary"
                size="small"
              />
              <.button
                :if={entry.status != "not_connected"}
                id={"connection-disconnect-#{entry.provider}"}
                label={gettext("Disconnect")}
                variant="destructive"
                size="small"
                phx-click="disconnect"
                phx-value-provider={entry.provider}
                data-confirm={gettext("Remove this account's stored credentials from Atlas?")}
              />
            </.card_section>
          </.card>
        </div>
      </div>
      <p data-part="description">
        {gettext(
          "Credentials are encrypted and never shown to agents. Disconnecting removes stored credentials; revoke app access in your provider settings to invalidate the grant there too. Google requests file and read-only calendar access, never Gmail access."
        )}
      </p>
    </section>
    """
  end

  defp status_label("connected"), do: gettext("Connected")
  defp status_label("needs_authorization"), do: gettext("Reconnect needed")
  defp status_label(_), do: gettext("Not connected")
end
