defmodule Tuist.Tests.Workers.CorrectTestCaseRunFlakyStateWorker do
  @moduledoc """
  Durably applies a bounded batch of flaky-state corrections.

  PostgreSQL keeps one ledger row per logical run before this job is enqueued.
  The worker writes up to 2,000 corrections in one ClickHouse insert, so a large
  report does not create one part per correction. A retry uses the same insert
  token and the insert itself excludes runs whose latest version is already
  flaky.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 10,
    unique: [
      keys: [:batch_id],
      period: :infinity,
      states: :incomplete
    ]

  alias Tuist.Tests

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"test_case_run_ids" => test_case_run_ids}}) do
    Tests.apply_test_case_run_flaky_corrections(test_case_run_ids)
  end
end
