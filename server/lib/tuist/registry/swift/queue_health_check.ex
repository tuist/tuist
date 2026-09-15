defmodule Tuist.Registry.Swift.QueueHealthCheck do
  @moduledoc """
  Self-healing supervisor for the `:swift_registry_sync` +
  `:swift_registry_release` queues.

  Runs only on pods with `TUIST_MODE=swift_registry_sync`. Once a minute
  it looks at those queues and, when it can prove the local producer
  has wedged, calls `:init.stop/0`. Kubernetes restarts the pod, the
  producer supervisor comes back clean, and jobs resume in seconds.

  This exists because switching `swift_registry_sync` pods to
  `Oban.Notifiers.Isolated` reduces the surface area for the specific
  `LISTEN`-connection drop we've seen in production, but it does not
  cover every failure mode of the Oban producer supervision tree.
  `Oban.Plugins.Pruner` and `Oban.Plugins.Lifeline` kept ticking on a
  wedged pod, so a plugin-based liveness probe wouldn't have caught
  the incident. The narrow, provable heuristic below covers what those
  plugins couldn't.

  ## The heuristic

  On every tick we inspect the two queues we own. A queue is wedged
  when both of the following hold:

  * The pod has been up long enough to make idle vs. wedged
    distinguishable — `@grace_period`. Fresh pods that boot into an
    empty queue must not restart themselves.
  * There is at least one job whose `state` is `available` and whose
    `scheduled_at` (or `inserted_at` for jobs without a schedule) is
    older than `@stuck_after`, **and** no job on the same queue has
    reached `state = executing` since that job became available. Any
    successful pickup on the queue after the stuck job would prove the
    producer is healthy and the stuck job simply hasn't been picked up
    yet.

  Both thresholds are conservative on purpose: this restarts the pod
  and we want to be sure we're not thrashing on a legitimately slow
  batch. A stall that clears in a couple of minutes is invisible to
  us; a stall lasting `@grace_period + @stuck_after` (currently 15 +
  10 = 25 minutes worst case, before the check even fires) triggers a
  restart on the next tick.
  """

  use GenServer

  require Logger

  alias Tuist.Repo

  @default_check_interval :timer.minutes(1)
  @default_grace_period :timer.minutes(15)
  @default_stuck_after :timer.minutes(10)
  @default_queues ["swift_registry_sync", "swift_registry_release"]

  @doc """
  Starts the health check with an optional `:halt` override for tests
  that don't want the check to actually stop the BEAM.

  ```
  Tuist.Registry.Swift.QueueHealthCheck.start_link(
    halt: fn -> send(pid, :halted) end,
    now: fn -> ~U[2026-01-01 00:00:00Z] end,
    boot_at: ~U[2025-12-31 23:00:00Z]
  )
  ```
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    state = %{
      check_interval: Keyword.get(opts, :check_interval, @default_check_interval),
      grace_period: Keyword.get(opts, :grace_period, @default_grace_period),
      stuck_after: Keyword.get(opts, :stuck_after, @default_stuck_after),
      queues: Keyword.get(opts, :queues, @default_queues),
      halt: Keyword.get(opts, :halt, &default_halt/0),
      now: Keyword.get(opts, :now, &default_now/0),
      boot_at: Keyword.get(opts, :boot_at, default_now())
    }

    schedule_tick(state.check_interval)
    {:ok, state}
  end

  @impl true
  def handle_info(:check, state) do
    case wedged_queue(state) do
      {:wedged, queue, stuck_since} ->
        Logger.error(
          "swift_registry_sync queue #{inspect(queue)} appears wedged " <>
            "(oldest available job since #{inspect(stuck_since)}, no executing job since); " <>
            "halting the BEAM so kubernetes replaces the pod."
        )

        state.halt.()
        # In tests the halt callback is a no-op; we still schedule the
        # next tick so the process stays observable.
        schedule_tick(state.check_interval)
        {:noreply, state}

      :ok ->
        schedule_tick(state.check_interval)
        {:noreply, state}
    end
  end

  # Public so `Tuist.Application` can decide whether to start us at
  # supervisor init time, and so unit tests can call it without spinning
  # up the GenServer.
  @doc false
  def wedged_queue(state) do
    now = state.now.()

    if within_grace?(now, state.boot_at, state.grace_period) do
      :ok
    else
      state.queues
      |> Enum.reduce_while(:ok, fn queue, _acc ->
        case queue_status(queue, now, state.stuck_after) do
          {:stuck, stuck_since} -> {:halt, {:wedged, queue, stuck_since}}
          :ok -> {:cont, :ok}
        end
      end)
    end
  end

  # A queue is stuck when there's an available job older than
  # `stuck_after` AND no job has been attempted on that queue since
  # that job became available. Both facts come from the same table so
  # the check is one round trip.
  defp queue_status(queue, now, stuck_after) do
    stuck_threshold = DateTime.add(now, -div(stuck_after, 1000), :second)

    query = """
    SELECT stuck_since, last_attempt_at
    FROM (
      SELECT
        MIN(COALESCE(scheduled_at, inserted_at)) AS stuck_since
      FROM oban_jobs
      WHERE queue = $1
        AND state = 'available'
        AND COALESCE(scheduled_at, inserted_at) <= $2
    ) stuck,
    (
      SELECT MAX(attempted_at) AS last_attempt_at
      FROM oban_jobs
      WHERE queue = $1
        AND attempted_at IS NOT NULL
    ) attempted
    """

    case Repo.query(query, [queue, stuck_threshold]) do
      {:ok, %{rows: [[nil, _]]}} ->
        :ok

      {:ok, %{rows: [[stuck_since, nil]]}} ->
        {:stuck, stuck_since}

      {:ok, %{rows: [[stuck_since, last_attempt_at]]}} ->
        if DateTime.compare(last_attempt_at, stuck_since) == :lt do
          {:stuck, stuck_since}
        else
          :ok
        end

      {:error, error} ->
        # A DB error on the health check itself is a poor signal to
        # halt on. Log it and move on; another tick will retry.
        Logger.warning("QueueHealthCheck query failed: #{inspect(error)}")
        :ok
    end
  end

  defp within_grace?(now, boot_at, grace_period) do
    DateTime.diff(now, boot_at, :millisecond) < grace_period
  end

  defp schedule_tick(interval) do
    Process.send_after(self(), :check, interval)
  end

  defp default_halt do
    Logger.flush()
    :init.stop()
  end

  defp default_now, do: DateTime.utc_now()
end
