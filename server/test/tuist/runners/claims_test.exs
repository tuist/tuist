defmodule Tuist.Runners.ClaimsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.Claim
  alias Tuist.Runners.Claims
  alias Tuist.Runners.ConcurrencyLimit
  alias Tuist.Runners.JobCompletion

  @linux_resources %{platform: :linux, vcpus: 1, memory_gb: 1}

  describe "attempt/5" do
    test "claims a workflow_job and returns the claim" do
      account = account_fixture()

      assert {:ok, %Claim{} = claim} =
               Claims.attempt(1001, account.id, "fleet-a", "pod-1", @linux_resources)

      assert claim.workflow_job_id == 1001
      assert claim.account_id == account.id
      assert claim.fleet_name == "fleet-a"
      assert claim.pod_name == "pod-1"
      assert claim.platform == :linux
      assert claim.vcpus == 1
      assert claim.memory_gb == 1
      assert claim.lifecycle_state == "claimed"
      assert %DateTime{} = claim.claimed_at
    end

    test "returns :lost_race on a duplicate workflow_job_id" do
      account = account_fixture()

      assert {:ok, _} = Claims.attempt(1002, account.id, "fleet-a", "pod-1", @linux_resources)
      assert {:error, :lost_race} = Claims.attempt(1002, account.id, "fleet-a", "pod-2", @linux_resources)
    end

    test "returns :pod_in_use when the same pod already has a live claim" do
      account = account_fixture()

      assert {:ok, _} = Claims.attempt(1300, account.id, "fleet-a", "pod-1", @linux_resources)

      # A customer-controlled workflow inside the VM that reads
      # /etc/tuist-sa-token and calls dispatch again must not be
      # able to claim a second job while the first is still
      # active — the live claim makes this fail-closed.
      assert {:error, :pod_in_use} = Claims.attempt(1301, account.id, "fleet-a", "pod-1", @linux_resources)
    end

    test "enforces pod ownership across accounts" do
      first_account = account_fixture()
      second_account = account_fixture()

      assert {:ok, _} = Claims.attempt(1310, first_account.id, "fleet-a", "shared-pod", @linux_resources)

      assert {:error, :pod_in_use} =
               Claims.attempt(1311, second_account.id, "fleet-a", "shared-pod", @linux_resources)
    end

    test "rejects invalid claim inputs" do
      account = account_fixture()

      assert {:error, :invalid_resources} =
               Claims.attempt(0, account.id, "fleet-a", "pod-1", @linux_resources)

      assert {:error, :invalid_resources} =
               Claims.attempt(1320, account.id, "", "pod-1", @linux_resources)

      assert {:error, :invalid_resources} =
               Claims.attempt(1320, account.id, "fleet-a", "pod-1", %{
                 platform: :linux,
                 vcpus: 0,
                 memory_gb: 1
               })
    end

    test "atomically rejects a shape that would exceed a platform budget" do
      account = account_fixture()
      macos_resources = %{platform: :macos, vcpus: 6, memory_gb: 14}

      assert {:ok, _} = Claims.attempt(1400, account.id, "fleet-macos", "pod-1", macos_resources)
      assert {:ok, _} = Claims.attempt(1401, account.id, "fleet-macos", "pod-2", macos_resources)

      assert {:error, {:concurrency_limit_reached, details}} =
               Claims.attempt(1402, account.id, "fleet-macos", "pod-3", macos_resources)

      assert details.platform == :macos
      assert details.used == %{vcpus: 12, memory_gb: 28}
      assert details.limit == %{vcpus: 12, memory_gb: 28}
      assert details.requested == macos_resources
      assert Claims.counts_per_account() == %{account.id => 2}
    end

    test "keeps Linux and macOS budgets independent" do
      account = account_fixture()
      macos_resources = %{platform: :macos, vcpus: 12, memory_gb: 28}
      linux_resources = %{platform: :linux, vcpus: 2, memory_gb: 8}

      assert {:ok, _} = Claims.attempt(1450, account.id, "fleet-macos", "pod-macos", macos_resources)
      assert {:ok, _} = Claims.attempt(1451, account.id, "fleet-linux", "pod-linux", linux_resources)
    end

    test "derives resources for live claims written by an old replica" do
      account = account_fixture()
      now = DateTime.utc_now()

      {1, _} =
        Repo.insert_all(Claim, [
          %{
            workflow_job_id: 1455,
            account_id: account.id,
            fleet_name: "macos-26-5",
            pod_name: "legacy-pod",
            claimed_at: now,
            platform: :linux,
            vcpus: 0,
            memory_gb: 0,
            lifecycle_state: "running",
            runner_name: "legacy-runner"
          }
        ])

      assert {:error, {:concurrency_limit_reached, details}} =
               Claims.attempt(1456, account.id, "macos-26-5", "new-pod", %{
                 platform: :macos,
                 vcpus: 12,
                 memory_gb: 28
               })

      assert details.used == %{vcpus: 6, memory_gb: 14}
      refute Repo.exists?(from(claim in Claim, where: claim.workflow_job_id == 1456))
    end

    test "fails closed when a platform limit row is missing" do
      account = account_fixture()

      Repo.delete_all(
        from(limit in ConcurrencyLimit,
          where: limit.account_id == ^account.id and limit.platform == :linux
        )
      )

      assert {:error, :concurrency_limit_missing} =
               Claims.attempt(1460, account.id, "fleet-linux", "pod-linux", @linux_resources)

      refute Repo.exists?(from(claim in Claim, where: claim.workflow_job_id == 1460))
    end
  end

  describe "mark_running/2" do
    test "promotes a claimed row to running" do
      account = account_fixture()
      {:ok, _} = Claims.attempt(1500, account.id, "fleet-a", "pod-1", @linux_resources)

      assert :ok = Claims.mark_running(1500, "runner-abc")

      row = Repo.one(from(c in Claim, where: c.workflow_job_id == ^1500))
      assert row.lifecycle_state == "running"
      assert row.runner_name == "runner-abc"
    end

    test "is a no-op when the row is gone" do
      assert :ok = Claims.mark_running(9_999_999, "runner-x")
    end
  end

  describe "release/2" do
    test "deletes a claim when (workflow_job_id, claimed_at) match" do
      account = account_fixture()
      {:ok, claim} = Claims.attempt(2001, account.id, "fleet-a", "pod-1", @linux_resources)

      assert :ok = Claims.release(claim.workflow_job_id, claim.claimed_at)
      assert Claims.counts_per_account() == %{}
    end

    test "returns :stale_claim when claimed_at has moved on" do
      account = account_fixture()
      {:ok, _claim} = Claims.attempt(2002, account.id, "fleet-a", "pod-1", @linux_resources)

      # Pretend the worker released and someone re-claimed with a
      # fresh handle — original serve's release shouldn't stomp.
      stale_handle = DateTime.add(DateTime.utc_now(), -3600, :second)

      assert {:error, :stale_claim} = Claims.release(2002, stale_handle)
      # Original claim is still there.
      assert Claims.counts_per_account() == %{account.id => 1}
    end

    test "returns :stale_claim when the row is gone" do
      assert {:error, :stale_claim} = Claims.release(9_999_999, DateTime.utc_now())
    end
  end

  describe "counts_per_account/0" do
    test "returns per-account inflight counts across ALL fleets" do
      a = account_fixture()
      b = account_fixture()

      {:ok, _} = Claims.attempt(3001, a.id, "fleet-cnt", "pod-a-1", @linux_resources)
      {:ok, _} = Claims.attempt(3002, a.id, "fleet-cnt", "pod-a-2", @linux_resources)
      {:ok, _} = Claims.attempt(3003, b.id, "fleet-cnt", "pod-b-1", @linux_resources)
      # The count is account-level, so this fourth claim on a
      # different fleet must still roll up to account `a`'s total.
      {:ok, _} = Claims.attempt(3004, a.id, "fleet-other", "pod-a-3", @linux_resources)

      counts = Claims.counts_per_account()
      assert Map.get(counts, a.id) == 3
      assert Map.get(counts, b.id) == 1
    end

    test "returns empty map when nothing is in flight" do
      assert Claims.counts_per_account() == %{}
    end
  end

  describe "counts_per_fleet/0" do
    test "returns per-fleet inflight counts across ALL accounts" do
      a = account_fixture()
      b = account_fixture()

      {:ok, _} = Claims.attempt(6001, a.id, "fleet-macos", "pod-m-1", @linux_resources)
      {:ok, _} = Claims.attempt(6002, a.id, "fleet-macos", "pod-m-2", @linux_resources)
      {:ok, _} = Claims.attempt(6003, b.id, "fleet-linux", "pod-l-1", @linux_resources)

      counts = Claims.counts_per_fleet()
      assert Map.get(counts, "fleet-macos") == 2
      assert Map.get(counts, "fleet-linux") == 1
    end

    test "returns empty map when nothing is in flight" do
      assert Claims.counts_per_fleet() == %{}
    end
  end

  describe "workflow_job_ids_for_fleet/1" do
    test "returns active workflow_job IDs for one fleet" do
      account = account_fixture()

      {:ok, _} = Claims.attempt(6101, account.id, "fleet-a", "pod-a-1", @linux_resources)
      {:ok, _} = Claims.attempt(6102, account.id, "fleet-a", "pod-a-2", @linux_resources)
      {:ok, _} = Claims.attempt(6103, account.id, "fleet-b", "pod-b-1", @linux_resources)

      assert "fleet-a" |> Claims.workflow_job_ids_for_fleet() |> Enum.sort() == [6101, 6102]
    end
  end

  describe "complete/1" do
    test "deletes the claim regardless of handle" do
      account = account_fixture()
      {:ok, _} = Claims.attempt(5001, account.id, "fleet-c", "pod-1", @linux_resources)

      assert :ok = Claims.complete(5001)
      assert Claims.counts_per_account() == %{}
    end

    test "is idempotent for unknown workflow_job_id" do
      assert :ok = Claims.complete(9_999_999)
    end
  end

  describe "list_stale/1" do
    test "returns claimed rows older than the threshold without deleting" do
      account = account_fixture()
      {:ok, _} = Claims.attempt(4001, account.id, "fleet-stale", "pod-1", @linux_resources)
      {:ok, _} = Claims.attempt(4002, account.id, "fleet-stale", "pod-2", @linux_resources)

      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      stale = Claims.list_stale(future)

      assert length(stale) == 2
      ids = stale |> Enum.map(& &1.workflow_job_id) |> Enum.sort()
      assert ids == [4001, 4002]
      # Rows are still in place — the caller will release each
      # via Claims.release/2 after writing the CH transition.
      assert Claims.counts_per_account() == %{account.id => 2}
    end

    test "skips claims that already transitioned to running" do
      account = account_fixture()
      {:ok, _} = Claims.attempt(4200, account.id, "fleet-running", "pod-1", @linux_resources)
      {:ok, _} = Claims.attempt(4201, account.id, "fleet-running", "pod-2", @linux_resources)

      # One claim is healthy and running for hours — must NOT be
      # reaped just because it's older than the threshold, since
      # the slot belongs to a real GitHub runner.
      :ok = Claims.mark_running(4200, "runner-long")

      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      stale = Claims.list_stale(future)

      ids = stale |> Enum.map(& &1.workflow_job_id) |> Enum.sort()
      assert ids == [4201]
    end

    test "leaves fresh claims alone" do
      account = account_fixture()
      {:ok, _} = Claims.attempt(4101, account.id, "fleet-fresh", "pod-1", @linux_resources)

      past = DateTime.add(DateTime.utc_now(), -3600, :second)
      assert [] = Claims.list_stale(past)
      assert Claims.counts_per_account() == %{account.id => 1}
    end
  end

  describe "live_pod_names/0" do
    test "returns the pod names of every live claim, claimed and running alike" do
      account = account_fixture()
      {:ok, _} = Claims.attempt(5001, account.id, "fleet-a", "pod-claimed", @linux_resources)
      {:ok, _} = Claims.attempt(5002, account.id, "fleet-a", "pod-running", @linux_resources)
      :ok = Claims.mark_running(5002, "runner-x")

      assert Claims.live_pod_names() == MapSet.new(["pod-claimed", "pod-running"])
    end

    test "is empty when there are no claims" do
      assert Claims.live_pod_names() == MapSet.new()
    end
  end

  describe "complete_by_runner_name/1" do
    test "releases the claim held by the runner that actually ran the job" do
      account = account_fixture()
      {:ok, _} = Claims.attempt(6001, account.id, "fleet-a", "pod-1", @linux_resources)
      :ok = Claims.mark_running(6001, "runner-x")

      assert 1 == Claims.complete_by_runner_name("runner-x", account.id)
      assert Claims.counts_per_account() == %{}
    end

    test "does not free a runner still executing a job it did not claim" do
      # The issue's scenario: A claims J1, B claims J2, GitHub runs J1
      # on B. J2's completion must NOT release B's slot — B is live and
      # executing J1. Releasing by the completed job's id would.
      account = account_fixture()
      {:ok, _} = Claims.attempt(6200, account.id, "fleet-a", "pod-a", @linux_resources)
      :ok = Claims.mark_running(6200, "runner-a")
      {:ok, _} = Claims.attempt(6201, account.id, "fleet-a", "pod-b", @linux_resources)
      :ok = Claims.mark_running(6201, "runner-b")

      # J2 (6201) was cancelled while queued: no runner ever ran it, so
      # the payload carries no runner_name and nothing is released.
      assert 0 == Claims.complete_by_runner_name("", account.id)

      # Both runners still counted: both Pods are alive, and B is
      # executing J1.
      assert Claims.counts_per_account() == %{account.id => 2}

      # J1 completes on runner-b — the executor's slot is the one freed.
      assert 1 == Claims.complete_by_runner_name("runner-b", account.id)
      assert Claims.counts_per_account() == %{account.id => 1}
    end

    test "is idempotent when the runner's claim is already gone" do
      account = account_fixture()
      assert 0 == Claims.complete_by_runner_name("ghost-runner", account.id)
    end

    test "never releases a colliding runner_name belonging to another account" do
      # Runner names are only unique within an account: any org can name
      # its own self-hosted runners whatever it likes, and its webhooks
      # authenticate as its own installation. A collision must not let
      # one account's delivery free another account's live claim.
      victim = account_fixture()
      attacker = account_fixture()
      {:ok, _} = Claims.attempt(9100, victim.id, "fleet-a", "victim-pod", @linux_resources)
      :ok = Claims.mark_running(9100, "shared-name")

      assert 0 == Claims.complete_by_runner_name("shared-name", attacker.id)
      assert Claims.counts_per_account() == %{victim.id => 1}

      assert 1 == Claims.complete_by_runner_name("shared-name", victim.id)
      assert Claims.counts_per_account() == %{}
    end
  end

  describe "release_by_pod_name/1" do
    test "deletes the claim held by the pod and returns the count freed" do
      account = account_fixture()
      {:ok, _} = Claims.attempt(9001, account.id, "fleet-a", "pod-1", @linux_resources)
      :ok = Claims.mark_running(9001, "runner-x")

      assert 1 == Claims.release_by_pod_name("pod-1")
      assert Claims.counts_per_account() == %{}
    end

    test "frees a stranded running claim regardless of lifecycle state" do
      account = account_fixture()
      {:ok, _} = Claims.attempt(9002, account.id, "fleet-a", "pod-2", @linux_resources)
      # never minted — still `claimed`; a Pod that stopped pre-mint.
      assert 1 == Claims.release_by_pod_name("pod-2")
    end

    test "returns 0 when the pod holds no claim (already completed before stop)" do
      assert 0 == Claims.release_by_pod_name("idle-pod")
    end

    test "is a no-op for an empty pod_name" do
      assert 0 == Claims.release_by_pod_name("")
    end
  end

  describe "executing?/1" do
    test "is true once GitHub proved the runner took some job" do
      account = account_fixture()
      {:ok, _} = Claims.attempt(7300, account.id, "fleet-a", "pod-1", @linux_resources)
      :ok = Claims.mark_running(7300, "runner-a")

      refute Claims.executing?(7300)

      # GitHub handed this runner a sibling's job, not the one it claimed.
      assert :mismatch = Claims.record_execution("runner-a", 7399, account.id)
      assert Claims.executing?(7300)
    end

    test "is false for a claim with no proven execution, or no claim at all" do
      account = account_fixture()
      {:ok, _} = Claims.attempt(7301, account.id, "fleet-a", "pod-2", @linux_resources)

      refute Claims.executing?(7301)
      refute Claims.executing?(999_999)
    end
  end

  describe "record_execution/2" do
    test "binds the executed job and reports :matched when it equals the claim" do
      account = account_fixture()
      {:ok, _} = Claims.attempt(7001, account.id, "fleet-a", "pod-1", @linux_resources)
      :ok = Claims.mark_running(7001, "runner-a")

      assert :matched = Claims.record_execution("runner-a", 7001, account.id)

      row = Repo.one(from(c in Claim, where: c.workflow_job_id == ^7001))
      assert row.executed_workflow_job_id == 7001
    end

    test "reports :mismatch and binds the real job when GitHub ran a different one" do
      account = account_fixture()
      {:ok, _} = Claims.attempt(7002, account.id, "fleet-a", "pod-1", @linux_resources)
      :ok = Claims.mark_running(7002, "runner-b")

      assert :mismatch = Claims.record_execution("runner-b", 7099, account.id)

      row = Repo.one(from(c in Claim, where: c.workflow_job_id == ^7002))
      assert row.executed_workflow_job_id == 7099
    end

    test "reports :unknown_runner when no live claim carries the runner_name" do
      account = account_fixture()
      assert :unknown_runner = Claims.record_execution("ghost-runner", 7100, account.id)
    end

    test "is a no-op for an empty runner_name" do
      account = account_fixture()
      assert :unknown_runner = Claims.record_execution("", 7101, account.id)
    end

    test "never binds a colliding runner_name belonging to another account" do
      victim = account_fixture()
      attacker = account_fixture()
      {:ok, _} = Claims.attempt(7200, victim.id, "fleet-a", "victim-pod", @linux_resources)
      :ok = Claims.mark_running(7200, "shared-name")

      assert :unknown_runner = Claims.record_execution("shared-name", 7299, attacker.id)
      assert Repo.one(from(c in Claim, where: c.workflow_job_id == ^7200)).executed_workflow_job_id == nil
    end
  end

  describe "by_workflow_job_id/1" do
    test "resolves the live claim for a workflow_job_id" do
      account = account_fixture()

      {:ok, _} =
        Claims.attempt(6201, account.id, "fleet-a", "pod-1", %{
          platform: :linux,
          vcpus: 4,
          memory_gb: 8
        })

      :ok = Claims.mark_running(6201, "runner-x")

      assert {:ok,
              %{
                workflow_job_id: 6201,
                account_id: account_id,
                fleet_name: "fleet-a",
                pod_name: "pod-1"
              }} = Claims.by_workflow_job_id(6201)

      assert account_id == account.id
    end

    test "returns :error when no live claim exists for the workflow_job_id" do
      assert Claims.by_workflow_job_id(9_999_999) == :error
    end
  end

  describe "release_completed/1" do
    defp completion_fixture(workflow_job_id, account) do
      Repo.insert_all(JobCompletion, [
        %{
          workflow_job_id: workflow_job_id,
          account_id: account.id,
          conclusion: "success",
          completed_at: DateTime.truncate(DateTime.utc_now(), :second),
          inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
          updated_at: DateTime.truncate(DateTime.utc_now(), :second)
        }
      ])
    end

    defp backdate_claim(workflow_job_id, seconds) do
      Repo.update_all(
        from(c in Claim, where: c.workflow_job_id == ^workflow_job_id),
        set: [claimed_at: DateTime.add(DateTime.utc_now(), -seconds, :second)]
      )
    end

    # The leak this exists for: the completion webhook recorded the job as
    # finished but the claim survived, so the slot stayed consumed. It sits
    # in `running`, which the time-based sweep must never touch, and its
    # ClickHouse row has already left `status = 'running'`, so the orphan
    # worker's scan cannot see it either.
    test "releases a running claim whose job has a recorded completion" do
      account = account_fixture()

      assert {:ok, _} = Claims.attempt(7001, account.id, "fleet-a", "pod-1", @linux_resources)
      assert :ok = Claims.mark_running(7001, "runner-1")
      completion_fixture(7001, account)
      backdate_claim(7001, 600)

      assert Claims.release_completed(DateTime.add(DateTime.utc_now(), -300, :second)) == 1
      refute Repo.exists?(from(c in Claim, where: c.workflow_job_id == 7001))
    end

    # The discriminator has to be the completion row, not age. A long build
    # legitimately holds its slot for hours, and reaping it would push the
    # account over its cap while a runner is still working.
    test "leaves a running claim with no recorded completion" do
      account = account_fixture()

      assert {:ok, _} = Claims.attempt(7002, account.id, "fleet-a", "pod-1", @linux_resources)
      assert :ok = Claims.mark_running(7002, "runner-1")
      backdate_claim(7002, 86_400)

      assert Claims.release_completed(DateTime.add(DateTime.utc_now(), -300, :second)) == 0
      assert Repo.exists?(from(c in Claim, where: c.workflow_job_id == 7002))
    end

    # The threshold only avoids racing the webhook's own release between
    # the completion insert and the delete. It is not the staleness signal.
    test "leaves a freshly claimed row inside the grace window" do
      account = account_fixture()

      assert {:ok, _} = Claims.attempt(7003, account.id, "fleet-a", "pod-1", @linux_resources)
      completion_fixture(7003, account)

      assert Claims.release_completed(DateTime.add(DateTime.utc_now(), -300, :second)) == 0
      assert Repo.exists?(from(c in Claim, where: c.workflow_job_id == 7003))
    end

    test "releases every stale claim and frees the account's capacity" do
      account = account_fixture()

      for id <- [7101, 7102, 7103] do
        assert {:ok, _} = Claims.attempt(id, account.id, "fleet-a", "pod-#{id}", @linux_resources)
        assert :ok = Claims.mark_running(id, "runner-#{id}")
        completion_fixture(id, account)
        backdate_claim(id, 600)
      end

      assert {:ok, _} = Claims.attempt(7104, account.id, "fleet-a", "pod-live", @linux_resources)

      assert Claims.release_completed(DateTime.add(DateTime.utc_now(), -300, :second)) == 3

      remaining = Repo.all(from(c in Claim, select: c.workflow_job_id))
      assert remaining == [7104]
    end

    # The trap this nearly walked into. GitHub hands a queued job to any
    # label-eligible runner, so the Pod that claimed job A is frequently
    # executing job B. Releasing on A's completion alone would delete a
    # live runner's reservation mid-job and push the account over cap.
    # Production had two claims in exactly this shape.
    test "leaves a claim whose runner is executing an unfinished job" do
      account = account_fixture()

      assert {:ok, _} = Claims.attempt(7201, account.id, "fleet-a", "pod-1", @linux_resources)
      assert :ok = Claims.mark_running(7201, "runner-busy")
      assert :mismatch = Claims.record_execution("runner-busy", 7299, account.id)

      # The CLAIMED job finished; the job the runner actually took has not.
      completion_fixture(7201, account)
      backdate_claim(7201, 86_400)

      assert Claims.release_completed(DateTime.add(DateTime.utc_now(), -300, :second)) == 0
      assert Repo.exists?(from(c in Claim, where: c.workflow_job_id == 7201))
    end

    # Once the executed job finishes too, the runner has nothing left and
    # the slot is genuinely leaked, so it must be reclaimed.
    test "releases once both the claimed and executed jobs are complete" do
      account = account_fixture()

      assert {:ok, _} = Claims.attempt(7202, account.id, "fleet-a", "pod-1", @linux_resources)
      assert :ok = Claims.mark_running(7202, "runner-done")
      assert :mismatch = Claims.record_execution("runner-done", 7298, account.id)

      completion_fixture(7202, account)
      completion_fixture(7298, account)
      backdate_claim(7202, 600)

      assert Claims.release_completed(DateTime.add(DateTime.utc_now(), -300, :second)) == 1
      refute Repo.exists?(from(c in Claim, where: c.workflow_job_id == 7202))
    end

    test "is a no-op when nothing is held past a completion" do
      assert Claims.release_completed(DateTime.utc_now()) == 0
    end
  end
end
