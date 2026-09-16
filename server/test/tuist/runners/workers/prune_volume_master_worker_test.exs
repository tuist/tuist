defmodule Tuist.Runners.Workers.PruneVolumeMasterWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Runners
  alias Tuist.Runners.Workers.PruneVolumeMasterWorker

  setup :verify_on_exit!

  describe "perform/1" do
    test "prunes the master object named by its id" do
      expect(Runners, :prune_superseded_volume_master, fn 42, "tree-content" -> :ok end)

      assert :ok = perform_job(PruneVolumeMasterWorker, %{account_id: 42, master_id: "tree-content"})
    end

    # Jobs enqueued before a master id could carry a content digest are still in
    # the queue after a deploy, and name their object by its inventory digest.
    test "prunes by the inventory digest a job enqueued before master ids carries" do
      expect(Runners, :prune_superseded_volume_master, fn 42, "tree" -> :ok end)

      assert :ok = perform_job(PruneVolumeMasterWorker, %{account_id: 42, tree_digest: "tree"})
    end
  end
end
