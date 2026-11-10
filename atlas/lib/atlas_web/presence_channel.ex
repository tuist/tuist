defmodule AtlasWeb.PresenceChannel do
  @moduledoc false
  use AtlasWeb, :channel

  alias Atlas.Guardian
  alias Atlas.Presence

  @impl true
  def join("presence:team", params, socket) do
    with {:ok, user, _claims} <- Guardian.resource_from_token(socket.assigns.access_token),
         id = Ecto.UUID.generate(),
         {:ok, params, _location} <- resolve_location(user, params),
         {:ok, snapshot} <- Presence.sync(user, id, params) do
      Presence.subscribe()
      Process.send_after(self(), :renew_presence, 10_000)

      {:ok, snapshot, assign(socket, current_user: user, connection_id: id, location: params, snapshot: snapshot)}
    else
      _ -> {:error, %{reason: "forbidden"}}
    end
  end

  @impl true
  def handle_in("location", params, socket) do
    with {:ok, user, _claims} <- Guardian.resource_from_token(socket.assigns.access_token),
         {:ok, params, _location} <- resolve_location(user, params),
         {:ok, snapshot} <- Presence.sync(user, socket.assigns.connection_id, params) do
      {:reply, {:ok, snapshot}, assign(socket, current_user: user, location: params, snapshot: snapshot)}
    else
      _ -> {:stop, :normal, {:error, %{reason: "forbidden"}}, socket}
    end
  end

  @impl true
  def handle_info(:presence_changed, socket) do
    with {:ok, user, _claims} <- Guardian.resource_from_token(socket.assigns.access_token),
         {:ok, params, location} <- resolve_location(user, socket.assigns.location) do
      snapshot =
        if params == socket.assigns.location do
          Presence.snapshot(user, location)
        else
          {:ok, snapshot} = Presence.sync(user, socket.assigns.connection_id, params)
          snapshot
        end

      if snapshot != socket.assigns.snapshot, do: push(socket, "snapshot", snapshot)
      {:noreply, assign(socket, current_user: user, location: params, snapshot: snapshot)}
    else
      _ -> {:stop, :normal, socket}
    end
  end

  def handle_info(:renew_presence, socket) do
    with {:ok, user, _claims} <- Guardian.resource_from_token(socket.assigns.access_token),
         {:ok, params, _location} <- resolve_location(user, socket.assigns.location) do
      if params == socket.assigns.location do
        Presence.renew(user, socket.assigns.connection_id, params)
      else
        {:ok, _snapshot} = Presence.sync(user, socket.assigns.connection_id, params)
      end

      Process.send_after(self(), :renew_presence, 10_000)
      {:noreply, assign(socket, current_user: user, location: params)}
    else
      _ -> {:stop, :normal, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    Presence.leave(socket.assigns.current_user, socket.assigns.connection_id)
    :ok
  end

  defp resolve_location(user, params) do
    case Presence.location(user, params) do
      {:ok, location} -> {:ok, params, location}
      # Losing access to a location must not disconnect an authenticated teammate.
      {:error, reason} when reason in [:forbidden, :not_found] -> {:ok, %{}, nil}
      error -> error
    end
  end
end
