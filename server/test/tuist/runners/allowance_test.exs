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
end
