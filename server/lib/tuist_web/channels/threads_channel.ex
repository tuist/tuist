defmodule TuistWeb.ThreadsChannel do
  @moduledoc false
  use Phoenix.Channel

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Threads
  alias Tuist.Threads.Clients
  alias TuistWeb.ThreadsSocket

  @poll_interval 10_000

  def join("jams:" <> scope, params, socket), do: join("threads:" <> scope, params, socket)

  # A thread's join may offer the app's tools (`Tuist.Threads.Clients`), which
  # the thread's agent can then call through this channel.
  def join("threads:" <> scope, params, socket) do
    with [handle, id] <- String.split(scope, ":"),
         {:ok, target} <- target(id),
         %Account{} = account <- Accounts.get_account_by_handle(handle),
         {:ok, user} <- ThreadsSocket.authenticate(socket.assigns.bearer),
         :ok <- Threads.authorize_reader(user, account) do
      # Subscribe before the authoritative read so a concurrent commit cannot
      # fall between the initial snapshot and subscription.
      Phoenix.PubSub.subscribe(Tuist.PubSub, Threads.topic(user.id, account.id))

      socket =
        socket
        |> assign(:app_user, user)
        |> assign(:account_handle, handle)
        |> assign(:account_id, account.id)
        |> assign(:target, target)

      case snapshot(socket) do
        {:ok, value} ->
          schedule_poll()
          tools = tools(target, params)
          if tools != [], do: {:ok, _} = Clients.join(target, user.id, tools)
          {:ok, value, socket |> assign(:snapshot, value) |> assign(:tool_calls, %{})}

        _ ->
          {:error, %{reason: "not_found"}}
      end
    else
      _ -> {:error, %{reason: "not_found"}}
    end
  end

  # The app answers a call `Clients.call/5` sent this channel.
  def handle_in("tool_result", %{"id" => id} = payload, socket) when is_binary(id) do
    case Map.pop(socket.assigns.tool_calls, id) do
      {{ref, from}, calls} ->
        send(from, {:client_tool_result, ref, Clients.result(payload)})
        {:noreply, assign(socket, :tool_calls, calls)}

      {nil, _calls} ->
        {:noreply, socket}
    end
  end

  def handle_in(_event, _payload, socket), do: {:noreply, socket}

  def handle_info({:client_tool_call, ref, from, name, args, timeout}, socket) do
    id = Ecto.UUID.generate()
    push(socket, "tool_call", %{id: id, name: name, arguments: args})
    # The caller stops waiting after `timeout`; an answer after it goes nowhere.
    Process.send_after(self(), {:tool_call_expired, id}, timeout)
    {:noreply, assign(socket, :tool_calls, Map.put(socket.assigns.tool_calls, id, {ref, from}))}
  end

  def handle_info({:tool_call_expired, id}, socket),
    do: {:noreply, assign(socket, :tool_calls, Map.delete(socket.assigns.tool_calls, id))}

  def handle_info(:poll_snapshot, socket) do
    # Local PubSub is a latency optimization, not a cross-replica guarantee.
    # This read repairs lost notifications and revalidates grants within 10s.
    schedule_poll()
    refresh(socket)
  end

  def handle_info(:threads_changed, socket), do: refresh(socket)

  defp refresh(socket) do
    case snapshot(socket) do
      {:ok, value} ->
        if value != socket.assigns.snapshot, do: push(socket, "snapshot", value)
        {:noreply, assign(socket, :snapshot, value)}

      _ ->
        {:stop, :normal, socket}
    end
  end

  defp snapshot(socket) do
    with {:ok, user} <- ThreadsSocket.authenticate(socket.assigns.bearer),
         true <- user.id == socket.assigns.app_user.id,
         %Account{} = account <- Accounts.get_account_by_handle(socket.assigns.account_handle),
         true <- account.id == socket.assigns.account_id,
         :ok <- Threads.authorize_reader(user, account),
         {:ok, value} <- Threads.snapshot(user, account, socket.assigns.target) do
      # Explicit allowlist: sockets carry invalidations and the running tool's
      # name, never conversation content such as tool arguments.
      {:ok, Map.take(value, [:revision, :agent_status, :activity])}
    else
      _ -> {:error, :not_found}
    end
  end

  # Tools the server doesn't accept, such as from a newer app, are left out
  # rather than refusing the join, which would also cost the app its live
  # updates. The inbox has no agent to call them.
  defp tools(:inbox, _params), do: []

  defp tools(_thread, params) do
    case Clients.validate(params["tools"]) do
      {:ok, tools} -> tools
      {:error, :invalid_tools} -> []
    end
  end

  defp target("inbox"), do: {:ok, :inbox}
  defp target(id), do: Ecto.UUID.cast(id)
  defp schedule_poll, do: Process.send_after(self(), :poll_snapshot, @poll_interval)
end
