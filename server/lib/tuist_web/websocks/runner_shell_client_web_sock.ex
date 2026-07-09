defmodule TuistWeb.RunnerShellClientWebSock do
  @moduledoc false

  @behaviour WebSock

  alias Tuist.Runners.InteractiveSessions
  alias Tuist.Runners.InteractiveShellBroker

  @impl WebSock
  def init(%{session: session}) do
    connection_id = Ecto.UUID.generate()
    :ok = InteractiveShellBroker.subscribe_client(session.id)

    case InteractiveSessions.mark_active(session, connection_id) do
      {:ok, active_session} ->
        :ok = InteractiveShellBroker.broadcast_to_runner(active_session.id, :client_connected)

        status =
          if session.state in [:ready, :active] do
            "connected"
          else
            "waiting"
          end

        state = %{session: active_session, connection_id: connection_id}
        {:push, {:text, Jason.encode!(%{type: "status", status: status})}, state}

      {:error, reason} ->
        {:stop, {:session_activate_failed, reason}, {1011, "session unavailable"}, %{}}
    end
  end

  @impl WebSock
  def handle_in({payload, [opcode: :binary]}, %{session: session} = state) do
    :ok = InteractiveShellBroker.broadcast_to_runner(session.id, {:stdin, payload})
    {:ok, state}
  end

  def handle_in({payload, [opcode: :text]}, %{session: session} = state) do
    case Jason.decode(payload) do
      {:ok, %{"type" => "resize", "columns" => columns, "rows" => rows}}
      when is_integer(columns) and is_integer(rows) and columns > 0 and rows > 0 ->
        :ok = InteractiveShellBroker.broadcast_to_runner(session.id, {:resize, columns, rows})

      {:ok, %{"type" => "close"}} ->
        :ok = InteractiveShellBroker.broadcast_to_runner(session.id, :client_disconnected)

      _ ->
        :ok
    end

    {:ok, state}
  end

  @impl WebSock
  def handle_info({:runner_shell, {:stdout, payload}}, state) when is_binary(payload) do
    {:push, {:binary, payload}, state}
  end

  def handle_info({:runner_shell, :runner_connected}, state) do
    {:push, {:text, Jason.encode!(%{type: "status", status: "connected"})}, state}
  end

  def handle_info({:runner_shell, :runner_disconnected}, state) do
    {:push, {:text, Jason.encode!(%{type: "status", status: "waiting"})}, state}
  end

  def handle_info({:runner_shell, {:runner_exit, status}}, state) do
    {:push, {:text, Jason.encode!(%{type: "exit", status: status})}, state}
  end

  def handle_info(_message, state), do: {:ok, state}

  @impl WebSock
  def terminate(_reason, %{session: session, connection_id: connection_id}) do
    _ = InteractiveSessions.schedule_disconnect_close(session, connection_id)
    :ok = InteractiveShellBroker.broadcast_to_runner(session.id, :client_disconnected)
    :ok
  end

  def terminate(_reason, _state), do: :ok
end
