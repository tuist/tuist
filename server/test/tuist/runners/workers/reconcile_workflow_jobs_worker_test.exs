defmodule Tuist.Runners.Workers.ReconcileWorkflowJobsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Runners.Claim
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Job
  alias Tuist.Runners.JobCompletion
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Workers.ReconcileWorkflowJobsWorker
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobs

  @linux %{platform: :linux, vcpus: 1, memory_gb: 1}

  setup :verify_on_exit!

  # A `runner_jobs` row written by code that predates the Postgres
  # lifecycle table — ClickHouse only, no `runner_workflow_jobs` twin.
  defp legacy_ch_row!(account, workflow_job_id, opts) do
    now = DateTime.utc_now()

    row = %{
      workflow_job_id: workflow_job_id,
      account_id: account.id,
      fleet_name: Keyword.get(opts, :fleet, "fleet-legacy"),
      platform: "linux",
      vcpus: 4,
      memory_gb: 16,
      repository: "acme/cli",
      workflow_run_id: workflow_job_id * 10,
      run_attempt: 1,
      workflow_name: "CI",
      job_name: "build",
      head_branch: "main",
      head_sha: "deadbeef",
      requested_dispatch_label: "tuist-linux",
      status: Keyword.fetch!(opts, :status),
      conclusion: Keyword.get(opts, :conclusion, ""),
      enqueued_at: Keyword.get(opts, :enqueued_at, DateTime.add(now, -600, :second)),
      claimed_at: Keyword.get(opts, :claimed_at),
      started_at: Keyword.get(opts, :started_at),
      completed_at: Keyword.get(opts, :completed_at),
      pod_name: Keyword.get(opts, :pod_name, ""),
      runner_name: Keyword.get(opts, :runner_name, ""),
      updated_at: now
    }

    {1, _} = IngestRepo.insert_all(Job, [row])
    :ok
  end

  test "adopts ClickHouse-only non-terminal rows so dispatch and recovery can see them" do
    account = account_fixture()
    started_at = DateTime.add(DateTime.utc_now(), -900, :second)

    :ok = legacy_ch_row!(account, 940_001, status: "queued")

    :ok =
      legacy_ch_row!(account, 940_002,
        status: "running",
        claimed_at: started_at,
        started_at: started_at,
        pod_name: "pod-legacy",
        runner_name: "runner-legacy"
      )

    :ok = legacy_ch_row!(account, 940_003, status: "completed", conclusion: "success")

    assert :ok = perform_job(ReconcileWorkflowJobsWorker, %{})

    queued = Repo.get!(WorkflowJob, 940_001)
    assert queued.status == "queued"
    assert queued.fleet_name == "fleet-legacy"

    running = Repo.get!(WorkflowJob, 940_002)
    assert running.status == "running"
    assert running.pod_name == "pod-legacy"
    assert DateTime.compare(running.claimed_at, started_at) == :eq

    # Terminal rows need no lifecycle twin — nothing dispatches them.
    assert Repo.get(WorkflowJob, 940_003) == nil

    # The adopted queued row is now a dispatch candidate, and the
    # adopted running row is visible to the orphan scan.
    assert {:ok, [%{workflow_job_id: 940_001}]} = Jobs.pick_queued_top_k("fleet-legacy", [], [], [], 20)
    assert [%{workflow_job_id: 940_002}] = Jobs.list_orphaned_running(DateTime.add(DateTime.utc_now(), -300, :second))
  end

  test "adopts under the workflow_job ordering lock" do
    # The completion writers (this release and the previous one) take
    # the same advisory lock, so the check-and-insert cannot straddle a
    # completion landing between them.
    account = account_fixture()
    :ok = legacy_ch_row!(account, 940_005, status: "queued")
    test_pid = self()

    expect(Jobs, :with_workflow_job_ordering_lock, fn 940_005, fun ->
      send(test_pid, {:locked, 940_005})
      fn -> fun.() end |> Repo.transaction() |> elem(1)
    end)

    assert :ok = perform_job(ReconcileWorkflowJobsWorker, %{})

    assert_received {:locked, 940_005}
    assert Repo.get!(WorkflowJob, 940_005).status == "queued"
  end

  test "leaves existing lifecycle rows alone and honors the completion guard" do
    account = account_fixture()

    # Postgres already has this job, claimed by a live Pod — CH lagging
    # behind must not resurrect it.
    :ok = legacy_ch_row!(account, 940_010, status: "queued")
    :ok = WorkflowJobs.upsert_queued(lifecycle_attrs(account, 940_010))
    {:ok, _claim} = Claims.attempt(940_010, account.id, "fleet-legacy", "pod-live", @linux)

    # Completion recorded while the CH row still reads queued — the
    # guard must win over adoption.
    :ok = legacy_ch_row!(account, 940_011, status: "queued")

    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert_all(JobCompletion, [
      %{
        workflow_job_id: 940_011,
        account_id: account.id,
        conclusion: "cancelled",
        completed_at: now,
        inserted_at: now,
        updated_at: now
      }
    ])

    assert :ok = perform_job(ReconcileWorkflowJobsWorker, %{})

    assert Repo.get!(WorkflowJob, 940_010).status == "claimed"
    assert Repo.get(WorkflowJob, 940_011) == nil
  end

  # --- Reconciliation of rows the previous release moved past ---
  #
  # Each case below reproduces the exact interleaving the old code
  # produces during a roll: it writes claims and completions but never
  # this table, so the lifecycle row freezes wherever the new code
  # last left it.

  test "closes a non-terminal row whose job the old code completed" do
    account = account_fixture()

    # New code enqueued and claimed; old code ran the job to completion
    # (completion recorded, claim released) without touching the row.
    :ok = WorkflowJobs.upsert_queued(lifecycle_attrs(account, 940_100))
    {:ok, claim} = Claims.attempt(940_100, account.id, "fleet-legacy", "pod-old", @linux)
    Repo.delete_all(from(c in Claim, where: c.workflow_job_id == 940_100))
    record_completion!(account, 940_100, "failure")
    assert Repo.get!(WorkflowJob, 940_100).status == "claimed"

    assert :ok = perform_job(ReconcileWorkflowJobsWorker, %{})

    row = Repo.get!(WorkflowJob, 940_100)
    assert row.status == "completed"
    assert row.conclusion == "failure"
    assert %DateTime{} = row.completed_at
    assert claim.claimed_at
  end

  test "maps an old-code cancellation onto the cancelled status" do
    account = account_fixture()
    :ok = WorkflowJobs.upsert_queued(lifecycle_attrs(account, 940_101))
    record_completion!(account, 940_101, "cancelled")

    assert :ok = perform_job(ReconcileWorkflowJobsWorker, %{})

    assert Repo.get!(WorkflowJob, 940_101).status == "cancelled"
  end

  test "re-queues a claimed row whose claim the old code released" do
    account = account_fixture()

    # New code claimed (row -> claimed); the old release paths delete
    # the claim without re-queueing the row, leaving it invisible to
    # dispatch and to every recovery scan.
    :ok = WorkflowJobs.upsert_queued(lifecycle_attrs(account, 940_110))
    {:ok, _claim} = Claims.attempt(940_110, account.id, "fleet-legacy", "pod-old", @linux)
    Repo.delete_all(from(c in Claim, where: c.workflow_job_id == 940_110))
    assert Repo.get!(WorkflowJob, 940_110).status == "claimed"

    assert :ok = perform_job(ReconcileWorkflowJobsWorker, %{})

    row = Repo.get!(WorkflowJob, 940_110)
    assert row.status == "queued"
    assert row.pod_name == nil
    assert {:ok, [%{workflow_job_id: 940_110}]} = Jobs.pick_queued_top_k("fleet-legacy", [], [], [], 20)
  end

  test "leaves a claimed row alone while its claim is live" do
    account = account_fixture()
    :ok = WorkflowJobs.upsert_queued(lifecycle_attrs(account, 940_111))
    {:ok, _claim} = Claims.attempt(940_111, account.id, "fleet-legacy", "pod-live", @linux)

    assert :ok = perform_job(ReconcileWorkflowJobsWorker, %{})

    assert Repo.get!(WorkflowJob, 940_111).status == "claimed"
  end

  test "moves a queued row the old code claimed to the claim's state" do
    account = account_fixture()

    # New code enqueued; old code's `Claims.attempt/5` + `mark_running/2`
    # wrote the claim only. Simulate by inserting the claim the way the
    # old code leaves it: present, running, row untouched.
    :ok = WorkflowJobs.upsert_queued(lifecycle_attrs(account, 940_120))
    claimed_at = DateTime.utc_now()

    Repo.insert_all(Claim, [
      %{
        workflow_job_id: 940_120,
        account_id: account.id,
        fleet_name: "fleet-legacy",
        pod_name: "pod-old-claimer",
        claimed_at: claimed_at,
        platform: :linux,
        vcpus: 1,
        memory_gb: 1,
        lifecycle_state: "running",
        runner_name: "runner-old"
      }
    ])

    assert Repo.get!(WorkflowJob, 940_120).status == "queued"

    assert :ok = perform_job(ReconcileWorkflowJobsWorker, %{})

    row = Repo.get!(WorkflowJob, 940_120)
    assert row.status == "running"
    assert row.pod_name == "pod-old-claimer"
    assert row.runner_name == "runner-old"
    assert DateTime.compare(row.claimed_at, claimed_at) == :eq
    # No longer a dispatch candidate.
    assert {:error, :empty} = Jobs.pick_queued_top_k("fleet-legacy", [], [], [], 20)
  end

  test "completion wins over the claim-side passes for the same row" do
    account = account_fixture()

    # A row can be both unbacked-claimed AND completed (old code ran it
    # and released the claim). Closing must win, not the requeue.
    :ok = WorkflowJobs.upsert_queued(lifecycle_attrs(account, 940_130))
    {:ok, _claim} = Claims.attempt(940_130, account.id, "fleet-legacy", "pod-old", @linux)
    Repo.delete_all(from(c in Claim, where: c.workflow_job_id == 940_130))
    record_completion!(account, 940_130, "success")

    assert :ok = perform_job(ReconcileWorkflowJobsWorker, %{})

    assert Repo.get!(WorkflowJob, 940_130).status == "completed"
  end

  test "is a no-op on a consistent table" do
    account = account_fixture()
    :ok = WorkflowJobs.upsert_queued(lifecycle_attrs(account, 940_140))
    {:ok, _} = Claims.attempt(940_141, account.id, "fleet-legacy", "pod-1", @linux)

    before =
      Repo.all(from(j in WorkflowJob, order_by: j.workflow_job_id, select: {j.workflow_job_id, j.status, j.updated_at}))

    assert :ok = perform_job(ReconcileWorkflowJobsWorker, %{})

    assert Repo.all(
             from(j in WorkflowJob, order_by: j.workflow_job_id, select: {j.workflow_job_id, j.status, j.updated_at})
           ) ==
             before
  end

  defp lifecycle_attrs(account, workflow_job_id) do
    %{
      workflow_job_id: workflow_job_id,
      account_id: account.id,
      fleet_name: "fleet-legacy",
      platform: "linux",
      vcpus: 1,
      memory_gb: 1,
      repository: "acme/cli"
    }
  end

  defp record_completion!(account, workflow_job_id, conclusion) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert_all(JobCompletion, [
      %{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        conclusion: conclusion,
        completed_at: now,
        inserted_at: now,
        updated_at: now
      }
    ])
  end
end
