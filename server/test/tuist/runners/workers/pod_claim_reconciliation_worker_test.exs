defmodule Tuist.Runners.Workers.PodClaimReconciliationWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query
  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Repo
  alias Tuist.Runners.Claim
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Workers.PodClaimReconciliationWorker

  setup :verify_on_exit!

  setup do
    stub(FunWithFlags, :enabled?, fn :runner_pod_reconciliation_paused -> false end)
    stub(Jobs, :record_queued, fn _workflow_job_id -> :ok end)
    :ok
  end

  @resources %{platform: :linux, vcpus: 1, memory_gb: 1}
  @selector "tuist.dev/runner=true"

  defp pod(name), do: %{"metadata" => %{"name" => name}}

  defp claim_fixture(account, workflow_job_id, pod_name, opts \\ []) do
    {:ok, _} = Claims.attempt(workflow_job_id, account.id, "fleet-a", pod_name, @resources)

    age = Keyword.get(opts, :age_seconds, 3600)

    updates = [claimed_at: DateTime.add(DateTime.utc_now(), -age, :second)]

    updates =
      case Keyword.get(opts, :missing_for_seconds) do
        nil -> updates
        s -> Keyword.put(updates, :pod_missing_since, DateTime.add(DateTime.utc_now(), -s, :second))
      end

    Repo.update_all(from(c in Claim, where: c.workflow_job_id == ^workflow_job_id), set: updates)
  end

  defp claim(workflow_job_id), do: Repo.get(Claim, workflow_job_id)

  describe "guards" do
    # Guard 1. A failed read is indistinguishable from every Pod having
    # vanished. Acting on it would free the whole fleet's capacity.
    test "does nothing when the cluster read fails" do
      account = account_fixture()
      claim_fixture(account, 9001, "pod-1")

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:error, :timeout} end)

      assert :ok = PodClaimReconciliationWorker.perform(%Oban.Job{})
      assert claim(9001).pod_missing_since == nil
    end

    # Guard 2. Zero Pods returned while claims exist means a bad
    # selector, wrong namespace, or an empty cache — not an empty fleet.
    test "does nothing when the read returns no pods at all" do
      account = account_fixture()
      claim_fixture(account, 9002, "pod-1")

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, []} end)

      assert :ok = PodClaimReconciliationWorker.perform(%Oban.Job{})
      assert claim(9002).pod_missing_since == nil
    end

    # Guard 3. A claim is inserted before its Pod is labelled and the
    # read is eventually consistent, so a young claim is legitimately
    # absent and must never be marked.
    test "ignores claims inside the grace window, without even reading the cluster" do
      account = account_fixture()
      claim_fixture(account, 9003, "pod-young", age_seconds: 30)

      # Nothing is eligible, so the worker must not spend an apiserver
      # call at all. Rejecting the mock asserts both the grace window and
      # that a quiet fleet costs nothing.
      reject(&K8sClient.list_pods/2)

      assert :ok = PodClaimReconciliationWorker.perform(%Oban.Job{})
      assert claim(9003).pod_missing_since == nil
    end

    # Guard 4. One absence only starts the clock. Releasing on a single
    # observation would let any transient read free a live runner.
    test "a first absence marks but does not release" do
      account = account_fixture()
      claim_fixture(account, 9004, "pod-gone")

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-other")]} end)

      assert :ok = PodClaimReconciliationWorker.perform(%Oban.Job{})

      assert claim(9004).pod_missing_since
    end

    # Guard 4, the other half. Absence has to be consecutive, so a Pod
    # that reappears resets the clock rather than accumulating toward a
    # release across unrelated blips.
    test "a reappearing pod clears the absence clock" do
      account = account_fixture()
      claim_fixture(account, 9005, "pod-flaky", missing_for_seconds: 240)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-flaky")]} end)

      assert :ok = PodClaimReconciliationWorker.perform(%Oban.Job{})

      assert claim(9005).pod_missing_since == nil
      assert claim(9005)
    end

    # The kill switch has to work without a deploy, so it is checked
    # before anything else the worker does.
    test "does nothing at all while paused" do
      account = account_fixture()
      claim_fixture(account, 9006, "pod-gone", missing_for_seconds: 600)

      stub(FunWithFlags, :enabled?, fn :runner_pod_reconciliation_paused -> true end)
      reject(&K8sClient.list_pods/2)

      assert :ok = PodClaimReconciliationWorker.perform(%Oban.Job{})
      assert claim(9006)
    end
  end

  describe "release" do
    # The behaviour the whole worker exists for: capacity held by a Pod
    # that no longer exists, invisible to every store-keyed sweep.
    test "releases a claim whose pod has been absent past the confirmation window" do
      account = account_fixture()
      claim_fixture(account, 9101, "pod-dead", missing_for_seconds: 600)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodClaimReconciliationWorker.perform(%Oban.Job{})
      assert claim(9101) == nil
    end

    test "leaves a claim whose pod is present" do
      account = account_fixture()
      claim_fixture(account, 9102, "pod-live", missing_for_seconds: 600)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodClaimReconciliationWorker.perform(%Oban.Job{})
      assert claim(9102)
      assert claim(9102).pod_missing_since == nil
    end

    # Absence recorded, but not for long enough yet.
    test "leaves a claim still inside the confirmation window" do
      account = account_fixture()
      claim_fixture(account, 9103, "pod-gone", missing_for_seconds: 60)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodClaimReconciliationWorker.perform(%Oban.Job{})
      assert claim(9103)
    end

    # CH before PG. A Pod can vanish while ClickHouse still reads
    # `claimed`, and deleting the claim first would free the slot while
    # stranding the workflow_job for good, since `pick_queued` only
    # selects `queued` and no claim would remain to recover from.
    test "writes the queued state to ClickHouse before dropping the claim" do
      account = account_fixture()
      claim_fixture(account, 9301, "pod-dead", missing_for_seconds: 600)

      test_pid = self()

      expect(Jobs, :record_queued, fn 9301 ->
        send(test_pid, {:recorded_queued, 9301})
        :ok
      end)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodClaimReconciliationWorker.perform(%Oban.Job{})

      assert_received {:recorded_queued, 9301}
      assert claim(9301) == nil
    end

    # If ClickHouse is unavailable we must keep the claim, so the pair is
    # retried intact rather than half-applied.
    test "keeps the claim when the ClickHouse write fails" do
      account = account_fixture()
      claim_fixture(account, 9302, "pod-dead", missing_for_seconds: 600)

      expect(Jobs, :record_queued, fn 9302 -> raise "clickhouse down" end)
      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodClaimReconciliationWorker.perform(%Oban.Job{})
      assert claim(9302)
    end

    # Guard 5. A wrong-but-plausible read that survives every other
    # check still cannot free everything at once.
    test "caps releases per tick and leaves the remainder for the next one" do
      account = account_fixture()

      for i <- 1..30 do
        claim_fixture(account, 9200 + i, "pod-dead-#{i}", missing_for_seconds: 600)
      end

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodClaimReconciliationWorker.perform(%Oban.Job{})

      remaining = Repo.aggregate(from(c in Claim, where: c.account_id == ^account.id), :count)
      assert remaining == 5
    end
  end
end
