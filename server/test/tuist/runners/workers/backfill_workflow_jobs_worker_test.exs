defmodule Tuist.Runners.Workers.BackfillWorkflowJobsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Runners.Job
  alias Tuist.Runners.JobCompletion
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.Workers.BackfillWorkflowJobsWorker

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

    assert :ok = perform_job(BackfillWorkflowJobsWorker, %{})

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

  test "leaves existing lifecycle rows alone and honors the completion guard" do
    account = account_fixture()

    # Postgres already has this job (claimed) — CH lagging behind must
    # not resurrect it.
    :ok = legacy_ch_row!(account, 940_010, status: "queued")

    Repo.insert_all(WorkflowJob, [
      %{
        workflow_job_id: 940_010,
        account_id: account.id,
        fleet_name: "fleet-legacy",
        status: "claimed",
        pod_name: "pod-live",
        enqueued_at: DateTime.utc_now(),
        inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
        updated_at: DateTime.truncate(DateTime.utc_now(), :second)
      }
    ])

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

    assert :ok = perform_job(BackfillWorkflowJobsWorker, %{})

    assert Repo.get!(WorkflowJob, 940_010).status == "claimed"
    assert Repo.get(WorkflowJob, 940_011) == nil
  end
end
