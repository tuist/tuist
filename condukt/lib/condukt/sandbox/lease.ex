defmodule Condukt.Sandbox.Lease do
  @moduledoc """
  Keeps a session's sandbox leased while the session needs it.

  A session whose sandbox implements `c:Condukt.Sandbox.activity/2` starts
  one lease process, linked to it. The session tells the lease when a turn
  starts and ends; the lease calls the sandbox, so a slow call, such as one
  that resumes a paused machine, never holds up the session:

    * `:active` once when a turn starts, and again every `:lease_interval`
      milliseconds (default `60_000`) while the turn runs or is parked;
    * `:idle` once the session has had no turn for `:idle_after`
      milliseconds (default `1_000`), so a queued turn that starts right
      after another does not give the sandbox up in between.

  A session given a sandbox that is already leased, as a sub-agent is its
  parent's, holds the same lease instead of starting another: the sandbox is
  active while any of its sessions has a turn, and idle once none has. A
  holder that exits counts as idle.

  The lease does not call `:idle` when the session that started it exits. A
  session that crashed or was drained for another node (see
  `Condukt.Sessions.stop/2`) leaves its sandbox to whoever takes over, and
  the sandbox's own expiry, such as a pod heartbeat or a residency's grace,
  covers a session that never comes back.
  """

  use GenServer

  alias Condukt.Sandbox

  require Logger

  @default_interval 60_000
  @default_idle_after 1_000

  @doc false
  # Starts the lease when the sandbox takes activity, and returns the sandbox
  # with it, so tools and the session reach it through the handle. A sandbox
  # that is already leased keeps its lease, which the session then holds too.
  def start(%Sandbox{lease: pid} = sandbox, _opts) when is_pid(pid) do
    if Process.alive?(pid), do: sandbox, else: start(%{sandbox | lease: nil}, [])
  end

  def start(%Sandbox{} = sandbox, opts) do
    if Sandbox.supports?(sandbox, :activity, 2) do
      {:ok, pid} = GenServer.start_link(__MODULE__, {sandbox, opts})
      %{sandbox | lease: pid}
    else
      sandbox
    end
  end

  @doc false
  # The calling session has a turn.
  def active(%Sandbox{lease: pid}) when is_pid(pid), do: GenServer.cast(pid, {:active, self()})
  def active(_sandbox), do: :ok

  @doc false
  # The calling session has no turn.
  def idle(%Sandbox{lease: pid}) when is_pid(pid), do: GenServer.cast(pid, {:idle, self()})
  def idle(_sandbox), do: :ok

  @impl true
  def init({sandbox, opts}) do
    {:ok,
     %{
       sandbox: sandbox,
       interval: Keyword.get(opts, :lease_interval) || @default_interval,
       idle_after: Keyword.get(opts, :idle_after) || @default_idle_after,
       held: false,
       holders: %{},
       renew: nil,
       release: nil
     }}
  end

  @impl true
  def handle_cast({:active, holder}, state) do
    state = cancel(state, :release)

    holders =
      if Map.has_key?(state.holders, holder),
        do: state.holders,
        else: Map.put(state.holders, holder, Process.monitor(holder))

    state = %{state | holders: holders}

    if state.held do
      {:noreply, state}
    else
      call(state, :active)
      {:noreply, %{state | held: true, renew: Process.send_after(self(), :renew, state.interval)}}
    end
  end

  def handle_cast({:idle, holder}, state), do: {:noreply, drop(state, holder)}

  @impl true
  def handle_info(:renew, %{held: true} = state) do
    call(state, :active)
    {:noreply, %{state | renew: Process.send_after(self(), :renew, state.interval)}}
  end

  def handle_info(:release, %{held: true, holders: holders} = state) when holders == %{} do
    call(state, :idle)
    {:noreply, %{cancel(state, :renew) | held: false, release: nil}}
  end

  def handle_info({:DOWN, _ref, :process, holder, _reason}, state), do: {:noreply, drop(state, holder)}

  def handle_info(_message, state), do: {:noreply, state}

  # The holder has no turn. Once no holder has one, the sandbox is given up
  # after `:idle_after`.
  defp drop(state, holder) do
    {monitor, holders} = Map.pop(state.holders, holder)
    if monitor, do: Process.demonitor(monitor, [:flush])
    state = %{state | holders: holders}

    if state.held and holders == %{} and state.release == nil,
      do: %{state | release: Process.send_after(self(), :release, state.idle_after)},
      else: state
  end

  defp cancel(state, timer) do
    case Map.fetch!(state, timer) do
      nil -> state
      ref -> Process.cancel_timer(ref) && Map.put(state, timer, nil)
    end
  end

  defp call(state, activity) do
    case Sandbox.activity(state.sandbox, activity) do
      :ok -> :ok
      other -> Logger.warning("sandbox #{activity} failed: #{inspect(other)}")
    end
  rescue
    error -> Logger.warning("sandbox #{activity} raised: #{Exception.message(error)}")
  end
end
