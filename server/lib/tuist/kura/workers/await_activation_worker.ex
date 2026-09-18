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

  ## Why the uniqueness window is bounded

  A run killed anyway — a `SIGKILL` past the grace period, a node lost — leaves
  its row `:executing`, and `Oban.Plugins.Lifeline` only rescues it after 30
  minutes. With an unbounded unique period every later enqueue for that server
  would conflict with the orphan and the fast path would be off for that server
  for half an hour, silently. Bounding the period to the reconciler's own
  cadence caps that at one tick, which is the backstop the fast path is layered
  on anyway. The cost is that a poll still running a minute later can be joined
  by a second job; both are idempotent and both stop at the same `:done`.
  """
  use Oban.Worker,
    queue: :kura_provisioning,
    max_attempts: 1,
    unique: [keys: [:server_id], period: 60, states: :incomplete]

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

  def enqueue(%Server{id: server_id}) do
    %{server_id: server_id}
    |> new()
    |> Oban.insert()
  end

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
