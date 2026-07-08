defmodule TuistWeb.RunnerVNCWebSock do
  @moduledoc false

  @behaviour WebSock

  alias Tuist.Runners.InteractiveSessions

  @connect_timeout_ms 5_000

  @impl WebSock
  def init(%{session: session}) do
    connection_id = Ecto.UUID.generate()

    case :gen_tcp.connect(
           String.to_charlist(session.relay_host),
           session.relay_port,
           [
             :binary,
             active: true,
             packet: :raw
           ],
           @connect_timeout_ms
         ) do
      {:ok, socket} ->
        case InteractiveSessions.mark_active(session, connection_id) do
          {:ok, active_session} ->
            {:ok, %{socket: socket, session: active_session, connection_id: connection_id}}

          {:error, reason} ->
            :gen_tcp.close(socket)
            {:stop, {:session_activate_failed, reason}, {1011, "session unavailable"}, %{}}
        end

      {:error, reason} ->
        {:stop, {:relay_connect_failed, reason}, {1011, "relay unavailable"}, %{}}
    end
  end

  @impl WebSock
  def handle_in({payload, [opcode: :binary]}, %{socket: socket} = state) do
    case :gen_tcp.send(socket, payload) do
      :ok -> {:ok, state}
      {:error, reason} -> {:stop, {:tcp_send_failed, reason}, state}
    end
  end

  def handle_in({_payload, [opcode: :text]}, state), do: {:ok, state}

  @impl WebSock
  def handle_info({:tcp, socket, data}, %{socket: socket} = state) do
    {:push, {:binary, data}, state}
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state), do: {:stop, :normal, state}
  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = state), do: {:stop, {:tcp_error, reason}, state}
  def handle_info(_message, state), do: {:ok, state}

  @impl WebSock
  def terminate(_reason, %{socket: socket, session: session, connection_id: connection_id}) do
    :gen_tcp.close(socket)
    _ = InteractiveSessions.schedule_disconnect_close(session, connection_id)
    :ok
  end

  def terminate(_reason, _state), do: :ok
end
