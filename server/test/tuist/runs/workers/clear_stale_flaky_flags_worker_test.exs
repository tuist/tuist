defmodule Tuist.Runs.Workers.ClearStaleFlakyFlagsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Runs
  alias Tuist.Runs.Workers.ClearStaleFlakyFlagsWorker

  describe "perform/1" do
    test "calls Runs.clear_stale_flaky_flags/0" do
      expect(Runs, :clear_stale_flaky_flags, fn -> {:ok, 0} end)

      assert {:ok, 0} = ClearStaleFlakyFlagsWorker.perform(%Oban.Job{args: %{}})
    end
  end
end
