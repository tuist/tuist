defmodule Tuist.Runners.ConcurrencyTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Concurrency
  alias Tuist.Runners.JobCompletion
  alias Tuist.Runners.RunnerSession

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

    session_fixture(account,
      platform: :linux,
      vcpus: 4,
      memory_gb: 8,
      started_at: datetime("2026-07-10T10:10:00Z"),
      job_ended_at: datetime("2026-07-10T11:40:00Z")
    )

    session_fixture(account,
      platform: :linux,
      vcpus: 4,
      memory_gb: 16,
      started_at: datetime("2026-07-10T10:30:00Z"),
      job_ended_at: datetime("2026-07-10T10:45:00Z")
    )

    session_fixture(account,
      platform: :macos,
      vcpus: 6,
      memory_gb: 14,
      started_at: datetime("2026-07-10T12:10:00Z"),
      job_ended_at: datetime("2026-07-10T12:50:00Z")
    )

    session_fixture(account,
      platform: :macos,
      vcpus: 6,
      memory_gb: 14,
      started_at: datetime("2026-07-10T12:20:00Z"),
      job_ended_at: datetime("2026-07-10T12:40:00Z")
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

  test "releases the slot when the runner's own job completed, not when the claimed job did" do
    account = account_fixture()
    claimed_job_id = 95_001 + System.unique_integer([:positive])
    executed_job_id = 95_501 + System.unique_integer([:positive])

    # The claimed job was handed to a different runner and finishes hours
    # later; this Pod ran a sibling and freed the slot when that ended.
    completion_fixture(account, executed_job_id, datetime("2026-07-10T10:40:00Z"))
    completion_fixture(account, claimed_job_id, datetime("2026-07-10T15:00:00Z"))

    session_fixture(account,
      workflow_job_id: claimed_job_id,
      executed_workflow_job_id: executed_job_id,
      platform: :linux,
      vcpus: 4,
      memory_gb: 16,
      started_at: datetime("2026-07-10T10:10:00Z")
    )

    usage =
      Concurrency.usage_over_time(
        account.id,
        datetime("2026-07-10T10:00:00Z"),
        datetime("2026-07-10T13:00:00Z"),
        :hour
      )

    assert usage.linux.vcpus == [4, 0, 0, 0]
    assert usage.linux.memory_gb == [16, 0, 0, 0]
  end

  test "releases the slot at the job's end rather than the Pod's teardown" do
    account = account_fixture()

    session_fixture(account,
      platform: :macos,
      vcpus: 6,
      memory_gb: 14,
      started_at: datetime("2026-07-10T10:10:00Z"),
      job_ended_at: datetime("2026-07-10T10:50:00Z"),
      ended_at: datetime("2026-07-10T11:30:00Z")
    )

    usage =
      Concurrency.usage_over_time(
        account.id,
        datetime("2026-07-10T10:00:00Z"),
        datetime("2026-07-10T12:00:00Z"),
        :hour
      )

    assert usage.macos.vcpus == [6, 0, 0]
    assert usage.macos.memory_gb == [14, 0, 0]
  end

  test "never holds the slot past the Pod stop" do
    account = account_fixture()
    workflow_job_id = 96_001 + System.unique_integer([:positive])

    # A Pod that stopped without ever running the job it claimed: the
    # claimed job's own completion lands much later, elsewhere.
    completion_fixture(account, workflow_job_id, datetime("2026-07-10T13:30:00Z"))

    session_fixture(account,
      workflow_job_id: workflow_job_id,
      platform: :linux,
      vcpus: 4,
      memory_gb: 16,
      started_at: datetime("2026-07-10T10:10:00Z"),
      ended_at: datetime("2026-07-10T10:40:00Z")
    )

    usage =
      Concurrency.usage_over_time(
        account.id,
        datetime("2026-07-10T10:00:00Z"),
        datetime("2026-07-10T13:00:00Z"),
        :hour
      )

    assert usage.linux.vcpus == [4, 0, 0, 0]
  end

  test "stops counting a session whose close was never reported at the runner session ceiling" do
    account = account_fixture()

    session_fixture(account,
      platform: :linux,
      vcpus: 4,
      memory_gb: 16,
      started_at: datetime("2026-07-10T10:10:00Z")
    )

    usage =
      Concurrency.usage_over_time(
        account.id,
        datetime("2026-07-10T10:00:00Z"),
        datetime("2026-07-10T20:00:00Z"),
        :hour
      )

    assert usage.linux.vcpus == [4, 4, 4, 4, 4, 4, 4, 0, 0, 0, 0]
    assert usage.linux.memory_gb == [16, 16, 16, 16, 16, 16, 16, 0, 0, 0, 0]
  end

  test "counts a session claimed before the window that is still holding its slot inside it" do
    account = account_fixture()

    session_fixture(account,
      platform: :linux,
      vcpus: 4,
      memory_gb: 16,
      started_at: datetime("2026-07-10T10:00:00Z")
    )

    usage =
      Concurrency.usage_over_time(
        account.id,
        datetime("2026-07-10T12:00:00Z"),
        datetime("2026-07-10T16:00:00Z"),
        :hour
      )

    assert usage.linux.vcpus == [4, 4, 4, 4, 0]
  end

  test "uses fleet platform and default resources for legacy rows" do
    account = account_fixture()
    default = Catalog.default_shape(:linux)

    session_fixture(account,
      fleet_name: "linux-amd64",
      started_at: datetime("2026-07-10T10:10:00Z"),
      job_ended_at: datetime("2026-07-10T10:40:00Z")
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

    session_fixture(account,
      fleet_name: fleet_name,
      started_at: datetime("2026-07-10T10:10:00Z"),
      job_ended_at: datetime("2026-07-10T10:40:00Z")
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

  test "ignores a session whose fleet resolves to no known platform" do
    account = account_fixture()

    session_fixture(account,
      fleet_name: "retired-pool",
      started_at: datetime("2026-07-10T10:10:00Z"),
      job_ended_at: datetime("2026-07-10T10:40:00Z")
    )

    usage =
      Concurrency.usage_over_time(
        account.id,
        datetime("2026-07-10T10:00:00Z"),
        datetime("2026-07-10T11:00:00Z"),
        :hour
      )

    assert usage.linux.vcpus == [0, 0]
    assert usage.macos.vcpus == [0, 0]
  end

  defp session_fixture(account, attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    defaults = %{
      account_id: account.id,
      workflow_job_id: System.unique_integer([:positive]),
      fleet_name: "linux-pool",
      pod_name: "pod-#{System.unique_integer([:positive])}",
      runner_name: "",
      started_at: DateTime.utc_now(),
      ended_at: nil,
      job_ended_at: nil,
      inserted_at: now,
      updated_at: now
    }

    Repo.insert!(struct(RunnerSession, Map.merge(defaults, Map.new(attrs))))
  end

  defp completion_fixture(account, workflow_job_id, %DateTime{} = completed_at) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert!(%JobCompletion{
      workflow_job_id: workflow_job_id,
      account_id: account.id,
      conclusion: "success",
      completed_at: DateTime.truncate(completed_at, :second),
      inserted_at: now,
      updated_at: now
    })
  end

  defp datetime(value) do
    {:ok, datetime, 0} = DateTime.from_iso8601(value)
    %{datetime | microsecond: {0, 6}}
  end

  describe "headroom_jobs/2" do
    test "returns how many more jobs of the shape fit under the limit" do
      account = account_fixture()

      # Default macOS limit is 12 vCPU / 28 GB; a 6/14 shape fits twice.
      assert Concurrency.headroom_jobs(account.id, %{platform: :macos, vcpus: 6, memory_gb: 14}) ==
               2
    end

    test "shrinks as claims consume the limit and reaches 0 at the cap" do
      account = account_fixture()
      shape = %{platform: :macos, vcpus: 6, memory_gb: 14}

      assert {:ok, _} =
               Claims.attempt(11_001, account.id, "macos-pool", "macos-pod-1", shape)

      assert Concurrency.headroom_jobs(account.id, shape) == 1

      assert {:ok, _} =
               Claims.attempt(11_002, account.id, "macos-pool", "macos-pod-2", shape)

      assert Concurrency.headroom_jobs(account.id, shape) == 0
    end

    # The whole point of the function: it must admit exactly what
    # `fits?/3` would admit, or the autoscaler sizes for jobs dispatch
    # then refuses (or starves a pool that could have been served).
    test "agrees with fits?/3 at the boundary" do
      account = account_fixture()
      shape = %{platform: :macos, vcpus: 6, memory_gb: 14}

      assert {:ok, _} =
               Claims.attempt(11_101, account.id, "macos-pool", "macos-pod-1", shape)

      headroom = Concurrency.headroom_jobs(account.id, shape)
      limit = Concurrency.limits_for(account.id, :macos)
      used = Map.fetch!(Concurrency.usage_by_platform(account.id), :macos)

      # `headroom` more jobs fit...
      nth = %{vcpus: shape.vcpus * headroom, memory_gb: shape.memory_gb * headroom}
      assert Concurrency.fits?(used, limit, nth)

      # ...and one beyond that does not.
      beyond = %{
        vcpus: shape.vcpus * (headroom + 1),
        memory_gb: shape.memory_gb * (headroom + 1)
      }

      refute Concurrency.fits?(used, limit, beyond)
    end

    test "is bounded by whichever resource runs out first" do
      account = account_fixture()

      # Default macOS limit 12 vCPU / 28 GB. This shape is cheap on CPU
      # (12 fit) but memory-heavy (2 fit), so memory decides.
      assert Concurrency.headroom_jobs(account.id, %{platform: :macos, vcpus: 1, memory_gb: 14}) ==
               2
    end

    test "never returns negative when usage already exceeds the limit" do
      account = account_fixture()
      shape = %{platform: :macos, vcpus: 6, memory_gb: 14}

      assert {:ok, _} = Claims.attempt(11_201, account.id, "macos-pool", "p1", shape)
      assert {:ok, _} = Claims.attempt(11_202, account.id, "macos-pool", "p2", shape)

      {:ok, _} = Concurrency.update_limits(account, %{"runner_macos_vcpus_limit" => "6"})

      assert Concurrency.headroom_jobs(account.id, shape) == 0
    end

    # Runs on the autoscaler poll path: one bad account must not raise
    # and take the whole fleet's demand signal down with it.
    test "returns 0 for unknown accounts and malformed shapes" do
      account = account_fixture()

      assert Concurrency.headroom_jobs(-1, %{platform: :macos, vcpus: 6, memory_gb: 14}) == 0
      assert Concurrency.headroom_jobs(account.id, %{platform: :macos, vcpus: 0, memory_gb: 14}) == 0
      assert Concurrency.headroom_jobs(account.id, %{platform: :bsd, vcpus: 1, memory_gb: 1}) == 0
      assert Concurrency.headroom_jobs(account.id, %{}) == 0
    end
  end
end
