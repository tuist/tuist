defmodule TuistEx.Cache.Reapi.Channel do
  @moduledoc false
  use GenServer

  def child_spec(options) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}, restart: :temporary}
  end

  def start_link(options), do: GenServer.start_link(__MODULE__, options, timeout: 6_000)

  def init({address, options, owner}) do
    monitor = Process.monitor(owner)

    case GRPC.Stub.connect(address, options) do
      {:ok, channel} -> {:ok, %{channel: channel, monitor: monitor}}
      {:error, reason} -> {:stop, reason}
    end
  end

  def handle_call(:channel, _from, state), do: {:reply, state.channel, state}

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{monitor: ref} = state),
    do: {:stop, :normal, state}

  def handle_info(_message, state), do: {:noreply, state}

  # grpc answers a disconnect before its connection process closes the socket,
  # so wait for that process: a closed session must hold no connection that
  # could keep buffering an abandoned stream. A TLS close can wait on the peer,
  # so one that does not finish promptly is ended.
  def terminate(_reason, state) do
    connection = state.channel.adapter_payload.conn_pid
    monitor = Process.monitor(connection)
    GRPC.Stub.disconnect(state.channel)

    receive do
      {:DOWN, ^monitor, :process, _pid, _reason} -> :ok
    after
      1_000 -> Process.exit(connection, :kill)
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end
end
