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

  defp pod(name, created_at, container_statuses \\ []) do
    %{
      "metadata" => %{"name" => name, "creationTimestamp" => created_at},
      "status" => %{"containerStatuses" => container_statuses}
    }
  end

  # The wedge state this worker exists to clean up: poller poll-loops
  # forever without claiming a JIT, so the `runner` container never
  # starts. kubelet reports it as waiting on the init container.
  defp runner_waiting do
    [%{"name" => "runner", "started" => false, "state" => %{"waiting" => %{"reason" => "PodInitializing"}}}]
  end

  # A live job: poller staged the JIT, kubelet started the runner
  # container, the `started` gate has flipped on. The Pod is mid-build
  # and must not be force-deleted regardless of the claim state.
  defp runner_executing do
    [%{"name" => "runner", "started" => true, "state" => %{"running" => %{"startedAt" => "2026-06-06T21:30:08Z"}}}]
  end

  # The narrow window between the runner exiting and the reconciler
  # reaping the Pod. `started` flips back to false on termination, so
  # the guard reads `state.terminated` instead.
  defp runner_terminated do
    [
      %{
        "name" => "runner",
        "started" => false,
        "state" => %{"terminated" => %{"exitCode" => 0, "reason" => "Completed"}}
      }
    ]
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

    test "leaves a stamped pod whose runner container is executing, even when the claim is missing" do
      # The class of incident this guard exists for: dispatch stamped
      # the label, the JIT was delivered to the Pod, the runner started
      # executing a customer job — and then *something* released the
      # PG claim (a stale webhook, a future bug, a code path that
      # reaches Claims.release while the runner is live). Without the
      # guard this worker would force-delete the running Pod and the
      # job would surface on GitHub as "lost communication with the
      # server." With the guard we trust the `started=true` signal on
      # the runner container and skip the reap.
      expect(K8sClient, :list_pods, fn @namespace, _selector ->
        {:ok, [pod("runner-live-build", aged(), runner_executing())]}
      end)

      expect(Claims, :live_pod_names, fn -> MapSet.new() end)

      reject(&K8sClient.delete_runner/2)

      assert :ok = OrphanedStampedPodsWorker.perform(%Oban.Job{})
    end

    test "leaves a stamped pod whose runner container has already terminated" do
      # Narrow window: the runner exited, the Pod is in cleanup, the
      # Pool reconciler hasn't reaped it yet. `started` flips back to
      # false on termination — the guard reads `state.terminated`
      # instead so we don't delete the Pod twice.
      expect(K8sClient, :list_pods, fn @namespace, _selector ->
        {:ok, [pod("runner-finished", aged(), runner_terminated())]}
      end)

      expect(Claims, :live_pod_names, fn -> MapSet.new() end)

      reject(&K8sClient.delete_runner/2)

      assert :ok = OrphanedStampedPodsWorker.perform(%Oban.Job{})
    end

    test "still reaps a stamped pod whose runner container is waiting on the poller" do
      # The original wedge signature: the poller never claimed a JIT,
      # so the runner container stays in `waiting`. `started=false`
      # AND no `terminated` state — guard does not apply, reap fires.
      expect(K8sClient, :list_pods, fn @namespace, _selector ->
        {:ok, [pod("runner-wedged", aged(), runner_waiting())]}
      end)

      expect(Claims, :live_pod_names, fn -> MapSet.new() end)

      expect(K8sClient, :delete_runner, fn @namespace, "runner-wedged" -> :ok end)

      assert :ok = OrphanedStampedPodsWorker.perform(%Oban.Job{})
    end

    test "reaps a stamped pod with no containerStatuses (very early lifecycle, no JIT yet)" do
      # If the Pod has no containerStatuses at all (scheduling/pull
      # phase before kubelet reports any container), the runner has
      # not started; the existing 5-min grace window already shields
      # legitimate early-lifecycle Pods, so any Pod past the grace
      # window with no runner status is a real orphan.
      expect(K8sClient, :list_pods, fn @namespace, _selector ->
        {:ok, [pod("runner-prestart", aged())]}
      end)

      expect(Claims, :live_pod_names, fn -> MapSet.new() end)

      expect(K8sClient, :delete_runner, fn @namespace, "runner-prestart" -> :ok end)

      assert :ok = OrphanedStampedPodsWorker.perform(%Oban.Job{})
    end

    test "reaps only the wedged orphan in a mixed batch with live and finished runners" do
      expect(K8sClient, :list_pods, fn @namespace, _selector ->
        {:ok,
         [
           pod("runner-wedged", aged(), runner_waiting()),
           pod("runner-live-build", aged(), runner_executing()),
           pod("runner-finished", aged(), runner_terminated())
         ]}
      end)

      expect(Claims, :live_pod_names, fn -> MapSet.new() end)

      expect(K8sClient, :delete_runner, fn @namespace, "runner-wedged" -> :ok end)

      assert :ok = OrphanedStampedPodsWorker.perform(%Oban.Job{})
    end
  end
end
