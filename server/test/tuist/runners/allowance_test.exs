defmodule Tuist.Runners.AllowanceTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Billing
  alias Tuist.Repo
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.RunnerSession
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    %{account: user.account}
  end

  defp used_minutes(account, minutes) do
    started = DateTime.add(DateTime.utc_now(), -2, :hour)

    Repo.insert!(%RunnerSession{
      account_id: account.id,
      workflow_job_id: System.unique_integer([:positive]),
      fleet_name: "tuist-staging-macos",
      pod_name: "pod-#{System.unique_integer([:positive])}",
      runner_name: "",
      platform: :macos,
      vcpus: 6,
      memory_gb: 14,
      billing_multiplier: 10_000,
      started_at: started,
      job_started_at: started,
      job_ended_at: DateTime.add(started, minutes * 60, :second),
      inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
      updated_at: DateTime.truncate(DateTime.utc_now(), :second)
    })
  end

  describe "exhausted?/1" do
    test "a free account with room left may still dispatch", %{account: account} do
      stub(Billing, :effective_plan, fn _account -> :air end)
      used_minutes(account, 40)

      refute Allowance.exhausted?(account)
      assert Allowance.minutes_remaining(account) == 60
    end

    test "a free account is cut off once the allowance is spent", %{account: account} do
      stub(Billing, :effective_plan, fn _account -> :air end)
      used_minutes(account, Allowance.free_monthly_minutes())

      assert Allowance.exhausted?(account)
      assert Allowance.minutes_remaining(account) == 0
    end

    test "a paid account is never cut off, because the excess is what it pays for", %{account: account} do
      used_minutes(account, Allowance.free_monthly_minutes() * 10)

      for plan <- [:pro, :enterprise] do
        stub(Billing, :effective_plan, fn _account -> plan end)
        refute Allowance.exhausted?(account), "expected #{plan} to keep dispatching"
      end
    end

    test "an account that has run nothing is not exhausted", %{account: account} do
      stub(Billing, :effective_plan, fn _account -> :air end)

      refute Allowance.exhausted?(account)
      assert Allowance.minutes_remaining(account) == Allowance.free_monthly_minutes()
    end
  end

  describe "minutes_used/1" do
    test "truncates to whole minutes, matching how the Price rounds", %{account: account} do
      # 90 seconds is one billable minute, not one and a half.
      started = DateTime.add(DateTime.utc_now(), -2, :hour)

      Repo.insert!(%RunnerSession{
        account_id: account.id,
        workflow_job_id: System.unique_integer([:positive]),
        fleet_name: "tuist-staging-macos",
        pod_name: "pod-#{System.unique_integer([:positive])}",
        runner_name: "",
        platform: :macos,
        vcpus: 6,
        memory_gb: 14,
        billing_multiplier: 10_000,
        started_at: started,
        job_started_at: started,
        job_ended_at: DateTime.add(started, 90, :second),
        inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
        updated_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

      assert Allowance.minutes_used(account) == 1
    end
  end

  describe "free_monthly_minutes/0" do
    # Pins the production number, which has to equal the first tier of
    # the production runner Price. An environment can lower both together
    # (staging does), but that override is runtime config rather than
    # something to mutate global state in a test to observe.
    test "defaults to the production allowance" do
      assert Allowance.free_monthly_minutes() == 100
    end
  end

  describe "monthly_breakdown/1" do
    test "spends the allowance in date order, so the day it runs out is split", %{account: account} do
      # Three days of 60 minutes against a 100 minute allowance: the
      # first is entirely free, the second straddles the boundary, the
      # third is entirely billed.
      for days_ago <- [3, 2, 1] do
        started = DateTime.add(DateTime.utc_now(), -days_ago, :day)

        Repo.insert!(%RunnerSession{
          account_id: account.id,
          workflow_job_id: System.unique_integer([:positive]),
          fleet_name: "tuist-macos",
          pod_name: "pod-#{System.unique_integer([:positive])}",
          runner_name: "",
          platform: :macos,
          vcpus: 6,
          memory_gb: 14,
          billing_multiplier: 10_000,
          started_at: started,
          job_started_at: started,
          job_ended_at: DateTime.add(started, 60 * 60, :second),
          inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
          updated_at: DateTime.truncate(DateTime.utc_now(), :second)
        })
      end

      breakdown = Allowance.monthly_breakdown(account)

      assert breakdown.minutes == 180
      # 180 minutes at $0.075, of which 80 are past the allowance.
      assert breakdown.gross == Money.new(1350, :USD)
      assert breakdown.billed == Money.new(600, :USD)

      [first, second, third] = breakdown.days
      assert first.gross == Money.new(450, :USD)
      assert first.billed == Money.new(0, :USD)
      # The allowance ran out 40 minutes into this day.
      assert second.gross == Money.new(450, :USD)
      assert second.billed == Money.new(150, :USD)
      assert third.gross == Money.new(450, :USD)
      assert third.billed == Money.new(450, :USD)
    end

    test "gives every day a stable id, since the table keys rows on it", %{account: account} do
      started = DateTime.add(DateTime.utc_now(), -1, :day)

      Repo.insert!(%RunnerSession{
        account_id: account.id,
        workflow_job_id: System.unique_integer([:positive]),
        fleet_name: "tuist-macos",
        pod_name: "pod-#{System.unique_integer([:positive])}",
        runner_name: "",
        platform: :macos,
        vcpus: 6,
        memory_gb: 14,
        billing_multiplier: 10_000,
        started_at: started,
        job_started_at: started,
        job_ended_at: DateTime.add(started, 600, :second),
        inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
        updated_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

      breakdown = Allowance.monthly_breakdown(account)

      ids = Enum.map(breakdown.days, & &1.id)
      assert ids == Enum.uniq(ids)
      assert Enum.all?(ids, &is_binary/1)
    end

    test "reports nothing for an account that has run no jobs", %{account: account} do
      breakdown = Allowance.monthly_breakdown(account)

      assert breakdown.minutes == 0
      assert breakdown.days == []
      assert breakdown.billed == Money.new(0, :USD)
    end
  end
end
