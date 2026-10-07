defmodule Tuist.Runners.CacheVolumes.BuiltinTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Runners.CacheVolumes
  alias Tuist.Runners.CacheVolumes.Builtin
  alias Tuist.Runners.CacheVolumes.Measurement
  alias Tuist.Runners.CacheVolumes.Usage
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.VolumeHeads
  alias Tuist.Runners.WorkflowJob
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    account = AccountsFixtures.account_fixture()
    now = DateTime.utc_now()

    job =
      Repo.insert!(%WorkflowJob{
        workflow_job_id: System.unique_integer([:positive]),
        workflow_run_id: 321,
        account_id: account.id,
        repository: "org/app",
        fleet_name: "macos",
        status: "completed",
        enqueued_at: now,
        job_name: "Build",
        workflow_name: "CI"
      })

    Repo.insert!(%RunnerSession{
      account_id: account.id,
      workflow_job_id: job.workflow_job_id,
      executed_workflow_job_id: job.workflow_job_id,
      fleet_name: "macos",
      platform: :macos,
      pod_name: "mac-pod",
      node_name: "mac-node",
      vcpus: 2,
      memory_gb: 8,
      billing_multiplier: 10_000,
      started_at: DateTime.add(now, -60)
    })

    name = VolumeHeads.volume_name_for_repository(job.repository)

    params = %{
      "pod_name" => "mac-pod",
      "pod_uid" => "uid-1",
      "volume_name" => name,
      "attached_at" => now |> DateTime.add(-30) |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "attach_ms" => 75,
      "attached_size_bytes" => 1024,
      "size_bytes" => 4096,
      "capacity_bytes" => 20_000_000_000,
      "warm" => false,
      "outcome" => "promoted",
      "generation" => 1,
      "base_generation" => 0
    }

    %{account: account, job: job, name: name, params: params}
  end

  test "measured volumes share inventory, detail history, analytics and job links", %{
    account: account,
    job: job,
    name: name,
    params: params
  } do
    assert {:ok, 1} = VolumeHeads.bump_head(account.id, "mac-node", "digest", 0, name)
    assert {:ok, %{id: id}} = Builtin.report("mac-node", params)
    assert %{volumes: [volume], stats: stats} = CacheVolumes.list(account.id)
    assert volume.id == id
    assert volume.key == "tuist-cache"
    assert volume.platform == "macos"
    assert volume.repository == job.repository
    assert stats[id].retained_bytes == 4096
    assert stats[id].retained_capacity_bytes == 20_000_000_000
    assert stats[id].uses == 1
    assert stats[id].hits == 0
    assert [%{job_name: "Build", attach_ms: 75, size_bytes: 4096}] = CacheVolumes.history(account.id, id)
    assert [%{volume_id: ^id}] = CacheVolumes.for_job(account.id, job.workflow_run_id, job.workflow_job_id)
    assert {:ok, %{id: ^id}} = Builtin.report("mac-node", params)
    assert Repo.aggregate(Usage, :count) == 1
    assert Repo.aggregate(Measurement, :count) == 2
    period = {DateTime.add(DateTime.utc_now(), -120), DateTime.utc_now()}
    assert %{uses: 1, hit_rate: 0.0} = CacheVolumes.usage_analytics(account.id, id, period)

    assert %{used_bytes: 4096, capacity_bytes: 20_000_000_000} =
             List.last(CacheVolumes.storage_history(account.id, period))

    assert {:error, :unsupported} = CacheVolumes.delete(account.id, id)
    assert {:ok, 0} = CacheVolumes.expire_inactive(DateTime.add(DateTime.utc_now(), 30, :day))
  end

  test "node and repository scope are taken from execution, not body", %{account: account, params: params} do
    assert {:error, :pending} = Builtin.report("other-node", params)
    assert {:error, :invalid_report} = Builtin.report("mac-node", %{params | "volume_name" => "repo-0000000000000000"})
    other = AccountsFixtures.account_fixture()
    assert {:ok, %{id: id}} = Builtin.report("mac-node", Map.put(params, "account_id", other.id))
    assert CacheVolumes.get(account.id, id)
    refute CacheVolumes.get(other.id, id)
  end

  test "rejects missing, negative and oversized measurements", %{params: params} do
    for bad <- [
          Map.delete(params, "size_bytes"),
          %{params | "size_bytes" => -1},
          %{params | "size_bytes" => 30_000_000_000},
          %{params | "warm" => nil}
        ] do
      assert {:error, :invalid_report} = Builtin.report("mac-node", bad)
    end

    assert Repo.aggregate(Usage, :count) == 0
  end

  test "first measured warm job supplies the inherited master size, even when discarded", %{
    account: account,
    name: name,
    params: params
  } do
    VolumeHeads.bump_head(account.id, "mac-node", "digest", 0, name)
    params = %{params | "outcome" => "discarded", "warm" => true, "base_generation" => 1, "generation" => 0}
    assert {:ok, %{id: id}} = Builtin.report("mac-node", params)
    assert CacheVolumes.statistics([id])[id].retained_bytes == 1024
    assert CacheVolumes.statistics([id])[id].hits == 1
  end

  test "supersession replaces the saved measurement without pretending physical deletion", %{
    account: account,
    name: name,
    params: params
  } do
    VolumeHeads.bump_head(account.id, "mac-node", "digest", 0, name)
    {:ok, %{id: id}} = Builtin.report("mac-node", params)
    first = Repo.one!(Usage)
    VolumeHeads.bump_head(account.id, "mac-node", "digest-2", 1, name)

    assert {:ok, _} =
             Builtin.report("mac-node", %{params | "pod_uid" => "uid-2", "generation" => 2, "size_bytes" => 8192})

    assert CacheVolumes.statistics([id])[id].retained_bytes == 8192
    assert Repo.get!(Usage, first.id).superseded_at
    assert is_nil(Repo.get!(Usage, first.id).deleted_at)
  end

  test "a delayed report for a superseded HEAD retires telemetry without acknowledging deletion", %{
    account: account,
    name: name,
    params: params
  } do
    VolumeHeads.bump_head(account.id, "mac-node", "digest", 0, name)
    VolumeHeads.bump_head(account.id, "mac-node", "newer-digest", 1, name)
    assert {:ok, %{id: id}} = Builtin.report("mac-node", params)
    usage = Repo.one!(Usage)
    assert usage.superseded_at
    assert is_nil(usage.deleted_at)
    assert is_nil(CacheVolumes.get(account.id, id).head_id)
    assert CacheVolumes.statistics([id])[id].retained_copies == 0
  end
end
