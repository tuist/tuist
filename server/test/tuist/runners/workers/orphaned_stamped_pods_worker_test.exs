defmodule Tuist.Runners.Workers.OrphanedStampedPodsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Workers.OrphanedStampedPodsWorker

  setup :verify_on_exit!

  @namespace "tuist-runners"
  @owner_label "tuist.dev/runner-pool-owner"

  defp pod(name, created_at) do
    %{"metadata" => %{"name" => name, "creationTimestamp" => created_at}}
  end

  # Comfortably outside the 300s grace window.
  defp aged, do: "2020-01-01T00:00:00Z"
  defp fresh, do: DateTime.to_iso8601(DateTime.utc_now())

  setup do
    stub(Environment, :runners_namespace, fn -> @namespace end)
    :ok
  end

  describe "perform/1" do
    test "reaps a stamped pod with no live claim that is older than the grace window" do
      # The exact wedge signature: a Pod left owner-stamped after its
      # claim was released (deploy crash / mint failure). The
      # reconciler can't scale it down because it isn't idle, so it
      # pins memory forever until we reap it.
      expect(K8sClient, :list_pods, fn @namespace, @owner_label ->
        {:ok, [pod("runner-leak", aged())]}
      end)

      expect(Claims, :live_pod_names, fn -> MapSet.new() end)

      expect(K8sClient, :delete_runner, fn @namespace, "runner-leak" -> :ok end)

      assert :ok = OrphanedStampedPodsWorker.perform(%Oban.Job{})
    end

    test "leaves a stamped pod that still holds a live claim" do
      # Stamped + claimed is the healthy busy state — a real job is
      # running on it. Reaping here would kill a live build.
      expect(K8sClient, :list_pods, fn @namespace, _selector ->
        {:ok, [pod("runner-busy", aged())]}
      end)

      expect(Claims, :live_pod_names, fn -> MapSet.new(["runner-busy"]) end)

      reject(&K8sClient.delete_runner/2)

      assert :ok = OrphanedStampedPodsWorker.perform(%Oban.Job{})
    end

    test "leaves a freshly-created stamped pod inside the grace window" do
      # Belt-and-suspenders against the list-pods/list-claims read
      # window: a Pod stamped moments ago is given the benefit of the
      # doubt even if its claim doesn't appear in the snapshot yet.
      expect(K8sClient, :list_pods, fn @namespace, _selector ->
        {:ok, [pod("runner-fresh", fresh())]}
      end)

      expect(Claims, :live_pod_names, fn -> MapSet.new() end)

      reject(&K8sClient.delete_runner/2)

      assert :ok = OrphanedStampedPodsWorker.perform(%Oban.Job{})
    end

    test "reaps only the orphans in a mixed batch" do
      expect(K8sClient, :list_pods, fn @namespace, _selector ->
        {:ok,
         [
           pod("runner-leak", aged()),
           pod("runner-busy", aged()),
           pod("runner-fresh", fresh())
         ]}
      end)

      expect(Claims, :live_pod_names, fn -> MapSet.new(["runner-busy"]) end)

      expect(K8sClient, :delete_runner, fn @namespace, "runner-leak" -> :ok end)

      assert :ok = OrphanedStampedPodsWorker.perform(%Oban.Job{})
    end

    test "is a no-op when no pods are stamped" do
      expect(K8sClient, :list_pods, fn @namespace, _selector -> {:ok, []} end)
      stub(Claims, :live_pod_names, fn -> MapSet.new() end)

      reject(&K8sClient.delete_runner/2)

      assert :ok = OrphanedStampedPodsWorker.perform(%Oban.Job{})
    end

    test "skips the tick when listing pods fails" do
      # No proof of orphan state without a fresh Pod list — retry next
      # tick rather than reap speculatively.
      expect(K8sClient, :list_pods, fn @namespace, _selector -> {:error, :timeout} end)

      reject(&Claims.live_pod_names/0)
      reject(&K8sClient.delete_runner/2)

      assert :ok = OrphanedStampedPodsWorker.perform(%Oban.Job{})
    end
  end
end
