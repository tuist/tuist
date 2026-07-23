defmodule Tuist.Runners.Workers.JobStateDriftWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import ExUnit.CaptureLog
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Workers.JobStateDriftWorker
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobs

  @drift_message "runners: workflow_job state drift between Postgres and ClickHouse"

  defp attrs(account, workflow_job_id) do
    %{
      workflow_job_id: workflow_job_id,
      account_id: account.id,
      fleet_name: "fleet-drift",
      platform: "linux",
      vcpus: 4,
      memory_gb: 16,
      repository: "acme/cli",
      workflow_run_id: workflow_job_id * 10,
      workflow_name: "CI",
      run_attempt: 1,
      job_name: "build",
      head_branch: "main",
      head_sha: "deadbeef",
      requested_dispatch_label: "tuist-linux"
    }
  end

  # The comparator skips rows updated in the last minute (Postgres
  # commits before the paired CH INSERT); tests backdate updated_at
  # to land inside the comparison window.
  defp settle!(workflow_job_id) do
    Repo.update_all(
      from(j in WorkflowJob, where: j.workflow_job_id == ^workflow_job_id),
      set: [updated_at: DateTime.utc_now() |> DateTime.add(-300, :second) |> DateTime.truncate(:second)]
    )
  end

  defp drift_log do
    capture_log([level: :warning], fn ->
      assert :ok = perform_job(JobStateDriftWorker, %{})
    end)
  end

  test "agreeing stores log no drift" do
    account = account_fixture()

    :ok = Jobs.enqueue(attrs(account, 930_001))
    settle!(930_001)

    refute drift_log() =~ @drift_message
  end

  test "logs a status mismatch between Postgres and ClickHouse" do
    account = account_fixture()

    # `Jobs.enqueue/1` writes both stores as queued; a Postgres-only
    # claim transition diverges them.
    :ok = Jobs.enqueue(attrs(account, 930_002))
    :ok = WorkflowJobs.transition_claimed(930_002, "pod-1", DateTime.utc_now())
    settle!(930_002)

    log = drift_log()
    assert log =~ @drift_message
    assert log =~ "status_mismatch"
    assert log =~ "930002"
  end

  test "logs rows missing from ClickHouse" do
    account = account_fixture()

    :ok = WorkflowJobs.upsert_queued(attrs(account, 930_003))
    settle!(930_003)

    log = drift_log()
    assert log =~ @drift_message
    assert log =~ "missing_in_clickhouse"
  end

  test "does not flag Postgres cancelled against ClickHouse completed with a cancelled conclusion" do
    account = account_fixture()

    :ok = Jobs.enqueue(attrs(account, 930_004))
    assert {:ok, _} = Jobs.complete(930_004, "cancelled")
    settle!(930_004)

    refute drift_log() =~ @drift_message
  end

  test "flags terminal rows whose cancelled-ness disagrees across stores" do
    account = account_fixture()

    # Postgres lands completed/success first, so the ClickHouse-side
    # cancellation only reaches CH (the PG terminal guard rejects the
    # rewrite) — the stores now disagree about how the job ended.
    :ok = Jobs.enqueue(attrs(account, 930_005))
    :ok = WorkflowJobs.record_completed(attrs(account, 930_005), "success", DateTime.utc_now())
    assert {:ok, _} = Jobs.complete(930_005, "cancelled")
    settle!(930_005)

    log = drift_log()
    assert log =~ @drift_message
    assert log =~ "status_mismatch"
  end
end
