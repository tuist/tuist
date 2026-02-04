defmodule Tuist.Tests.Workers.ClearStaleFlakyFlagsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Tests
  alias Tuist.Tests.Workers.ClearStaleFlakyFlagsWorker

  describe "perform/1" do
    test "calls Tests.clear_stale_flaky_flags/0" do
      expect(Tests, :clear_stale_flaky_flags, fn -> {:ok, 0} end)

      assert {:ok, 0} = ClearStaleFlakyFlagsWorker.perform(%Oban.Job{args: %{}})
    end
  end
end
