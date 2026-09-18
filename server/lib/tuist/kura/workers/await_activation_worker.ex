defmodule Tuist.Kura.Workers.AwaitActivationWorker do
  @moduledoc """
  Activates a Kura instance that is coming up within about half a second of its
  endpoint answering, rather than on the next minute's reconciler tick.

  Each run checks `Tuist.Kura.Reconciler.activate_when_ready/1` about twice a
  second, then snoozes without a delay. Snoozing after every check would space
  them by Oban's stager and fetch, measured at 2.5 to 3 seconds apart, so each
  run keeps its own clock and only pays that gap once per run. It gives up once
  the attempt has run for `Tuist.Kura.provisioning_stall_seconds/0`, where the
  tick reports the stall and keeps retrying on its own cadence.

  ## Why the run is bounded by a clock rather than by a check count

  A check is not free and is not bounded by the check interval: it reads the
  instance's image tag from the cluster's apiserver, asks the zone's
  authoritative nameservers whether the endpoint's record is published, and
  probes `/up` over HTTPS with a five-second timeout of its own.
  A gateway that accepts TCP and never finishes the handshake — the normal
  state between the record being published and a healthy upstream existing,
  which is exactly what this polls through — spends that whole timeout in one
  check. Counting checks would therefore size the run against the fast path and
  overrun on the slow one, and a run that overruns Oban's shutdown grace period
  is killed mid-check by a deploy.

  So the run starts no check it cannot finish inside `@run_budget_ms`, which
  leaves `@worst_case_check_ms` of Oban's 15-second grace for the check in
  flight. `@checks_per_run` is what that budget buys at the nominal interval,
  and caps the run when checks come back instantly; the clock is what holds the
  run inside the grace period when they do not. A run that spends either
  snoozes early and the next run picks the poll back up, for the cost of one
  stager gap.

  ## Why an orphaned run is recovered rather than waited out

  A run killed anyway — a `SIGKILL` past the grace period, a node lost — leaves
  its row `:executing`, and `Oban.Plugins.Lifeline` only rescues it after 30
  minutes (`config/runtime.exs`). Uniqueness is what makes that bite: every
  later enqueue for the server conflicts with the orphan, so the fast path is
  off for that server for half an hour and nothing says so.

  Bounding the unique period instead would trade that for a worse problem. A
  snooze keeps the job's `inserted_at`, so a poll that outlives the period is
  no longer its own conflict: a provision running to
  `Tuist.Kura.provisioning_stall_seconds/0` would collect one more polling job
  every period, and `:kura_provisioning` is `limit: 10` per node and shared
  with `Tuist.Kura.Workers.ProvisionOnDemandWorker` — so one slow server would
  end up starving the worker that starts provisions at all.

  So the period stays unbounded and `enqueue/1` recovers the orphan directly.
  On a conflict Oban hands back the job that won; if that job has been
  `:executing` for longer than any run can legitimately take
  (`@orphan_after_ms`, several times the run budget so a throttled or
  garbage-collecting pod is never mistaken for a dead one), it is cancelled and
  the insert retried. A snoozing job is `:scheduled`, never `:executing`, so a
  healthy poll is never cancelled by this.
  """
  use Oban.Worker,
    queue: :kura_provisioning,
    max_attempts: 1,
    unique: [keys: [:server_id], period: :infinity, states: :incomplete]

  alias Tuist.Environment
  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Reconciler
  alias Tuist.Kura.Server

  @check_interval_ms Application.compile_env(:tuist, [__MODULE__, :check_interval_ms], 500)

  # The apiserver read, the authoritative DNS lookup and the `/up` probe's own
  # timeout, rounded up. Held back from the run's budget so a check that costs
  # all of it still finishes inside Oban's shutdown grace period.
  @worst_case_check_ms 8_000
  @oban_shutdown_grace_ms 15_000
  @default_run_budget_ms @oban_shutdown_grace_ms - @worst_case_check_ms
  @run_budget_ms Application.compile_env(:tuist, [__MODULE__, :run_budget_ms], @default_run_budget_ms)

  # What the production budget buys at the nominal interval, rather than at the
  # configured one, so a test that drops the interval to zero still exercises
  # the cap rather than spinning against the clock.
  @checks_per_run div(@default_run_budget_ms, 500)

  # How long a row may sit `:executing` before it is taken for the remains of a
  # killed run. A run cannot exceed the budget plus one worst-case check, so
  # this is four times the longest legitimate one: a pod paused by CPU
  # throttling or a stop-the-world collection must never have its live poll
  # cancelled out from under it.
  @orphan_after_ms 4 * (@default_run_budget_ms + @worst_case_check_ms)

  def enqueue(%Server{id: server_id}) do
    case insert(server_id) do
      {:ok, %Oban.Job{conflict?: true} = held} -> reclaim_if_orphaned(held, server_id)
      result -> result
    end
  end

  defp insert(server_id) do
    %{server_id: server_id}
    |> new()
    |> Oban.insert()
  end

  defp reclaim_if_orphaned(%Oban.Job{state: "executing", attempted_at: %DateTime{} = attempted_at} = held, server_id) do
    if DateTime.diff(DateTime.utc_now(), attempted_at, :millisecond) > @orphan_after_ms do
      # Best effort: a cancel that does not land leaves the tick as the
      # backstop, which is where this server was headed anyway. Re-inserting
      # can conflict again if another node reclaimed first, and that answer is
      # as good as ours.
      case Oban.cancel_job(held.id) do
        :ok -> insert(server_id)
        _error -> {:ok, held}
      end
    else
      {:ok, held}
    end
  end

  defp reclaim_if_orphaned(held, _server_id), do: {:ok, held}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"server_id" => server_id}}) do
    if Environment.kura_control_plane?() do
      check(server_id, @checks_per_run, System.monotonic_time(:millisecond) + @run_budget_ms)
    else
      :ok
    end
  end

  defp check(server_id, remaining, deadline) do
    with {:waiting, %Deployment{inserted_at: started_at}} <- Reconciler.activate_when_ready(server_id),
         true <- DateTime.diff(DateTime.utc_now(), started_at) < Kura.provisioning_stall_seconds() do
      if remaining > 1 and System.monotonic_time(:millisecond) + @check_interval_ms < deadline do
        Process.sleep(@check_interval_ms)
        check(server_id, remaining - 1, deadline)
      else
        {:snooze, 0}
      end
    else
      _ -> :ok
    end
  end
end
