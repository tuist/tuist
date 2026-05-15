defmodule Tuist.RunnersTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners

  setup :verify_on_exit!

  # The SA name and the Pod name are the same by construction (the
  # runners-controller's podtemplate stamps both with the same name),
  # so the test fixture just uses one string everywhere.
  defp sa_with_pool_label(pod_name, fleet_name) do
    %{
      "metadata" => %{
        "name" => pod_name,
        "namespace" => "tuist-runners",
        "labels" => %{"tuist.dev/runner-pool" => fleet_name}
      }
    }
  end

  defp pod_with_image(pod_name, image) do
    %{
      "metadata" => %{"name" => pod_name, "namespace" => "tuist-runners"},
      "spec" => %{"containers" => [%{"name" => "runner", "image" => image}]}
    }
  end

  # When `rolled_at` is provided, `slot_active?` will gate the drain
  # on the per-Pod hash; the tests below either pick a `rolled_at`
  # far enough in the past that every slot is open, or use a fresh
  # roll to assert the slot defers the drain.
  defp pool_with_image(image, opts \\ []) do
    status =
      case Keyword.get(opts, :rolled_at) do
        %DateTime{} = ts -> %{"imageRolledAt" => DateTime.to_iso8601(ts)}
        nil -> %{}
      end

    %{
      "metadata" => %{"name" => "fleet-a"},
      "spec" => %{"image" => image, "dispatchLabel" => "tuist-macos"},
      "status" => status
    }
  end

  describe "dispatch_for_sa/2 stale-image drain" do
    test "returns :drain when Pod image differs and the Pod's drain slot is open" do
      old_image = "ghcr.io/tuist/tuist-runner@sha256:old"
      new_image = "ghcr.io/tuist/tuist-runner@sha256:new"
      # Far enough in the past that every slot is drain-eligible
      # (8 slots * 30s = 240s window, so 1h covers the entire ramp).
      rolled = DateTime.add(DateTime.utc_now(), -3600, :second)

      expect(K8sClient, :get_service_account, fn "tuist-runners", "pod-1" ->
        {:ok, sa_with_pool_label("pod-1", "fleet-a")}
      end)

      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
        {:ok, pool_with_image(new_image, rolled_at: rolled)}
      end)

      expect(K8sClient, :get_pod, fn "tuist-runners", "pod-1" ->
        {:ok, pod_with_image("pod-1", old_image)}
      end)

      assert {:error, :drain} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
    end

    test "defers drain when Pod is stale but its drain slot has not opened yet" do
      # The fresh `rolled_at` here means only slot 0 is open. We pick
      # a Pod name whose phash2 over 8 slots is NOT slot 0, so the
      # check should return `:ok` (let it keep polling) instead of
      # `:drain`. This is the staggered-rollout contract: not all
      # warm Pods drain on the same poll tick after a digest bump.
      pod_name = pick_pod_in_nonzero_slot()
      old_image = "ghcr.io/tuist/tuist-runner@sha256:old"
      new_image = "ghcr.io/tuist/tuist-runner@sha256:new"
      rolled_now = DateTime.utc_now()

      expect(K8sClient, :get_service_account, fn "tuist-runners", ^pod_name ->
        {:ok, sa_with_pool_label(pod_name, "fleet-a")}
      end)

      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
        {:ok, pool_with_image(new_image, rolled_at: rolled_now)}
      end)

      expect(K8sClient, :get_pod, fn "tuist-runners", ^pod_name ->
        {:ok, pod_with_image(pod_name, old_image)}
      end)

      assert {:error, :no_work_yet} = Runners.dispatch_for_sa("tuist-runners", pod_name)
    end

    test "defers drain when status.imageRolledAt is missing (controller hasn't caught up)" do
      # A stale Pod hitting a pool the controller hasn't yet
      # reconciled (so `status.imageRolledAt` is absent) must NOT
      # drain — without a reference t=0, the slot calculation has
      # nothing to anchor against, so we defer rather than fire
      # eagerly and risk a thundering herd before the controller
      # has had a chance to record the roll.
      old_image = "ghcr.io/tuist/tuist-runner@sha256:old"
      new_image = "ghcr.io/tuist/tuist-runner@sha256:new"

      expect(K8sClient, :get_service_account, fn "tuist-runners", "pod-1" ->
        {:ok, sa_with_pool_label("pod-1", "fleet-a")}
      end)

      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
        # No rolled_at → no status.imageRolledAt in the response.
        {:ok, pool_with_image(new_image)}
      end)

      expect(K8sClient, :get_pod, fn "tuist-runners", "pod-1" ->
        {:ok, pod_with_image("pod-1", old_image)}
      end)

      assert {:error, :no_work_yet} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
    end

    test "does not drain when Pod image matches RunnerPool spec.image" do
      # No drain fires; the dispatch proceeds into the workflow_job
      # claim path. With no queued work, the claim path returns
      # `:no_work_yet` — which is the contract we want: image-match
      # falls through to the existing eligibility check.
      image = "ghcr.io/tuist/tuist-runner@sha256:current"
      rolled = DateTime.add(DateTime.utc_now(), -3600, :second)

      expect(K8sClient, :get_service_account, fn "tuist-runners", "pod-1" ->
        {:ok, sa_with_pool_label("pod-1", "fleet-a")}
      end)

      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
        {:ok, pool_with_image(image, rolled_at: rolled)}
      end)

      expect(K8sClient, :get_pod, fn "tuist-runners", "pod-1" ->
        {:ok, pod_with_image("pod-1", image)}
      end)

      assert {:error, :no_work_yet} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
    end

    test "downgrades transient k8s lookup failure to :ok and proceeds with dispatch" do
      # Refusing to dispatch on a transient k8s blip would stall the
      # whole pool. The drain check is opportunistic cleanup, not a
      # correctness gate; the reconciler's Pending-stale path catches
      # the unhappy long-tail. On a `get_pod` error here we fall
      # through to the normal claim path.
      rolled = DateTime.add(DateTime.utc_now(), -3600, :second)

      expect(K8sClient, :get_service_account, fn "tuist-runners", "pod-1" ->
        {:ok, sa_with_pool_label("pod-1", "fleet-a")}
      end)

      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
        {:ok, pool_with_image("ghcr.io/tuist/tuist-runner@sha256:new", rolled_at: rolled)}
      end)

      expect(K8sClient, :get_pod, fn "tuist-runners", "pod-1" ->
        {:error, :not_in_cluster}
      end)

      assert {:error, :no_work_yet} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
    end

    test "downgrades missing RunnerPool to :ok and proceeds with dispatch" do
      expect(K8sClient, :get_service_account, fn "tuist-runners", "pod-1" ->
        {:ok, sa_with_pool_label("pod-1", "fleet-a")}
      end)

      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
        {:error, :not_found}
      end)

      assert {:error, :no_work_yet} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
    end
  end

  # Find a Pod name that falls in slot != 0. The slot count is 8
  # (kept in lockstep with `@drain_slots` in lib/tuist/runners.ex);
  # bumping that constant means revisiting this helper.
  defp pick_pod_in_nonzero_slot do
    Enum.find(0..1000, fn i ->
      :erlang.phash2("pod-#{i}", 8) != 0
    end)
    |> then(&"pod-#{&1}")
  end
end
