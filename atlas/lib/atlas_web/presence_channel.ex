defmodule AtlasWeb.PresenceChannel do
  @moduledoc false
  use AtlasWeb, :channel

  alias Atlas.Guardian
  alias Atlas.Presence

  @impl true
  def join("presence:team", params, socket) do
    with {:ok, user, _claims} <- Guardian.resource_from_token(socket.assigns.access_token),
         id = Ecto.UUID.generate(),
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
         {:ok, snapshot} <- Presence.sync(user, socket.assigns.connection_id, params) do
      {:reply, {:ok, snapshot}, assign(socket, current_user: user, location: params, snapshot: snapshot)}
    else
      _ -> {:stop, :normal, {:error, %{reason: "forbidden"}}, socket}
    end
  end

  @impl true
  def handle_info(:presence_changed, socket) do
    with {:ok, user, _claims} <- Guardian.resource_from_token(socket.assigns.access_token),
         {:ok, location} <- Presence.location(user, socket.assigns.location) do
      snapshot = Presence.snapshot(user, location)
      if snapshot != socket.assigns.snapshot, do: push(socket, "snapshot", snapshot)
      {:noreply, assign(socket, current_user: user, snapshot: snapshot)}
    else
      _ -> {:stop, :normal, socket}
    end
  end

  def handle_info(:renew_presence, socket) do
    with {:ok, user, _claims} <- Guardian.resource_from_token(socket.assigns.access_token),
         {:ok, _location} <- Presence.location(user, socket.assigns.location) do
      Presence.renew(user, socket.assigns.connection_id, socket.assigns.location)
      Process.send_after(self(), :renew_presence, 10_000)
      {:noreply, assign(socket, :current_user, user)}
    else
      _ -> {:stop, :normal, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    Presence.leave(socket.assigns.current_user, socket.assigns.connection_id)
    :ok
  end
end
