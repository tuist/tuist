defmodule Tuist.Runners.ConcurrencyTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts.Account
  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Concurrency
  alias Tuist.Runners.Job

  test "returns the default platform limits and empty usage" do
    account = account_fixture()

    assert Concurrency.summaries(account) == [
             %{
               platform: :linux,
               used_vcpus: 0,
               used_memory_gb: 0,
               limit_vcpus: 32,
               limit_memory_gb: 64
             },
             %{
               platform: :macos,
               used_vcpus: 0,
               used_memory_gb: 0,
               limit_vcpus: 12,
               limit_memory_gb: 28
             }
           ]
  end

  test "creates default platform limits for organization accounts" do
    organization = organization_fixture()

    assert Concurrency.limits_for(organization.account, :linux) == %{vcpus: 32, memory_gb: 64}
    assert Concurrency.limits_for(organization.account, :macos) == %{vcpus: 12, memory_gb: 28}
  end

  test "database creates default limits for accounts inserted by an old replica" do
    user = user_fixture()
    Repo.delete!(user.account)

    {:ok, account} =
      %Account{}
      |> Account.create_changeset(%{
        name: user.account.name,
        billing_email: user.email,
        user_id: user.id
      })
      |> Repo.insert()

    assert Concurrency.limits_for(account, :linux) == %{vcpus: 32, memory_gb: 64}
    assert Concurrency.limits_for(account, :macos) == %{vcpus: 12, memory_gb: 28}
  end

  test "updates each platform's limits independently" do
    account = account_fixture()

    assert {:ok, _account} =
             Concurrency.update_limits(account, %{
               "runner_linux_vcpus_limit" => "48",
               "runner_linux_memory_gb_limit" => "96",
               "runner_macos_vcpus_limit" => "18",
               "runner_macos_memory_gb_limit" => "42"
             })

    assert Concurrency.limits_for(account, :linux) == %{vcpus: 48, memory_gb: 96}
    assert Concurrency.limits_for(account, :macos) == %{vcpus: 18, memory_gb: 42}
  end

  test "summarizes active resource usage independently by platform" do
    account = account_fixture()

    assert {:ok, _} =
             Claims.attempt(10_001, account.id, "linux-pool", "linux-pod", %{
               platform: :linux,
               vcpus: 2,
               memory_gb: 8
             })

    assert {:ok, _} =
             Claims.attempt(10_002, account.id, "macos-pool", "macos-pod", %{
               platform: :macos,
               vcpus: 6,
               memory_gb: 14
             })

    summaries = Map.new(Concurrency.summaries(account), &{&1.platform, &1})

    assert summaries.linux.used_vcpus == 2
    assert summaries.linux.used_memory_gb == 8
    assert summaries.macos.used_vcpus == 6
    assert summaries.macos.used_memory_gb == 14
  end

  test "rejects non-positive limits" do
    account = account_fixture()

    assert {:error, changeset} =
             Concurrency.update_limits(account, %{"runner_macos_vcpus_limit" => "0"})

    assert "must be greater than 0" in errors_on(changeset).runner_macos_vcpus_limit
  end

  test "checks capacity using a pure resource comparison" do
    used = %{vcpus: 6, memory_gb: 14}
    limit = %{vcpus: 12, memory_gb: 28}

    assert Concurrency.fits?(used, limit, %{vcpus: 6, memory_gb: 14})
    refute Concurrency.fits?(used, limit, %{vcpus: 7, memory_gb: 14})
    refute Concurrency.fits?(used, limit, %{vcpus: 6, memory_gb: 15})
    refute Concurrency.fits?(used, limit, %{vcpus: -1, memory_gb: 14})
  end

  test "returns exact peak resource usage per platform and time bucket" do
    account = account_fixture()
    start_dt = datetime("2026-07-10T10:00:00Z")
    end_dt = datetime("2026-07-10T14:00:00Z")

    insert_completed_job(account.id, 91_001,
      platform: "linux",
      vcpus: 4,
      memory_gb: 8,
      claimed_at: datetime("2026-07-10T10:10:00Z"),
      completed_at: datetime("2026-07-10T11:40:00Z")
    )

    insert_completed_job(account.id, 91_002,
      platform: "linux",
      vcpus: 4,
      memory_gb: 16,
      claimed_at: datetime("2026-07-10T10:30:00Z"),
      completed_at: datetime("2026-07-10T10:45:00Z")
    )

    insert_completed_job(account.id, 91_003,
      platform: "macos",
      vcpus: 6,
      memory_gb: 14,
      claimed_at: datetime("2026-07-10T12:10:00Z"),
      completed_at: datetime("2026-07-10T12:50:00Z")
    )

    insert_completed_job(account.id, 91_004,
      platform: "macos",
      vcpus: 6,
      memory_gb: 14,
      claimed_at: datetime("2026-07-10T12:20:00Z"),
      completed_at: datetime("2026-07-10T12:40:00Z")
    )

    usage = Concurrency.usage_over_time(account.id, start_dt, end_dt, :hour)

    assert length(usage.dates) == 5
    assert usage.linux.vcpus == [8, 4, 0, 0, 0]
    assert usage.linux.memory_gb == [24, 8, 0, 0, 0]
    assert usage.macos.vcpus == [0, 0, 12, 0, 0]
    assert usage.macos.memory_gb == [0, 0, 28, 0, 0]
  end

  test "keeps hourly resolution across a 30-day window" do
    account = account_fixture()
    end_dt = datetime("2026-07-10T14:37:00Z")
    start_dt = DateTime.add(end_dt, -30, :day)

    usage = Concurrency.usage_over_time(account.id, start_dt, end_dt, :hour)

    assert length(usage.dates) == 721
    assert Enum.all?(usage.dates, &(&1.minute == 0 and &1.second == 0))
    assert length(usage.linux.vcpus) == 721
    assert length(usage.macos.memory_gb) == 721
  end

  test "uses fleet platform and default resources for legacy rows" do
    account = account_fixture()
    default = Catalog.default_shape(:linux)

    insert_completed_job(account.id, 92_001,
      platform: "",
      fleet_name: "linux-amd64",
      vcpus: 0,
      memory_gb: 0,
      claimed_at: datetime("2026-07-10T10:10:00Z"),
      completed_at: datetime("2026-07-10T10:40:00Z")
    )

    usage =
      Concurrency.usage_over_time(
        account.id,
        datetime("2026-07-10T10:00:00Z"),
        datetime("2026-07-10T11:00:00Z"),
        :hour
      )

    assert usage.linux.vcpus == [default.vcpus, 0]
    assert usage.linux.memory_gb == [default.memory_gb, 0]
  end

  test "uses the fleet's configured shape for legacy history" do
    account = account_fixture()
    shape = Enum.find(Catalog.shapes(:linux), &(!&1.default?))
    fleet_name = Catalog.pool_name(Map.put(shape, :platform, :linux))

    insert_completed_job(account.id, 92_101,
      platform: "",
      fleet_name: fleet_name,
      vcpus: 0,
      memory_gb: 0,
      claimed_at: datetime("2026-07-10T10:10:00Z"),
      completed_at: datetime("2026-07-10T10:40:00Z")
    )

    usage =
      Concurrency.usage_over_time(
        account.id,
        datetime("2026-07-10T10:00:00Z"),
        datetime("2026-07-10T11:00:00Z"),
        :hour
      )

    assert usage.linux.vcpus == [shape.vcpus, 0]
    assert usage.linux.memory_gb == [shape.memory_gb, 0]
  end

  test "does not count a requeued job as continuously claimed" do
    account = account_fixture()
    workflow_job_id = 93_001 + System.unique_integer([:positive])
    claimed_at = datetime("2026-07-10T10:10:00Z")
    requeued_at = datetime("2026-07-10T10:30:00Z")

    base_row = %{
      workflow_job_id: workflow_job_id,
      account_id: account.id,
      fleet_name: "linux-pool",
      platform: "linux",
      vcpus: 4,
      memory_gb: 16,
      repository: "tuist/tuist",
      workflow_run_id: workflow_job_id,
      run_attempt: 1,
      workflow_name: "CI",
      job_name: "Test",
      head_branch: "main",
      head_sha: "abcdef0",
      conclusion: "",
      enqueued_at: claimed_at,
      started_at: nil,
      completed_at: nil,
      pod_name: "",
      runner_name: "",
      requested_dispatch_label: ""
    }

    {1, _} =
      IngestRepo.insert_all(Job, [
        Map.merge(base_row, %{status: "claimed", claimed_at: claimed_at, updated_at: claimed_at})
      ])

    {1, _} =
      IngestRepo.insert_all(Job, [
        Map.merge(base_row, %{status: "queued", claimed_at: nil, updated_at: requeued_at})
      ])

    usage =
      Concurrency.usage_over_time(
        account.id,
        datetime("2026-07-10T10:00:00Z"),
        datetime("2026-07-10T12:00:00Z"),
        :hour
      )

    assert usage.linux.vcpus == [0, 0, 0]
    assert usage.linux.memory_gb == [0, 0, 0]
  end

  defp insert_completed_job(account_id, workflow_job_id, opts) do
    claimed_at = Keyword.fetch!(opts, :claimed_at)
    completed_at = Keyword.fetch!(opts, :completed_at)

    {1, _} =
      IngestRepo.insert_all(Job, [
        %{
          workflow_job_id: workflow_job_id + System.unique_integer([:positive]),
          account_id: account_id,
          fleet_name: Keyword.get(opts, :fleet_name, "#{Keyword.fetch!(opts, :platform)}-pool"),
          platform: Keyword.fetch!(opts, :platform),
          vcpus: Keyword.fetch!(opts, :vcpus),
          memory_gb: Keyword.fetch!(opts, :memory_gb),
          repository: "tuist/tuist",
          workflow_run_id: workflow_job_id,
          run_attempt: 1,
          workflow_name: "CI",
          job_name: "Test",
          head_branch: "main",
          head_sha: "abcdef0",
          status: "completed",
          conclusion: "success",
          enqueued_at: claimed_at,
          claimed_at: claimed_at,
          started_at: claimed_at,
          completed_at: completed_at,
          pod_name: "",
          runner_name: "",
          requested_dispatch_label: "",
          updated_at: completed_at
        }
      ])

    :ok
  end

  defp datetime(value) do
    {:ok, datetime, 0} = DateTime.from_iso8601(value)
    %{datetime | microsecond: {0, 6}}
  end
end
