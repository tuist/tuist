defmodule Tuist.Runners.Workers.JobStateDriftWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Telemetry
  alias Tuist.Runners.Workers.JobStateDriftWorker
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobs

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

  defp attach_drift_telemetry! do
    handler_id = make_ref()
    on_exit(fn -> :telemetry.detach(handler_id) end)
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        Telemetry.event_name_workflow_job_drift(),
        fn _name, measurements, metadata, _ ->
          send(test_pid, {:drift, measurements, metadata})
        end,
        nil
      )
  end

  test "agreeing stores report only the compared count" do
    attach_drift_telemetry!()
    account = account_fixture()

    :ok = Jobs.enqueue(attrs(account, 930_001))
    settle!(930_001)

    assert :ok = perform_job(JobStateDriftWorker, %{})

    assert_receive {:drift, %{count: 1}, %{kind: "compared"}}, 500
    refute_receive {:drift, _, %{kind: "status_mismatch"}}, 100
    refute_receive {:drift, _, %{kind: "missing_in_clickhouse"}}, 100
  end

  test "reports a status mismatch between Postgres and ClickHouse" do
    attach_drift_telemetry!()
    account = account_fixture()

    # `Jobs.enqueue/1` dark-writes both stores as queued; a
    # Postgres-only claim transition diverges them.
    :ok = Jobs.enqueue(attrs(account, 930_002))
    :ok = WorkflowJobs.transition_claimed(930_002, "pod-1", DateTime.utc_now())
    settle!(930_002)

    assert :ok = perform_job(JobStateDriftWorker, %{})

    assert_receive {:drift, %{count: 1}, %{kind: "status_mismatch"}}, 500
  end

  test "reports rows missing from ClickHouse" do
    attach_drift_telemetry!()
    account = account_fixture()

    :ok = WorkflowJobs.upsert_queued(attrs(account, 930_003))
    settle!(930_003)

    assert :ok = perform_job(JobStateDriftWorker, %{})

    assert_receive {:drift, %{count: 1}, %{kind: "missing_in_clickhouse"}}, 500
  end

  test "does not flag Postgres cancelled against ClickHouse completed" do
    attach_drift_telemetry!()
    account = account_fixture()

    :ok = Jobs.enqueue(attrs(account, 930_004))
    assert {:ok, _} = Jobs.complete(930_004, "cancelled")
    settle!(930_004)

    assert :ok = perform_job(JobStateDriftWorker, %{})

    assert_receive {:drift, %{count: 1}, %{kind: "compared"}}, 500
    refute_receive {:drift, _, %{kind: "status_mismatch"}}, 100
  end
end
