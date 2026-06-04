defmodule Tuist.RunnersTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Environment
  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners
  alias Tuist.Runners.CacheToken
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.Jobs
  alias Tuist.VCS

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

  describe "dispatch_for_sa/2 dispatch-label carry-through" do
    # The candidate the claim path serves. `requested_dispatch_label`
    # is the only field these tests vary — everything else is just
    # enough to satisfy `serve_claim/5` + `RunnerSessions.open/1`.
    defp candidate_with_label(account, requested_dispatch_label) do
      %{
        workflow_job_id: 90_001,
        account_id: account.id,
        fleet_name: "fleet-a",
        repository: "acme/cli",
        workflow_name: "CI",
        requested_dispatch_label: requested_dispatch_label,
        enqueued_at: DateTime.utc_now()
      }
    end

    # Stub every collaborator `dispatch_for_sa/2` touches except the
    # JIT mint, whose `labels` the caller asserts on. The PG-backed
    # `RunnerSessions.open/1` and `Accounts.get_account_by_id/1` run
    # for real against the sandboxed repo.
    defp stub_dispatch_path(account, candidate, test_pid) do
      expect(K8sClient, :get_service_account, fn "tuist-runners", "pod-1" ->
        {:ok, sa_with_pool_label("pod-1", "fleet-a")}
      end)

      # Missing RunnerPool downgrades the stale-image check to :ok.
      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
        {:error, :not_found}
      end)

      expect(Jobs, :pick_queued, fn "fleet-a", _ineligible -> {:ok, candidate} end)
      expect(Claims, :attempt, fn 90_001, _account_id, "fleet-a", "pod-1" -> {:ok, %{claimed_at: DateTime.utc_now()}} end)
      expect(Jobs, :record_claimed, fn ^candidate, "pod-1", _claimed_at -> :ok end)

      expect(Dispatch, :pool_summary_by_name, fn "fleet-a" ->
        {:ok, %{dispatch_label: "shape-linux-4vcpu-16gb", runner_labels: ["self-hosted", "Linux", "X64"]}}
      end)

      stub(K8sClient, :patch_pod, fn _ns, _pod, _patch -> {:ok, %{}} end)

      stub(VCS, :get_github_app_installation_for_account, fn account_id ->
        assert account_id == account.id
        {:ok, %{installation_id: 42, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :generate_jit_config, fn _installation, _login, %{labels: labels} ->
        send(test_pid, {:jit_labels, labels})
        {:ok, %{encoded_jit_config: "jit-blob", runner_name: "pod-1"}}
      end)

      expect(Claims, :mark_running, fn 90_001, "pod-1" -> :ok end)
      expect(Jobs, :record_running, fn 90_001, "pod-1" -> :ok end)
    end

    test "stamps the candidate's requested_dispatch_label on the minted JIT" do
      account = account_fixture()
      candidate = candidate_with_label(account, "tuist-default")
      stub_dispatch_path(account, candidate, self())

      assert {:ok, %{runner_name: "pod-1"}} = Runners.dispatch_for_sa("tuist-runners", "pod-1")

      assert_receive {:jit_labels, labels}
      # The customer's profile label wins; the pool's internal
      # dispatchLabel must NOT leak onto the runner or GitHub never
      # binds the job to `runs-on: tuist-default`.
      assert "tuist-default" in labels
      refute "shape-linux-4vcpu-16gb" in labels
    end

    test "falls back to the pool dispatchLabel when the candidate has no requested label (legacy row)" do
      account = account_fixture()
      candidate = candidate_with_label(account, "")
      stub_dispatch_path(account, candidate, self())

      assert {:ok, %{runner_name: "pod-1"}} = Runners.dispatch_for_sa("tuist-runners", "pod-1")

      assert_receive {:jit_labels, labels}
      assert "shape-linux-4vcpu-16gb" in labels
    end

    test "retries the owner-label stamp on a transient patch failure and still dispatches" do
      account = account_fixture()
      candidate = candidate_with_label(account, "tuist-default")
      stub_dispatch_path(account, candidate, self())

      # Two transient failures then success. The owner label gates the
      # dispatch-egress NetworkPolicy, so a flaky patch must not leave
      # the Pod unstamped. Sequential expects are consumed in order,
      # ahead of the stub stub_dispatch_path installed.
      expect(K8sClient, :patch_pod, fn _ns, _pod, _patch -> {:error, :timeout} end)
      expect(K8sClient, :patch_pod, fn _ns, _pod, _patch -> {:error, :timeout} end)
      expect(K8sClient, :patch_pod, fn _ns, _pod, _patch -> {:ok, %{}} end)

      assert {:ok, %{runner_name: "pod-1"}} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
      assert_receive {:jit_labels, _labels}
    end

    test "gives up after the stamp retry budget but still dispatches (non-fatal)" do
      account = account_fixture()
      candidate = candidate_with_label(account, "tuist-default")
      stub_dispatch_path(account, candidate, self())

      # Every attempt fails. Dispatch must still succeed (the claim is
      # already won) and the stamp must be bounded at @owner_label_stamp_attempts,
      # not retried forever — verify_on_exit! asserts exactly 3 calls.
      expect(K8sClient, :patch_pod, 3, fn _ns, _pod, _patch -> {:error, :timeout} end)

      assert {:ok, %{runner_name: "pod-1"}} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
    end
  end

  describe "dispatch_for_sa/2 cache dispatch" do
    test "omits cache fields when the feature is disabled (no gateway URL)" do
      account = account_fixture()
      candidate = candidate_with_label(account, "tuist-default")
      stub_dispatch_path(account, candidate, self())

      # No gateway URL configured for either OS => feature off.
      stub(Environment, :cache_gateway_url, fn _os -> nil end)

      assert {:ok, dispatch} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
      assert_receive {:jit_labels, _labels}
      assert dispatch.cache_token == nil
      assert dispatch.cache_gateway_url == nil
    end

    test "includes the minted token and the per-OS gateway URL when enabled" do
      account = account_fixture()
      candidate = candidate_with_label(account, "tuist-default")
      stub_dispatch_path(account, candidate, self())

      test_pid = self()
      # runner_labels from stub_dispatch_path are ["self-hosted", "Linux", "X64"].
      stub(Environment, :cache_gateway_url, fn os ->
        send(test_pid, {:gateway_os, os})
        "https://cache-gateway.linux.internal"
      end)

      expect(CacheToken, :mint, fn ^candidate, ^account, os ->
        send(test_pid, {:mint_os, os})
        {:ok, "cache-jwt"}
      end)

      assert {:ok, dispatch} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
      assert_receive {:jit_labels, _labels}
      assert dispatch.cache_token == "cache-jwt"
      assert dispatch.cache_gateway_url == "https://cache-gateway.linux.internal"
      # A Linux fleet selects the linux gateway and stamps :linux into the token.
      assert_receive {:gateway_os, :linux}
      assert_receive {:mint_os, :linux}
    end

    test "fails open to no cache when minting fails despite a configured URL" do
      account = account_fixture()
      candidate = candidate_with_label(account, "tuist-default")
      stub_dispatch_path(account, candidate, self())

      stub(Environment, :cache_gateway_url, fn _os -> "https://cache-gateway.linux.internal" end)
      expect(CacheToken, :mint, fn _candidate, _account, _os -> {:error, :disabled} end)

      assert {:ok, dispatch} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
      assert_receive {:jit_labels, _labels}
      assert dispatch.cache_token == nil
      assert dispatch.cache_gateway_url == nil
    end
  end

  # Find a Pod name that falls in slot != 0. The slot count is 8
  # (kept in lockstep with `@drain_slots` in lib/tuist/runners.ex);
  # bumping that constant means revisiting this helper.
  defp pick_pod_in_nonzero_slot do
    0..1000
    |> Enum.find(fn i ->
      :erlang.phash2("pod-#{i}", 8) != 0
    end)
    |> then(&"pod-#{&1}")
  end
end
