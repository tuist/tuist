defmodule Tuist.Runners.Watcher do
  @moduledoc """
  Drives the runner-pool reconciler from Pod-event-driven triggers
  rather than a periodic cron.

  Architecture:

      Tuist.Runners.Watcher (this GenServer)
        ├─ on init: reconcile once + spawn watch task
        ├─ watch task streams Pod events from the API server
        │  (long-lived HTTP), each event sent to this process
        ├─ event handler: throttle + invoke Reconciler.reconcile/0
        └─ on watch end / error: backoff + reconnect

  Why event-driven over cron: the only thing the reconciler does
  is fill gaps between observed and desired warm-pool size. A
  Pod terminates (job finished) → gap appears → reconcile. K8s
  emits that exact transition as a watch event the moment it
  happens; polling once a minute means up to ~60 s of zero
  warm-pool capacity in the worst case. Watch reduces that to
  ~hundreds of milliseconds.

  Throttling: a flurry of events (e.g. a node draining 3 Pods at
  once) shouldn't fire 3 sequential reconciles. We coalesce —
  any event during an in-flight reconcile schedules one followup,
  so the next reconcile starts ~5 s after the previous one
  finishes. Idempotent reconcile makes this safe even if we miss
  an event entirely.

  Reconnection: K8s API servers close idle watches at their own
  cadence (~5–10 min). The streaming task exits cleanly when the
  upstream closes; we re-spawn after a short backoff. On a long
  outage we stop spamming retries (cap at 30 s).

  Initial reconcile: every Watcher boot calls reconcile/0 once
  before opening the watch. That covers the gap between the BEAM
  going down and coming back — any Pod terminations during that
  window get noticed even though the watch missed them.
  """

  use GenServer

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client
  alias Tuist.Runners.PodSpec
  alias Tuist.Runners.Reconciler

  require Logger

  # Minimum interval between reconcile invocations. Coalesces
  # bursts of events.
  @reconcile_throttle_ms 5_000

  # Reconnect backoff window.
  @backoff_min_ms 1_000
  @backoff_max_ms 30_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Force an immediate reconcile from outside (e.g. an ops command
  or a controller test). Throttled the same way watch-driven
  reconciles are.
  """
  def kick do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, :reconcile)
      :ok
    else
      {:error, :not_running}
    end
  end

  @impl GenServer
  def init(_opts) do
    state = %{
      task: nil,
      backoff: @backoff_min_ms,
      last_reconcile: 0,
      pending: false
    }

    if Environment.runners_enabled?() do
      send(self(), :start)
      {:ok, state}
    else
      Logger.info("runners: watcher disabled (TUIST_RUNNER_* env vars not set)")
      :ignore
    end
  end

  @impl GenServer
  def handle_info(:start, state) do
    # Initial reconcile to repopulate the warm pool from whatever
    # state the cluster is in. Catches Pod terminations that
    # happened while the BEAM was down.
    Reconciler.reconcile()
    {:noreply, spawn_watch(%{state | last_reconcile: now_ms()})}
  end

  def handle_info({:watch_event, event}, state) do
    if relevant?(event) do
      {:noreply, maybe_reconcile(state)}
    else
      {:noreply, state}
    end
  end

  def handle_info(:reconcile_throttled, state) do
    if state.pending do
      Reconciler.reconcile()
      {:noreply, %{state | last_reconcile: now_ms(), pending: false}}
    else
      {:noreply, state}
    end
  end

  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    # Watch task returned. Result is :ok (clean stream end) or
    # {:error, reason}. Schedule reconnect with backoff either
    # way — clean ends are normal (server idle timeout) and not
    # an error.
    Process.demonitor(ref, [:flush])
    backoff = compute_backoff(state.backoff, result)

    Logger.info("runners: watch ended; reconnecting",
      reason: inspect(result),
      backoff_ms: backoff
    )

    Process.send_after(self(), :reconnect, backoff)
    {:noreply, %{state | task: nil, backoff: backoff}}
  end

  def handle_info({:DOWN, ref, :process, _, reason}, %{task: %Task{ref: ref}} = state) do
    # Task crashed (exit signal). Treat same as error result.
    backoff = min(state.backoff * 2, @backoff_max_ms)

    Logger.warning("runners: watch task crashed",
      reason: inspect(reason),
      backoff_ms: backoff
    )

    Process.send_after(self(), :reconnect, backoff)
    {:noreply, %{state | task: nil, backoff: backoff}}
  end

  def handle_info(:reconnect, state) do
    # Reconcile on reconnect — same rationale as initial: covers
    # any gap created during the backoff.
    Reconciler.reconcile()
    {:noreply, spawn_watch(%{state | last_reconcile: now_ms()})}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def handle_cast(:reconcile, state), do: {:noreply, maybe_reconcile(state)}

  defp spawn_watch(state) do
    parent = self()

    task =
      Task.async(fn ->
        Client.stream_watch_pods(PodSpec.namespace(), PodSpec.selector_label(), fn event ->
          send(parent, {:watch_event, event})
        end)
      end)

    %{state | task: task}
  end

  # Decide whether an event meaningfully affects the warm-pool
  # count. ADDED events are usually our own creates — no
  # reconcile needed (we already accounted for it). MODIFIED to
  # a terminal phase or DELETED reduces the alive count;
  # reconcile to refill.
  defp relevant?(%{"type" => "DELETED"}), do: true

  defp relevant?(%{"type" => "MODIFIED", "object" => %{"status" => %{"phase" => phase}}})
       when phase in ["Succeeded", "Failed"], do: true

  defp relevant?(%{"type" => "MODIFIED", "object" => %{"metadata" => %{"deletionTimestamp" => ts}}}) when is_binary(ts),
    do: true

  defp relevant?(_), do: false

  defp maybe_reconcile(state) do
    elapsed = now_ms() - state.last_reconcile

    if elapsed >= @reconcile_throttle_ms do
      Reconciler.reconcile()
      %{state | last_reconcile: now_ms(), pending: false}
    else
      # Inside the throttle window: schedule a coalesced
      # follow-up. Multiple events arriving in this window
      # all collapse into one extra reconcile.
      if not state.pending do
        delay = max(@reconcile_throttle_ms - elapsed, 0)
        Process.send_after(self(), :reconcile_throttled, delay)
      end

      %{state | pending: true}
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp compute_backoff(_current, :ok), do: @backoff_min_ms
  defp compute_backoff(current, _), do: min(current * 2, @backoff_max_ms)
end
