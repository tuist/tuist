defmodule Tuist.Runners.Workers.FlushJobTransitionEventsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.ClickHouseRepo
  alias Tuist.Repo
  alias Tuist.Runners.Job
  alias Tuist.Runners.Workers.FlushJobTransitionEventsWorker
  alias Tuist.Runners.WorkflowJobs
  alias Tuist.Runners.WorkflowJobTransitionEvent

  defp attrs(account, workflow_job_id) do
    %{
      workflow_job_id: workflow_job_id,
      account_id: account.id,
      fleet_name: "fleet-flush",
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

  # Latest state per workflow_job, the way every CH reader consumes
  # `runner_jobs`. Flushing several transitions of one job in a single
  # INSERT lets the RMT collapse them to the newest `updated_at`
  # within the part, so intermediate rows are not guaranteed to
  # survive — same post-merge semantics as the direct write path.
  defp ch_state(workflow_job_id) do
    ClickHouseRepo.one(
      from(j in Job,
        where: j.workflow_job_id == ^workflow_job_id,
        group_by: j.workflow_job_id,
        select: %{
          status: fragment("argMax(?, ?)", j.status, j.updated_at),
          conclusion: fragment("argMax(?, ?)", j.conclusion, j.updated_at),
          pod_name: fragment("argMax(?, ?)", j.pod_name, j.updated_at)
        }
      )
    )
  end

  test "replays outbox events as ClickHouse runner_jobs rows and deletes them" do
    account = account_fixture()

    :ok = WorkflowJobs.upsert_queued(attrs(account, 920_001))
    :ok = WorkflowJobs.transition_claimed(920_001, "pod-1", DateTime.utc_now())
    :ok = WorkflowJobs.record_completed(attrs(account, 920_001), "success", DateTime.utc_now())
    :ok = WorkflowJobs.upsert_queued(attrs(account, 920_002))

    assert length(Repo.all(WorkflowJobTransitionEvent)) == 4

    assert :ok = perform_job(FlushJobTransitionEventsWorker, %{})

    assert Repo.all(WorkflowJobTransitionEvent) == []

    assert %{status: "completed", conclusion: "success", pod_name: "pod-1"} = ch_state(920_001)
    assert %{status: "queued", conclusion: "", pod_name: ""} = ch_state(920_002)
  end

  test "is a no-op on an empty outbox" do
    assert :ok = perform_job(FlushJobTransitionEventsWorker, %{})
    assert Repo.all(WorkflowJobTransitionEvent) == []
  end
end
