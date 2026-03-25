defmodule Tuist.Tests.Workers.ExpireStaleTestRunsWorker do
  @moduledoc """
  Marks in-progress test runs as failed after 6 hours.

  Sharded test runs stay in_progress until all shards report. If a CI run
  is cancelled before all shards finish, the test run would stay in_progress
  forever. This worker periodically cleans those up.
  """
  use Oban.Worker

  alias Tuist.Tests

  @impl Oban.Worker
  def perform(_args) do
    Tests.expire_stale_in_progress_test_runs()
  end
end
