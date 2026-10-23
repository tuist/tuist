defmodule AtlasWeb.OrbitInboxChannel do
  @moduledoc """
  Live invalidation for the caller's thread list (`orbit:me`).

  Pushes `snapshot` with `%{revision, people: []}`, where `revision` is a
  fingerprint of the caller's authorized list. Clients refetch the list over
  HTTP when it moves. Invalidations are id-free; the channel recomputes the
  authorized list itself, re-checking the OAuth grant on every push and on a
  ten-second renewal that also covers missed notifications.
  """
  use AtlasWeb, :channel

  alias Atlas.Guardian
  alias Atlas.Orbit

  @renew_interval :timer.seconds(10)
  @coalesce_interval 500

  @impl true
  def join("orbit:me", _params, socket) do
    case Guardian.resource_from_token(socket.assigns.access_token) do
      {:ok, user, _claims} ->
        Orbit.subscribe_list()
        Process.send_after(self(), :renew, @renew_interval)
        snapshot = snapshot(user)
        {:ok, snapshot, assign(socket, snapshot: snapshot, refresh_scheduled: false)}

      _ ->
        {:error, %{reason: "unavailable"}}
    end
  end

  @impl true
  def handle_info(:orbit_changed, %{assigns: %{refresh_scheduled: true}} = socket), do: {:noreply, socket}

  def handle_info(:orbit_changed, socket) do
    Process.send_after(self(), :refresh, @coalesce_interval)
    {:noreply, assign(socket, :refresh_scheduled, true)}
  end

  def handle_info(:refresh, socket), do: refresh(assign(socket, :refresh_scheduled, false))

  def handle_info(:renew, socket) do
    Process.send_after(self(), :renew, @renew_interval)
    refresh(socket)
  end

  defp refresh(socket) do
    case Guardian.resource_from_token(socket.assigns.access_token) do
      {:ok, user, _claims} ->
        snapshot = snapshot(user)

        if snapshot == socket.assigns.snapshot do
          {:noreply, socket}
        else
          push(socket, "snapshot", snapshot)
          {:noreply, assign(socket, :snapshot, snapshot)}
        end

      _ ->
        {:stop, :normal, socket}
    end
  end

  defp snapshot(user), do: %{revision: Orbit.list_revision(user), people: []}
end
