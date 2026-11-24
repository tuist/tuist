defmodule LuftServerWeb.PresenceChannel do
  @moduledoc "Account-scoped presence; periodic checks revalidate authority, not conversation state."
  use Phoenix.Channel

  alias LuftServer.Lounges.Presence
  alias LuftServer.Tuist.Scope
  alias LuftServerWeb.ConversationsSocket
  alias Phoenix.Socket.Broadcast

  @recheck_ms 30_000

  def join("presence:" <> handle, _params, socket) do
    with {:ok, session} <- ConversationsSocket.authenticate(socket),
         {:ok, scope} <- Scope.load(session, handle) do
      Phoenix.PubSub.subscribe(LuftServer.PubSub, Presence.topic(scope))
      send(self(), :track_presence)
      Process.send_after(self(), :recheck_authority, @recheck_ms)
      {:ok, socket |> assign(:scope, scope) |> assign(:handle, handle)}
    else
      _ -> {:error, %{reason: "not_found"}}
    end
  end

  def handle_info(:track_presence, socket) do
    scope = socket.assigns.scope
    person = Enum.find(scope.people, &(&1.id == scope.user_id))

    {:ok, _} =
      Presence.track(self(), Presence.topic(scope), to_string(scope.user_id), %{
        handle: person.handle,
        online_at: System.system_time(:second)
      })

    push(socket, "presence_state", Presence.list(Presence.topic(scope)))
    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: "presence_diff", payload: diff}, socket) do
    case ConversationsSocket.authenticate(socket) do
      {:ok, _session} ->
        push(socket, "presence_diff", diff)
        {:noreply, socket}

      _ ->
        {:stop, :normal, socket}
    end
  end

  def handle_info(:recheck_authority, socket) do
    with {:ok, session} <- ConversationsSocket.authenticate(socket),
         {:ok, scope} <- Scope.load(session, socket.assigns.handle),
         true <- scope.account_id == socket.assigns.scope.account_id,
         true <- scope.user_id == socket.assigns.scope.user_id do
      Process.send_after(self(), :recheck_authority, @recheck_ms)
      {:noreply, assign(socket, :scope, scope)}
    else
      _ -> {:stop, :normal, socket}
    end
  end
end
