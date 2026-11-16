defmodule Tuist.Agents.Runner do
  @moduledoc """
  Hosts durable agent sessions on this node: claims sessions that want a host
  (`Tuist.Agents.Lease`) while the node has room, starts each through the
  module of its kind (`Tuist.Agents.Kind`), renews their leases, and hands
  them back.

  Admission is by capacity, not by a queue: the runner claims only while it
  hosts fewer than `:max_sessions` and the VM uses less than `:memory_ratio`
  of `:memory_limit_bytes`. Runners are woken over PubSub when a session
  wants a host (`Tuist.Agents.Lease.wake/1`), and poll as a backstop.

  The runner never waits on a session's process, so renewing every lease on
  the node takes one query however slow a session is. A session leaves its
  host in one of four ways:

    * It went idle. After each renewal the runner asks it to stop if idle,
      with the want count the renewal read; a session that stops replies, and
      is released as no longer wanted unless a want arrived since.
    * Its process ended. It is released as still wanted, and a host resumes
      it from its journal. One that ended with `{:shutdown, :unavailable}` could
      not reach its session store or the database; it is claimable again only after
      `:store_retry_ms`, so an outage is not retried at the pace of the poll.
    * Its lease was lost on renewal. The runner asks it to drain and forgets
      it without releasing it: another host already holds it, and the store
      fences its writes.
    * The node stops, as on a deploy. Every session is asked to drain, which
      leaves sandbox commands running; the runner waits up to `:drain_ms` for
      them to exit and releases them as wanted, so a host on the new release
      claims them at once and resumes them.
  """

  use GenServer

  alias Tuist.Agents.Kind
  alias Tuist.Agents.Lease

  require Logger

  @renew_ms 5_000
  @poll_ms 2_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @doc "The sessions this runner hosts, by id."
  def hosted(server \\ __MODULE__), do: GenServer.call(server, :hosted)

  @impl true
  def init(opts) do
    # Shutdown must reach terminate/2 so the node drains its sessions.
    Process.flag(:trap_exit, true)

    state = %{
      host: Keyword.get_lazy(opts, :host, fn -> "#{node()}/#{System.unique_integer([:positive])}" end),
      kinds: Keyword.get_lazy(opts, :kinds, fn -> Application.get_env(:tuist, __MODULE__, [])[:kinds] || %{} end),
      max_sessions: Keyword.get(opts, :max_sessions, 50),
      memory_limit: Keyword.get(opts, :memory_limit_bytes),
      memory_ratio: Keyword.get(opts, :memory_ratio, 0.7),
      memory: Keyword.get(opts, :memory, fn -> :erlang.memory(:total) end),
      drain_ms: Keyword.get(opts, :drain_ms, 25_000),
      store_retry_ms: Keyword.get(opts, :store_retry_ms, 30_000),
      sessions: %{}
    }

    Phoenix.PubSub.subscribe(Tuist.PubSub, Lease.hosts_topic())

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
      # Leases outlive a failed renewal by most of their TTL; the next tick
      # tries again, and a session whose lease lapses meanwhile is fenced.
      :error -> {:noreply, state}
    end
  end

  def handle_info({Kind, :idle, pid, {id, epoch, seq}}, state) do
    case state.sessions do
      %{^id => %{pid: ^pid, epoch: ^epoch} = session} ->
        Process.demonitor(session.ref, [:flush])
        # A release that fails leaves the lease to lapse, after which a host
        # claims the session and finds it idle.
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

        delay_ms = if reason == {:shutdown, :unavailable}, do: state.store_retry_ms, else: 0
        safely(fn -> Lease.release(id, session.epoch, delay_ms: delay_ms) end)
        {:noreply, forget(state, id)}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp renewed(state, held) do
    Enum.reduce(state.sessions, state, fn {id, session}, state ->
      case Map.fetch(held, {id, session.epoch}) do
        {:ok, seq} ->
          # The token is the want count read before the session decides.
          session.kind.stop_if_idle(session.pid, self(), {id, session.epoch, seq})
          state

        :error ->
          # Another host holds it now; stopping it must not release it.
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
    await_down(Map.new(state.sessions, fn {_id, session} -> {session.ref, session} end), state.drain_ms)

    # Released even if a session did not exit in time: its writes are fenced
    # by the next host's claim.
    Enum.each(state.sessions, fn {id, session} -> safely(fn -> Lease.release(id, session.epoch) end) end)
  end

  defp await_down(refs, _left) when map_size(refs) == 0, do: :ok

  defp await_down(refs, left) do
    started = System.monotonic_time(:millisecond)

    receive do
      {:DOWN, ref, :process, _pid, _reason} when is_map_key(refs, ref) ->
        await_down(Map.delete(refs, ref), max(left - (System.monotonic_time(:millisecond) - started), 0))
    after
      left -> :ok
    end
  end

  # A failed claim is retried by the next poll.
  defp claim(state) do
    room = room(state)

    case safely(fn -> Lease.claim(state.host, room) end) do
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
        # Wanted again by the next host to poll, which may have what this
        # one lacked; a session that can never start is the kind's to end.
        Logger.warning("agent session #{id} failed to start: #{inspect(reason, limit: 5)}")
        safely(fn -> Lease.release(id, epoch) end)
        state
    end
  end

  # The runner is a permanent child of the application's supervisor: a
  # database error, as during a failover, must not crash it, or a few in a
  # row would take the whole application down. Every lease operation is
  # retried by a later tick or covered by the lease's TTL.
  defp safely(fun) do
    {:ok, fun.()}
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      Logger.warning("agent runner database call failed: #{Exception.message(error)}")
      :error
  end

  defp forget(state, id), do: %{state | sessions: Map.delete(state.sessions, id)}
end
