defmodule TuistWeb.Orchard.WatchSocket do
  @moduledoc """
  WebSock handler for `/api/orchard/v1/rpc/watch`. One process per
  connected worker; subscribes to that worker's PubSub topic and
  forwards every published `WatchInstruction` to the client as a
  JSON binary frame.

  Cirrus's worker daemon expects pings every ~30s; we send them
  ourselves rather than relying on Bandit's keepalive so the protocol
  stays compatible with workers that have read deadlines.
  """
  @behaviour WebSock

  alias Tuist.Orchard.WorkerNotifier

  require Logger

  @ping_interval 30_000

  @impl WebSock
  def init(%{worker_name: worker_name}) do
    :ok = WorkerNotifier.subscribe(worker_name)
    Process.send_after(self(), :ping, @ping_interval)
    {:ok, %{worker_name: worker_name}}
  end

  @impl WebSock
  def handle_info({:watch_instruction, instruction}, state) do
    case Jason.encode(instruction) do
      {:ok, payload} ->
        {:push, {:binary, payload}, state}

      {:error, reason} ->
        Logger.warning("WatchSocket: failed to encode instruction: #{inspect(reason)}")
        {:ok, state}
    end
  end

  @impl WebSock
  def handle_info(:ping, state) do
    Process.send_after(self(), :ping, @ping_interval)
    {:push, {:ping, ""}, state}
  end

  @impl WebSock
  def handle_info(_msg, state), do: {:ok, state}

  @impl WebSock
  def handle_in({_payload, _opts}, state) do
    # Workers don't send messages on this channel — it's controller →
    # worker only. Ignore anything we receive.
    {:ok, state}
  end

  @impl WebSock
  def handle_control(_msg, state), do: {:ok, state}

  @impl WebSock
  def terminate(_reason, %{worker_name: worker_name}) do
    WorkerNotifier.unsubscribe(worker_name)
    :ok
  end

  def terminate(_reason, _state), do: :ok
end
