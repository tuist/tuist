defmodule Tuist.Runners.Shadow.SnapshotTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Runners.Claim
  alias Tuist.Runners.ConcurrencyLimit
  alias Tuist.Runners.Shadow.Snapshot
  alias Tuist.Runners.WorkflowJob

  test "reads minimal demand, all active usage, and budgets without changing lifecycle state" do
    account = account_fixture()
    now = DateTime.utc_now()
    base = System.unique_integer([:positive]) * 10_000
    queued = insert_job(account.id, base + 1, "queued", now)
    insert_job(account.id, base + 2, "completed", now)
    insert_job(account.id, base + 4, "queued", DateTime.add(now, -8, :day))

    pod_name = "busy-#{base}"

    claim =
      Repo.insert!(%Claim{
        pod_name: pod_name,
        workflow_job_id: nil,
        executed_workflow_job_id: base + 3,
        account_id: account.id,
        fleet_name: "another-pool",
        platform: :linux,
        vcpus: 4,
        memory_gb: 16,
        claimed_at: now
      })

    snapshot = Snapshot.capture()

    assert snapshot.complete
    assert snapshot.version == 1

    assert [%{job_id: job_id, account_id: id, pool: "linux", resources: %{vcpus: 2, memory_gb: 8}} = demand] =
             snapshot.demand

    assert id == account.id
    assert job_id == base + 1
    refute Map.has_key?(demand, :repository)
    refute Map.has_key?(demand, :job_name)

    assert [%{pod: ^pod_name, job_id: nil, executed_job_id: executed_id, resources: %{vcpus: 4, memory_gb: 16}}] =
             snapshot.claims

    assert executed_id == base + 3
    assert Enum.any?(snapshot.accounts, &(&1.account_id == id and &1.platform == :linux))
    assert Repo.get!(WorkflowJob, base + 1) == queued
    assert Repo.get!(Claim, pod_name) == claim
  end

  test "orders demand deterministically and does not invent missing account limits" do
    account = account_fixture()
    now = DateTime.utc_now()
    base = System.unique_integer([:positive]) * 10_000
    insert_job(account.id, base + 2, "queued", now)
    insert_job(account.id, base + 1, "queued", now)
    Repo.delete_all(from(l in ConcurrencyLimit, where: l.account_id == ^account.id and l.platform == :linux))

    snapshot = Snapshot.capture()

    assert Enum.map(snapshot.demand, & &1.job_id) == [base + 1, base + 2]
    refute Enum.any?(snapshot.accounts, &(&1.platform == :linux))
  end

  test "marks an oversized queue incomplete instead of presenting a biased prefix" do
    account = account_fixture()
    now = DateTime.utc_now()
    base = System.unique_integer([:positive]) * 10_000
    timestamps = DateTime.truncate(now, :second)

    rows =
      for id <- 1..1001 do
        %{
          workflow_job_id: base + id,
          account_id: account.id,
          fleet_name: "linux",
          status: "queued",
          enqueued_at: now,
          inserted_at: timestamps,
          updated_at: timestamps
        }
      end

    Repo.insert_all(WorkflowJob, rows)

    assert %{complete: false, demand: [], claims: [], accounts: []} = Snapshot.capture()
    assert Repo.aggregate(WorkflowJob, :count) == 1001
  end

  defp insert_job(account_id, id, status, now) do
    Repo.insert!(%WorkflowJob{
      workflow_job_id: id,
      account_id: account_id,
      status: status,
      fleet_name: "linux",
      platform: "linux",
      vcpus: 2,
      memory_gb: 8,
      enqueued_at: now,
      repository: "private/repository",
      job_name: "private workflow"
    })
  end
end
