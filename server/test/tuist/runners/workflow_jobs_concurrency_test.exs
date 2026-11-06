defmodule Tuist.Runners.WorkflowJobsConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Repo
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobs
  alias Tuist.Runners.WorkflowJobTransitionEvent

  @timeout 5_000

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    user = user_fixture(preload: [:account])

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      Repo.delete!(user.account)
      Repo.delete!(user)
      Sandbox.checkin(Repo)
    end)

    %{account: user.account}
  end

  # The completion reads its clock, then blocks on the row lock a claim
  # holds. The claim reads a later clock and commits first, so the
  # completion lands second in Postgres. ClickHouse resolves the replica
  # by the highest `updated_at`, so the completion's must be the higher
  # one or the replica stays `claimed` for good.
  test "a completion that waited on a claim's row lock outranks it in the replica", %{account: account} do
    workflow_job_id = 9_140_001
    :ok = WorkflowJobs.upsert_queued(attrs(account, workflow_job_id))

    claimer = hold_row_then_claim(workflow_job_id)

    completer =
      db_task(fn ->
        WorkflowJobs.record_completed(attrs(account, workflow_job_id), "cancelled", DateTime.utc_now())
      end)

    await_lock_wait()
    send(claimer.pid, :claim)

    assert {:ok, :ok} = Task.await(claimer, @timeout)
    assert :ok = Task.await(completer, @timeout)

    assert Repo.get!(WorkflowJob, workflow_job_id).status == "cancelled"

    latest =
      WorkflowJobTransitionEvent
      |> where([e], e.workflow_job_id == ^workflow_job_id)
      |> Repo.all()
      |> Enum.map(&WorkflowJobs.decode_transition_payload(&1.payload))
      |> Enum.max_by(& &1.updated_at, DateTime)

    assert latest.status == "completed"
    assert latest.conclusion == "cancelled"
  end

  defp hold_row_then_claim(workflow_job_id) do
    parent = self()

    task =
      db_task(fn ->
        Repo.transaction(fn ->
          Repo.one!(from(j in WorkflowJob, where: j.workflow_job_id == ^workflow_job_id, lock: "FOR UPDATE"))
          send(parent, {:row_locked, self()})

          receive do
            :claim -> WorkflowJobs.transition_claimed(workflow_job_id, "pod-1", DateTime.utc_now())
          end
        end)
      end)

    pid = task.pid
    assert_receive {:row_locked, ^pid}, @timeout
    task
  end

  defp db_task(function) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        function.()
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp await_lock_wait(retries \\ 500) do
    %{rows: [[waiting]]} =
      Repo.query!("SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND datname = current_database()")

    cond do
      waiting > 0 ->
        :ok

      retries == 0 ->
        flunk("the completion never blocked on the claim's row lock")

      true ->
        Process.sleep(10)
        await_lock_wait(retries - 1)
    end
  end

  defp attrs(account, workflow_job_id) do
    %{
      workflow_job_id: workflow_job_id,
      account_id: account.id,
      fleet_name: "fleet-race",
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
end
