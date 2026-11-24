defmodule LuftServer.Agents.Runner do
  @moduledoc """
  Hosts durable sessions up to a count and optional memory limit. Claims and
  renewals are batched; idle checks never wait on a session. Lost leases drain
  without release; shutdown drains with a deadline and hands leases back.
  Database outages are retried by polling and bounded by the lease TTL.
  """
  use GenServer

  alias LuftServer.Agents.Kind
  alias LuftServer.Agents.Lease

  require Logger

  @renew_ms 5_000
  @poll_ms 2_000

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def hosted(server \\ __MODULE__), do: GenServer.call(server, :hosted)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    state = %{
      host:
        Keyword.get_lazy(opts, :host, fn -> "#{node()}/#{System.unique_integer([:positive])}" end),
      kinds:
        Keyword.get_lazy(opts, :kinds, fn ->
          Application.get_env(:luft_server, __MODULE__, [])[:kinds] || %{}
        end),
      max_sessions:
        Keyword.get_lazy(opts, :max_sessions, fn ->
          if opts[:memory_limit_bytes], do: 500, else: 50
        end),
      memory_limit: Keyword.get(opts, :memory_limit_bytes),
      memory_ratio: Keyword.get(opts, :memory_ratio, 0.7),
      memory: Keyword.get(opts, :memory, fn -> :erlang.memory(:total) end),
      drain_ms: Keyword.get(opts, :drain_ms, 25_000),
      retry_ms: Keyword.get(opts, :retry_ms, 30_000),
      sessions: %{}
    }

    Phoenix.PubSub.subscribe(LuftServer.PubSub, Lease.hosts_topic())
    send(self(), :claim)
    Process.send_after(self(), :renew, @renew_ms)
    {:ok, state}
  end

  @impl true
  def handle_call(:hosted, _from, state), do: {:reply, Map.keys(state.sessions), state}

  @impl true
  def handle_info(:claim, state) do
    Process.send_after(self(), :claim, @poll_ms)
    {:noreply, claim(state)}
  end

  def handle_info({Lease, :claimable}, state), do: {:noreply, claim(state)}

  def handle_info(:renew, state) do
    Process.send_after(self(), :renew, @renew_ms)
    leases = Enum.map(state.sessions, fn {id, session} -> {id, session.epoch} end)

    case safely(fn -> Lease.renew(state.host, leases) end) do
      {:ok, held} -> {:noreply, renewed(state, held)}
      :error -> {:noreply, state}
    end
  end

  def handle_info({Kind, :idle, pid, {id, epoch, seq}}, state) do
    case state.sessions do
      %{^id => %{pid: ^pid, epoch: ^epoch} = session} ->
        Process.demonitor(session.ref, [:flush])
        safely(fn -> Lease.release(id, epoch, wanted: false, seen: seq) end)
        {:noreply, forget(state, id)}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Enum.find(state.sessions, fn {_id, session} -> session.ref == ref end) do
      {id, session} ->
        if reason not in [:normal, :shutdown] and not match?({:shutdown, _}, reason),
          do: Logger.warning("agent session #{id} exited: #{inspect(reason, limit: 5)}")

        delay_ms = if handed_on?(reason), do: 0, else: state.retry_ms
        safely(fn -> Lease.release(id, session.epoch, delay_ms: delay_ms) end)
        {:noreply, forget(state, id)}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp handed_on?(reason) when reason in [:normal, :shutdown], do: true
  defp handed_on?({:shutdown, :unavailable}), do: false
  defp handed_on?({:shutdown, _reason}), do: true
  defp handed_on?(_reason), do: false

  defp renewed(state, held) do
    Enum.reduce(state.sessions, state, fn {id, session}, state ->
      case Map.fetch(held, {id, session.epoch}) do
        {:ok, seq} ->
          session.kind.stop_if_idle(session.pid, self(), {id, session.epoch, seq})
          state

        :error ->
          Logger.warning("agent session #{id} lost its lease, draining it")
          Process.demonitor(session.ref, [:flush])
          session.kind.drain(session.pid)
          forget(state, id)
      end
    end)
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.sessions, fn {_id, session} -> session.kind.drain(session.pid) end)

    await_down(
      Map.new(state.sessions, fn {_id, session} -> {session.ref, session} end),
      state.drain_ms
    )

    # Even a process that missed the deadline is fenced by the next claim.
    Enum.each(state.sessions, fn {id, session} ->
      safely(fn -> Lease.release(id, session.epoch) end)
    end)
  end

  defp await_down(refs, _left) when map_size(refs) == 0, do: :ok

  defp await_down(refs, left) do
    started = System.monotonic_time(:millisecond)

    receive do
      {:DOWN, ref, :process, _pid, _reason} when is_map_key(refs, ref) ->
        await_down(
          Map.delete(refs, ref),
          max(left - (System.monotonic_time(:millisecond) - started), 0)
        )
    after
      left -> :ok
    end
  end

  defp claim(state) do
    case safely(fn -> Lease.claim(state.host, room(state)) end) do
      {:ok, claimed} -> Enum.reduce(claimed, state, &host/2)
      :error -> state
    end
  end

  defp room(state) do
    under_memory? =
      is_nil(state.memory_limit) or state.memory.() < state.memory_limit * state.memory_ratio

    if under_memory?, do: max(state.max_sessions - map_size(state.sessions), 0), else: 0
  end

  defp host(%{id: id, kind: kind, epoch: epoch}, state) do
    # A poll can reclaim an expired lease before renewal notices the old host.
    state =
      case state.sessions do
        %{^id => old} ->
          Process.demonitor(old.ref, [:flush])
          old.kind.drain(old.pid)
          forget(state, id)

        _ ->
          state
      end

    with {:ok, module} <- Map.fetch(state.kinds, kind),
         {:ok, pid} <- module.start(id, epoch) do
      session = %{epoch: epoch, kind: module, pid: pid, ref: Process.monitor(pid)}
      %{state | sessions: Map.put(state.sessions, id, session)}
    else
      :error ->
        Logger.error("agent session #{id} has unknown kind #{inspect(kind)}")
        safely(fn -> Lease.release(id, epoch, wanted: false) end)
        state

      {:error, reason} ->
        Logger.warning("agent session #{id} failed to start: #{inspect(reason, limit: 5)}")
        safely(fn -> Lease.release(id, epoch, delay_ms: state.retry_ms) end)
        state
    end
  end

  defp safely(fun) do
    {:ok, fun.()}
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      Logger.warning("agent runner database call failed: #{Exception.message(error)}")
      :error
  end

  defp forget(state, id), do: %{state | sessions: Map.delete(state.sessions, id)}
end
