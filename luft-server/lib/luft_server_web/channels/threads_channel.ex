defmodule LuftServerWeb.ThreadsChannel do
  @moduledoc "Commit-driven thread invalidations and the triggering author's ephemeral app tools."
  use Phoenix.Channel

  alias LuftServer.Threads
  alias LuftServer.Threads.Clients
  alias LuftServer.Tuist.Scope
  alias LuftServerWeb.ConversationsSocket

  @recheck_ms 30_000

  def join("threads:" <> path, params, socket) do
    with [handle, id] <- String.split(path, ":"),
         {:ok, target} <- target(id),
         {:ok, session} <- ConversationsSocket.authenticate(socket),
         {:ok, scope} <- Scope.load(session, handle) do
      # Subscribe before reading: a commit cannot disappear between the two.
      Phoenix.PubSub.subscribe(LuftServer.PubSub, Threads.topic(scope.user_id, scope.account_id))

      case Threads.snapshot(scope, target) do
        {:ok, snapshot} ->
          tools = tools(target, params)
          if tools != [], do: {:ok, _} = Clients.join(target, scope.user_id, tools)
          Process.send_after(self(), :recheck_authority, @recheck_ms)

          {:ok, snapshot,
           socket
           |> assign(:handle, handle)
           |> assign(:scope, scope)
           |> assign(:target, target)
           |> assign(:snapshot, snapshot)
           |> assign(:tool_calls, %{})}

        _ ->
          {:error, %{reason: "not_found"}}
      end
    else
      _ -> {:error, %{reason: "not_found"}}
    end
  end

  def handle_in("tool_result", %{"id" => id} = payload, socket) when is_binary(id) do
    case Map.pop(socket.assigns.tool_calls, id) do
      {{ref, from}, pending} ->
        with {:ok, _session} <- ConversationsSocket.authenticate(socket),
             {:ok, _snapshot} <- Threads.snapshot(socket.assigns.scope, socket.assigns.target) do
          send(from, {:client_tool_result, ref, Clients.result(payload)})
          {:noreply, assign(socket, :tool_calls, pending)}
        else
          _ -> {:stop, :normal, socket}
        end

      {nil, _pending} ->
        {:noreply, socket}
    end
  end

  def handle_in(_event, _payload, socket), do: {:noreply, socket}

  def handle_info(:threads_changed, socket), do: refresh(socket)

  def handle_info(:recheck_authority, socket) do
    with {:ok, session} <- ConversationsSocket.authenticate(socket),
         {:ok, scope} <- Scope.load(session, socket.assigns.handle),
         true <- scope.account_id == socket.assigns.scope.account_id,
         true <- scope.user_id == socket.assigns.scope.user_id do
      Process.send_after(self(), :recheck_authority, @recheck_ms)
      # Recheck readership too, but do not poll for conversation snapshots.
      case Threads.snapshot(scope, socket.assigns.target) do
        {:ok, _snapshot} -> {:noreply, assign(socket, :scope, scope)}
        _ -> {:stop, :normal, socket}
      end
    else
      _ -> {:stop, :normal, socket}
    end
  end

  def handle_info({:client_tool_call, ref, from, name, args, timeout}, socket) do
    with {:ok, session} <- ConversationsSocket.authenticate(socket),
         {:ok, scope} <- Scope.load(session, socket.assigns.handle),
         true <- scope.account_id == socket.assigns.scope.account_id,
         {:ok, _snapshot} <- Threads.snapshot(scope, socket.assigns.target) do
      id = Ecto.UUID.generate()
      push(socket, "tool_call", %{id: id, name: name, arguments: args})
      Process.send_after(self(), {:tool_call_expired, id}, timeout)

      {:noreply,
       socket
       |> assign(:scope, scope)
       |> assign(:tool_calls, Map.put(socket.assigns.tool_calls, id, {ref, from}))}
    else
      _ -> {:stop, :normal, socket}
    end
  end

  def handle_info({:tool_call_expired, id}, socket),
    do: {:noreply, assign(socket, :tool_calls, Map.delete(socket.assigns.tool_calls, id))}

  defp refresh(socket) do
    with {:ok, _session} <- ConversationsSocket.authenticate(socket),
         {:ok, snapshot} <- Threads.snapshot(socket.assigns.scope, socket.assigns.target) do
      if snapshot != socket.assigns.snapshot, do: push(socket, "snapshot", snapshot)
      {:noreply, assign(socket, :snapshot, snapshot)}
    else
      _ -> {:stop, :normal, socket}
    end
  end

  defp target("inbox"), do: {:ok, :inbox}
  defp target(id), do: Ecto.UUID.cast(id)
  defp tools(:inbox, _params), do: []

  defp tools(_id, params) do
    case Clients.validate(params["tools"]) do
      {:ok, tools} -> tools
      _ -> []
    end
  end
end
