defmodule Tuist.Runners.Workers.RepairReplicaDivergenceWorker do
  @moduledoc """
  Repairs ClickHouse `runner_jobs` rows left non-terminal while the
  Postgres lifecycle row is terminal (`Tuist.Runners.Jobs.repair_replica_divergence/3`).

  A terminal job emits no further outbox events, so a replica row that
  missed its completion never converges on its own: the Jobs dashboard
  and the MCP job listing show it as running forever, and
  `Runners.Analytics` drops it from durations and outcome counts. Dispatch
  and concurrency limits read Postgres, so they are not affected.

  Runs from cron every 5 minutes over the window the
  `tuist_runners_replica_divergence_count` gauge watches, leaving rows
  younger than the settle window to the regular flush.

  Queued once with `enqueued_after` (an ISO-8601 timestamp), it repairs
  every diverged row enqueued since then, and also closes the diverged
  rows that have no lifecycle row (`close_untracked: true`). A capped scan
  snoozes until the flush has carried the repaired rows to ClickHouse,
  then scans again.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Telemetry

  require Logger

  @settle_minutes 5
  @window_days 7
  @scan_limit 5_000
  @snooze_seconds 120

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"enqueued_after" => enqueued_after}}) do
    {:ok, enqueued_floor, _offset} = DateTime.from_iso8601(enqueued_after)

    result = repair(enqueued_floor, close_untracked: true)

    if result.scanned == @scan_limit, do: {:snooze, @snooze_seconds}, else: :ok
  end

  def perform(_job) do
    _result = repair(DateTime.add(DateTime.utc_now(), -@window_days, :day))
    :ok
  end

  defp repair(enqueued_floor, opts \\ []) do
    settled_before = DateTime.add(DateTime.utc_now(), -@settle_minutes, :minute)

    result =
      Jobs.repair_replica_divergence(settled_before, enqueued_floor, Keyword.put(opts, :limit, @scan_limit))

    repaired = result.republished + result.closed

    if repaired > 0 do
      Logger.warning(
        "runners: repaired ClickHouse runner_jobs rows left non-terminal " <>
          "(republished #{result.republished}, closed #{result.closed}, scanned #{result.scanned})"
      )

      :telemetry.execute(Telemetry.event_name_recovery(), %{count: repaired}, %{kind: "replica_divergence"})
    end

    result
  end
end
