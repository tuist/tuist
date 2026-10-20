defmodule Tuist.Runners.Workers.PruneVolumeMasterOrphanWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Runners
  alias Tuist.Runners.Workers.PruneVolumeMasterOrphanWorker

  setup :verify_on_exit!

  describe "perform/1" do
    test "reclaims the orphaned master object named by its id" do
      expect(Runners, :prune_orphan_volume_master, fn 42, "tuist-cache", "tree-content" -> :ok end)

      assert :ok = perform_job(PruneVolumeMasterOrphanWorker, %{account_id: 42, master_id: "tree-content"})
    end

    test "reclaims in the volume the job names" do
      expect(Runners, :prune_orphan_volume_master, fn 42, "repo-eae044a4c27633ea", "tree" -> :ok end)

      assert :ok =
               perform_job(PruneVolumeMasterOrphanWorker, %{
                 account_id: 42,
                 volume_name: "repo-eae044a4c27633ea",
                 master_id: "tree"
               })
    end

    # Jobs enqueued before a master id could carry a content digest are still in
    # the queue after a deploy, and name their object by its inventory digest.
    test "reclaims by the inventory digest a job enqueued before master ids carries" do
      expect(Runners, :prune_orphan_volume_master, fn 42, "tuist-cache", "tree" -> :ok end)

      assert :ok = perform_job(PruneVolumeMasterOrphanWorker, %{account_id: 42, tree_digest: "tree"})
    end
  end
end
