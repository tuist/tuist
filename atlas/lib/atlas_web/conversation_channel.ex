defmodule AtlasWeb.ConversationChannel do
  @moduledoc """
  Live viewers, typing, and history invalidation for one conversation.

  Pushes `snapshot` with `%{revision, people}`; clients fetch messages over HTTP
  when the revision moves. Every join, push, typing update, and renewal
  re-checks the OAuth grant and the caller's current read access; losing either
  stops the channel.
  """
  use AtlasWeb, :channel

  alias Atlas.Conversations
  alias Atlas.Conversations.Viewers
  alias Atlas.Guardian

  @renew_interval :timer.seconds(10)

  @impl true
  def join("conversation:" <> id, _params, socket) do
    case authorize(socket, id) do
      {:ok, user, conversation} ->
        connection_id = Ecto.UUID.generate()
        Conversations.subscribe(conversation.id)
        :ok = Viewers.enter(conversation, user, connection_id)
        Process.send_after(self(), :renew, @renew_interval)
        snapshot = Viewers.snapshot(conversation)

        {:ok, snapshot,
         assign(socket, conversation_id: conversation.id, connection_id: connection_id, snapshot: snapshot)}

      _ ->
        {:error, %{reason: "unavailable"}}
    end
  end

  @impl true
  def handle_in("typing", %{"typing" => typing}, socket) when is_boolean(typing) do
    case authorize(socket, socket.assigns.conversation_id) do
      {:ok, _user, _conversation} ->
        :ok = Viewers.typing(socket.assigns.conversation_id, socket.assigns.connection_id, typing)
        if typing, do: Process.send_after(self(), :conversation_changed, :timer.seconds(Viewers.typing_seconds()) + 500)
        {:reply, :ok, socket}

      _ ->
        {:stop, :normal, {:error, %{reason: "unavailable"}}, socket}
    end
  end

  def handle_in("typing", _params, socket), do: {:reply, {:error, %{reason: "invalid"}}, socket}

  @impl true
  def handle_info(:conversation_changed, socket) do
    case authorize(socket, socket.assigns.conversation_id) do
      {:ok, _user, conversation} -> {:noreply, push_snapshot(socket, conversation)}
      _ -> {:stop, :normal, socket}
    end
  end

  def handle_info(:renew, socket) do
    case authorize(socket, socket.assigns.conversation_id) do
      {:ok, user, conversation} ->
        :ok = Viewers.renew(conversation, user, socket.assigns.connection_id)
        Process.send_after(self(), :renew, @renew_interval)
        {:noreply, push_snapshot(socket, conversation)}

      _ ->
        {:stop, :normal, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:connection_id] do
      Viewers.leave(socket.assigns.conversation_id, socket.assigns.connection_id)
    end

    :ok
  end

  defp authorize(socket, id) do
    with {:ok, user, _claims} <- Guardian.resource_from_token(socket.assigns.access_token),
         {:ok, conversation} <- Conversations.fetch(user, id) do
      {:ok, user, conversation}
    end
  end

  defp push_snapshot(socket, conversation) do
    snapshot = Viewers.snapshot(conversation)

    if snapshot == socket.assigns.snapshot do
      socket
    else
      push(socket, "snapshot", snapshot)
      assign(socket, :snapshot, snapshot)
    end
  end
end
