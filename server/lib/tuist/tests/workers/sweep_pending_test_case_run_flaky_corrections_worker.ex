defmodule Tuist.Tests.Workers.SweepPendingTestCaseRunFlakyCorrectionsWorker do
  @moduledoc """
  Re-enqueues correction ledger rows left pending after an exhausted or lost job.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 240]

  alias Tuist.Tests

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, _enqueued_count} = Tests.enqueue_pending_test_case_run_flaky_corrections()
    :ok
  end
end
