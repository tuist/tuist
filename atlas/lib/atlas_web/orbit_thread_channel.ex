defmodule AtlasWeb.OrbitThreadChannel do
  @moduledoc """
  Live viewers, typing, and history invalidation for one thread.

  Pushes `snapshot` with `%{revision, people, agent_status}`; clients fetch messages
  over HTTP when the revision moves and apply activity even without a new revision. Every join, push, typing update, and renewal
  re-checks the OAuth grant and the caller's current read access; losing either
  stops the channel.
  """
  use AtlasWeb, :channel

  alias Atlas.Guardian
  alias Atlas.Orbit
  alias Atlas.Orbit.Viewers

  @renew_interval :timer.seconds(10)

  @impl true
  def join("orbit:thread:" <> id, _params, socket) do
    case authorize(socket, id) do
      {:ok, user, thread} ->
        connection_id = Ecto.UUID.generate()
        Orbit.subscribe(thread.id)
        :ok = Viewers.enter(thread, user, connection_id)
        Process.send_after(self(), :renew, @renew_interval)
        snapshot = Viewers.snapshot(thread)

        {:ok, snapshot, assign(socket, thread_id: thread.id, connection_id: connection_id, snapshot: snapshot)}

      _ ->
        {:error, %{reason: "unavailable"}}
    end
  end

  @impl true
  def handle_in("typing", %{"typing" => typing}, socket) when is_boolean(typing) do
    case authorize(socket, socket.assigns.thread_id) do
      {:ok, _user, _thread} ->
        :ok = Viewers.typing(socket.assigns.thread_id, socket.assigns.connection_id, typing)
        if typing, do: Process.send_after(self(), :thread_changed, :timer.seconds(Viewers.typing_seconds()) + 500)
        {:reply, :ok, socket}

      _ ->
        {:stop, :normal, {:error, %{reason: "unavailable"}}, socket}
    end
  end

  def handle_in("typing", _params, socket), do: {:reply, {:error, %{reason: "invalid"}}, socket}

  @impl true
  def handle_info(:thread_changed, socket) do
    case authorize(socket, socket.assigns.thread_id) do
      {:ok, _user, thread} -> {:noreply, push_snapshot(socket, thread)}
      _ -> {:stop, :normal, socket}
    end
  end

  def handle_info(:renew, socket) do
    case authorize(socket, socket.assigns.thread_id) do
      {:ok, user, thread} ->
        :ok = Viewers.renew(thread, user, socket.assigns.connection_id)
        Process.send_after(self(), :renew, @renew_interval)
        {:noreply, push_snapshot(socket, thread)}

      _ ->
        {:stop, :normal, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:connection_id] do
      Viewers.leave(socket.assigns.thread_id, socket.assigns.connection_id)
    end

    :ok
  end

  defp authorize(socket, id) do
    with {:ok, user, _claims} <- Guardian.resource_from_token(socket.assigns.access_token),
         {:ok, thread} <- Orbit.fetch(user, id) do
      {:ok, user, thread}
    end
  end

  defp push_snapshot(socket, thread) do
    snapshot = Viewers.snapshot(thread)

    if snapshot == socket.assigns.snapshot do
      socket
    else
      push(socket, "snapshot", snapshot)
      assign(socket, :snapshot, snapshot)
    end
  end
end
