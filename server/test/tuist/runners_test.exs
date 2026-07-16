defmodule Tuist.RunnersTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners
  alias Tuist.Runners.CacheGrant
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.VolumeAffinities
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

    spec =
      then(%{"containers" => [%{"name" => "runner", "image" => image}]}, fn spec ->
        case Keyword.get(opts, :node_name) do
          node when is_binary(node) -> Map.put(spec, "nodeName", node)
          _ -> spec
        end
      end)

    %{
      "metadata" => %{"name" => pod_name, "namespace" => "tuist-runners", "labels" => labels},
      "spec" => spec
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

    test "downgrades transient k8s Pod lookup failure to :ok and proceeds with dispatch" do
      # Refusing to dispatch on a transient k8s blip would stall the
      # whole pool. The Pod fetch (commitment + staleness) is opportunistic,
      # not a correctness gate; the reconciler's Pending-stale path catches
      # the unhappy long-tail. On a `get_pod` error we fall through to the
      # normal claim path.
      expect(K8sClient, :get_service_account, fn "tuist-runners", "pod-1" ->
        {:ok, sa_with_pool_label("pod-1", "fleet-a")}
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

      expect(K8sClient, :get_pod, fn "tuist-runners", "pod-1" ->
        {:ok, pod_with_image("pod-1", "ghcr.io/tuist/tuist-runner@sha256:current")}
      end)

      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
        {:error, :not_found}
      end)

      assert {:error, :no_work_yet} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
    end

    test "reaps a committed-but-polling Pod (its dispatch response was lost)" do
      # The account label is stamped only after a dispatch commits. A committed
      # Pod polling again means it never received its JIT — it must be replaced,
      # not handed a second account on the cache materialized for the first.
      committed_pod = %{
        "metadata" => %{
          "name" => "pod-1",
          "namespace" => "tuist-runners",
          "labels" => %{"tuist.dev/runner-account" => "42"}
        },
        "spec" => %{"containers" => [%{"name" => "runner", "image" => "img"}]}
      }

      expect(K8sClient, :get_service_account, fn "tuist-runners", "pod-1" ->
        {:ok, sa_with_pool_label("pod-1", "fleet-a")}
      end)

      expect(K8sClient, :get_pod, fn "tuist-runners", "pod-1" -> {:ok, committed_pod} end)

      # No claim is attempted; the Pod is refused so the guest halts (410).
      reject(&Claims.attempt/5)

      assert {:error, :pod_committed} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
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
        platform: "linux",
        vcpus: 4,
        memory_gb: 16,
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

      node_name = Keyword.get(opts, :node_name)
      image = "ghcr.io/tuist/tuist-runner@sha256:current"

      # check_not_stale fetches the Pod first (to reject committed Pods), so the
      # Pod is always read. It carries no account label, so it is not committed.
      expect(K8sClient, :get_pod, fn "tuist-runners", ^pod_name ->
        {:ok, pod_with_image(pod_name, image, node_name: node_name)}
      end)

      expect(K8sClient, :get_service_account, fn "tuist-runners", ^pod_name ->
        {:ok, sa_with_pool_label(pod_name, "fleet-a")}
      end)

      if node_name do
        # Image-match path so the staleness check reads the Pod's spec.nodeName
        # and threads it into the affinity scoring.
        expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
          {:ok, pool_with_image(image)}
        end)
      else
        # Missing RunnerPool downgrades the stale-image check to the Pod's node
        # (nil here, since this Pod has no spec.nodeName) — no affinity.
        expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
          {:error, :not_found}
        end)
      end

      expect(Claims, :workflow_job_ids_for_fleet, fn "fleet-a" -> excluded_workflow_job_ids end)

      expect(Jobs, :pick_queued_top_k, fn "fleet-a", [], ^excluded_workflow_job_ids, _k -> {:ok, [candidate]} end)

      expect(Claims, :attempt, fn ^workflow_job_id, _account_id, "fleet-a", ^pod_name, resources ->
        assert resources == %{platform: :linux, vcpus: 4, memory_gb: 16}
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

      # Trust check: default to a same-repo (trusted) run so the cache path runs.
      # Fork/fail-closed cases override this stub in their own tests.
      stub(GitHubClient, :get_workflow_run, fn %{repository_full_handle: repo} ->
        {:ok, %{"head_repository" => %{"full_name" => repo}, "repository" => %{"full_name" => repo}}}
      end)

      expect(GitHubClient, :generate_jit_config, fn _installation, login, %{labels: labels, name: runner_name} ->
        send(test_pid, {:jit_labels, labels})
        send(test_pid, {:jit_runner_name, runner_name})
        send(test_pid, {:jit_login, login})
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

    test "includes the minted cache signing grant in the dispatch result" do
      account = account_fixture()
      candidate = candidate_with_label(account, "tuist-default")
      stub_dispatch_path(account, candidate, self())

      expect(CacheGrant, :mint, fn account_id ->
        assert account_id == account.id
        "signed-grant-token"
      end)

      assert {:ok, %{cache_signing_grant: "signed-grant-token"}} =
               Runners.dispatch_for_sa("tuist-runners", "pod-1")
    end

    test "excludes an untrusted fork job from the cache (no grant, no HEAD, untrusted label)" do
      account = account_fixture()
      candidate = candidate_with_label(account, "tuist-default")
      test_pid = self()
      stub_dispatch_path(account, candidate, test_pid)

      # Fork: the run's head repository differs from the base repository.
      stub(GitHubClient, :get_workflow_run, fn %{repository_full_handle: repo} ->
        {:ok, %{"head_repository" => %{"full_name" => "attacker/#{repo}"}, "repository" => %{"full_name" => repo}}}
      end)

      stub(K8sClient, :patch_pod, fn _ns, _pod, patch ->
        send(test_pid, {:patched, get_in(patch, ["metadata", "labels"])})
        {:ok, %{}}
      end)

      # An untrusted job must never get a grant nor a volume HEAD.
      reject(&CacheGrant.mint/1)

      assert {:ok, result} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
      assert result.cache_signing_grant == nil
      assert result.volume_head == nil
      assert_receive {:patched, %{"tuist.dev/runner-cache-untrusted" => "true"}}
    end

    test "treats a job as untrusted (cold) when the workflow-run lookup fails, fail-closed" do
      account = account_fixture()
      candidate = candidate_with_label(account, "tuist-default")
      stub_dispatch_path(account, candidate, self())

      stub(GitHubClient, :get_workflow_run, fn _ -> {:error, "boom"} end)
      reject(&CacheGrant.mint/1)

      assert {:ok, result} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
      assert result.cache_signing_grant == nil
      assert result.volume_head == nil
    end

    test "records volume affinity for the polling node on a successful claim" do
      account = account_fixture()
      candidate = candidate_with_label(account, "tuist-default")
      test_pid = self()
      stub_dispatch_path(account, candidate, test_pid, node_name: "mac-07")

      # Affinity is macOS-only (only the Mac fleet holds cache masters), so the
      # fleet must resolve to :macos for record/select to run at all.
      stub(Catalog, :fleet_platform, fn _ -> :macos end)

      expect(VolumeAffinities, :record, fn "mac-07", account_id ->
        send(test_pid, {:affinity_recorded, account_id})
        :ok
      end)

      # With a single candidate the affinity scoring returns the head; the
      # point here is that node identity is threaded through and the claim
      # records affinity for that node.
      expect(VolumeAffinities, :select_candidate, fn [^candidate], "mac-07", _tolerance -> candidate end)

      assert {:ok, _} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
      assert_receive {:affinity_recorded, recorded_account_id}
      assert recorded_account_id == account.id
    end

    test "does not record volume affinity for a non-macOS fleet" do
      account = account_fixture()
      candidate = candidate_with_label(account, "tuist-default")
      stub_dispatch_path(account, candidate, self(), node_name: "linux-01")

      # Linux runners hold no cache masters, so affinity must not reorder or
      # record for them — the plain oldest-queued head is dispatched.
      stub(Catalog, :fleet_platform, fn _ -> :linux end)
      reject(&VolumeAffinities.record/2)

      assert {:ok, %{workflow_job_id: 90_001}} = Runners.dispatch_for_sa("tuist-runners", "pod-1")
    end

    test "registers the runner under the repo's GitHub org login, not the Tuist account handle" do
      account = account_fixture()
      # The Tuist handle differs from the GitHub org that owns the repo.
      # The org-scoped JIT endpoint must be hit with the GitHub org login
      # (repo owner), or GitHub 404s and the job churns.
      candidate =
        account
        |> candidate_with_label("tuist-default")
        |> Map.put(:repository, "octo-github-org/mobile-app")

      stub_dispatch_path(account, candidate, self())

      assert {:ok, _} = Runners.dispatch_for_sa("tuist-runners", "pod-1")

      assert_receive {:jit_login, "octo-github-org"}
      refute account.name == "octo-github-org"
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

      # check_not_stale fetches the (uncommitted) Pod first, then the pool.
      expect(K8sClient, :get_pod, fn "tuist-runners", ^pod_name ->
        {:ok, pod_with_image(pod_name, "img")}
      end)

      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
        {:error, :not_found}
      end)

      expect(Claims, :workflow_job_ids_for_fleet, fn "fleet-a" -> [] end)

      expect(Jobs, :pick_queued_top_k, fn "fleet-a", [], [], _k -> {:ok, [stale_candidate]} end)

      expect(Claims, :attempt, fn 90_001, _account_id, "fleet-a", ^pod_name, _resources ->
        {:error, :lost_race}
      end)

      expect(Jobs, :pick_queued_top_k, fn "fleet-a", [], [90_001], _k -> {:ok, [candidate]} end)

      expect(Claims, :attempt, fn 90_002, _account_id, "fleet-a", ^pod_name, _resources ->
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

    test "skips all queued work for an account that reached its platform limit" do
      capped_account = account_fixture()
      other_account = account_fixture()
      capped_candidate = candidate_with_label(capped_account, "tuist-default", workflow_job_id: 91_001)
      other_candidate = candidate_with_label(other_account, "tuist-default", workflow_job_id: 91_002)
      pod_name = "pod-1"

      expect(K8sClient, :get_service_account, fn "tuist-runners", ^pod_name ->
        {:ok, sa_with_pool_label(pod_name, "fleet-a")}
      end)

      expect(K8sClient, :get_pod, fn "tuist-runners", ^pod_name ->
        {:ok, pod_with_image(pod_name, "ghcr.io/tuist/tuist-runner@sha256:current")}
      end)

      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
        {:error, :not_found}
      end)

      expect(Claims, :workflow_job_ids_for_fleet, fn "fleet-a" -> [] end)
      expect(Jobs, :pick_queued_top_k, fn "fleet-a", [], [], _k -> {:ok, [capped_candidate]} end)

      expect(Claims, :attempt, fn 91_001, account_id, "fleet-a", ^pod_name, resources ->
        assert account_id == capped_account.id

        {:error,
         {:concurrency_limit_reached,
          %{
            platform: :linux,
            requested: resources,
            used: %{vcpus: 32, memory_gb: 64},
            limit: %{vcpus: 32, memory_gb: 64}
          }}}
      end)

      expect(Jobs, :pick_queued_top_k, fn "fleet-a", excluded_account_ids, [], _k ->
        assert excluded_account_ids == [capped_account.id]
        assert other_candidate.account_id == other_account.id
        {:error, :empty}
      end)

      assert {:error, :no_work_yet} = Runners.dispatch_for_sa("tuist-runners", pod_name)
    end

    test "skips a busy account without consuming the lost-race retry budget" do
      busy_account = account_fixture()
      busy_candidate = candidate_with_label(busy_account, "tuist-default", workflow_job_id: 91_010)
      pod_name = "pod-1"

      expect(K8sClient, :get_service_account, fn "tuist-runners", ^pod_name ->
        {:ok, sa_with_pool_label(pod_name, "fleet-a")}
      end)

      expect(K8sClient, :get_pod, fn "tuist-runners", ^pod_name ->
        {:ok, pod_with_image(pod_name, "ghcr.io/tuist/tuist-runner@sha256:current")}
      end)

      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
        {:error, :not_found}
      end)

      expect(Claims, :workflow_job_ids_for_fleet, fn "fleet-a" -> [] end)
      expect(Jobs, :pick_queued_top_k, fn "fleet-a", [], [], _k -> {:ok, [busy_candidate]} end)

      expect(Claims, :attempt, fn 91_010, account_id, "fleet-a", ^pod_name, _resources ->
        assert account_id == busy_account.id
        {:error, :account_busy}
      end)

      expect(Jobs, :pick_queued_top_k, fn "fleet-a", excluded_account_ids, [], _k ->
        assert excluded_account_ids == [busy_account.id]
        {:error, :empty}
      end)

      assert {:error, :no_work_yet} = Runners.dispatch_for_sa("tuist-runners", pod_name)
    end

    test "capped accounts do not exhaust the retry budget before eligible work" do
      capped_candidates =
        Enum.map(1..16, fn index ->
          account = account_fixture()
          candidate_with_label(account, "tuist-default", workflow_job_id: 92_000 + index)
        end)

      eligible_account = account_fixture()
      eligible_candidate = candidate_with_label(eligible_account, "tuist-default", workflow_job_id: 92_017)
      candidates = capped_candidates ++ [eligible_candidate]
      capped_account_ids = MapSet.new(capped_candidates, & &1.account_id)
      pod_name = "pod-1"

      expect(K8sClient, :get_service_account, fn "tuist-runners", ^pod_name ->
        {:ok, sa_with_pool_label(pod_name, "fleet-a")}
      end)

      expect(K8sClient, :get_pod, fn "tuist-runners", ^pod_name ->
        {:ok, pod_with_image(pod_name, "ghcr.io/tuist/tuist-runner@sha256:current")}
      end)

      expect(K8sClient, :get_runner_pool, fn "tuist-runners", "fleet-a" ->
        {:error, :not_found}
      end)

      expect(Claims, :workflow_job_ids_for_fleet, fn "fleet-a" -> [] end)

      expect(Jobs, :pick_queued_top_k, 17, fn "fleet-a", excluded_account_ids, [], _k ->
        candidate = Enum.find(candidates, &(&1.account_id not in excluded_account_ids))
        {:ok, [candidate]}
      end)

      expect(Claims, :attempt, 17, fn workflow_job_id, account_id, "fleet-a", ^pod_name, resources ->
        if MapSet.member?(capped_account_ids, account_id) do
          {:error,
           {:concurrency_limit_reached,
            %{
              platform: :linux,
              requested: resources,
              used: %{vcpus: 32, memory_gb: 64},
              limit: %{vcpus: 32, memory_gb: 64}
            }}}
        else
          assert account_id == eligible_account.id
          assert workflow_job_id == eligible_candidate.workflow_job_id
          {:ok, %{claimed_at: DateTime.utc_now()}}
        end
      end)

      expect(Jobs, :record_claimed, fn ^eligible_candidate, ^pod_name, _claimed_at -> :ok end)

      expect(Dispatch, :pool_summary_by_name, fn "fleet-a" ->
        {:ok, %{dispatch_label: "shape-linux-4vcpu-16gb", runner_labels: ["self-hosted", "Linux", "X64"]}}
      end)

      stub(K8sClient, :patch_pod, fn _ns, _pod, _patch -> {:ok, %{}} end)

      stub(VCS, :get_github_app_installation_for_account, fn account_id ->
        assert account_id == eligible_account.id
        {:ok, %{installation_id: 42, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :generate_jit_config, fn _installation, "acme", %{name: runner_name} ->
        {:ok, %{encoded_jit_config: "jit-blob", runner_name: runner_name}}
      end)

      expect(Claims, :mark_running, fn 92_017, _runner_name -> :ok end)
      expect(Jobs, :record_running, fn 92_017, _runner_name -> :ok end)

      assert {:ok, %{workflow_job_id: 92_017}} =
               Runners.dispatch_for_sa("tuist-runners", pod_name)
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

  describe "account_id_for_sa/2" do
    test "resolves the account from a trusted pod's runner-account label" do
      expect(K8sClient, :get_pod, fn "tuist-runners", "pod-1" ->
        {:ok, %{"metadata" => %{"labels" => %{"tuist.dev/runner-account" => "42"}}}}
      end)

      assert {:ok, 42} = Runners.account_id_for_sa("tuist-runners", "pod-1")
    end

    test "rejects an untrusted (fork) pod so it cannot advance a shared HEAD" do
      expect(K8sClient, :get_pod, fn "tuist-runners", "pod-1" ->
        {:ok,
         %{
           "metadata" => %{
             "labels" => %{
               "tuist.dev/runner-account" => "42",
               "tuist.dev/runner-cache-untrusted" => "true"
             }
           }
         }}
      end)

      assert {:error, :cache_untrusted} = Runners.account_id_for_sa("tuist-runners", "pod-1")
    end

    test "returns :account_unresolved when the label is absent" do
      expect(K8sClient, :get_pod, fn "tuist-runners", "pod-1" ->
        {:ok, %{"metadata" => %{"labels" => %{}}}}
      end)

      assert {:error, :account_unresolved} = Runners.account_id_for_sa("tuist-runners", "pod-1")
    end
  end
end
