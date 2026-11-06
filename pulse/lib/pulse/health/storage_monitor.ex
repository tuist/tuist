defmodule Pulse.Health.StorageMonitor do
  @moduledoc """
  Periodically probes the object store so readiness can be answered from memory.

  The probe lists a well-known, normally empty prefix. Unlike a read of a
  missing key, a listing fails when the bucket does not exist, so a
  misconfigured bucket cannot pass for healthy. Until the first probe
  finishes the status is `{:error, :not_probed}`.

  Successful object-store requests the node made since the previous probe
  already prove the bucket reachable, so the default probe skips its LIST
  (a billed Class A request) while ingest, queries or maintenance are
  talking to the store; an idle or failing node still lists.

  At most one probe is ever in flight. The probe runs in a process linked to
  the monitor, so it cannot outlive it, and the monitor traps exits so a
  crashing probe is reported instead of taking the monitor down. When a probe
  passes its deadline the status turns to `{:error, :probe_timeout}` but the
  probe is *not* abandoned: the object store call blocks a dirty native
  scheduler and cannot be cancelled by killing its caller, so the next probe
  waits until the stalled one returns (bounded by the object store client's own
  timeouts). A late result replaces the timeout status.

  Options (all but `:config` also read from `config :pulse, Pulse.Health`):

    * `:config` — object store config map (required).
    * `:interval_ms` — time between probes, default 15 seconds.
    * `:timeout_ms` — per-probe deadline, default 5 seconds.
    * `:probe` — `(config -> :ok | {:error, term})` override, for tests.
  """

  use Pulse.Runtime.GenServer

  alias Pulse.ObjectStore
  alias Pulse.Runtime
  alias Pulse.Runtime.GenServer

  @probe_prefix ".pulse/"
  @default_interval_ms 15_000
  @default_timeout_ms 5_000

  @spec start_link(keyword()) :: Elixir.GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @doc "The result of the most recent probe."
  @spec status(Elixir.GenServer.server()) :: :ok | {:error, term()}
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  catch
    :exit, _ -> {:error, :monitor_not_running}
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    env = Runtime.get_env(:pulse, Pulse.Health, [])

    state = %{
      config: Keyword.fetch!(opts, :config),
      interval_ms: Keyword.get(opts, :interval_ms, Keyword.get(env, :probe_interval_ms, @default_interval_ms)),
      timeout_ms: Keyword.get(opts, :timeout_ms, Keyword.get(env, :probe_timeout_ms, @default_timeout_ms)),
      probe: Keyword.get(opts, :probe, &default_probe/1),
      # Object-store successes counted when the last probe started; nil with
      # an explicit probe, which always runs.
      successes: if(!Keyword.has_key?(opts, :probe), do: -1),
      status: {:error, :not_probed},
      task: nil
    }

    {:ok, state, {:continue, :probe}}
  end

  @impl true
  def handle_continue(:probe, state), do: {:noreply, start_probe(state)}

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state.status, state}

  @impl true
  def handle_info(:probe, %{task: nil} = state), do: {:noreply, start_probe(state)}
  def handle_info(:probe, state), do: {:noreply, state}

  def handle_info({:probe_result, tag, result}, %{task: %{tag: tag}} = state) do
    {:noreply, finish_probe(state, normalize(result))}
  end

  def handle_info({:EXIT, pid, reason}, %{task: %{pid: pid}} = state) do
    {:noreply, finish_probe(state, {:error, {:probe_crashed, reason}})}
  end

  def handle_info({:probe_timeout, tag}, %{task: %{tag: tag}} = state) do
    {:noreply, %{state | status: {:error, :probe_timeout}}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # A link alone does not stop the probe on a normal shutdown (a `:normal`
  # exit signal is ignored), so end it explicitly. Abrupt monitor death is
  # covered by the link.
  @impl true
  def terminate(_reason, %{task: %{pid: pid}}), do: Process.exit(pid, :kill)
  def terminate(_reason, _state), do: :ok

  defp start_probe(%{successes: seen} = state) when is_integer(seen) do
    case Pulse.SelfMetrics.object_successes() do
      count when seen >= 0 and count > seen ->
        Process.send_after(self(), :probe, state.interval_ms)
        %{state | status: :ok, successes: count}

      _count ->
        run_probe(state)
    end
  end

  defp start_probe(state), do: run_probe(state)

  defp run_probe(state) do
    parent = self()
    tag = make_ref()
    config = state.config
    probe = state.probe
    # The probe records object-store metrics; run it in this monitor's runtime.
    pid = spawn_link(Runtime.capture(fn -> send(parent, {:probe_result, tag, probe.(config)}) end))
    timer = Process.send_after(self(), {:probe_timeout, tag}, state.timeout_ms)
    %{state | task: %{pid: pid, tag: tag, timer: timer}}
  end

  defp finish_probe(%{task: %{timer: timer}} = state, status) do
    Process.cancel_timer(timer)
    Process.send_after(self(), :probe, state.interval_ms)
    # Only requests after this probe's own LIST stand in for the next one.
    successes = if is_integer(state.successes), do: Pulse.SelfMetrics.object_successes()
    %{state | status: status, task: nil, successes: successes}
  end

  defp normalize(:ok), do: :ok
  defp normalize({:ok, _keys}), do: :ok
  defp normalize({:error, reason}), do: {:error, reason}
  defp normalize(other), do: {:error, {:unexpected_probe_result, other}}

  defp default_probe(config), do: ObjectStore.list(config, @probe_prefix)
end
