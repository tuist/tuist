defmodule Tuist.Runners.ConcurrencySizingTest do
  # Sizing intentionally shares a transaction-level fleet budget lock.
  use TuistTestSupport.Cases.DataCase, async: false

  import Ecto.Query
  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.BillingFixtures

  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Concurrency
  alias Tuist.Runners.ConcurrencyHistory
  alias Tuist.Runners.ConcurrencySizing
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.WorkflowJobs

  setup :set_mimic_from_context

  setup do
    stub(Tuist.FeatureFlags, :runner_concurrency_growth_enabled?, fn _ -> true end)
    account = account_fixture()
    subscription_fixture(account_id: account.id, plan: :pro)
    %{account: account, now: DateTime.utc_now()}
  end

  test "grows a paid account for a blocked job, preserves admission and records an idempotent history", %{
    account: account,
    now: now
  } do
    fill_macos(account)
    queue(account, now)

    assert {:ok, %{vcpus: 24, memory_gb: 72}} = ConcurrencySizing.grow(account, :macos, :queue, now)
    assert Concurrency.limits_for(account, :linux) == %{vcpus: 32, memory_gb: 64}
    assert {:ok, :unchanged} = ConcurrencySizing.grow(account, :macos, :queue, now)

    changes = Repo.all(from h in ConcurrencyHistory, where: h.account_id == ^account.id and h.source == "automatic")
    assert [%{platform: :macos, vcpus: 24, memory_gb: 72, reason: "queue:" <> _}] = changes

    assert {:ok, _} =
             Claims.attempt(unique_id(), account.id, "macos-pool", "after-growth", %{
               platform: :macos,
               vcpus: 8,
               memory_gb: 24
             })

    assert {:error, {:concurrency_limit_reached, _}} =
             Claims.attempt(unique_id(), account.id, "macos-pool", "still-bounded", %{
               platform: :macos,
               vcpus: 8,
               memory_gb: 24
             })
  end

  test "does not resize Air, disabled runners, or an operator-held account", %{now: now, account: paid} do
    air = account_fixture()

    for account <- [air, paid] do
      fill_macos(account)
      queue(account, now)
    end

    assert {:ok, :unchanged} = ConcurrencySizing.grow(air, :macos, :queue, now)
    stub(Environment, :runners_available?, fn -> false end)
    assert {:ok, :unchanged} = ConcurrencySizing.grow(paid, :macos, :queue, now)
    stub(Tuist.FeatureFlags, :runner_concurrency_growth_enabled?, fn _ -> false end)
    assert {:ok, :unchanged} = ConcurrencySizing.grow(paid, :macos, :queue, now)
  end

  test "does not mistake free account headroom, stale queues or invalid shapes for pressure", %{
    account: account,
    now: now
  } do
    job_id = queue(account, now)
    assert {:ok, :unchanged} = ConcurrencySizing.grow(account, :macos, :queue, now)
    fill_macos(account)

    Repo.query!("UPDATE runner_workflow_jobs SET enqueued_at = $1 WHERE workflow_job_id = $2", [
      DateTime.add(now, -3601, :second),
      job_id
    ])

    assert {:ok, :unchanged} = ConcurrencySizing.grow(account, :macos, :queue, now)

    Repo.query!("UPDATE runner_workflow_jobs SET enqueued_at = $1, vcpus = 1000 WHERE workflow_job_id = $2", [
      DateTime.add(now, -120, :second),
      job_id
    ])

    assert {:ok, :unchanged} = ConcurrencySizing.grow(account, :macos, :queue, now)
  end

  test "recurring sizing ignores a single spike and separates CPU from memory", %{account: account, now: now} do
    for days_ago <- [2, 4], _ <- 1..2, do: session(account, now, days_ago, :macos, 8, 24)
    for _ <- 1..8, do: session(account, now, 1, :macos, 8, 24)
    assert {:ok, %{vcpus: 24, memory_gb: 72}} = ConcurrencySizing.grow(account, :macos, :daily, now)

    for days_ago <- [2, 4], _ <- 1..2, do: session(account, now, days_ago, :linux, 8, 32)
    assert {:ok, %{vcpus: 32, memory_gb: 96}} = ConcurrencySizing.grow(account, :linux, :daily, now)
  end

  test "one active day is not recurring demand, and completion prevents phantom overlaps", %{account: account, now: now} do
    for _ <- 1..4, do: session(account, now, 1, :macos, 8, 24)
    assert {:ok, :unchanged} = ConcurrencySizing.grow(account, :macos, :daily, now)

    # On another day four pods were reclaimed sequentially: old sessions lack
    # ended_at, but recorded job completion must keep their peaks at one pod.
    for offset <- 0..3 do
      row = session(account, now, 3, :macos, 8, 24, offset * 120)

      Repo.update_all(from(s in RunnerSession, where: s.id == ^row.id),
        set: [ended_at: nil, job_ended_at: DateTime.add(row.started_at, 60, :second)]
      )
    end

    # With no release or completion evidence at all, an orphan is not
    # affirmative evidence of hours of concurrent demand.
    for _ <- 1..4 do
      row = session(account, now, 5, :macos, 8, 24)
      Repo.update_all(from(s in RunnerSession, where: s.id == ^row.id), set: [ended_at: nil])
    end

    assert {:ok, :unchanged} = ConcurrencySizing.grow(account, :macos, :daily, now)
  end

  test "honors weekly and absolute ceilings without reducing existing grants", %{account: account, now: now} do
    configure_macos(account, 120, 360, now)
    for days_ago <- [1, 2], _ <- 1..16, do: session(account, now, days_ago, :macos, 8, 24)
    assert {:ok, %{vcpus: 128, memory_gb: 384}} = ConcurrencySizing.grow(account, :macos, :daily, now)

    # A larger contract remains above the automatic ceiling, untouched.
    configure_macos(account, 256, 768, now)
    assert {:ok, :unchanged} = ConcurrencySizing.grow(account, :macos, :daily, now)
    assert Concurrency.limits_for(account, :macos) == %{vcpus: 256, memory_gb: 768}

    configure_macos(account, 32, 96, now)

    Repo.insert!(%ConcurrencyHistory{
      account_id: account.id,
      platform: :macos,
      vcpus: 16,
      memory_gb: 48,
      source: "baseline",
      reason: "",
      recorded_at: DateTime.add(now, -6, :day)
    })

    assert {:ok, :unchanged} = ConcurrencySizing.grow(account, :macos, :daily, now)
  end

  test "weekly doubling counts from the latest operator grant, not a lower limit before it", %{
    account: account,
    now: now
  } do
    # A lower baseline, then an operator raise past the plan's defaults that
    # leaves an upgrade with no `plan` row to record.
    configure_macos(account, 16, 48, now)
    {:ok, _} = Concurrency.update_limits(account, %{runner_macos_vcpus_limit: 32, runner_macos_memory_gb_limit: 96})

    Repo.update_all(
      from(h in ConcurrencyHistory,
        where: h.account_id == ^account.id and h.platform == :macos and h.vcpus == 32 and h.source == "manual"
      ),
      set: [recorded_at: DateTime.add(now, -2, :day)]
    )

    for days_ago <- [1, 2], _ <- 1..5, do: session(account, now, days_ago, :macos, 8, 24)

    assert {:ok, %{vcpus: 48, memory_gb: 144}} = ConcurrencySizing.grow(account, :macos, :daily, now)
  end

  test "manual edits get a cooldown and rejected sizing spends no fleet budget", %{account: account, now: now} do
    fill_macos(account)
    queue(account, now)
    Concurrency.update_limits(account, %{runner_macos_vcpus_limit: 16, runner_macos_memory_gb_limit: 49})
    assert {:ok, :unchanged} = ConcurrencySizing.grow(account, :macos, :queue, now)

    for n <- 1..5 do
      Repo.insert!(%ConcurrencyHistory{
        account_id: account.id,
        platform: :linux,
        vcpus: 32 + n,
        memory_gb: 64,
        source: "automatic",
        reason: "budget",
        recorded_at: DateTime.add(now, -120, :second)
      })
    end

    other = account_fixture()
    subscription_fixture(account_id: other.id, plan: :enterprise)
    fill_macos(other)
    queue(other, now)
    assert {:ok, :unchanged} = ConcurrencySizing.grow(other, :macos, :queue, now)
    Repo.delete_all(from h in ConcurrencyHistory, where: h.account_id == ^account.id and h.reason == "budget")
    assert {:ok, %{vcpus: 24, memory_gb: 72}} = ConcurrencySizing.grow(other, :macos, :queue, now)
  end

  # Fills the account's whole macOS limit with one claim, whatever its plan.
  defp fill_macos(account) do
    limit = Concurrency.limits_for(account, :macos)

    assert {:ok, _} =
             Claims.attempt(
               unique_id(),
               account.id,
               "macos-pool",
               "full-#{account.id}",
               Map.put(limit, :platform, :macos)
             )
  end

  defp queue(account, now) do
    id = unique_id()

    :ok =
      WorkflowJobs.upsert_queued(%{
        account_id: account.id,
        workflow_job_id: id,
        fleet_name: "macos-pool",
        platform: "macos",
        vcpus: 8,
        memory_gb: 24,
        enqueued_at: DateTime.add(now, -120, :second)
      })

    id
  end

  defp session(account, now, days_ago, platform, vcpus, memory_gb, offset \\ 0) do
    started_at =
      now
      |> DateTime.to_date()
      |> Date.add(-days_ago)
      |> DateTime.new!(~T[12:00:00.000000], "Etc/UTC")
      |> DateTime.add(offset, :second)

    Repo.insert!(%RunnerSession{
      account_id: account.id,
      workflow_job_id: unique_id(),
      fleet_name: "#{platform}-pool",
      platform: platform,
      vcpus: vcpus,
      memory_gb: memory_gb,
      started_at: started_at,
      ended_at: DateTime.add(started_at, 60, :second)
    })
  end

  defp configure_macos(account, cpu, memory, now) do
    limits = %{runner_macos_vcpus_limit: cpu, runner_macos_memory_gb_limit: memory}
    {:ok, _} = Concurrency.update_limits(account, limits)

    Repo.update_all(from(h in ConcurrencyHistory, where: h.account_id == ^account.id and h.platform == :macos),
      set: [recorded_at: DateTime.add(now, -8, :day)]
    )
  end

  defp unique_id, do: System.unique_integer([:positive])
end
