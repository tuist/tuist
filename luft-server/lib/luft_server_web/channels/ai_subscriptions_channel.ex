defmodule LuftServerWeb.AISubscriptionsChannel do
  @moduledoc """
  The person's AI subscriptions, live: the join replies with them, and the
  channel pushes `snapshot` with the new list whenever it changes
  (`LuftServer.AISubscriptions.broadcast/1`). Luft stores the subscriptions,
  so every change goes through it. The channel still rechecks the session
  every 15 seconds and leaves once it is gone.
  """
  use Phoenix.Channel

  alias LuftServer.AISubscriptions
  alias LuftServerWeb.ConversationsSocket

  @poll_ms 15_000

  def join("ai_subscriptions", _params, socket) do
    with {:ok, session} <- ConversationsSocket.authenticate(socket),
         # Subscribe before reading: a change cannot disappear between the two.
         :ok <- Phoenix.PubSub.subscribe(LuftServer.PubSub, AISubscriptions.topic(session)),
         {:ok, subscriptions} <- AISubscriptions.list(session) do
      Process.send_after(self(), :poll, @poll_ms)

      {:ok, %{subscriptions: subscriptions}, assign(socket, :subscriptions, subscriptions)}
    else
      _ -> {:error, %{reason: "not_found"}}
    end
  end

  def handle_in(_event, _payload, socket), do: {:noreply, socket}

  def handle_info({:ai_subscriptions, subscriptions}, socket) do
    case ConversationsSocket.authenticate(socket) do
      {:ok, _session} -> {:noreply, show(socket, subscriptions)}
      _ -> {:stop, :normal, socket}
    end
  end

  def handle_info(:poll, socket) do
    case ConversationsSocket.authenticate(socket) do
      {:ok, _session} ->
        Process.send_after(self(), :poll, @poll_ms)
        {:noreply, socket}

      _ ->
        {:stop, :normal, socket}
    end
  end

  defp show(socket, subscriptions) do
    if subscriptions != socket.assigns.subscriptions,
      do: push(socket, "snapshot", %{subscriptions: subscriptions})

    assign(socket, :subscriptions, subscriptions)
  end
end
