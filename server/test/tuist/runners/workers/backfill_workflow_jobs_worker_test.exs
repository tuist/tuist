defmodule Tuist.Runners.Workers.BackfillWorkflowJobsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Runners.Job
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Workers.BackfillWorkflowJobsWorker
  alias Tuist.Runners.Workers.FlushJobTransitionEventsWorker
  alias Tuist.Runners.WorkflowJob

  test "creates a terminal lifecycle row for a job only ClickHouse has" do
    account = account_fixture()
    archived_at = ~U[2026-10-01 10:00:00.000000Z]
    replica_row!(account.id, 960_001, %{log_archived_at: archived_at})

    assert :ok = perform_job(BackfillWorkflowJobsWorker, %{})

    row = Repo.get!(WorkflowJob, 960_001)
    assert row.account_id == account.id
    assert row.provider == "github"
    assert row.status == "completed"
    assert row.conclusion == "success"
    assert row.workflow_run_id == 9_600_010
    assert row.repository == "acme/cli"
    assert row.pod_name == "pod-1"
    assert row.runner_name == "runner-1"
    assert row.log_archived_at == archived_at

    assert {:ok, %Job{status: "completed", conclusion: "success", log_archived_at: ^archived_at}} =
             Jobs.get_for_account(account.id, 960_001)
  end

  test "maps a cancelled job to the lifecycle status and empty strings to NULL" do
    account = account_fixture()
    replica_row!(account.id, 960_011, %{conclusion: "cancelled", pod_name: "", runner_name: "", started_at: nil})

    BackfillWorkflowJobsWorker.backfill(100)

    row = Repo.get!(WorkflowJob, 960_011)
    assert row.status == "cancelled"
    assert row.conclusion == "cancelled"
    assert is_nil(row.pod_name)
    assert is_nil(row.runner_name)
  end

  test "skips jobs ClickHouse has not seen finish" do
    account = account_fixture()
    replica_row!(account.id, 960_021, %{status: "running", conclusion: "", completed_at: nil})

    BackfillWorkflowJobsWorker.backfill(100)

    refute Repo.get(WorkflowJob, 960_021)
  end

  test "skips jobs of accounts that no longer exist" do
    replica_row!(9_999_999_999, 960_031)

    BackfillWorkflowJobsWorker.backfill(100)

    refute Repo.get(WorkflowJob, 960_031)
  end

  test "walks ClickHouse in batches" do
    account = account_fixture()
    replica_row!(account.id, 960_041)
    replica_row!(account.id, 960_042)

    BackfillWorkflowJobsWorker.backfill(1)

    assert Repo.get(WorkflowJob, 960_041)
    assert Repo.get(WorkflowJob, 960_042)
  end

  test "leaves the state of a job the lifecycle table already tracks" do
    account = account_fixture()
    enqueue!(account, 960_051)
    {:ok, _} = Jobs.complete(960_051, "failure")

    BackfillWorkflowJobsWorker.backfill(100)

    row = Repo.get!(WorkflowJob, 960_051)
    assert row.status == "completed"
    assert row.conclusion == "failure"
  end

  test "copies an archive marker that predates the lifecycle column" do
    account = account_fixture()
    enqueue!(account, 960_061)
    {:ok, _} = Jobs.complete(960_061, "success")
    flush!()
    archived_at = ~U[2026-10-02 10:00:00.000000Z]
    stamp_replica_only!(960_061, archived_at)

    BackfillWorkflowJobsWorker.backfill(100)

    assert Repo.get!(WorkflowJob, 960_061).log_archived_at == archived_at
  end

  test "does not copy an archive marker while the job has transitions ClickHouse has not seen" do
    account = account_fixture()
    enqueue!(account, 960_071)
    {:ok, _} = Jobs.complete(960_071, "success")
    :ok = Jobs.set_log_archived_at(960_071, ~U[2026-10-03 10:00:00.000000Z])
    flush!()
    :ok = Jobs.set_log_archived_at(960_071, nil)

    BackfillWorkflowJobsWorker.backfill(100)

    assert is_nil(Repo.get!(WorkflowJob, 960_071).log_archived_at)
  end

  test "running it again changes nothing" do
    account = account_fixture()
    replica_row!(account.id, 960_081)

    BackfillWorkflowJobsWorker.backfill(100)
    first = Repo.get!(WorkflowJob, 960_081)
    BackfillWorkflowJobsWorker.backfill(100)

    assert Repo.get!(WorkflowJob, 960_081) == first
  end

  defp replica_row!(account_id, workflow_job_id, overrides \\ %{}) do
    now = DateTime.utc_now()

    row =
      Map.merge(
        %{
          workflow_job_id: workflow_job_id,
          account_id: account_id,
          fleet_name: "linux-amd64",
          repository: "acme/cli",
          platform: "linux",
          vcpus: 4,
          memory_gb: 16,
          workflow_run_id: workflow_job_id * 10,
          workflow_name: "CI",
          run_attempt: 1,
          job_name: "build",
          head_branch: "main",
          head_sha: "deadbeef",
          status: "completed",
          conclusion: "success",
          enqueued_at: DateTime.add(now, -3_600, :second),
          claimed_at: DateTime.add(now, -3_590, :second),
          started_at: DateTime.add(now, -3_580, :second),
          completed_at: DateTime.add(now, -3_000, :second),
          pod_name: "pod-1",
          runner_name: "runner-1",
          log_archived_at: nil,
          executor_claimed_at: nil,
          requested_dispatch_label: "tuist-linux",
          updated_at: now
        },
        overrides
      )

    IngestRepo.insert_all(Job, [row])
  end

  defp stamp_replica_only!(workflow_job_id, archived_at) do
    {:ok, job} = Jobs.get(workflow_job_id)

    row =
      job
      |> Map.from_struct()
      |> Map.delete(:__meta__)
      |> Map.merge(%{log_archived_at: archived_at, updated_at: DateTime.utc_now()})

    IngestRepo.insert_all(Job, [row])
  end

  defp enqueue!(account, workflow_job_id) do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "acme/cli",
        workflow_run_id: workflow_job_id * 10
      })

    flush!()
  end

  defp flush! do
    :ok = perform_job(FlushJobTransitionEventsWorker, %{})
  end
end
