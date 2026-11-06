defmodule Tuist.Tests.Coverage.Workers.SourceBackfillWorker do
  @moduledoc """
  Records the test versions and target sources of one project's runs from
  before the indexes existed (`Tuist.Tests.Coverage.TestSources.backfill/1`):
  carried tests and targets are found through them. Queued once per project by the migration that
  ships it. A server that runs the queue but predates the worker, or a
  server that starts before the ClickHouse table exists, fails the job, and
  it runs again later.
  """
  use Oban.Worker, queue: :coverage_deltas, max_attempts: 20

  alias Tuist.Tests.Coverage.TestSources

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id}}) do
    TestSources.backfill(project_id)
  end
end
