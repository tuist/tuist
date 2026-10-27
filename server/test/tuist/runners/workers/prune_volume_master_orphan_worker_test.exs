defmodule Tuist.Runners.Workers.PruneVolumeMasterOrphanWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Runners
  alias Tuist.Runners.Workers.PruneVolumeMasterOrphanWorker

  setup :verify_on_exit!

  @volume "linux-" <> String.duplicate("a", 64)

  describe "perform/1" do
    test "reclaims the orphaned master object named by its id in the volume the job names" do
      expect(Runners, :prune_orphan_volume_master, fn 42, @volume, "tree-content" -> :ok end)

      assert :ok =
               perform_job(PruneVolumeMasterOrphanWorker, %{
                 account_id: 42,
                 volume_name: @volume,
                 master_id: "tree-content"
               })
    end

    test "reclaims by the inventory digest a job enqueued before master ids carries" do
      expect(Runners, :prune_orphan_volume_master, fn 42, @volume, "tree" -> :ok end)

      assert :ok =
               perform_job(PruneVolumeMasterOrphanWorker, %{account_id: 42, volume_name: @volume, tree_digest: "tree"})
    end
  end
end
