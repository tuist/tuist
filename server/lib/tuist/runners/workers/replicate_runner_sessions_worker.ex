defmodule Tuist.Runners.Workers.ReplicateRunnerSessionsWorker do
  @moduledoc """
  Drains Postgres `runner_sessions` into the ClickHouse replica the
  Concurrency card reads. See `Tuist.Runners.SessionReplication` for
  the resume-point and idempotency contract.

  Loops while batches come back full so an empty replica catches up on
  history in a handful of ticks instead of one batch a minute, and
  stops at `@max_batches_per_tick` so a backfill cannot monopolise the
  queue.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Runners.SessionReplication

  require Logger

  @max_batches_per_tick 20

  @impl Oban.Worker
  def perform(_job) do
    replicate(@max_batches_per_tick, 0)
  end

  defp replicate(0, total) do
    Logger.info("runners: session replication stopped at its per-tick cap after #{total} sessions")
    :ok
  end

  defp replicate(remaining, total) do
    {:ok, count} = SessionReplication.replicate_batch()

    if SessionReplication.full_batch?(count) do
      replicate(remaining - 1, total + count)
    else
      :ok
    end
  end
end
