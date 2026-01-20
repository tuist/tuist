defmodule Tuist.Runs.Workers.ClearStaleFlakyFlagsWorker do
  @moduledoc """
  A worker that clears stale flaky flags from test cases.

  A test case's is_flaky flag is considered stale if there have been no flaky
  test case runs for that test case in the last 14 days.
  """
  use Oban.Worker

  alias Tuist.Runs

  @impl Oban.Worker
  def perform(_args) do
    Runs.clear_stale_flaky_flags()
  end
end
