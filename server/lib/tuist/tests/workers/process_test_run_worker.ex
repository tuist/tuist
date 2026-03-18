defmodule Tuist.Tests.Workers.ProcessTestRunWorker do
  @moduledoc """
  Oban worker that processes the deferred parts of a test run.

  After `Tests.create_test/1` inserts the test run and minimal test case runs
  synchronously (so the CLI can immediately upload attachments using the returned
  test_case_run IDs), this worker handles the remaining heavy work:

  - Test module and suite run aggregates
  - Cross-run flaky detection (ClickHouse reads against commit SHA)
  - New test case detection (ClickHouse reads against default branch)
  - Full TestCase records with duration averages
  - Updated TestCaseRun rows with correct is_flaky / is_new flags
  - TestCaseFailure and TestCaseRunRepetition records
  - First-run events for new test cases
  - PubSub broadcast and FlakyThresholdCheckWorker scheduling
  """

  use Oban.Worker, max_attempts: 3

  alias Tuist.Tests

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Tests.process_test_run_deferred(args)
  end
end
