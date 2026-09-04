defmodule Tuist.ClickHouse.Workers.ParityWorker do
  @moduledoc """
  Checks that the two ClickHouse servers still agree, while both are being
  written to (spec #73).

  The migration's own parity runs are one-shot: someone deploys a step and
  reads the result. That is the right shape for judging a backfill and the
  wrong one for judging a mirror, which can start dropping writes at any point
  during the weeks the two servers run side by side. Staging has already shown
  how it fails, and how quietly: a single row lost in the seconds after a pod
  started, found only because a parity run happened to follow it.

  ## What it compares

  A window, not the whole dataset. Fingerprinting every table means summing
  every numeric column of the largest ones, which reads the dataset and cannot
  be repeated hourly. The window is also the only part still at risk: a
  mirrored write is dropped as it happens, so recent rows are where a broken
  mirror shows up. The backfill's correctness is a separate question, already
  answered by the one-shot runs.

  The window overlaps itself deliberately. Each run looks back further than
  the hour it covers, so a row arriving late still falls inside some run's
  window rather than between two of them.

  ## What it does about a difference

  Counts it, and says which tables. It does not raise: Oban would retry, and
  the retry re-runs the comparison against a moving window, which turns one
  real difference into several confusing ones. The counter is the signal to
  alert on, and the repair is a backfill re-run with a later cutoff.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.ClickHouse.Parity
  alias Tuist.Environment

  require Logger

  # Two hours for an hourly run. The overlap is what stops a row that arrives
  # late from falling between two windows and being checked by neither.
  @window_hours 2

  @impl Oban.Worker
  def perform(_job) do
    if Environment.clickhouse_shadow_writes_enabled?() do
      compare()
    else
      :ok
    end
  end

  defp compare do
    since = DateTime.add(DateTime.utc_now(), -@window_hours, :hour)

    case Parity.compare(since: since) do
      {:ok, report} ->
        :telemetry.execute(
          [:tuist, :clickhouse, :parity],
          %{compared: report.compared, differing: length(report.differing)},
          %{}
        )

        if report.differing != [] do
          Logger.error(
            "ClickHouse parity: #{length(report.differing)} of #{report.compared} table(s) differ over the last #{@window_hours}h: #{inspect(report.differing)}"
          )
        end

        :ok

      {:error, reason} ->
        # Inert everywhere that is not mid-migration, which is every
        # environment without a destination configured.
        Logger.info("ClickHouse parity check skipped: #{inspect(reason)}")
        :ok
    end
  end
end
