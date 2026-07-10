defmodule Tuist.RunnersTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners
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

  defp pod_with_image(pod_name, image, opts \\ []) do
    labels =
      if Keyword.get(opts, :drain_eligible, false) do
        %{"tuist.dev/drain-eligible" => "true"}
      else
        %{}
      end

    %{
      "metadata" => %{"name" => pod_name, "namespace" => "tuist-runners", "labels" => labels},
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
    test "returns :drain when Pod is stale and the controller marked it drain-eligible" do
      old_image = "ghcr.io/tuist/tuist-runner@sha256:old"
      new_image = "ghcr.io/tuist/tuist-runner@sha256:new"

      expect(K8sClient, :get_service_account, fn "tuist-runners", "pod-1" ->
        {:ok, sa_with_pool_label("pod-1", "fleet-a")}
      end)

      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
        {:ok, pool_with_image(new_image)}
      end)

      expect(K8sClient, :get_pod, fn "tuist-runners", "pod-1" ->
        {:ok, pod_with_image("pod-1", old_image, drain_eligible: true)}
      end)

      assert {:error, :drain} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
    end

    test "defers drain when Pod is stale but not yet drain-eligible (controller paces the roll)" do
      # The controller marks only a capped number of stale Pods
      # drain-eligible at a time, so an unmarked stale Pod keeps polling
      # (no 410) until its turn — that's how a digest roll avoids the
      # whole fleet pulling the new image at once.
      old_image = "ghcr.io/tuist/tuist-runner@sha256:old"
      new_image = "ghcr.io/tuist/tuist-runner@sha256:new"

      expect(K8sClient, :get_service_account, fn "tuist-runners", "pod-1" ->
        {:ok, sa_with_pool_label("pod-1", "fleet-a")}
      end)

      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
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

      expect(K8sClient, :get_service_account, fn "tuist-runners", "pod-1" ->
        {:ok, sa_with_pool_label("pod-1", "fleet-a")}
      end)

      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
        {:ok, pool_with_image(image)}
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
      expect(K8sClient, :get_service_account, fn "tuist-runners", "pod-1" ->
        {:ok, sa_with_pool_label("pod-1", "fleet-a")}
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
    defp candidate_with_label(account, requested_dispatch_label, opts \\ []) do
      workflow_job_id = Keyword.get(opts, :workflow_job_id, 90_001)

      %{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        fleet_name: "fleet-a",
        repository: "acme/cli",
        workflow_run_id: workflow_job_id * 10,
        run_attempt: 1,
        workflow_name: "CI",
        job_name: "build",
        head_branch: "main",
        head_sha: "deadbeef",
        requested_dispatch_label: requested_dispatch_label,
        enqueued_at: DateTime.utc_now()
      }
    end

    # Stub every collaborator `dispatch_for_sa/2` touches except the
    # JIT mint, whose `labels` the caller asserts on. The PG-backed
    # `RunnerSessions.open/1` and `Accounts.get_account_by_id/1` run
    # for real against the sandboxed repo.
    defp stub_dispatch_path(account, candidate, test_pid, opts \\ []) do
      pod_name = Keyword.get(opts, :pod_name, "pod-1")
      excluded_workflow_job_ids = Keyword.get(opts, :excluded_workflow_job_ids, [])
      workflow_job_id = candidate.workflow_job_id

      expect(K8sClient, :get_service_account, fn "tuist-runners", ^pod_name ->
        {:ok, sa_with_pool_label(pod_name, "fleet-a")}
      end)

      # Missing RunnerPool downgrades the stale-image check to :ok.
      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
        {:error, :not_found}
      end)

      expect(Claims, :workflow_job_ids_for_fleet, fn "fleet-a" -> excluded_workflow_job_ids end)

      expect(Jobs, :pick_queued, fn "fleet-a", [], ^excluded_workflow_job_ids -> {:ok, candidate} end)

      expect(Claims, :attempt, fn ^workflow_job_id, _account_id, "fleet-a", ^pod_name ->
        {:ok, %{claimed_at: DateTime.utc_now()}}
      end)

      expect(Jobs, :record_claimed, fn ^candidate, ^pod_name, _claimed_at -> :ok end)

      expect(Dispatch, :pool_summary_by_name, fn "fleet-a" ->
        {:ok, %{dispatch_label: "shape-linux-4vcpu-16gb", runner_labels: ["self-hosted", "Linux", "X64"]}}
      end)

      stub(K8sClient, :patch_pod, fn _ns, _pod, _patch -> {:ok, %{}} end)

      stub(VCS, :get_github_app_installation_for_account, fn account_id ->
        assert account_id == account.id
        {:ok, %{installation_id: 42, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :generate_jit_config, fn _installation, _login, %{labels: labels, name: runner_name} ->
        send(test_pid, {:jit_labels, labels})
        send(test_pid, {:jit_runner_name, runner_name})
        {:ok, %{encoded_jit_config: "jit-blob", runner_name: runner_name}}
      end)

      expect(Claims, :mark_running, fn ^workflow_job_id, runner_name ->
        assert String.starts_with?(runner_name, String.slice(pod_name, 0, 55))
        assert byte_size(runner_name) <= 64
        :ok
      end)

      expect(Jobs, :record_running, fn ^workflow_job_id, runner_name ->
        assert String.starts_with?(runner_name, String.slice(pod_name, 0, 55))
        assert byte_size(runner_name) <= 64
        :ok
      end)
    end

    test "stamps the candidate's requested_dispatch_label on the minted JIT" do
      account = account_fixture()
      candidate = candidate_with_label(account, "tuist-default")
      stub_dispatch_path(account, candidate, self())

      assert {:ok, %{runner_name: runner_name}} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
      assert String.starts_with?(runner_name, "pod-1-")
      assert byte_size(runner_name) <= 64

      assert_receive {:jit_labels, labels}
      # The customer's profile label wins; the pool's internal
      # dispatchLabel must NOT leak onto the runner or GitHub never
      # binds the job to `runs-on: tuist-default`.
      assert "tuist-default" in labels
      refute "shape-linux-4vcpu-16gb" in labels
    end

    test "keeps generated GitHub runner names within the API limit" do
      account = account_fixture()
      candidate = candidate_with_label(account, "tuist-default")
      pod_name = "tuist-tuist-runner-pool-linux-ubuntu-22-04-runner-01234567"
      stub_dispatch_path(account, candidate, self(), pod_name: pod_name)

      assert {:ok, %{runner_name: runner_name}} = Runners.dispatch_for_sa("tuist-runners", pod_name)

      assert_receive {:jit_runner_name, ^runner_name}
      assert byte_size(runner_name) == 64
      assert runner_name =~ ~r/-[0-9a-f]{8}$/
      assert runner_name != pod_name
    end

    test "falls back to the pool dispatchLabel when the candidate has no requested label (legacy row)" do
      account = account_fixture()
      candidate = candidate_with_label(account, "")
      stub_dispatch_path(account, candidate, self())

      assert {:ok, %{runner_name: runner_name}} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
      assert String.starts_with?(runner_name, "pod-1-")

      assert_receive {:jit_labels, labels}
      assert "shape-linux-4vcpu-16gb" in labels
    end

    test "excludes workflow jobs that already have active Postgres claims before picking queued work" do
      account = account_fixture()
      candidate = candidate_with_label(account, "tuist-default", workflow_job_id: 90_002)
      stub_dispatch_path(account, candidate, self(), excluded_workflow_job_ids: [90_001])

      assert {:ok, %{workflow_job_id: 90_002}} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
    end

    test "tries the next queued job after losing a claim race" do
      account = account_fixture()
      stale_candidate = candidate_with_label(account, "tuist-default", workflow_job_id: 90_001)
      candidate = candidate_with_label(account, "tuist-default", workflow_job_id: 90_002)
      pod_name = "pod-1"
      test_pid = self()

      expect(K8sClient, :get_service_account, fn "tuist-runners", ^pod_name ->
        {:ok, sa_with_pool_label(pod_name, "fleet-a")}
      end)

      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
        {:error, :not_found}
      end)

      expect(Claims, :workflow_job_ids_for_fleet, fn "fleet-a" -> [] end)

      expect(Jobs, :pick_queued, fn "fleet-a", [], [] -> {:ok, stale_candidate} end)

      expect(Claims, :attempt, fn 90_001, _account_id, "fleet-a", ^pod_name ->
        {:error, :lost_race}
      end)

      expect(Jobs, :pick_queued, fn "fleet-a", [], [90_001] -> {:ok, candidate} end)

      expect(Claims, :attempt, fn 90_002, _account_id, "fleet-a", ^pod_name ->
        {:ok, %{claimed_at: DateTime.utc_now()}}
      end)

      expect(Jobs, :record_claimed, fn ^candidate, ^pod_name, _claimed_at -> :ok end)

      expect(Dispatch, :pool_summary_by_name, fn "fleet-a" ->
        {:ok, %{dispatch_label: "shape-linux-4vcpu-16gb", runner_labels: ["self-hosted", "Linux", "X64"]}}
      end)

      stub(K8sClient, :patch_pod, fn _ns, _pod, _patch -> {:ok, %{}} end)

      stub(VCS, :get_github_app_installation_for_account, fn account_id ->
        assert account_id == account.id
        {:ok, %{installation_id: 42, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :generate_jit_config, fn _installation, _login, %{labels: labels, name: runner_name} ->
        send(test_pid, {:jit_labels, labels})
        {:ok, %{encoded_jit_config: "jit-blob", runner_name: runner_name}}
      end)

      expect(Claims, :mark_running, fn 90_002, runner_name ->
        assert String.starts_with?(runner_name, pod_name)
        :ok
      end)

      expect(Jobs, :record_running, fn 90_002, runner_name ->
        assert String.starts_with?(runner_name, pod_name)
        :ok
      end)

      assert {:ok, %{workflow_job_id: 90_002}} = Runners.dispatch_for_sa("tuist-runners", pod_name)
      assert_receive {:jit_labels, labels}
      assert "tuist-default" in labels
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

      assert {:ok, %{runner_name: runner_name}} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
      assert String.starts_with?(runner_name, "pod-1-")
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

      assert {:ok, %{runner_name: runner_name}} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
      assert String.starts_with?(runner_name, "pod-1-")
    end
  end
end
