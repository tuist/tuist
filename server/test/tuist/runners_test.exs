defmodule Tuist.RunnersTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners

  setup :verify_on_exit!

  # The SA name and the Pod name are the same by construction (the
  # runners-controller's podtemplate stamps both with the same name),
  # so the test fixture just uses one string everywhere.
  defp sa_with_pool_label(fleet_name) do
    %{
      "metadata" => %{
        "name" => "pod-1",
        "namespace" => "tuist-runners",
        "labels" => %{"tuist.dev/runner-pool" => fleet_name}
      }
    }
  end

  defp pod_with_image(image) do
    %{
      "metadata" => %{"name" => "pod-1", "namespace" => "tuist-runners"},
      "spec" => %{"containers" => [%{"name" => "runner", "image" => image}]}
    }
  end

  defp pool_with_image(image) do
    %{
      "metadata" => %{"name" => "fleet-a"},
      "spec" => %{"image" => image, "dispatchLabel" => "tuist-macos"}
    }
  end

  describe "dispatch_for_sa/2 stale-image drain" do
    test "returns :drain when Pod image differs from RunnerPool spec.image" do
      old_image = "ghcr.io/tuist/tuist-runner@sha256:old"
      new_image = "ghcr.io/tuist/tuist-runner@sha256:new"

      expect(K8sClient, :get_service_account, fn "tuist-runners", "pod-1" ->
        {:ok, sa_with_pool_label("fleet-a")}
      end)

      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
        {:ok, pool_with_image(new_image)}
      end)

      expect(K8sClient, :get_pod, fn "tuist-runners", "pod-1" ->
        {:ok, pod_with_image(old_image)}
      end)

      assert {:error, :drain} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
    end

    test "does not drain when Pod image matches RunnerPool spec.image" do
      # No drain fires; the dispatch proceeds into the workflow_job
      # claim path. With no queued work, the claim path returns
      # `:no_work_yet` — which is the contract we want: image-match
      # falls through to the existing eligibility check.
      image = "ghcr.io/tuist/tuist-runner@sha256:current"

      expect(K8sClient, :get_service_account, fn "tuist-runners", "pod-1" ->
        {:ok, sa_with_pool_label("fleet-a")}
      end)

      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
        {:ok, pool_with_image(image)}
      end)

      expect(K8sClient, :get_pod, fn "tuist-runners", "pod-1" ->
        {:ok, pod_with_image(image)}
      end)

      assert {:error, :no_work_yet} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
    end

    test "downgrades transient k8s lookup failure to :ok and proceeds with dispatch" do
      # Refusing to dispatch on a transient k8s blip would stall the
      # whole pool. The drain check is opportunistic cleanup, not a
      # correctness gate; the reconciler's Pending-stale path catches
      # the unhappy long-tail. On a `get_pod` error here we fall
      # through to the normal claim path.
      expect(K8sClient, :get_service_account, fn "tuist-runners", "pod-1" ->
        {:ok, sa_with_pool_label("fleet-a")}
      end)

      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
        {:ok, pool_with_image("ghcr.io/tuist/tuist-runner@sha256:new")}
      end)

      expect(K8sClient, :get_pod, fn "tuist-runners", "pod-1" ->
        {:error, :not_in_cluster}
      end)

      assert {:error, :no_work_yet} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
    end

    test "downgrades missing RunnerPool to :ok and proceeds with dispatch" do
      expect(K8sClient, :get_service_account, fn "tuist-runners", "pod-1" ->
        {:ok, sa_with_pool_label("fleet-a")}
      end)

      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
        {:error, :not_found}
      end)

      assert {:error, :no_work_yet} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
    end
  end
end
