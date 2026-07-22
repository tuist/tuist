defmodule Tuist.Runners.WorkflowJobsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.JobCompletion
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobs
  alias Tuist.Runners.WorkflowJobTransitionEvent

  defp attrs(account, workflow_job_id, opts \\ []) do
    %{
      workflow_job_id: workflow_job_id,
      account_id: account.id,
      fleet_name: Keyword.get(opts, :fleet, "fleet-a"),
      platform: "linux",
      vcpus: 4,
      memory_gb: 16,
      repository: Keyword.get(opts, :repository, "acme/cli"),
      workflow_run_id: workflow_job_id * 10,
      workflow_name: "CI",
      run_attempt: 1,
      job_name: "build",
      head_branch: "main",
      head_sha: "deadbeef",
      requested_dispatch_label: "tuist-linux",
      enqueued_at: Keyword.get(opts, :enqueued_at)
    }
  end

  defp get_row!(workflow_job_id), do: Repo.get!(WorkflowJob, workflow_job_id)

  defp record_completion!(account, workflow_job_id) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert_all(JobCompletion, [
      %{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        conclusion: "cancelled",
        completed_at: now,
        inserted_at: now,
        updated_at: now
      }
    ])
  end

  describe "upsert_queued/1" do
    test "inserts a queued row carrying the candidate metadata" do
      account = account_fixture()

      assert :ok = WorkflowJobs.upsert_queued(attrs(account, 910_001))

      row = get_row!(910_001)
      assert row.status == "queued"
      assert row.account_id == account.id
      assert row.fleet_name == "fleet-a"
      assert row.repository == "acme/cli"
      assert row.platform == "linux"
      assert row.vcpus == 4
      assert row.requested_dispatch_label == "tuist-linux"
      assert %DateTime{} = row.enqueued_at
    end

    test "a redelivery leaves an existing row alone, whatever its status" do
      account = account_fixture()

      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_002))
      :ok = WorkflowJobs.transition_claimed(910_002, "pod-1", DateTime.utc_now())

      assert :ok = WorkflowJobs.upsert_queued(attrs(account, 910_002))
      assert get_row!(910_002).status == "claimed"
    end

    test "does not resurrect a job whose completion is recorded" do
      account = account_fixture()
      record_completion!(account, 910_003)

      assert :ok = WorkflowJobs.upsert_queued(attrs(account, 910_003))
      assert Repo.get(WorkflowJob, 910_003) == nil
    end
  end

  describe "transition_claimed/3" do
    test "CAS queued → claimed stamps pod_name and claimed_at" do
      account = account_fixture()
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_010))
      claimed_at = DateTime.utc_now()

      assert :ok = WorkflowJobs.transition_claimed(910_010, "pod-1", claimed_at)

      row = get_row!(910_010)
      assert row.status == "claimed"
      assert row.pod_name == "pod-1"
      assert DateTime.compare(row.claimed_at, claimed_at) == :eq
    end

    test "is a :noop when the row is not queued" do
      account = account_fixture()
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_011))
      :ok = WorkflowJobs.record_completed(attrs(account, 910_011), "success", DateTime.utc_now())

      assert :noop = WorkflowJobs.transition_claimed(910_011, "pod-1", DateTime.utc_now())
      assert get_row!(910_011).status == "completed"
    end

    test "is a :noop when the row is missing" do
      assert :noop = WorkflowJobs.transition_claimed(910_012, "pod-1", DateTime.utc_now())
    end
  end

  describe "transition_running/2" do
    test "CAS claimed → running stamps runner_name and started_at" do
      account = account_fixture()
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_020))
      :ok = WorkflowJobs.transition_claimed(910_020, "pod-1", DateTime.utc_now())

      assert :ok = WorkflowJobs.transition_running(910_020, "runner-x")

      row = get_row!(910_020)
      assert row.status == "running"
      assert row.runner_name == "runner-x"
      assert %DateTime{} = row.started_at
    end

    test "is a :noop from queued — the claim transition cannot be skipped" do
      account = account_fixture()
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_021))

      assert :noop = WorkflowJobs.transition_running(910_021, "runner-x")
      assert get_row!(910_021).status == "queued"
    end
  end

  describe "requeue/1" do
    test "moves a claimed row back to queued and clears the claim binding" do
      account = account_fixture()
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_030))
      :ok = WorkflowJobs.transition_claimed(910_030, "pod-1", DateTime.utc_now())

      assert :ok = WorkflowJobs.requeue(910_030)

      row = get_row!(910_030)
      assert row.status == "queued"
      assert row.pod_name == nil
      assert row.runner_name == nil
      assert row.claimed_at == nil
      assert row.started_at == nil
    end

    test "moves a running row back to queued" do
      account = account_fixture()
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_031))
      :ok = WorkflowJobs.transition_claimed(910_031, "pod-1", DateTime.utc_now())
      :ok = WorkflowJobs.transition_running(910_031, "runner-x")

      assert :ok = WorkflowJobs.requeue(910_031)
      assert get_row!(910_031).status == "queued"
    end

    test "leaves terminal rows alone" do
      account = account_fixture()
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_032))
      :ok = WorkflowJobs.record_completed(attrs(account, 910_032), "success", DateTime.utc_now())

      assert :noop = WorkflowJobs.requeue(910_032)
      assert get_row!(910_032).status == "completed"
    end
  end

  describe "record_completed/3" do
    test "transitions an existing row from any non-terminal status" do
      account = account_fixture()
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_040))
      :ok = WorkflowJobs.transition_claimed(910_040, "pod-1", DateTime.utc_now())
      completed_at = DateTime.utc_now()

      assert :ok = WorkflowJobs.record_completed(attrs(account, 910_040), "failure", completed_at)

      row = get_row!(910_040)
      assert row.status == "completed"
      assert row.conclusion == "failure"
      assert DateTime.compare(row.completed_at, completed_at) == :eq
      # The CAS update preserves the claim-path columns the insert
      # branch would not know about.
      assert row.pod_name == "pod-1"
    end

    test "inserts a terminal row when completed arrives before queued" do
      account = account_fixture()

      assert :ok = WorkflowJobs.record_completed(attrs(account, 910_041), "success", DateTime.utc_now())

      row = get_row!(910_041)
      assert row.status == "completed"
      assert row.conclusion == "success"
    end

    test "maps a cancelled conclusion to the cancelled status" do
      account = account_fixture()

      assert :ok = WorkflowJobs.record_completed(attrs(account, 910_042), "cancelled", DateTime.utc_now())

      assert get_row!(910_042).status == "cancelled"
    end

    test "a redelivery cannot rewrite an already-terminal row" do
      account = account_fixture()
      :ok = WorkflowJobs.record_completed(attrs(account, 910_043), "cancelled", DateTime.utc_now())

      assert :ok = WorkflowJobs.record_completed(attrs(account, 910_043), "success", DateTime.utc_now())

      row = get_row!(910_043)
      assert row.status == "cancelled"
      assert row.conclusion == "cancelled"
    end
  end

  describe "record_execution/3" do
    test "stamps the binding on both the executed job's row and the claim's row" do
      account = account_fixture()
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_050))
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_051))
      :ok = WorkflowJobs.transition_claimed(910_050, "pod-1", DateTime.utc_now())
      :ok = WorkflowJobs.transition_running(910_050, "runner-x")

      # GitHub ran 910_051 on the runner minted for 910_050.
      assert :ok = WorkflowJobs.record_execution("runner-x", 910_051, account.id)

      claim_row = get_row!(910_050)
      executed_row = get_row!(910_051)
      assert claim_row.executed_workflow_job_id == 910_051
      assert executed_row.runner_name == "runner-x"
      assert executed_row.executed_workflow_job_id == 910_051
    end

    test "is scoped to the webhook's account" do
      account = account_fixture()
      other_account = account_fixture()
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_052))

      assert :ok = WorkflowJobs.record_execution("runner-x", 910_052, other_account.id)

      assert get_row!(910_052).runner_name == nil
    end
  end

  describe "pick_queued_top_k/6" do
    test "returns queued candidates in (enqueued_at, workflow_job_id) order with the CH candidate shape" do
      account = account_fixture()
      now = DateTime.utc_now()
      floor = DateTime.add(now, -7 * 86_400, :second)

      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_061, enqueued_at: DateTime.add(now, -60, :second)))
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_060, enqueued_at: DateTime.add(now, -120, :second)))
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_062, enqueued_at: DateTime.add(now, -30, :second)))

      assert {:ok, [first, second, third]} = WorkflowJobs.pick_queued_top_k("fleet-a", [], [], [], 20, floor)

      assert [first.workflow_job_id, second.workflow_job_id, third.workflow_job_id] == [910_060, 910_061, 910_062]

      assert %{
               workflow_job_id: 910_060,
               account_id: _,
               fleet_name: "fleet-a",
               platform: "linux",
               vcpus: 4,
               memory_gb: 16,
               repository: "acme/cli",
               workflow_run_id: _,
               workflow_name: "CI",
               run_attempt: 1,
               job_name: "build",
               head_branch: "main",
               head_sha: "deadbeef",
               enqueued_at: %DateTime{},
               requested_dispatch_label: "tuist-linux"
             } = first
    end

    test "applies the account, repository, and workflow_job exclusions" do
      account = account_fixture()
      excluded_account = account_fixture()
      floor = DateTime.add(DateTime.utc_now(), -7 * 86_400, :second)

      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_070))
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_071))
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_072, repository: "acme/other"))
      :ok = WorkflowJobs.upsert_queued(attrs(excluded_account, 910_073))

      assert {:ok, [candidate]} =
               WorkflowJobs.pick_queued_top_k("fleet-a", [excluded_account.id], ["acme/other"], [910_070], 20, floor)

      assert candidate.workflow_job_id == 910_071
    end

    test "skips non-queued rows and rows older than the floor" do
      account = account_fixture()
      now = DateTime.utc_now()
      floor = DateTime.add(now, -7 * 86_400, :second)

      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_080))
      :ok = WorkflowJobs.transition_claimed(910_080, "pod-1", now)
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_081, enqueued_at: DateTime.add(now, -8 * 86_400, :second)))

      assert {:error, :empty} = WorkflowJobs.pick_queued_top_k("fleet-a", [], [], [], 20, floor)
    end
  end

  describe "queued counts" do
    test "count totals and per-account breakdown match the queued rows" do
      account = account_fixture()
      other_account = account_fixture()
      floor = DateTime.add(DateTime.utc_now(), -7 * 86_400, :second)

      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_090))
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_091))
      :ok = WorkflowJobs.upsert_queued(attrs(other_account, 910_092))
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_093, fleet: "fleet-b"))
      :ok = WorkflowJobs.transition_claimed(910_091, "pod-1", DateTime.utc_now())

      assert WorkflowJobs.queued_count_by_fleet("fleet-a", floor) == 2

      assert WorkflowJobs.queued_count_by_fleet_and_account("fleet-a", floor) == %{
               account.id => 1,
               other_account.id => 1
             }
    end
  end

  describe "transition outbox" do
    test "does not write events while the flag is off" do
      account = account_fixture()

      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_100))
      :ok = WorkflowJobs.transition_claimed(910_100, "pod-1", DateTime.utc_now())

      assert Repo.all(WorkflowJobTransitionEvent) == []
    end

    test "writes one event per applied transition carrying the CH insert shape" do
      stub(FunWithFlags, :enabled?, fn :runner_job_transition_outbox -> true end)
      account = account_fixture()
      claimed_at = DateTime.utc_now()

      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_101))
      :ok = WorkflowJobs.transition_claimed(910_101, "pod-1", claimed_at)
      :ok = WorkflowJobs.transition_running(910_101, "runner-x")
      :ok = WorkflowJobs.record_completed(attrs(account, 910_101), "success", DateTime.utc_now())

      events = Repo.all(from(e in WorkflowJobTransitionEvent, order_by: [asc: e.id]))
      assert Enum.map(events, & &1.workflow_job_id) == [910_101, 910_101, 910_101, 910_101]
      assert Enum.all?(events, &(&1.account_id == account.id))

      statuses = Enum.map(events, & &1.payload["status"])
      assert statuses == ["queued", "claimed", "running", "completed"]

      completed = List.last(events)
      assert completed.payload["conclusion"] == "success"
      assert completed.payload["pod_name"] == "pod-1"
      assert completed.payload["runner_name"] == "runner-x"
      assert completed.payload["fleet_name"] == "fleet-a"
      assert completed.payload["account_id"] == account.id
      assert is_binary(completed.payload["enqueued_at"])
      assert is_binary(completed.payload["updated_at"])
    end

    test "guard misses emit no events and a cancelled status maps to CH completed" do
      stub(FunWithFlags, :enabled?, fn :runner_job_transition_outbox -> true end)
      account = account_fixture()

      :ok = WorkflowJobs.record_completed(attrs(account, 910_102), "cancelled", DateTime.utc_now())
      # Terminal redelivery and a stale requeue both miss their guards.
      :ok = WorkflowJobs.record_completed(attrs(account, 910_102), "success", DateTime.utc_now())
      :noop = WorkflowJobs.requeue(910_102)

      assert [event] = Repo.all(WorkflowJobTransitionEvent)
      assert event.payload["status"] == "completed"
      assert event.payload["conclusion"] == "cancelled"
    end
  end

  describe "decode_transition_payload/1" do
    test "round-trips a stored payload into the CH insert row" do
      stub(FunWithFlags, :enabled?, fn :runner_job_transition_outbox -> true end)
      account = account_fixture()

      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_110))

      [event] = Repo.all(WorkflowJobTransitionEvent)
      row = WorkflowJobs.decode_transition_payload(event.payload)

      assert row.workflow_job_id == 910_110
      assert row.account_id == account.id
      assert row.status == "queued"
      assert %DateTime{microsecond: {_, 6}} = row.enqueued_at
      assert %DateTime{microsecond: {_, 6}} = row.updated_at
      assert row.claimed_at == nil
      assert row.pod_name == ""
    end
  end

  describe "list_recently_updated/3" do
    test "returns rows inside the window only" do
      account = account_fixture()
      now = DateTime.utc_now()

      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_120))
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_121))

      Repo.update_all(
        from(j in WorkflowJob, where: j.workflow_job_id == ^910_120),
        set: [updated_at: now |> DateTime.add(-120, :second) |> DateTime.truncate(:second)]
      )

      rows = WorkflowJobs.list_recently_updated(DateTime.add(now, -3_600, :second), DateTime.add(now, -60, :second), 100)

      assert Enum.map(rows, & &1.workflow_job_id) == [910_120]
      assert [%{status: "queued", enqueued_at: %DateTime{}}] = rows
    end
  end

  describe "recovery scans" do
    test "list_orphaned_running/1 returns running rows older than the threshold with the worker shape" do
      account = account_fixture()
      claimed_at = DateTime.utc_now()

      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_130))
      :ok = WorkflowJobs.transition_claimed(910_130, "pod-1", claimed_at)
      :ok = WorkflowJobs.transition_running(910_130, "runner-x")

      Repo.update_all(
        from(j in WorkflowJob, where: j.workflow_job_id == ^910_130),
        set: [started_at: DateTime.add(claimed_at, -600, :second)]
      )

      # Still claimed (not running) and recently running rows are not candidates.
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_131))
      :ok = WorkflowJobs.transition_claimed(910_131, "pod-2", DateTime.utc_now())
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_132))
      :ok = WorkflowJobs.transition_claimed(910_132, "pod-3", DateTime.utc_now())
      :ok = WorkflowJobs.transition_running(910_132, "runner-z")

      threshold = DateTime.add(DateTime.utc_now(), -300, :second)

      assert [candidate] = WorkflowJobs.list_orphaned_running(threshold)
      assert %{workflow_job_id: 910_130, repository: "acme/cli", pod_name: "pod-1", started_at: %DateTime{}} = candidate
      assert DateTime.compare(candidate.claimed_at, claimed_at) == :eq
      assert candidate.account_id == account.id
    end

    test "list_stale_queued/2 returns queued rows inside the enqueued_at window with the worker shape" do
      account = account_fixture()
      now = DateTime.utc_now()

      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_140, enqueued_at: DateTime.add(now, -7_200, :second)))
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_141, enqueued_at: DateTime.add(now, -60, :second)))
      :ok = WorkflowJobs.upsert_queued(attrs(account, 910_142, enqueued_at: DateTime.add(now, -7_200, :second)))
      :ok = WorkflowJobs.transition_claimed(910_142, "pod-1", now)

      candidates = WorkflowJobs.list_stale_queued(DateTime.add(now, -86_400, :second), DateTime.add(now, -3_600, :second))

      assert [%{workflow_job_id: 910_140, repository: "acme/cli", enqueued_at: %DateTime{}, account_id: _}] = candidates
    end
  end
end
