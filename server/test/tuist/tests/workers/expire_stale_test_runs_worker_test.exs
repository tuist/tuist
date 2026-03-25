defmodule Tuist.Tests.Workers.ExpireStaleTestRunsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Tests
  alias Tuist.Tests.Workers.ExpireStaleTestRunsWorker

  describe "perform/1" do
    test "calls Tests.expire_stale_in_progress_test_runs/0" do
      expect(Tests, :expire_stale_in_progress_test_runs, fn -> :ok end)

      assert :ok = ExpireStaleTestRunsWorker.perform(%Oban.Job{args: %{}})
    end
  end
end
