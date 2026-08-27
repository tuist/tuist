defmodule Tuist.Runners.Workers.ReplicateRunnerSessionsWorker do
  @moduledoc """
  Drains Postgres `runner_sessions` into the ClickHouse replica the
  Concurrency card reads. See `Tuist.Runners.SessionReplication` for
  the resume-point and idempotency contract.

  Resolves the resume point once and pages from it, so a drain always
  moves forward even when the overlap window holds a full batch. Loops
  while batches come back full so an empty replica catches up on
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
    replicate(@max_batches_per_tick, SessionReplication.start_cursor(), 0)
  end

  defp replicate(0, _cursor, total) do
    Logger.info("runners: session replication stopped at its per-tick cap after #{total} sessions")
    :ok
  end

  defp replicate(remaining, cursor, total) do
    {:ok, count, next_cursor} = SessionReplication.replicate_batch(cursor)

    if SessionReplication.full_batch?(count) do
      replicate(remaining - 1, next_cursor, total + count)
    else
      :ok
    end
  end
end
