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

  def terminate(_reason, state) do
    GRPC.Stub.disconnect(state.channel)
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end
end
