defmodule TuistWeb.RunnerShellAgentWebSock do
  @moduledoc false

  @behaviour WebSock

  alias Tuist.Runners.InteractiveSessions
  alias Tuist.Runners.InteractiveShellBroker

  @impl WebSock
  def init(%{session: session}) do
    :ok = InteractiveShellBroker.subscribe_runner(session.id)

    case InteractiveSessions.mark_shell_ready(session) do
      {:ok, ready_session} ->
        :ok = InteractiveShellBroker.broadcast_to_client(ready_session.id, :runner_connected)
        {:ok, %{session: ready_session}}

      {:error, reason} ->
        {:stop, {:session_ready_failed, reason}, {1011, "session unavailable"}, %{}}
    end
  end

  @impl WebSock
  def handle_in({payload, [opcode: :binary]}, %{session: session} = state) do
    :ok = InteractiveShellBroker.broadcast_to_client(session.id, {:stdout, payload})
    {:ok, state}
  end

  def handle_in({payload, [opcode: :text]}, %{session: session} = state) do
    case Jason.decode(payload) do
      {:ok, %{"type" => "exit", "status" => status}} ->
        :ok = InteractiveShellBroker.broadcast_to_client(session.id, {:runner_exit, status})

      _ ->
        :ok
    end

    {:ok, state}
  end

  @impl WebSock
  def handle_info({:runner_shell, {:stdin, payload}}, state) when is_binary(payload) do
    {:push, {:binary, payload}, state}
  end

  def handle_info({:runner_shell, {:resize, columns, rows}}, state) do
    {:push, {:text, Jason.encode!(%{type: "resize", columns: columns, rows: rows})}, state}
  end

  def handle_info({:runner_shell, :client_connected}, state) do
    {:push, {:text, Jason.encode!(%{type: "client", status: "connected"})}, state}
  end

  def handle_info({:runner_shell, :client_disconnected}, state) do
    {:push, {:text, Jason.encode!(%{type: "client", status: "disconnected"})}, state}
  end

  def handle_info(_message, state), do: {:ok, state}

  @impl WebSock
  def terminate(_reason, %{session: session}) do
    :ok = InteractiveShellBroker.broadcast_to_client(session.id, :runner_disconnected)
    :ok
  end

  def terminate(_reason, _state), do: :ok
end
