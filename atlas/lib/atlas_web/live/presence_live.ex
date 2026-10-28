defmodule AtlasWeb.PresenceLive do
  @moduledoc false

  import Phoenix.Component
  import Phoenix.LiveView

  alias Atlas.Demo
  alias Atlas.Presence

  def attach(socket) do
    socket =
      socket
      |> assign(:presence_here, [])
      |> assign(:presence_snapshot, nil)
      |> assign(:presence_location, %{})
      |> assign(:presence_visible, false)
      |> assign(:presence_connection, nil)
      |> stream(:presence_people, [])

    if connected?(socket) and not Demo.enabled?() do
      params = get_connect_params(socket) || %{}

      id = Ecto.UUID.generate()
      {:ok, _tracker} = Presence.track(socket.assigns.current_user, id)
      Presence.subscribe()
      Process.send_after(self(), :presence_renew, 10_000)

      socket
      |> assign(:presence_connection, id)
      |> assign(:presence_visible, params["presence_visible"] != false)
      |> attach_hook(:presence_params, :handle_params, fn _params, uri, socket ->
        location = Presence.page_location(socket.assigns.current_user, URI.parse(uri).path)
        {:cont, socket |> assign(:presence_location, location) |> refresh()}
      end)
      |> attach_hook(:presence_event, :handle_event, &handle_event/3)
      |> attach_hook(:presence_info, :handle_info, &handle_info/2)
    else
      socket
    end
  end

  defp handle_event("presence_visibility", %{"visible" => visible}, socket) when is_boolean(visible) do
    if not visible, do: Presence.leave(socket.assigns.current_user, socket.assigns.presence_connection)
    {:halt, socket |> assign(:presence_visible, visible) |> refresh()}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp handle_info(:presence_renew, socket) do
    Process.send_after(self(), :presence_renew, 10_000)

    if socket.assigns.presence_visible do
      Presence.renew(socket.assigns.current_user, socket.assigns.presence_connection, socket.assigns.presence_location)
    end

    {:halt, socket}
  end

  defp handle_info(:presence_changed, socket), do: {:halt, snapshot(socket)}

  defp handle_info(_message, socket), do: {:cont, socket}

  defp refresh(socket) do
    user = socket.assigns.current_user

    if socket.assigns.presence_visible do
      Presence.sync(user, socket.assigns.presence_connection, socket.assigns.presence_location)
    end

    snapshot(socket)
  end

  defp snapshot(socket) do
    user = socket.assigns.current_user

    location =
      case Presence.location(user, socket.assigns.presence_location) do
        {:ok, location} -> location
        _ -> nil
      end

    snapshot = Presence.snapshot(user, location)

    if socket.assigns.presence_snapshot == snapshot do
      socket
    else
      socket
      |> assign(:presence_snapshot, snapshot)
      |> assign(:presence_here, Enum.filter(snapshot.people, & &1.here))
      |> stream(:presence_people, snapshot.people, reset: true)
    end
  end
end
