defmodule Tuist.Runners.AllowanceTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Billing
  alias Tuist.Repo
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.Trials
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

  defp ran_minutes(account, started, minutes) do
    # Session timestamps are microsecond-precision; callers pass whatever
    # precision the instant they care about happens to carry.
    started = %{started | microsecond: {elem(started.microsecond, 0), 6}}

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
      job_ended_at: DateTime.add(started, minutes * 60, :second),
      inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
      updated_at: DateTime.truncate(DateTime.utc_now(), :second)
    })
  end

  defp trial_ended(account, at) do
    account
    |> Ecto.Changeset.change(
      runner_trial_started_at: at |> DateTime.add(-30, :day) |> DateTime.truncate(:second),
      runner_trial_ended_at: DateTime.truncate(at, :second)
    )
    |> Repo.update!()
  end

  defp on_trial_since(account, at) do
    account
    |> Ecto.Changeset.change(runner_trial_started_at: DateTime.truncate(at, :second))
    |> Repo.update!()
  end

  describe "exhausted?/1" do
    test "a free account with room left may still dispatch", %{account: account} do
      stub(Billing, :effective_plan, fn _account -> :air end)
      stub(Billing, :current_billing_period, fn _account -> nil end)
      used_minutes(account, 40)

      refute Allowance.exhausted?(account)
      assert Allowance.minutes_remaining(account) == 60
    end

    test "a free account is cut off once the allowance is spent", %{account: account} do
      stub(Billing, :effective_plan, fn _account -> :air end)
      stub(Billing, :current_billing_period, fn _account -> nil end)
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

    test "an account on a runner trial is never cut off", %{account: account} do
      # A trial is "uses runners without being billed for them", and a trial
      # account has no subscription, so effective_plan reports :air. Without
      # this the account is cut off at the baseline and the trial does not let
      # it run runners at all — which is the whole thing it grants.
      stub(Billing, :effective_plan, fn _account -> :air end)
      stub(Billing, :current_billing_period, fn _account -> nil end)
      used_minutes(account, Allowance.free_monthly_minutes() * 10)

      {:ok, account} = Trials.start(account)

      refute Allowance.exhausted?(account)
    end

    test "an account whose trial was cancelled is cut off again", %{account: account} do
      stub(Billing, :effective_plan, fn _account -> :air end)
      stub(Billing, :current_billing_period, fn _account -> nil end)
      used_minutes(account, Allowance.free_monthly_minutes())

      {:ok, account} = Trials.start(account)
      {:ok, account} = Trials.cancel(account)

      assert Allowance.exhausted?(account)
    end

    test "an account that has run nothing is not exhausted", %{account: account} do
      stub(Billing, :effective_plan, fn _account -> :air end)
      stub(Billing, :current_billing_period, fn _account -> nil end)

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

  describe "period_breakdown/1" do
    setup do
      # No subscription in these fixtures, so the window is the calendar
      # month; stubbed so the fallback is exercised without Stripe.
      stub(Billing, :current_billing_period, fn _account -> nil end)
      :ok
    end

    test "projects every remaining day of an open period from the rate so far", %{account: account} do
      # Early in a period is exactly when the shape of the month ahead is
      # worth seeing, so the days after today carry the daily rate so far
      # rather than being left blank.
      used_minutes(account, 60)

      today = Date.utc_today()
      period_start = DateTime.new!(Date.add(today, -1), ~T[00:00:00], "Etc/UTC")
      period_end = DateTime.shift(period_start, month: 1)

      breakdown = Allowance.period_breakdown(account, {period_start, period_end})

      assert [first | _] = breakdown.projected_days
      assert first.date == Date.add(today, 1)
      assert List.last(breakdown.projected_days).date == period_end |> DateTime.to_date() |> Date.add(-1)
      # Two days into the period, 60 minutes averages to 30 a day.
      assert first.total_ms == 30 * 60_000
    end

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

      breakdown = Allowance.period_breakdown(account)

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

      breakdown = Allowance.period_breakdown(account)

      ids = Enum.map(breakdown.days, & &1.id)
      assert ids == Enum.uniq(ids)
      assert Enum.all?(ids, &is_binary/1)
    end

    test "reports nothing for an account that has run no jobs", %{account: account} do
      breakdown = Allowance.period_breakdown(account)

      assert breakdown.minutes == 0
      assert breakdown.days == []
      assert breakdown.billed == Money.new(0, :USD)
    end
  end

  describe "period_breakdown/1 platform rows" do
    setup do
      stub(Billing, :current_billing_period, fn _account -> nil end)
      :ok
    end

    test "reports the period, its projection, what is included and the period before", %{account: account} do
      # 60 minutes on the 1st of the period, so the projection scales a
      # known figure across a known stretch of it. The clock is frozen
      # because the projection divides by elapsed seconds: against the
      # real clock the same usage projects to a different figure
      # depending on the hour of the day and the length of the month the
      # test happens to run in.
      now = ~U[2024-01-17 00:00:00.000000Z]
      stub(DateTime, :utc_now, fn -> now end)
      started = %{now | day: 1}

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

      assert [row] = Allowance.period_breakdown(account).platforms

      assert row.platform == :macos
      assert row.id == "macos"
      assert row.minutes == 60
      assert row.included_minutes == Allowance.free_monthly_minutes()
      assert row.previous_minutes == 0
      assert row.gross == Money.new(450, :USD)
      # Inside the allowance, so nothing of it is billable yet.
      assert row.billed == Money.new(0, :USD)

      # Straight-line to the end of the window: 60 minutes over the 16
      # elapsed days of a 31-day month, which is 116 minutes and a
      # quarter by the end of it.
      assert row.projected_minutes == 116
      assert row.projected_minutes >= row.minutes
    end

    test "puts no money on usage from a platform with no rate", %{account: account} do
      # Linux minutes past the allowance were being priced at the macOS
      # rate and reported as money billed, against a macOS row reading
      # zero. No invoice can carry them: Linux has no Price.
      # Started early enough that the whole run falls inside the window.
      started = DateTime.add(DateTime.utc_now(), -4, :hour)

      Repo.insert!(%RunnerSession{
        account_id: account.id,
        workflow_job_id: System.unique_integer([:positive]),
        fleet_name: "tuist-linux",
        pod_name: "pod-#{System.unique_integer([:positive])}",
        runner_name: "",
        platform: :linux,
        vcpus: 2,
        memory_gb: 8,
        billing_multiplier: 10_000,
        started_at: started,
        job_started_at: started,
        job_ended_at: DateTime.add(started, 160 * 60, :second),
        inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
        updated_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

      breakdown = Allowance.period_breakdown(account)

      # Reported, because the account did run them.
      assert breakdown.minutes == 160
      # Not priced, because there is no rate to price them at.
      assert breakdown.gross == Money.new(0, :USD)
      assert breakdown.billed == Money.new(0, :USD)
      assert breakdown.days == []
    end

    test "leaves out a platform with no agreed rate", %{account: account} do
      started = DateTime.add(DateTime.utc_now(), -1, :hour)

      Repo.insert!(%RunnerSession{
        account_id: account.id,
        workflow_job_id: System.unique_integer([:positive]),
        fleet_name: "tuist-linux",
        pod_name: "pod-#{System.unique_integer([:positive])}",
        runner_name: "",
        platform: :linux,
        vcpus: 2,
        memory_gb: 8,
        billing_multiplier: 10_000,
        started_at: started,
        job_started_at: started,
        job_ended_at: DateTime.add(started, 600, :second),
        inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
        updated_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

      # Linux has no rate, so there is nothing to put on a receipt for
      # it. Its minutes still count towards the account's total; they
      # just have no line of their own until Linux is priced.
      assert [row] = Allowance.period_breakdown(account).platforms

      assert row.platform == :macos
      assert row.minutes == 0
    end

    test "reports the priced platform for an account that ran nothing", %{account: account} do
      # An account has an allowance whether or not it has run anything,
      # and a receipt reading zero says that better than no receipt.
      assert [row] = Allowance.period_breakdown(account).platforms

      assert row.platform == :macos
      assert row.minutes == 0
      assert row.gross == Money.new(0, :USD)
      assert row.billed == Money.new(0, :USD)
      assert row.included_minutes == Allowance.free_monthly_minutes()
    end
  end

  describe "period_breakdown/1 runner trials" do
    setup do
      stub(Billing, :current_billing_period, fn _account -> nil end)
      :ok
    end

    test "prices nothing the trial covered when it ended inside the period", %{account: account} do
      # Stripe bills the runner item from the instant the trial ended, so
      # a period that straddles the cancellation is part covered and part
      # billable. Pricing the whole of it showed a bill no invoice was
      # going to carry.
      now = DateTime.utc_now()
      period = {DateTime.add(now, -4, :day), DateTime.add(now, 1, :day)}
      account = trial_ended(account, DateTime.add(now, -2, :day))

      ran_minutes(account, DateTime.add(now, -3, :day), 60)
      ran_minutes(account, DateTime.add(now, -1, :day), 180)

      breakdown = Allowance.period_breakdown(account, period)

      # Every minute it ran, priced at the standard rate.
      assert breakdown.minutes == 240
      assert breakdown.gross == Money.new(1800, :USD)
      assert breakdown.trial_covered == Money.new(450, :USD)
      # 180 billable minutes, 100 of them included. The trial's 60 must
      # not have eaten the allowance on their way past.
      assert breakdown.billed == Money.new(600, :USD)
    end

    test "counts only the part of a run that fell after the trial ended", %{account: account} do
      now = DateTime.utc_now()
      period = {DateTime.add(now, -4, :day), DateTime.add(now, 1, :day)}
      trial_end = now |> DateTime.add(-6, :hour) |> DateTime.truncate(:second)
      account = trial_ended(account, trial_end)

      ran_minutes(account, DateTime.add(trial_end, -60, :minute), 120)

      breakdown = Allowance.period_breakdown(account, period)

      assert breakdown.minutes == 120
      assert breakdown.gross == Money.new(900, :USD)
      assert breakdown.trial_covered == Money.new(450, :USD)
      assert breakdown.billed == Money.new(0, :USD)
    end

    test "leaves a day that ran wholly inside the trial with nothing billed", %{account: account} do
      # Past the allowance, so a day the trial covered has to be zeroed
      # deliberately rather than by the free tier happening to reach it.
      now = DateTime.utc_now()
      period = {DateTime.add(now, -4, :day), DateTime.add(now, 1, :day)}
      account = trial_ended(account, DateTime.add(now, -2, :day))

      ran_minutes(account, DateTime.add(now, -3, :day), 180)

      assert [day] = Allowance.period_breakdown(account, period).days
      assert day.gross == Money.new(1350, :USD)
      assert day.billed == Money.new(0, :USD)
    end

    test "prices the whole period once the trial ended before it started", %{account: account} do
      now = DateTime.utc_now()
      period = {DateTime.add(now, -2, :day), DateTime.add(now, 1, :day)}
      account = trial_ended(account, DateTime.add(now, -10, :day))

      ran_minutes(account, DateTime.add(now, -1, :day), 180)

      breakdown = Allowance.period_breakdown(account, period)

      assert breakdown.trial_covered == Money.new(0, :USD)
      assert breakdown.billed == Money.new(600, :USD)
    end

    test "prices a period that closed before the trial began", %{account: account} do
      # The usage page offers a year of history. A trial that starts today
      # says nothing about a period that was invoiced months ago, and
      # reading the trial's end alone marked every one of them covered.
      now = DateTime.utc_now()
      period = {DateTime.add(now, -10, :day), DateTime.add(now, -6, :day)}
      account = on_trial_since(account, DateTime.add(now, -2, :day))

      ran_minutes(account, DateTime.add(now, -8, :day), 180)

      breakdown = Allowance.period_breakdown(account, period)

      assert breakdown.trial_covered == Money.new(0, :USD)
      assert breakdown.billed == Money.new(600, :USD)
    end

    test "covers only what ran after the trial started", %{account: account} do
      now = DateTime.utc_now()
      period = {DateTime.add(now, -4, :day), DateTime.add(now, 1, :day)}
      account = on_trial_since(account, DateTime.add(now, -2, :day))

      ran_minutes(account, DateTime.add(now, -3, :day), 180)
      ran_minutes(account, DateTime.add(now, -1, :day), 60)

      breakdown = Allowance.period_breakdown(account, period)

      assert breakdown.minutes == 240
      assert breakdown.gross == Money.new(1800, :USD)
      assert breakdown.trial_covered == Money.new(450, :USD)
      assert breakdown.billed == Money.new(600, :USD)
    end

    test "prices nothing at all while the trial is still running", %{account: account} do
      account = on_trial_since(account, DateTime.add(DateTime.utc_now(), -30, :day))
      ran_minutes(account, DateTime.add(DateTime.utc_now(), -4, :hour), 180)

      breakdown = Allowance.period_breakdown(account)

      assert breakdown.gross == Money.new(1350, :USD)
      assert breakdown.trial_covered == Money.new(1350, :USD)
      assert breakdown.billed == Money.new(0, :USD)

      # An allowance the account cannot reach yet is not a line worth
      # showing; the trial already covers everything above it.
      assert [row] = breakdown.platforms
      assert row.trial_covered == Money.new(1350, :USD)
      assert row.billed == Money.new(0, :USD)
      assert row.included_minutes == nil
    end

    test "bills a platform row only for what ran after the trial", %{account: account} do
      now = DateTime.utc_now()
      period = {DateTime.add(now, -4, :day), DateTime.add(now, 1, :day)}
      account = trial_ended(account, DateTime.add(now, -2, :day))

      ran_minutes(account, DateTime.add(now, -3, :day), 60)
      ran_minutes(account, DateTime.add(now, -1, :day), 180)

      assert [row] = Allowance.period_breakdown(account, period).platforms

      assert row.minutes == 240
      assert row.gross == Money.new(1800, :USD)
      assert row.trial_covered == Money.new(450, :USD)
      assert row.billed == Money.new(600, :USD)
      assert row.included_minutes == Allowance.free_monthly_minutes()
    end
  end
end
